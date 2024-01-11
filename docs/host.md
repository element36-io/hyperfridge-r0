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

## Verifier

### Usage of host program

This program processes EBICS (Electronic Banking Internet Communication Standard) responses.
It takes various input parameters, including cryptographic keys and XML data, performs
decryption and authentication operations, and outputs a receipt in JSON format.

#### Command line arguments

To run the host program, you need to provide the following arguments in order:

1. **EBICS Response XML**: The EBICS response in XML format.
2. **Bank Public Key (PEM Format)**: The public key of the bank in PEM format.
3. **User Private Key (PEM Format)**: The private key of the user in PEM format.


The arguments should be provided in the exact order as mentioned above.

#### Example command

Without data from the banking backend and valid keys, the program would not be able to
do something meaningful. So included test data to see how it works:  

```bash
host ../data/test/test.xml ../data/bank_public.pem ../data/client.pem
```

- **`../data/test/test.xml`**- '<ebics_response_xml>': The document provided by the backend of the bank which contains the payload
(bank statements), transaction keys to decrypt the payload and other data singed by the bank.
- **`../data/bank_public.pem`**: The public key of the bank. Due to signing needs, we also need the
private key of the bank to test data.
- **`../data/client.pem`**: The private key of the client which is needed to decrypt the transaction
key of 'text.xml'.

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

See further below for more information on generating the input files.

### Output

Upon successful execution, the program prints a receipt in JSON format stored under 'data/test.xml-Receipt'
'data/<ebics_response_xml>-Receipt'.

### Use as docker image

Find the docker image which contains host, guest and verifier [here][hf-dockerhub].
Images are tagged with risc0 image ID, same tags are used in the [hyperfridge github repo][hf-github].

Call the image with test data:

```bash
docker run e36io/hyperfridge-r0:0.0.0-5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05
```

With own data:

```bash
TODO wasa test& finish
docker run e36io/hyperfridge-r0:v0.2.0-beta.1-5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05 /data/test/test.xml-Receipt

docker run -v /home/w/workspace/hyperfridge-r0/data:/mydata e36io/hyperfridge-r0:5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05 /data2/test/test.xml
```

### Use with binary release (ZIP)

[Download][hf-github] and install binaries - especially the proofing libary because of the "hyperfridge" is RISC-V.

RISC-V is an open standard instruction set architecture (ISA) based on established reduced instruction set computer (RISC) principles.
Many companies are offering or have announced RISC-V hardware; open source operating systems with RISC-V support are available,
and the instruction set is supported in several popular software toolchains like Linux.


### Verify programmatically

Here is an example how to verify in rust:

```rust
#[allow(unused_imports)]
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};

use risc0_zkvm::Receipt;
#[allow(unused_imports)]
use risc0_zkvm::{default_prover, ExecutorEnv};
use std::fs;
use std::env;

const DEFAULT_PROOF_JSON: &str = "../data/test/test.xml-Receipt";


fn main() {
    println!("Start Verify");
    // Get the first argument from command line, if available
    let args: Vec<String> = env::args().collect();
    let binding = DEFAULT_PROOF_JSON.to_string();
    let proof_json_path = args.get(1).unwrap_or(&binding);

    let receipt_json: Vec<u8> = fs::read(proof_json_path)
        .unwrap_or_else(|_| panic!("Failed to read file at {}", proof_json_path));

    let receipt: Receipt = serde_json::from_slice(&receipt_json)
        .expect("Failed to parse proof JSON");
    let result_string = String::from_utf8(receipt.journal.bytes)
        .expect("Failed to convert bytes to string");
    print!("Commitments in receipt: {}", result_string);
}
```

TODO:wasa/dastan- show TOML as well; how to import? Do we need a library?

## Prepare Input Files

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
input files. Working with Ebics XML may be challenging, please reach out if you are stuck.
- [createTestResponse.sh](../data/createTestResponse.sh) This script can is used to generate test data. It creates and
signs documents which usually is generated by the bank, and at the end it calls the script `checkResponse.sh` which
generates the input documents for the verifier.
- [export_primes.sh](../data/export_primes.sh): Exports primes from keys.
- [extract_pems_from_p12.sh](../data/extract_pems_from_p12.sh): Helps to convert key files to the PEM format.

[host]: https://dev.risczero.com/api/zkvm/developer-guide/host-code-101
[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts
[hf-dockerhub]: https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general
[hf-github]: https://github.com/element36-io/hyperfridge-r0
