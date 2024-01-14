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

set -e

if [ -z "${xml_file}" ]; then
    echo "xml_file variable is not set. Set to default."
    xml_file="response_template.xml"
fi
xml_file_stem=$(basename "$xml_file")

if [ -z "${dir_name}" ]; then
    echo "xml_dir variable is not set. Set to default."
    dir_name="${xml_file%.xml}"
fi

mkdir -p "$dir_name"
mkdir -p "${dir_name}/tmp" 


check_generate_keys() {
    local keyvar="$1_pem"
    local keyfile="$1.pem"
    local pub_keyfile="pub_$keyfile"

    if [ ! -z "${keyvar}" ]; then
        if [ ! -f "${keyfile}" ]; then
            openssl genpkey -algorithm RSA -out "${keyfile}" -pass pass: -pkeyopt rsa_keygen_bits:2048
            echo "New private key file (no password) generated ${keyfile}"
        fi
    fi

    if [ ! -f "${pub_keyfile}" ]; then
        # Extract public cert from ${keyfile}
        openssl rsa -in "${keyfile}" -pubout -out "${pub_keyfile}"
        echo "New public key file generated ${pub_keyfile}"
    fi

    declare -g "$1_pem"="${keyfile}"
    declare -g "pub_$1_pem"="${pub_keyfile}"
}

check_generate_keys "client"
check_generate_keys "bank"
check_generate_keys "witness"


decrypted_file="$dir_name/tmp/${xml_file_stem}_payload_camt53_decrypted.zip"

openssl rsa -in $client_pem -check -noout
#openssl rsa -pubin -in $pub_bank_pem -text -noout > ${dir_name}/tmp/${pub_bank_pem}.txt

# Generate timestamp
timestamp=$(date +%Y%m%d%H%M%S)

# Assign parameters to variables
header_file=$dir_name/${xml_file_stem}-authenticated
signedinfo_file=$dir_name/${xml_file_stem}-c14n-signedinfo

echo xml_file: $xml_file public key bank: $pub_bank_pem  private key client: $client_pem 


# extract the digest value from the XML and compare it which the digest of the content marked with a authenticate="true"
# which is in the case of ebics <header authenticate="true">
# digest is base64 string in DigestValue. 
expected_digest=$(awk '/<ds:DigestValue>/,/<\/ds:DigestValue>/' "$xml_file" | sed 's/.*<ds:DigestValue>//' | sed 's/<\/ds:DigestValue>.*$//' | tr -d '\n')
echo "$expected_digest" > $dir_name/tmp/$xml_file_stem-DigestInfo-value
# Base64 --> binary --> hex
expected_digest_hex=$(echo $expected_digest | openssl enc -d -a -A | xxd -p -c256)

# According to standard, we need to inherit all upper namespaces form the sourrounding xml document if we c14n a snippet
# Beware that also the sorting is an issue, as well as the blanks between the tags (!) - therefore
# take the real document get transmitted by the backend - there is no other way knowing which blanks they might use inbetween 
# tags. This is quite unfortunate for a c14n algorithm, but it defined as such in the w3c standard. 
# We hardcode the add_namespaces here because this script is a tool for analyzing how the XML need to be processed. 
# 
add_namespaces=" xmlns=\"http://www.ebics.org/H003\"" 
perl -ne 'print $1 if /(<header.*<\/header>)/' "$xml_file"| xmllint -exc-c14n - | sed "s+<header +<header${add_namespaces} +" > "$header_file"
perl -ne 'print $1 if /(<DataEncryptionInfo.*<\/DataEncryptionInfo>)/' "$xml_file"| xmllint -exc-c14n - | sed "s+<DataEncryptionInfo +<DataEncryptionInfo${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<SignatureData.*<\/SignatureData>)/' "$xml_file"| xmllint -exc-c14n - | sed "s+<SignatureData +<SignatureData${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<ReturnCode auth.*<\/ReturnCode>)/' "$xml_file" | xmllint -exc-c14n - | sed "s+<ReturnCode +<ReturnCode${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<TimestampBankParameter.*<\/TimestampBankParameter>)/' "$xml_file" | xmllint -exc-c14n - | sed "s+<TimestampBankParameter +<TimestampBankParameter${add_namespaces} +" >> "$header_file"

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
    echo calculated digest headertag hex: $calculated_digest_hex
    echo expected digest headertag hex: $expected_digest_hex
    exit -1;
fi

# Signature according to Ebics A004 standard. 
# Now do similar process with SignedInfo as we did with header tag, which same namespace hack. Beware the correct sorting/ordering.
# The hash of Signed. As SingedInfo contains the DigestValue from above
# also above hash is confirmed. The XML signature standard foresees that you can 
# add more than one hash to SignInfo and Sign more hashes in one go. In our case we have just digest to sign. 

export add_namespaces=" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
# need to be 2 steps, because xmllint would remove this unneeded one but the standard sais all top-level need to be included 
export add_namespaces2=" xmlns=\"http://www.ebics.org/H003\""
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$xml_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "$dir_name/${xml_file_stem}-SignedInfo"
signedinfo_digest_file="${dir_name}/tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "$dir_name/${xml_file_stem}-SignedInfo" > "$signedinfo_digest_file"
echo "created digest for SignedInfo from XML, now checking Signature"

perl -ne 'print $1 if /(<ds:SignatureValue.*<\/ds:SignatureValue>)/' "$xml_file" > $dir_name/$xml_file_stem-SignatureValue
# Create file names with timestamp
awk '/<ds:SignatureValue>/,/<\/ds:SignatureValue>/' $xml_file | sed 's/.*<ds:SignatureValue>//' | sed 's/<\/ds:SignatureValue>.*$//' | tr -d '\n' > "$dir_name/tmp/${xml_file_stem}-SignatureValue-value"
#echo signature value from xml as base64: $signature_base64
signature_file="${dir_name}/tmp/signature_$timestamp.bin"
cat $dir_name/tmp/${xml_file_stem}-SignatureValue-value   | openssl enc -d -a -A -out $signature_file

echo "check signature with public key from bank $pub_bank_pem"
# needs X002 from bank
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file" -pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pub_bank_pem"
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"  -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pub_bank_pem"
echo "check typical key sizes for integritiy - size of digest and signature bin files:" $(stat --format="%s" "$signedinfo_digest_file") $(stat --format="%s" "$signature_file")
[ $(stat --format=%s "$signedinfo_digest_file") -eq 32 ] || { echo "Wrong filesize of signedinfo_digest_file "; exit 1; }
[ $(stat --format=%s "$signature_file") -eq 256 ] || { echo "Wrong filesize of signature_file "; exit 1; }

echo "hash of digest bin file:" $(openssl dgst -sha256 -r "$signedinfo_digest_file")
echo "hash of signature bin file:" $(openssl dgst -r -sha256 "$signature_file")

# decript and unzip base64 data
# Base64 decoding, Decrypting, Decompressing, Verifying the signature
awk '/<TransactionKey>/,/<\/TransactionKey>/' $xml_file | sed 's/.*<TransactionKey>//' | sed 's/<\/TransactionKey>.*$//' | tr -d '\n' > "$dir_name/tmp/${xml_file_stem}-TransactionKey"
awk '/<OrderData>/,/<\/OrderData>/' $xml_file | sed 's/.*<OrderData>//' | sed 's/<\/OrderData>.*$//' | tr -d '\n' > "$dir_name/tmp/${xml_file_stem}-OrderData-value"
perl -ne 'print $1 if /(<OrderData.*<\/OrderData>)/' $xml_file > "$dir_name/${xml_file_stem}-OrderData"

# the transaction key is ecrypted with the clients public key - so first we have to decrypt the 
# tx key before we can use it for decrypting the payload. 
encrypted_txkey_file_bin="${dir_name}/tmp/${timestamp}_encrypted_transaction_key.bin"
cat "$dir_name/tmp/${xml_file_stem}-TransactionKey" | base64 --decode > ${encrypted_txkey_file_bin}
decrypted_txkey_file_bin="${dir_name}/tmp/${timestamp}_transaction_key.bin"

