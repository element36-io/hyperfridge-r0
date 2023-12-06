#!/bin/bash

# deb packages needed: 	libxml2-utils (xmllint), perl, openssl, openssl-dev, qpdf (zlib-flate)
#
# The Script needs legacy support for openssl to handle banking protocols. 
# Activate these with following configurations:  
# /usr/lib/ssl openssl.conf  for legacy check: 
# List of providers to load
# [provider_sect]
# default = default_sect
# legacy = legacy_sect
# [legacy_sect]
# activate = 1
# [default_sect]
# activate = 1

if [ -z "${xml_file}" ]; then
    echo "xml_file variable is not set. Set to default."
    exit 1
fi

if [ -z "${pem_file}" ]; then
    echo "pem_file variable for bank public key X002 is not set. Set to default."
    exit 1
fi
set -e

# Generate timestamp
timestamp=$(date +%Y%m%d%H%M%S)

# Assign parameters to variables
header_file=$xml_file-authenticated
signedinfo_file=$xml_file-c14n-signedinfo
echo ---------------------------------------------
echo xml_file: $xml_file pem_file: $pem_file


# extract the digest value from the XML and compare it which the digest of the content marked with a authenticate="true"
# which is in the case of ebics <header authenticate="true">
expected_digest=$(awk '/<ds:DigestValue>/,/<\/ds:DigestValue>/' "$xml_file" | sed 's/.*<ds:DigestValue>//' | sed 's/<\/ds:DigestValue>.*$//' | tr -d '\n')
echo "$expected_digest" > digest_base64.txt
echo "$expected_digest" > $xml_file-DigestInfo-value
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
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$xml_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "${xml_file}-SignedInfo"
signedinfo_digest_file="/tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "${xml_file}-SignedInfo" > "$signedinfo_digest_file"


perl -ne 'print $1 if /(<ds:SignatureValue.*<\/ds:SignatureValue>)/' "$xml_file" > $xml_file-SignatureValue
# Create file names with timestamp
awk '/<ds:SignatureValue>/,/<\/ds:SignatureValue>/' $xml_file | sed 's/.*<ds:SignatureValue>//' | sed 's/<\/ds:SignatureValue>.*$//' | tr -d '\n' > "${xml_file}-SignatureValue-value"
#echo signature value from xml as base64: $signature_base64
signature_file="/tmp/signature_$timestamp.bin"
cat ${xml_file}-SignatureValue-value   | openssl enc -d -a -A -out $signature_file

# needs X002 from bank
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file" -pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"
openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"  -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"
echo "size of digest and signature bin files:" $(stat --format="%s" "$signedinfo_digest_file") $(stat --format="%s" "$signature_file")
echo "hash of digest bin file:" $(openssl dgst -sha256 -r "$signedinfo_digest_file")
echo "hash of signature bin file:" $(openssl dgst -r -sha256 "$signature_file")

# decript and unzip base64 data
# Base64 decoding, Decrypting, Decompressing, Verifying the signature
awk '/<TransactionKey>/,/<\/TransactionKey>/' $xml_file | sed 's/.*<TransactionKey>//' | sed 's/<\/TransactionKey>.*$//' | tr -d '\n' > "${xml_file}-TransactionKey"
awk '/<OrderData>/,/<\/OrderData>/' $xml_file | sed 's/.*<OrderData>//' | sed 's/<\/OrderData>.*$//' | tr -d '\n' > "${xml_file}-OrderData-value"
perl -ne 'print $1 if /(<OrderData.*<\/OrderData>)/'  er3.xml > "${xml_file}-OrderData"


txkey_file="/tmp/${timestamp}_encrypted_transaction_key.bin"
cat "${xml_file}-TransactionKey" | base64 --decode > ${txkey_file}

# PKCS#1 page 265, process for asymmetrical encryption of the transaction key
openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1

# openssl pkeyutl -decrypt -in ${trimmed_txkey_file} -out pdek.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
# transaction_key.bin="/tmp/${timestamp}_transaction_key.bin"
# tail -c 16 pdek.bin > ${transaction_key.bin}

# AES-128 bit key in hex
transaction_key_hex=$(xxd -p -c256 transaction_key.bin | tr -d '\n')
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

decrypted_file="orderdata_decrypted.zip"
cat  "${xml_file}-OrderData-value" | tr -d '\n' | base64 --decode > orderdata_decoded.bin 

openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
# openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -pass file:transaction_key.bin -iv 00000000000000000000000000000000
echo "size $(stat -c %s "orderdata_decoded.bin") and hash of orderdata bin file:" $(openssl dgst -sha256 -r "orderdata_decoded.bin")
echo "size $(stat -c %s "$decrypted_file") and hash of decrypted bin file:" $(openssl dgst -sha256 -r "$decrypted_file")


echo "result without padding: $decrypted_file"
# Check if the decrypted file exists, wo do not want to mess with the dd command. 
if [ ! -f "$decrypted_file" ]; then
    echo "Error: Decrypted file ($decrypted_file) does not exist."
    exit 1
fi

# the result is a compressed binary using standard RFC 1951 which is just (de)compressing a stream
zlib-flate -uncompress  < $decrypted_file > $xml_file.zip
echo "size $(stat -c %s "$xml_file.zip") hash of zip file:" $(openssl dgst -sha256 -r "$xml_file.zip")
# The uncompressed stream is then a zip file which holds the filenames.. so its actually compressed twice. 
unzip $xml_file.zip -o -d ./camt53