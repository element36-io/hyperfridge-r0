#!/bin/bash

# Function to convert hex to binary and write to file
convert_to_bin() {
    local hex_string=$1
    local output_file=$2

    # Remove colons and new lines, then convert hex to binary
    echo -n "$hex_string" | tr -d ':\n' | xxd -r -p > "$output_file"
}

# Default PEM file
PEM_FILE="e002_private_key.pem"

# Override default file if parameter is provided
if [ ! -z "$1" ]; then
    PEM_FILE="$1"
fi

# Check if the PEM file exists
if [ ! -f "$PEM_FILE" ]; then
    echo "PEM file not found: $PEM_FILE"
    exit 1
fi

# Extract data using OpenSSL
openssl_output=$(openssl rsa -in "$PEM_FILE" -text )

# Parsing each section and converting to .bin files
convert_to_bin "$(echo "$openssl_output" | awk '/modulus:/{flag=1;next}/publicExponent:/{flag=0}flag')" "modulus.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/privateExponent:/{flag=1;next}/prime1:/{flag=0}flag')" "privateExponent.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/prime1:/{flag=1;next}/prime2:/{flag=0}flag')" "prime1.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/prime2:/{flag=1;next}/exponent1:/{flag=0}flag')" "prime2.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/exponent1:/{flag=1;next}/exponent2:/{flag=0}flag')" "exponent1.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/exponent2:/{flag=1;next}/coefficient:/{flag=0}flag')" "exponent2.bin"
convert_to_bin "$(echo "$openssl_output" | awk '/coefficient:/{flag=1;next}/writing/{flag=0}flag')" "coefficient.bin"



echo "Conversion completed."