# PKCS#1 page 265, process for asymmetrical encryption of the transaction key
[ $(stat --format=%s "$encrypted_txkey_file_bin") -eq 256 ] || { echo "Wrong filesize of encrypted tx key"; exit 1; }
openssl pkeyutl -decrypt -in "${encrypted_txkey_file_bin}" -out "${decrypted_txkey_file_bin}" -inkey $client_pem -pkeyopt rsa_padding_mode:pkcs1 
# leave padding intact so we can compute from message to cyphertext in the circuit which is must faster than vice-versa
openssl pkeyutl -decrypt --in "${encrypted_txkey_file_bin}" -out "${decrypted_txkey_file_bin}-raw" -inkey $client_pem -pkeyopt rsa_padding_mode:none
# echo "size tx key (should be 16) $(stat -c %s "$decrypted_txkey_file_bin") "
[ $(stat --format=%s "$decrypted_txkey_file_bin") -eq 16 ] || { echo "Wrong filesize of decrypted tx key"; exit 1; }

# AES-128 bit key in hex
transaction_key_hex=$(xxd -p -c256 $decrypted_txkey_file_bin  | tr -d '\n')
echo "transaction_key_hex: $transaction_key_hex"
echo "$transaction_key_hex" > "$dir_name/tmp/${xml_file_stem}-TransactionKeyDecrypt"

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

orderdata_bin_file="${dir_name}/tmp/${timestamp}_orderdata_decoded.bin"
cat  "$dir_name/tmp/${xml_file_stem}-OrderData-value" | tr -d '\n' | base64 --decode > $orderdata_bin_file 

openssl enc -d -aes-128-cbc -nopad -in $orderdata_bin_file -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
# openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -pass file:transaction_key.bin -iv 00000000000000000000000000000000
echo "size $(stat -c %s "$orderdata_bin_file") and hash of orderdata bin file:" $(openssl dgst -sha256 -r "$orderdata_bin_file")
echo "size $(stat -c %s "$decrypted_file") and hash of decrypted orderdata bin file:" $(openssl dgst -sha256 -r "$decrypted_file")


# Check if the decrypted file exists, wo do not want to mess with the dd command. 
if [ ! -f "$decrypted_file" ]; then
    echo "Error: Decrypted file ($decrypted_file) does not exist."
    exit 1
fi

# Sign OrderData  = EMSA-PKCS1-v1_5 with SHA-256 
# Signing order data is is marked as planned in the standard
# Until the standard covers this, we add a "witness" who is signing the data instead of the bank. 

# First we need need order data digest in binary format
orderdata_digest_file="${dir_name}/tmp/orderdata_digescheck_$timestamp.bin"
# we need the digest as a digest file; digest again with -binary 
openssl dgst -sha256 -binary -r $orderdata_bin_file > "$orderdata_digest_file"
orderdata_signature_file="${dir_name}/tmp/orderdata_signature_$timestamp.bin"

# digest of binary order data (from base64)
orderdata_signature_output_file="${dir_name}/tmp/orderdata_signature_$timestamp.bin"
# Now do the signing with witness key, then convert the result to hex and store it in Witness.hex as hex
openssl pkeyutl -sign -inkey "$witness_pem" -in "$orderdata_digest_file" -out "$orderdata_signature_output_file" -pkeyopt rsa_padding_mode:pkcs1 -pkeyopt digest:sha256
orderdata_signature_hex_output_file=${dir_name}/${xml_file_stem}-Witness.hex
xxd -p "$orderdata_signature_output_file" > "$orderdata_signature_hex_output_file"
# check signature we just created based on generated hex files 
# openssl pkeyutl -verify -inkey "$pub_witness_pem" -pubin -in $orderdata_digest_file -sigfile $orderdata_signature_output_file -pkeyopt digest:sha256
openssl pkeyutl -verify -inkey "$pub_witness_pem" -pubin -in $orderdata_digest_file -sigfile <(xxd -r -p "$orderdata_signature_hex_output_file") -pkeyopt digest:sha256

# the result is a compressed binary using standard RFC 1951 which is just (de)compressing a stream
payload_file="${dir_name}/tmp/${xml_file_stem}_payload_camt53.zip"
zlib-flate -uncompress  < $decrypted_file > $payload_file
echo "size $(stat -c %s "$dir_name/$xml_file_stem.zip") hash of zip file:" $(openssl dgst -sha256 -r "$payload_file")
# The uncompressed stream is then a zip file which holds the filenames.. so its actually compressed twice. 
unzip -o $payload_file -d  $dir_name/tmp/camt53/
