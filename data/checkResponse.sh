#!/bin/bash
echo ---------------------------------------------
# deb packages needed: 	libxml2-utils (xmllint), perl, openssl, openssl-dev, qpdf (zlib-flate)
#
# The Script needs legacy support for openssl to handle banking protocols. 
# Activate these with following configurations:  
# /usr/lib/ssl openssl.conf  for legacy check: 
# List of providers to load
# [provider_sect]
# default = default_sect
# legacy = legacy_sect
# [default_sect]
# activate = 1
# [legacy_sect]
# activate = 1


if [ "${work_dir}" ]; then
    echo "work_dir variable is set"
    cd "${work_dir}"
fi

echo "work dir of script $(pwd)"

echo "work dir of script $(pwd)"

if [ -z "${xml_file}" ]; then
    echo "xml_file variable is not set. Set to default."
    xml_file="response_template.xml"
fi
xml_file_stem=$(basename "$xml_file")

if [ ! -f "${xml_file}" ]; then
    echo "can not find ebics response file $xml_file"
    exit 7
fi

if [ -z "${output_dir_name}" ]; then
    echo "xml_dir variable is not set. Set to default."
    output_dir_name="./${xml_file%.xml}"
fi

mkdir -p "$output_dir_name"
mkdir -p "${output_dir_name}/tmp" 


check_private() {
    local keyvar="$1_pem"
    local keyfile="$1.pem"
    local exit_on_missing="$3"

    # keyfile file was specified by environment var
    if [ -n "$2" ]; then
        keyfile="$2"
      
        if [ ! -f "${keyfile}" ]; then
            echo "private  keyfile not found: $1, $2"
            if [ -n "$exit_on_missing" ]; then 
                exit 3
            fi
        fi
    else 
        echo checking file ${keyfile} exist for $1
        if [ ! -f "${keyfile}" ]; then
            echo "default private keyfile not found: $1 $1"
        fi
    fi  

    echo "setting private keyfie of $1 to ${keyfile}"
    declare -g "$1_pem"="${keyfile}" # e.g. witness_pem or client_pem
}

check_pub() {
    local keyvar="$1_pem"
    local keyfile="$1.pem"
    local pub_keyfile="pub_$keyfile"

    # Check if the second argument is present and not empty
    if [ -n "$2" ]; then
        pub_keyfile="$2"

        if [ ! -f "${pub_keyfile}" ]; then
            echo "public keyfile not found: $1 $2"
            exit 4
        fi
    # no argument for file given, default is generate if not found
    else 
        if [ ! -f "${pub_keyfile}" ]; then
            echo "default public keyfile not found: $1 $1"
        fi
    fi  

    echo "setting pub keyfie of $1 to ${pub_keyfile}"
    declare -g "pub_$1_pem"="${pub_keyfile}"
}

check_pub "client" $pub_client
check_private "client" $client
check_pub "bank" $pub_bank
check_pub "witness" $pub_witness
check_private "witness" "$witness" "false"

decrypted_file="$output_dir_name/tmp/${xml_file_stem}_payload_camt53_decrypted.zip"

openssl rsa -in $client_pem -check -noout
#openssl rsa -pubin -in $pub_bank_pem -text -noout > ${output_dir_name}/tmp/${pub_bank_pem}.txt

# Generate timestamp
timestamp=$(date +%Y%m%d%H%M%S)

# Assign parameters to variables
header_file=$output_dir_name/${xml_file_stem}-authenticated
signedinfo_file=$output_dir_name/${xml_file_stem}-c14n-signedinfo

echo xml_file: $xml_file public key bank: $pub_bank_pem  private key client: $client_pem 


# extract the digest value from the XML and compare it which the digest of the content marked with a authenticate="true"
# which is in the case of ebics <header authenticate="true">
# digest is base64 string in DigestValue. 
expected_digest=$(awk '/<ds:DigestValue>/,/<\/ds:DigestValue>/' "$xml_file" | sed 's/.*<ds:DigestValue>//' | sed 's/<\/ds:DigestValue>.*$//' | tr -d '\n')
echo "$expected_digest" > $output_dir_name/tmp/$xml_file_stem-DigestInfo-value
# Base64 --> binary --> hex
expected_digest_hex=$(echo $expected_digest | openssl enc -d -a -A | xxd -p -c256)
# According to standard, we need to inherit all upper namespaces form the sourrounding xml document if we c14n a snippet
# Beware that also the sorting is an issue, as well as the blanks between the tags (!) - therefore
# take the real document get transmitted by the backend - there is no other way knowing which blanks they might use inbetween 
# tags. This is quite unfortunate for a c14n algorithm, but it defined as such in the w3c standard. 
# We hardcode the add_namespaces here because this script is a tool for analyzing how the XML need to be processed. 
#

