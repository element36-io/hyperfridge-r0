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

### Usage

#### Command Line Arguments

To

1. **Bank Public Key (PEM Format)**: The public key of the bank in PEM format.
2. **User Private Key (PEM Format)**: The private key of the user in PEM format.
3. **EBICS Response XML**: The EBICS response in XML format.

The arguments should be provided in the exact order as mentioned above.

#### Example Command

Without data from the banking backend and valid keys, the program would not be able to
do somehting meaningful. So included test data to see how it works:  

```bash
host ../data/test/test.xml ../data/bank_public.pem ../data/client.pem
```


- **`../data/test/test.xml`**: The document provided by the backend of the bank which contains the payload
(bank statements), transaction keys to decrypt the payload and other data singed by the bank.
- **`<../data/bank_public.pem`**: The public key of the bank. Due to signing needs, we also need the
private key of the bank to test data. 
- **`<.../data/client.pem`**: The private key of the client which is needed to decrypt the transaction
key of 'text.xml'.

#### Files Required

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
if your EBICS response XML file is `../data/test/test.xml`, the decrypted transaction key should be named `../data/test/test-decrypted_tx_key.binary`.

## Output
Upon successful execution, the program prints a receipt in JSON format to the standard output (stdout).

### Use as docker image


### Use with binary release (ZIP)


### Verfiy programmatically



## Prepare Input Files


## References

[host]: https://dev.risczero.com/api/zkvm/developer-guide/host-code-101
[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts