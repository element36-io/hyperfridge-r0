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
```bash
program ../data/test/test.xml ../data/bank_public.pem ../data/client.pem

### Use as docker image


### Use with binary release (ZIP)


### Verfiy programmatically



## Prepare Input Files


## References

[host]: https://dev.risczero.com/api/zkvm/developer-guide/host-code-101
[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts