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
    xml_file="productive_example.xml"
fi
dir_name="${xml_file%.xml}"

if [ ! -d "$dir_name" ]; then
    mkdir "$dir_name"
fi

if [ -z "${pem_file}" ]; then
    echo "pem_file variable for bank public key X002 is not set. Set to default."
    pem_file="productive_bank_x002.pem"
fi

if [ -z "${private_pem_file}" ]; then
    echo "pem_file variable for bank public key X002 is not set. Set to default."
    private_pem_file="../secrets/e002_private_key.pem"
fi

decrypted_file="$dir_name/orderdata_decrypted.zip"

openssl rsa -in $private_pem_file -check -noout
openssl rsa -pubin -in $pem_file -text -noout > /dev/null

# Generate timestamp
timestamp=$(date +%Y%m%d%H%M%S)

# Assign parameters to variables
header_file=$dir_name/$xml_file-authenticated
signedinfo_file=$dir_name/$xml_file-c14n-signedinfo

echo xml_file: $xml_file public key bank: $pem_file  private key client: $private_pem_file 


# extract the digest value from the XML and compare it which the digest of the content marked with a authenticate="true"
# which is in the case of ebics <header authenticate="true">
# digest is base64 string in DigestValue. 
expected_digest=$(awk '/<ds:DigestValue>/,/<\/ds:DigestValue>/' "$xml_file" | sed 's/.*<ds:DigestValue>//' | sed 's/<\/ds:DigestValue>.*$//' | tr -d '\n')
echo "$expected_digest" > $dir_name/$xml_file-DigestInfo-value
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
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$xml_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "$dir_name/${xml_file}-SignedInfo"
signedinfo_digest_file="./tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "$dir_name/${xml_file}-SignedInfo" > "$signedinfo_digest_file"
echo "created digest for SignedInfo from XML, now checking Signature"

perl -ne 'print $1 if /(<ds:SignatureValue.*<\/ds:SignatureValue>)/' "$xml_file" > $dir_name/$xml_file-SignatureValue
# Create file names with timestamp
awk '/<ds:SignatureValue>/,/<\/ds:SignatureValue>/' $xml_file | sed 's/.*<ds:SignatureValue>//' | sed 's/<\/ds:SignatureValue>.*$//' | tr -d '\n' > "$dir_name/${xml_file}-SignatureValue-value"
#echo signature value from xml as base64: $signature_base64
signature_file="./tmp/signature_$timestamp.bin"
cat $dir_name/${xml_file}-SignatureValue-value   | openssl enc -d -a -A -out $signature_file

echo "check signature with public key from bank $pem_file"
# needs X002 from bank
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file" -pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"  -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"
echo "check typical key sizes for integritiy - size of digest and signature bin files:" $(stat --format="%s" "$signedinfo_digest_file") $(stat --format="%s" "$signature_file")
[ $(stat --format=%s "$signedinfo_digest_file") -eq 32 ] || { echo "Wrong filesize of signedinfo_digest_file "; exit 1; }
[ $(stat --format=%s "$signature_file") -eq 256 ] || { echo "Wrong filesize of signature_file "; exit 1; }

echo "hash of digest bin file:" $(openssl dgst -sha256 -r "$signedinfo_digest_file")
echo "hash of signature bin file:" $(openssl dgst -r -sha256 "$signature_file")

# decript and unzip base64 data
# Base64 decoding, Decrypting, Decompressing, Verifying the signature
awk '/<TransactionKey>/,/<\/TransactionKey>/' $xml_file | sed 's/.*<TransactionKey>//' | sed 's/<\/TransactionKey>.*$//' | tr -d '\n' > "$dir_name/${xml_file}-TransactionKey"
awk '/<OrderData>/,/<\/OrderData>/' $xml_file | sed 's/.*<OrderData>//' | sed 's/<\/OrderData>.*$//' | tr -d '\n' > "$dir_name/${xml_file}-OrderData-value"
perl -ne 'print $1 if /(<OrderData.*<\/OrderData>)/' $xml_file > "$dir_name/${xml_file}-OrderData"

# the transaction key is ecrypted with the clients public key - so first we have to decrypt the 
# tx key before we can use it for decrypting the payload. 
encrypted_txkey_file_bin="./tmp/${timestamp}_encrypted_transaction_key.bin"
cat "$dir_name/${xml_file}-TransactionKey" | base64 --decode > ${encrypted_txkey_file_bin}

decrypted_txkey_file_bin="./tmp/${timestamp}_transaction_key.bin"
# PKCS#1 page 265, process for asymmetrical encryption of the transaction key
[ $(stat --format=%s "$encrypted_txkey_file_bin") -eq 256 ] || { echo "Wrong filesize of encrypted tx key"; exit 1; }
openssl pkeyutl -decrypt -in "${encrypted_txkey_file_bin}" -out "${decrypted_txkey_file_bin}" -inkey $private_pem_file -pkeyopt rsa_padding_mode:pkcs1 
# echo "size tx key (should be 16) $(stat -c %s "$decrypted_txkey_file_bin") "
[ $(stat --format=%s "$decrypted_txkey_file_bin") -eq 16 ] || { echo "Wrong filesize of decrypted tx key"; exit 1; }

# AES-128 bit key in hex
transaction_key_hex=$(xxd -p -c256 $decrypted_txkey_file_bin  | tr -d '\n')
echo "transaction_key_hex: $transaction_key_hex"
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

orderdata_bin_file="./tmp/${timestamp}_orderdata_decoded.bin"
cat  "$dir_name/${xml_file}-OrderData-value" | tr -d '\n' | base64 --decode > $orderdata_bin_file 

openssl enc -d -aes-128-cbc -nopad -in $orderdata_bin_file -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
# openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -pass file:transaction_key.bin -iv 00000000000000000000000000000000
echo "size $(stat -c %s "$orderdata_bin_file") and hash of orderdata bin file:" $(openssl dgst -sha256 -r "$orderdata_bin_file")
echo "size $(stat -c %s "$decrypted_file") and hash of decrypted bin file:" $(openssl dgst -sha256 -r "$decrypted_file")


echo "result without padding: $decrypted_file"
# Check if the decrypted file exists, wo do not want to mess with the dd command. 
if [ ! -f "$decrypted_file" ]; then
    echo "Error: Decrypted file ($decrypted_file) does not exist."
    exit 1
fi

# the result is a compressed binary using standard RFC 1951 which is just (de)compressing a stream
zlib-flate -uncompress  < $decrypted_file > $dir_name/$xml_file.zip
echo "size $(stat -c %s "$dir_name/$xml_file.zip") hash of zip file:" $(openssl dgst -sha256 -r "$dir_name/$xml_file.zip")
# The uncompressed stream is then a zip file which holds the filenames.. so its actually compressed twice. 
unzip -o $dir_name/$xml_file.zip -d  ./$dir_name/camt53/