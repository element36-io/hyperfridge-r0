# How to generate a proof

## Overview

The [host][host] code is responsible to create a proof (aka [receipt][receipt]), which
is the output of running the host code. Anyone can read the receipt (a simple json) and 
validate it with a "verifier". If the receipt is validated it means, that the code which
produced the receipt was not tempered and produced what it meant to produce.

Here we describe how to create a receipt which can prove the data like balance, transaction or
even portfolios (stocks) any bank account supporting a specific banking standards.

So if you are holder of a bank account, hyperfridge offers a tool to prove this data - most
importingly to other systems or ledgers with Smart Contracts. As a result, you can
use Smart Contracts to "wrap" functionality around TradFi accounts, similar like you can
do it today with blockchain wallets and cryptocurrencies.


## Verfier

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
do somehting meaningful. So included test data to see how it works:  

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

### Output

Upon successful execution, the program prints a receipt in JSON format stored under 'data/test.xml-Receipt'
'data/<ebics_response_xml>-Receipt'.


### Use as docker image

Find the docker image wich contains host, guest and verififer [here][hf-dockerhub].
Images are tagged with risc0 image ID, same tags are used in the [hyperfridge github repo][hf-github].

Call the image with test data:

```bash
docker run e36io/hyperfridge-r0:0.0.0-5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05
```

With own data:

```bash
docker run e36io/hyperfridge-r0:0.0.0-5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05 /data/test/test.xml-Receipt

docker run -v /home/w/workspace/hyperfridge-r0/data:/mydata e36io/hyperfridge-r0:5dc027519ae151903285c5b964d51643193131426f131c16cff31a8e7bd56c05 /data2/test/test.xml
```

### Use with binary release (ZIP)


### Verfiy programmatically

Here is an example how to verify in rust: 

```rust
#[allow(unused_imports)]
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};

use risc0_zkvm::Receipt;
#[allow(unused_imports)]
use risc0_zkvm::{default_prover, ExecutorEnv};
use std::fs;

const PROOF_JSON: &str = "../data/test/test.xml-Receipt";

fn main() {
    println!("Start Verify");
    let receipt_json: Vec<u8> = fs::read(PROOF_JSON).expect("Failed to read transaction key file");

    let receipt: Receipt =
        serde_json::from_slice(receipt_json.as_slice()).expect("Failed to parse proof JSON");
    let result_string =
        String::from_utf8(receipt.journal.bytes).expect("Failed to convert bytes to string");
    print!(" commitments in receipt {}", result_string);
}

```

TODO:wasa/data- show TOML as well; how to import? Do we need a library?


## Prepare Input Files




## References

[host]: https://dev.risczero.com/api/zkvm/developer-guide/host-code-101
[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts
[hf-dockerhub]: https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general
[hf-github]: https://github.com/element36-io/hyperfridge-r0
