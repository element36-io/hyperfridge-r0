#!/bin/bash

prkey_file="28953700.p12"
prkey_pwd=""

openssl pkcs12 -in "${prkey_file}" -nocerts -nodes -out all_private_keys.pem -password pass:${prkey_pwd} -nomacver -provider legacy 
head -n 32 all_private_keys.pem > e002_private_key.pem 
#tail -n +65 all_private_keys.pem | head -n 32 > e002_private_key.pem