#add_namespaces=" xmlns=\"http://www.ebics.org/H003\"" 
# Extract namespace from xml file
namespace=$(grep -o 'xmlns="http://www.ebics.org/H00[34]"' "$xml_file" | sed 's/xmlns="//' | sed 's/"//')
if [[ -z "$namespace" ]]; then
    namespace=$(grep -o 'xmlns="urn:org:ebics:H00[34]"' "$xml_file" | sed 's/xmlns="//' | sed 's/"//')
fi
alg_namespace=$namespace;

# Set add_namespaces variable based on extracted namespace
if [[ -n "$namespace" ]]; then
    add_namespaces=" xmlns=\"$namespace\""
    if [[ $namespace == *"H004"* ]]; then
        add_namespaces="$add_namespaces xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
    fi
else   
    echo failed to extract namespace
    exit 34
fi

perl -ne 'print $1 if /(<header.*<\/header>)/' "$xml_file"| xmllint -exc-c14n - | sed "s+<header +<header${add_namespaces} +" > "$header_file"
perl -ne 'print $1 if /(<DataEncryptionInfo.*<\/DataEncryptionInfo>)/' "$xml_file"| xmllint -exc-c14n - | sed "s+<DataEncryptionInfo +<DataEncryptionInfo${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<ReturnCode auth.*<\/ReturnCode>)/' "$xml_file" | xmllint -exc-c14n - | sed "s+<ReturnCode +<ReturnCode${add_namespaces} +" >> "$header_file"
if perl -ne 'exit(0) if /(<TimestampBankParameter.*<\/TimestampBankParameter>)/; exit(1)' "$xml_file"; then
    perl -ne 'print $1 if /(<TimestampBankParameter.*<\/TimestampBankParameter>)/' "$xml_file" | xmllint -exc-c14n - | sed "s+<TimestampBankParameter +<TimestampBankParameter${add_namespaces} +" >> "$header_file"
fi

echo "size of authenticate file:" $(stat --format="%s" "$header_file")

# extract the hex; the cut is needed to get the raw digest value from the command line output

calculated_digest_hex=$( openssl dgst -sha256 -r $header_file | cut -d ' ' -f 1 )
if  [ "$expected_digest_hex" == "$calculated_digest_hex" ]; then 
    # echo calculated digest headertag hex: $calculated_digest_hex
    # echo -n $calculated_digest_hex | xxd -r -p | base64
    # echo expected digest headertag hex: $expected_digest_hex
    # echo -n $expected_digest_hex | xxd -r -p | base64
    echo "digest is matching!" 
else 
    echo "digest is not matching - look for authenticate=true attribues which indicate the Tags which are digested." 
    echo calculated digest headertag hex: $calculated_digest_hex for $header_file
    echo expected digest headertag hex: $expected_digest_hex
    echo command: "openssl dgst -sha256 -r $header_file | cut -d ' ' -f 1"
    exit -1;
fi

# Signature according to Ebics A004 and A006 standard. 
# Now do similar process with SignedInfo as we did with header tag, which same namespace hack. Beware the correct sorting/ordering.
# The hash of Signed. As SingedInfo contains the DigestValue from above
# also above hash is confirmed. The XML signature standard foresees that you can 
# add more than one hash to SignInfo and Sign more hashes in one go. In our case we have just digest to sign. 

if [[ $alg_namespace == *"H004"* ]]; then
    export add_namespaces=" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
    # need to be 2 steps, because xmllint would remove this unneeded one but the standard sais all top-level need to be included 
    export add_namespaces2=" xmlns=\"urn:org:ebics:H004\""
else
    export add_namespaces=" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
    # need to be 2 steps, because xmllint would remove this unneeded one but the standard sais all top-level need to be included 
    export add_namespaces2=" xmlns=\"http://www.ebics.org/H003\""
fi
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$xml_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "$output_dir_name/${xml_file_stem}-SignedInfo"
signedinfo_digest_file="${output_dir_name}/tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "$output_dir_name/${xml_file_stem}-SignedInfo" > "$signedinfo_digest_file"
[ $(stat --format=%s "$signedinfo_digest_file") -eq 32 ] || { echo "Wrong filesize of signedinfo_digest_file "; exit 1; }
echo "created digest for SignedInfo from XML, now checking Signature"

