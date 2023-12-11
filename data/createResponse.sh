
#!/bin/bash
set -e
set -x

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

xml_file="er3.xml-orig"
if [ -z "${xml_file}" ]; then
    echo "xml_file variable is not set. Set to default. ${xml_file}"
    #exit 1
fi

created_file="$xml_file-created"
cp "$xml_file" "$created_file"

echo "response template xml_file: ${xml_file} - created xml file $created_file" 

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
if [ -z "bank.pem" ]; then
    openssl genpkey -algorithm RSA -out bank.pem -pkeyopt rsa_keygen_bits:2048
    echo "new bank keys generated"
fi
if [ -z "client.pem" ]; then
    openssl genpkey -algorithm RSA -out client.pem -pkeyopt rsa_keygen_bits:2048
    echo "new client generated"
fi
if [ -z "transaction_key.bin" ]; then
# 1. Generate a new 128-bit AES key in hexadecimal format
    transaction_key_hex_temp=$(openssl rand -hex 16)
    echo "Generated transaction key (hex): $transaction_key_hex_temp"
        # Convert the hex string to a binary file
    echo "$transaction_key_hex_temp" | xxd -r -p > transaction_key.bin
    echo "new transaction keys generated"
fi

transaction_key_hex=$(xxd -p -c 256 transaction_key.bin | tr -d '\n')
echo "transaction key hex: $transaction_key_hex"

# Encrypt the ZIP file
# Replace 'your_zip_file.zip' with the path to your ZIP file

encrypted_file="orderdata_encrypted.bin"

# Encrypting the ZIP file
openssl enc -e -aes-128-cbc -nopad -in "$decrypted_file" -out "$encrypted_file" -K "$transaction_key_hex" -iv 00000000000000000000000000000000
echo "Encrypted file: $encrypted_file   - convert to base64 nd put it as value into the OrderData Tag "
# echo "Sha256 eynrypted_file: $(sha256sum $encrypted_file)"
# echo "Sha256 decrypted_file: $(sha256sum $decrypted_file)"


base64_encrypted=$(base64 -w 0 "$encrypted_file")
# Use Perl to replace the content inside the OrderData tag
perl -pi -e "s|<OrderData>.*?</OrderData>|<OrderData>$base64_encrypted</OrderData>|s" "$created_file"


# As  next step, encrypt the binary transaction key (bin file) with  public key of client.pem, then base64 it. 
# openssl defaults to PKCS#1, Ebics page 265, process for asymmetrical encryption of the transaction key

# extract public cert form client.pem
openssl rsa -in client.pem -pubout -out client_public.pem
# Encrypt the transaction key with the public key
openssl rsautl -encrypt -pubin -inkey client_public.pem -in transaction_key.bin -out encrypted_transaction_key.bin
# Convert the encrypted key to Base64
base64_encrypted_transaction_key=$(base64 -w 0 encrypted_transaction_key.bin)
# Insert the Base64 encoded encrypted transaction key into the XML file
perl -pi -e "s|<TransactionKey>.*?</TransactionKey>|<TransactionKey>$base64_encrypted_transaction_key</TransactionKey>|s" "$created_file"
echo "Transaction key encrypted and inserted into the XML file. Next calculate DigestValue of all Tags markeed with authenticated=true"


# get all tags with authtenticated= true; then process it according to C14N rulez. 
header_file=$created_file-authenticated
add_namespaces=" xmlns=\"http://www.ebics.org/H003\"" 
perl -ne 'print $1 if /(<header.*<\/header>)/' "$created_file"| xmllint -exc-c14n - | sed "s+<header +<header${add_namespaces} +" > "$header_file"
perl -ne 'print $1 if /(<DataEncryptionInfo.*<\/DataEncryptionInfo>)/' "$created_file"| xmllint -exc-c14n - | sed "s+<DataEncryptionInfo +<DataEncryptionInfo${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<ReturnCode auth.*<\/ReturnCode>)/' "$created_file" | xmllint -exc-c14n - | sed "s+<ReturnCode +<ReturnCode${add_namespaces} +" >> "$header_file"
perl -ne 'print $1 if /(<TimestampBankParameter.*<\/TimestampBankParameter>)/' "$created_file" | xmllint -exc-c14n - | sed "s+<TimestampBankParameter +<TimestampBankParameter${add_namespaces} +" >> "$header_file"

echo "size of authenticate file:" $(stat --format="%s" "$header_file")
calculated_digest_hex=$( openssl dgst -sha256 -r $header_file | cut -d ' ' -f 1 )
echo calculated digest headertag hex: $calculated_digest_hex
# Put the digest into the document
perl -pi -e "s|<ds:DigestValue>.*?</ds:DigestValue>|<ds:DigestValue>$digest_value</ds:DigestValue>|s" "$created_file"


# Now we need to produce the "SingedInfo" Text and sign the tings which are wrapped by the  <ds:SignedInfo> tag
# first extract SignedInfo Tag and do C14N

export add_namespaces=" xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\""
# need to be 2 steps, because xmllint would remove this unneeded one but the standard sais all top-level need to be included 
export add_namespaces2=" xmlns=\"http://www.ebics.org/H003\""
perl -ne 'print $1 if /(<ds:SignedInfo.*<\/ds:SignedInfo>)/' "$created_file" | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces}+" | xmllint -exc-c14n - | sed "s+<ds:SignedInfo+<ds:SignedInfo${add_namespaces2}+" > "${created_file}-SignedInfo"
signedinfo_digest_file="/tmp/signedinfo_digest_$timestamp.bin"
openssl dgst -sha256 -binary  "${created_file}-SignedInfo" > "$signedinfo_digest_file"
echo "created digest for SignedInfo from XML, now creating Signature"


signature_output_file="signature-output-file.bin"
# Create a signature
openssl pkeyutl -sign -inkey "bank.pem" -in "$signedinfo_digest_file" -out "$signature_output_file" -pkeyopt rsa_padding_mode:pkcs1 -pkeyopt digest:sha256

# Convert the signature to Base64
base64_signature=$(base64 -w 0 "$signature_output_file")

# Replace the <ds:SignatureValue> content in the XML file
perl -pi -e "s|<ds:SignatureValue>.*?</ds:SignatureValue>|<ds:SignatureValue>$base64_signature</ds:SignatureValue>|s" "$created_file"

echo "Signature inserted into the XML file."
