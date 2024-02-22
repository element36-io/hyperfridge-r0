# How to generate a proof

## Overview

The [host][host] code is responsible for creating a proof (aka [receipt][receipt]), which
is the output of running the host code. Anyone can read the receipt (a simple json) and
validate it with a "verifier". If the receipt is validated it means that the code which
produced the receipt was not tempered and produced what it was meant to produce.

Here we describe how to create a receipt which can prove the data like balance, transaction or
even portfolios (stocks) any bank account supporting a specific banking standard.

So if you are a holder of a bank account, hyperfridge offers a tool to prove this data - most
importantly to other systems or ledgers with Smart Contracts. As a result, you can
use Smart Contracts to "wrap" functionality around TradFi accounts, similar like you can
do it today with blockchain wallets and cryptocurrencies.

## Create a STARK proof with host program

### Usage of host program

This program processes EBICS (Electronic Banking Internet Communication Standard) responses.
It takes various input parameters, including cryptographic keys and XML data, performs
decryption and authentication operations, and outputs a receipt in JSON format.

#### Command line arguments

To run the host program, you need to provide the following arguments in order:

1. **EBICS Response XML**: The EBICS response in XML format.
2. **Bank Public Key (PEM Format)**: The public key of the bank in PEM format.
3. **User Private Key (PEM Format)**: The private key of the user in PEM format.
4. **Witness Private Key (PEM Format)**: The public key of the witness in PEM format.

See [Testing Guide](INSTRUCTIONS.md) for exmples how to use the command line. 

#### Files required

We try to offload as much computation from the proofing algorithm as possible to make it fast.
Therefore we process and data outside and feed it to the proof. Thus host program requires several
files, which should be named and placed according to the conventions described below:

- **`<ebics_response_xml>-decrypted_tx_key.binary`**: The decrypted transaction key binary file.
- **`<ebics_response_xml>-SignedInfo`**: The Canonical XML (C14N) of the SignedInfo element.
- **`<ebics_response_xml>-authenticated`**: The Canonical XML (C14N) of the authenticated data.
- **`<ebics_response_xml>-SignatureValue`**: The XML file containing the signature value.
- **`<ebics_response_xml>-OrderData`**: The XML file containing the order data.
- **`<ebics_response_xml>-DataDigest`**: The XML file containing the data digest of the order data.

Replace `<ebics_response_xml>` with the path and base name of your EBICS response XML file. For instance,
if your EBICS response XML file is `../data/test/test.xml`, the decrypted transaction key should be
named `../data/test/test-decrypted_tx_key.binary`.


### Output of the Receipt

Upon successful execution, the program prints a receipt in JSON format stored under `data/test.xml-Receipt/` where test.xml is replaced by the filename of your EbicsResponse XML document.

### How to use

Find the docker image which contains host, guest and verifier [here][hf-dockerhub]. Images are tagged with risc0 image ID, same tags are used in the [hyperfridge github repo][hf-github]. Check out [Testing Guide](INSTRUCTIONS.md) how to use hyperfridge with docker and command line.

### Verify programmatically

Here is an example how to verify in rust:

```rust

    let receipt_json: Vec<u8> = fs::read(proof_json_path)
        .unwrap_or_else(|_| panic!("Failed to read file at {}", proof_json_path));

    let receipt: Receipt = serde_json::from_slice(&receipt_json)
        .expect("Failed to parse proof JSON");

    receipt
        .verify(image_id_array) // image-id, hex converted to byte
        .unwrap_or_else(|_| panic!("verify failed with image id: {}", &image_id_hex));

    let result_string = String::from_utf8(receipt.journal.bytes)
        .expect("Failed to convert bytes to string");

```

### Standards involved

- [EBICS](http://www.ebics.org) describes the transport protocol of the bank and how elements are signed or hashed - hyperfridge has
implemented E002, A005, adding others (like A006) should be trivial.    
- [ISO20022](https://www.iso20022.org/): After data has been transmitted and decrypted,
bank data is represented via XML documents following the ISO20022 standard.
- [XML Signature](http://www.w3.org/2000/09/xmldsig#): Defines the standard how to sign areas of an XML document. EBICS uses this
standard to encrypt, hash or sign data.
- [XML C14N (canonization)](http://www.w3.org/TR/2001/REC-xml-c14n-20010315):
For hashing, it describes how to come up with a canonised presentation. C14N (canonization) of XML:
The standard does not remove blanks between tags, e.g.
`<tag>some value</tag>   <tag>other value</tag>` would keep the blanks. A consequence is,
that if you have a document and then a DOM created, then this "information" is lost.
This means, that we need to retain the blanks which are used by the bank in order to
compute correct hashes for areas which are marked with the attribute authenticated="true".
But when we concatenate all tags with that attribute we need to remove the blanks.
Another remark to XML Namespaces: The C14N algorithm also foresees to "copy" namespace declarations from
parent tags.
- [XML Encryption Syntax and Processing](http://www.w3.org/2001/04/xmlenc#sha256):
This document specifies a process for encrypting data and representing the result in XML

### checkResponse.sh and other supporting scripts

- [checkResponse.sh](../data/checkResponse.sh) This script can be used to pre-check signatures and to create the necessary
input files. Working with EBICS XML may be challenging, please reach out if you are stuck.
- [createTestResponse.sh](../data/createTestResponse.sh) This script can is used to generate test data. It creates and
signs documents which usually is generated by the bank, and at the end it calls the script `checkResponse.sh` which
generates the input documents for the verifier.
- [export_primes.sh](../data/export_primes.sh): Exports primes from keys.
- [extract_pems_from_p12.sh](../data/extract_pems_from_p12.sh): Helps to convert key files to the PEM format.

[host]: https://dev.risczero.com/api/zkvm/developer-guide/host-code-101
[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts
[hf-dockerhub]: https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general
[hf-github]: https://github.com/element36-io/hyperfridge-r0
