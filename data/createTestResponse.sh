#!/bin/bash
set -e

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


# Generate timestamp
timestamp=$(date +%Y%m%d%H%M%S)

# Use productive example as template
echo "============================"
if [ -z "${xml_file}" ]; then
    xml_file="response_template.xml"
    echo "xml_file variable is not set, defaults to: ${xml_file}"
fi

# template dir
template_dir="${xml_file%.xml}"

generated_file="${xml_file%.xml}-generated.xml"
xml_file_stem=$(basename "$generated_file")

# target file where we put our hashes and signatures
cp "$xml_file" "$generated_file"

if [ -z "${dir_name}" ]; then
    echo "xml_dir variable is not set. Set to default."
    dir_name="${generated_file%.xml}"
fi

mkdir -p "$dir_name"
mkdir -p "${dir_name}/tmp" 

echo "response template: ${xml_file} - created new xml file from template: $generated_file" 
pwd
ls

# actual starting point - we need to zip, flate-comopress then encrypt payload this
ls -la "$template_dir/camt53"/*
zip "${dir_name}/tmp/orderdata_decrypted.zip" "$template_dir/camt53"/*
zlib-flate -compress  < "${dir_name}/tmp/orderdata_decrypted.zip" > ${dir_name}/tmp/orderdata_decrypted-flated.zip
decrypted_file="${dir_name}/tmp/orderdata_decrypted-flated.zip"

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

check_generate_keys "bank"
check_generate_keys "client"

txkey_file_bin="${dir_name}/tmp/create_tx_key_$timestamp.bin"
# 1. Generate a new 128-bit AES key in hexadecimal format
transaction_key_hex_temp=$(openssl rand -hex 16)
echo "Generated transaction key (hex): $transaction_key_hex_temp"
# Convert the hex string to a binary file
echo "$transaction_key_hex_temp" | xxd -r -p > $txkey_file_bin

transaction_key_hex=$(xxd -p -c 256 $txkey_file_bin | tr -d '\n')
echo "transaction key from file should be same as above: $transaction_key_hex"

# Encrypt the ZIP file
# Replace 'your_zip_file.zip' with the path to your ZIP file
encrypted_file="${dir_name}/tmp/create_orderdata_$timestamp.bin"

# Encrypting the ZIP file
openssl enc -e -aes-128-cbc -in "$decrypted_file" -out "$encrypted_file" -K "$transaction_key_hex" -iv 00000000000000000000000000000000
echo "Encrypted file: $encrypted_file   - convert to base64 and put it as value into the OrderData Tag "

base64_encrypted=$(base64 -w 0 "$encrypted_file")
# Use Perl to replace the content inside the OrderData tag
perl -pi -e "s|<OrderData>.*?</OrderData>|<OrderData>$base64_encrypted</OrderData>|s" "$generated_file"


# As  next step, encrypt the binary transaction key (bin file) with  public key of client.pem, then base64 it. 
# openssl defaults to PKCS#1, Ebics page 265, process for asymmetrical encryption of the transaction key

# Encrypt the transaction key with the public key
encrypted_txkey_file_bin="${dir_name}/tmp/create_ecrypted_tx_key_$timestamp.bin"
openssl rsautl -encrypt -pubin -inkey $pub_client_pem -in $txkey_file_bin -out $encrypted_txkey_file_bin
# Convert the encrypted key to Base64
base64_encrypted_transaction_key=$(base64 -w 0 $encrypted_txkey_file_bin)
# Insert the Base64 encoded encrypted transaction key into the XML file
perl -pi -e "s|<TransactionKey>.*?</TransactionKey>|<TransactionKey>$base64_encrypted_transaction_key</TransactionKey>|s" "$generated_file"
echo "Transaction key encrypted and inserted into the XML file. Next calculate DigestValue of all Tags marked with authenticated=true"

# get all tags with authtenticated= true; then process it according to C14N rulez. 
header_file=$dir_name/$generated_file-authenticated
add_namespaces=" xmlns=\"http://www.ebics.org/H003\"" 
perl -ne 'print $1 if /(<header.*<\/header>)/' "$generated_file"                                 | xmllint -exc-c14n - | sed "s+<header +<header${add_namespaces} +" > "$header_file"
perl -ne 'print $1 if /(<DataEncryptionInfo.*<\/DataEncryptionInfo>)/' "$generated_file"         | xmllint -exc-c14n - | sed "s+<DataEncryptionInfo +<DataEncryptionInfo${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<ReturnCode auth.*<\/ReturnCode>)/' "$generated_file"                    | xmllint -exc-c14n - | sed "s+<ReturnCode +<ReturnCode${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<TimestampBankParameter.*<\/TimestampBankParameter>)/' "$generated_file" | xmllint -exc-c14n - | sed "s+<TimestampBankParameter +<TimestampBankParameter${add_namespaces} +" >> "$header_file"

echo "size of authenticate file:" $(stat --format="%s" "$header_file")
# get sha256 hex value; cut removes the filename in the output
calculated_digest_hex=$( openssl dgst -sha256 -r $header_file | cut -d ' ' -f 1 )
echo calculated digest headertag hex: $calculated_digest_hex
# hex --> binary --> to base64;
digest_value=$(echo "$calculated_digest_hex" | xxd -r -p | openssl enc -a -A)

# Put the digest into the document
perl -pi -e "s|<ds:DigestValue>.*?</ds:DigestValue>|<ds:DigestValue>$digest_value</ds:DigestValue>|s" "$generated_file"


# Now we need to produce the "SingedInfo" Text and sign the tings which are wrapped by the  <ds:SignedInfo> tag
# first extract SignedInfo Tag and do C14N

export add_namespaces=" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
# need to be 2 steps, because xmllint would remove this unneeded one but the standard sais all top-level need to be included 
export add_namespaces2=" xmlns=\"http://www.ebics.org/H003\""
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$generated_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "$dir_name/${generated_file}-SignedInfo"
signedinfo_digest_file="${dir_name}/tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "${dir_name}/${generated_file}-SignedInfo" > "$signedinfo_digest_file"
echo "created digest for SignedInfo from XML, now creating Signature"

signature_output_file="${dir_name}/tmp/created_signature-output-$timestamp.bin"
# Create a signature
openssl pkeyutl -sign -inkey $bank_pem -in "$signedinfo_digest_file" -out "$signature_output_file" -pkeyopt rsa_padding_mode:pkcs1 -pkeyopt digest:sha256


# Convert the signature to Base64
base64_signature=$(base64 -w 0 "$signature_output_file")

# Replace the <ds:SignatureValue> content in the XML file
perl -pi -e "s|<ds:SignatureValue>.*?</ds:SignatureValue>|<ds:SignatureValue>$base64_signature</ds:SignatureValue>|s" "$generated_file"
echo "Signature inserted into the XML file."

# archive new file to new name; call checkResponse with new name
cp  "$generated_file" "$dir_name/$generated_file"
xmllint -format "$dir_name/$generated_file"  > $dir_name/tmp/${xml_file_stem}-pretty.xml
echo "Test XMLs created, calling checkResponse.sh with the generated XML to check it - $pub_bank_pem $client_pem"
xml_file="$generated_file" pem_file=$pub_bank_pem  private_pem_file=$client_pem ./checkResponse.sh