# old version with HBL: perl -ne  'print $1 if /(<ds:SignatureValue.*<\/ds:SignatureValue>)/' "$xml_file" > $output_dir_name/$xml_file_stem-SignatureValue
# perl -0777 -ne 'print $1 if /<ds:SignatureValue[^>]*>(.*?)<\/ds:SignatureValue>/s'  "$xml_file" > $output_dir_name/$xml_file_stem-SignatureValue
perl -0777 -ne 'print $1 if /(<ds:SignatureValue>.*?<\/ds:SignatureValue>)/s' "$xml_file" | sed 's/&#13;//g' | tr -d '\n' > $output_dir_name/$xml_file_stem-SignatureValue
[ $(stat -c %s "$output_dir_name/$xml_file_stem-SignatureValue") -eq 0 ] && echo "Error: The SignatureValue file is empty" && exit 19

# Create file names with timestamp
awk '/<ds:SignatureValue>/,/<\/ds:SignatureValue>/' $xml_file | sed 's/.*<ds:SignatureValue>//' | sed 's/<\/ds:SignatureValue>.*$//' |  sed 's/&#13;//g' | tr -d '\n' > "$output_dir_name/tmp/${xml_file_stem}-SignatureValue-value"
signature_file="${output_dir_name}/tmp/signature_$timestamp.bin"
base64 -d -i "$output_dir_name/tmp/${xml_file_stem}-SignatureValue-value" > "$signature_file"
[ $(stat --format=%s "$signature_file") -eq 256 ] || { echo "Wrong filesize of signature_file "; exit 1; }

# spec: https://www.w3.org/TR/xmldsig-core/#sec-CoreValidation
echo "check signature with public key from bank $pub_bank_pem"
echo "command: openssl  pkeyutl  -verify -in  $signedinfo_digest_file -sigfile  $signature_file -pkeyopt digest:sha256 -pubin -keyform PEM -inkey $pub_bank_pem"
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"  -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pub_bank_pem"

echo "hash of digest bin file:" $(openssl dgst -sha256 -r "$signedinfo_digest_file")
echo "hash of signature bin file:" $(openssl dgst -r -sha256 "$signature_file")

# decript and unzip base64 data
# Base64 decoding, Decrypting, Decompressing, Verifying the signature
awk '/<TransactionKey>/,/<\/TransactionKey>/' $xml_file | sed 's/.*<TransactionKey>//' | sed 's/<\/TransactionKey>.*$//' | tr -d '\n' > "$output_dir_name/tmp/${xml_file_stem}-TransactionKey"
awk '/<OrderData>/,/<\/OrderData>/' $xml_file | sed 's/.*<OrderData>//' | sed 's/<\/OrderData>.*$//' | tr -d '\n' > "$output_dir_name/tmp/${xml_file_stem}-OrderData-value"
perl -ne 'print $1 if /(<OrderData.*<\/OrderData>)/' $xml_file > "$output_dir_name/${xml_file_stem}-OrderData"

# the transaction key is ecrypted with the clients public key - so first we have to decrypt the 
# tx key before we can use it for decrypting the payload. 
encrypted_txkey_file_bin="${output_dir_name}/tmp/${timestamp}_encrypted_transaction_key.bin"
cat "$output_dir_name/tmp/${xml_file_stem}-TransactionKey" | base64 --decode > ${encrypted_txkey_file_bin}
decrypted_txkey_file_bin="${output_dir_name}/tmp/${timestamp}_transaction_key.bin"

# PKCS#1 page 265, process for asymmetrical encryption of the transaction key
[ $(stat --format=%s "$encrypted_txkey_file_bin") -eq 256 ] || { echo "Wrong filesize of encrypted tx key"; exit 1; }
openssl pkeyutl -decrypt -in "${encrypted_txkey_file_bin}" -out "${decrypted_txkey_file_bin}" -inkey $client_pem -pkeyopt rsa_padding_mode:pkcs1 
# leave padding intact so we can compute from message to cyphertext in the circuit which is must faster than vice-versa
openssl pkeyutl -decrypt --in "${encrypted_txkey_file_bin}" -out "${decrypted_txkey_file_bin}-raw" -inkey $client_pem -pkeyopt rsa_padding_mode:none
# echo "size tx key (should be 16) $(stat -c %s "$decrypted_txkey_file_bin") "
[ $(stat --format=%s "$decrypted_txkey_file_bin") -eq 16 ] || { echo "Wrong filesize of decrypted tx key"; exit 1; }
cp  "${decrypted_txkey_file_bin}-raw" "$output_dir_name/${xml_file_stem}-TransactionKeyDecrypt.bin"

