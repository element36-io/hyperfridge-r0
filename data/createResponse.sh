
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

xml_file="er3.xml-orig"
set -e
created_file="$xml_file-created"

cp "$xml_file" "$created_file"


if [ -z "${xml_file}" ]; then
    echo "xml_file variable is not set. Set to default. ${xml_file}"
    #exit 1
fi


echo "response xml_file: ${xml_file}"

fileAuthenticated="${xml_file}-authenticated"
fileOrderData="${xml_file}-OrderData"
fileSignatureValue="${xml_file}-SignatureValue"
fileSignedInfo="${xml_file}-SignedInfo"
decrypted_file="orderdata_decrypted.zip"

# Check if all files exist
if [ ! -f "$fileAuthenticated" ] || [ ! -f "$fileOrderData" ] || [ ! -f "$fileSignatureValue" ] || [ ! -f "$fileSignedInfo" ]  || [ ! -f "$decrypted_file" ] ; then
    echo "One or more files are missing."
    exit 1
fi



# generate bank and use keys RSA
openssl genpkey -algorithm RSA -out bank.pem -pkeyopt rsa_keygen_bits:2048
openssl genpkey -algorithm RSA -out client.pem -pkeyopt rsa_keygen_bits:2048
# 1. Generate a new 128-bit AES key in hexadecimal format
transaction_key_hex=$(openssl rand -hex 16)
echo "Generated transaction key (hex): $transaction_key_hex"
echo "new keys generated"

# Encrypt the ZIP file
# Replace 'your_zip_file.zip' with the path to your ZIP file

encrypted_file="orderdata_encrypted.bin"

# Encrypting the ZIP file
openssl enc -e -aes-128-cbc -nopad -in "$decrypted_file" -out "$encrypted_file" -K "$transaction_key_hex" -iv 00000000000000000000000000000000
echo "Encrypted file: $encrypted_file   - convert to base64 nd put it as value into the OrderData Tag "

Add next steps put the base64 converted file as text between the OrderData tags of the file created_file="$xml_file-created"

 <?xml version="1.0" encoding="utf-8"?><ebicsResponse Revision="1" Version="H003" xmlns="http://www.ebics.org/H003"><header authenticate="true"><static><TransactionID>DD85DCE9DD8442B3DA74A2C174BEACE3</TransactionID><NumSegments>1</NumSegments></static><mutable><TransactionPhase>Initialisation</TransactionPhase><SegmentNumber lastSegment="true">1</SegmentNumber><ReturnCode>000000</ReturnCode><ReportText>[EBICS_OK] OK</ReportText></mutable></header><AuthSignature xmlns:ds="http://www.w3.org/2000/09/xmldsig#"><ds:SignedInfo><ds:CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315" /><ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" /><ds:Reference URI="#xpointer(//*[@authenticate='true'])"><ds:Transforms><ds:Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315" /></ds:Transforms><ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256" /><ds:DigestValue>VkdMpq9P+oYx7NUp0JhQnZw/17yulOzmAzqJQvvnT0w=</ds:DigestValue></ds:Reference></ds:SignedInfo><ds:SignatureValue>YmozAQZ66YHSqx0m68vlmWhjxV7KoFGlkn3oUTXnvdw6QnyYnlLCEgtoNPnoI9GIeuPVUZ1nQ4uz/P4G9hX/Gx6brf+6JSMy5DqIRaISmBN/BjmmGjM+cSlTpGBut0SDxNbf8H5fY2oLBzdwapI4LrTP9GwzPXuD+8nUqObLVDOL/tBXW3AIpf+0SmS8n80uJBADFdV3/u80+pLDZYaE+cId1Y9QvUBoew297cw+ZZiAy1Vt7FZFBA7RnIjL64ohdcYHKrjrtDI5EOk5rA39Iu0ANmMJsBfHchjnsUeBSOC3Lok8r1r3mb7C9c1OgaOOgLQy5k/pItAXemfGCNqcbg==</ds:SignatureValue></AuthSignature><body><DataTransfer><DataEncryptionInfo authenticate="true"><EncryptionPubKeyDigest Algorithm="http://www.w3.org/2001/04/xmlenc#sha256" Version="E002">iHehyz6aY84DY6T3ubzm0k/RfvbENVc3yHX8EUm7WdU=</EncryptionPubKeyDigest><TransactionKey>ZX9km6Rg0Fghizh42Z+5VMoyGz9MFtPoBhmzDZq4V1TdBbraESTEpgXusr9vPiOx8uOJ097LWshc7uUNMK44KIo6+n4auaHUgUPnfDY9dsiqYTzdp7W7yZBXNcgWYKDxGOwCK9TZqQEgu+OdXv9GM8JEeT6AqaQwRMALzAaIZVFgxuVnJFc1HqESeoTon4jdPU38JsXSc9ukEVqFkDfYh+DCFYf0moxeBQ6WjJMuAM1GtHZHDXL3UyCoNkInmh3+zucshwcv70d2EcaDT7uHzR8MwFdjYAiLL8urQZcsPF/FNSzUZyWG0kDJWwxFR3G7nxWsF4Dn5s482UELLkJIJg==</TransactionKey></DataEncryptionInfo><OrderData>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</OrderData></DataTransfer><ReturnCode authenticate="true">000000</ReturnCode><TimestampBankParameter authenticate="true">2023-11-30T08:38:11.8835379Z</TimestampBankParameter></body></ebicsResponse>