# AES-128 bit key in hex
transaction_key_hex=$(xxd -p -c256 $decrypted_txkey_file_bin  | tr -d '\n')

key_length=${#transaction_key_hex}
# For AES-128, the key should be 32 hex characters
if [ $key_length -ne 32 ]; then
    echo "Error: Invalid key length. Length is $key_length, expected 32."
    echo "Key length: ${#transaction_key_hex}"
    echo "$transaction_key_hex"
    exit 1
fi

#  Base64 decoding, Decrypting, Decompressing, 
# Decrypt the OrderData using AES-128-ECB
# https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf#page=303&zoom=100,0,0
# page 256, 306
# aes-128-cbc, padding ANSI X9.23 / ISO 10126-2.  page 265, 
# openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
# but openssl does not handle ISO10126Padding, so use -nopad and do the padding manually

orderdata_bin_file="${output_dir_name}/tmp/${timestamp}_orderdata_decoded.bin"
cat  "$output_dir_name/tmp/${xml_file_stem}-OrderData-value" | tr -d '\n' | base64 --decode > $orderdata_bin_file 

openssl enc -d -aes-128-cbc -nopad -in $orderdata_bin_file -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
# openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -pass file:transaction_key.bin -iv 00000000000000000000000000000000
echo "size $(stat -c %s "$orderdata_bin_file") and hash of orderdata bin file:" $(openssl dgst -sha256 -r "$orderdata_bin_file")
echo "size $(stat -c %s "$decrypted_file") and hash of decrypted orderdata bin file:" $(openssl dgst -sha256 -r "$decrypted_file")


# Check if the decrypted file exists, wo do not want to mess with the dd command. 
if [ ! -f "$decrypted_file" ]; then
    echo "Error: Decrypted file ($decrypted_file) does not exist."
    exit 1
fi


# Signing order data is is marked as planned in the standard
# Until the standard covers this, we add a "witness" who is signing the data instead of the bank. 
# First we need need order data digest in binary format
orderdata_digest_file="${output_dir_name}/tmp/orderdata_digestcheck_$timestamp.bin"
openssl dgst -sha256 -binary  $orderdata_bin_file > "$orderdata_digest_file"
orderdata_signature_hex_output_file=${output_dir_name}/${xml_file_stem}-Witness.hex

# Witness file needs to be present, generated before this script by hyperfridge or here
# if the witness-private key is present; sign the payload. 
if [ -f "$witness_pem" ]; then
    echo "generating witness signature"
    orderdata_signature_output_file="${output_dir_name}/tmp/orderdata_signature_$timestamp.bin"
    openssl pkeyutl -sign -inkey "$witness_pem" -in "$orderdata_digest_file" -out "$orderdata_signature_output_file" -pkeyopt rsa_padding_mode:pkcs1 -pkeyopt digest:sha256
    xxd -p "$orderdata_signature_output_file" > "$orderdata_signature_hex_output_file"
else   
    echo "not generating witness signature, private key not set or found"
fi

# check signature we just created based on generated hex files 
# openssl pkeyutl -verify -inkey "$pub_witness_pem" -pubin -in $orderdata_digest_file -sigfile $orderdata_signature_output_file -pkeyopt digest:sha256
openssl pkeyutl -verify -inkey "$pub_witness_pem" -pubin -in $orderdata_digest_file -sigfile <(xxd -r -p "$orderdata_signature_hex_output_file") -pkeyopt digest:sha256

# the result is a compressed binary using standard RFC 1951 which is just (de)compressing a stream
payload_file="${output_dir_name}/tmp/${xml_file_stem}_payload_camt53.zip"
zlib-flate -uncompress  < $decrypted_file > $payload_file

echo "size $(stat -c %s "$payload_file") hash of zip file:" $(openssl dgst -sha256 -r "$payload_file")
# The uncompressed stream is then a zip file which holds the filenames.. so its actually compressed twice. 
unzip -o $payload_file -d  $output_dir_name/tmp/camt53/
echo "Secret Input Data generated."