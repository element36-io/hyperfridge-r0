# Testing Guide

This document describes in-depth our rust-modules and the zero-knowledge proof, and how to run various tests.

For better understanding, lets look at roundtrip of the proofing system:

1. Request and retrieval of banking documents with daily statements (Ebics request and response) through an Ebics banking client, e.g. [ebics-java-client]. The client
2. Pre-Processing of the Ebics Response, which is an XML document. Pre-processing is necessary to off-load as much as possible from expensive proof-generation and to keep the proof-code flexible. Pre-processing is done with script 'data/checkResponse.sh'
3. Present data from previous step and the private key of the client to the proover, and generate proof of computation (a STARK) and produce the [Receipt] which contains balance, currency date and accountnumber.
4. A generic risc0 based verifier can check the proof, thus the above account data can be trusted.
5. On-chain integration (validation) of the proof-system using the Substrate Off-Chain-Worker. 

**Important note**: [Milestone 1](https://github.com/w3f/Grants-Program/blob/master/applications/hyperfridge.md#milestone-1---risk-zero-zkp-implementation-based-on-static-test-data) only covers work around generating and validating the STARK with the Risk-Zero framework - so "1." is not included yet - this will be done in milestone 2. Starting with milestone 3 integration with substrate gets implemented.


## Releases and installation

The binary distribution can be downloaded from [github](https://github.com/element36-io/hyperfridge-r0/releases). Docker containers are on [dockerhub](https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general). It is crucial to understand the concept of a "sealed" binary. Means, that the (RiscV) binary producing the STARK is pinned by its hash ("Image-ID"). Proofs can only validated if you know the Image-Id, that is why we included the Image-ID in the releases and docker tags and as a file (IMAGE_ID.hex) in the distributions.


### Preparations

If you are using the binary distribution make sure you are running a glibc compatible environment and necessary tools are installed to run the scripts for pre-processing the Ebics Response. On debian based systems you may use `apt install -y openssl perl qpdf xxd libxml2-utils` - versions are given only as FYI.

```bash
ldd /bin/bash #  linux-vdso.so.1 (0x00007ffc33bee000) ....
opennssl version # output, e.g. OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
xxd --version # xxd 2021-10-22 by Juergen Weigert et al.
zlib-flate --version # zlib-flate from qpdf version 10.6.3
xmllint --version # xmllint: using libxml version 20913
perl --version # 5 Version 34

```

Usiing docker, make sure its installed:
```bash
docker --version # output, e.g. Docker version 24.0.7, build afdd53b
```

Label the container you want to use with a shortcut "fridge" for later usage:
```bash
docker tag e36io/hyperfridge-r0:v0.0.3-6f416022c36c94602d7f6a41c878374b5177207c0a75e65661cc053f5afa9ddf fridge
# no output is given by docker
```

Test your installation by showing the command line help:

```bash
host --help
# or with docker
docker run fridge host --help
# output should show command line parameters: Usage: host [OPTIONS] [COMMAND] ...
```

### Integration tests with provided test data

We included all test data which is necessary to run a quick shake-down test to generate and validate a proof in one go. This creates a proof based on test data, prints the JSON-receipt which is the STARK-proof and contains public and committed data. Steps "3." and "4." of the rountrip are tested in that way.

*Note:* You may remove `RISC0_DEV_MODE=true` variable to create a real proof, expect the execution time to be several hours to create the STARK. You may add `--verbose` afer each command (host or verifier) to see what is going on. 

```bash
host test 
# or with docker: 
docker run --env RISC0_DEV_MODE=true  fridge host test
```

You may create new keys, additional test data and payload which is described [here](testdata.md).

## Tests in rust environment

We assume you have [installed rust](https://github.com/element36-io/ocw-ebics/blob/main/docs/rust-setup.md) and [risk zero environment](https://dev.risczero.com/api/zkvm/install).


### Unit tests

Unit tests for the host program in `host` will create receipt for the test data:

```bash
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  -- --nocapture
```

Most important, run unit test for the guest code in directory `methods/guest`:

```bash
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture 
```

Run the tests on your own data with: 

```bash
cd ./host
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose prove-camt53  --request="/data/test/test.xml" --bankkey ../data/pub_bank.pem --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312 --script=../data/checkResponse.sh


RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- ../data/test/test.xml ../data/bank_public.pem ../data/client.pem CH4308307000289537312 > "create-receipt-$(date).log"

```


This will create a directory with the name of the Ebics response XML file and puts all files in there, prefixed by the name of the ebics file: `./test.xml/test-xml-*`.

### Creating the Receipt

For proof of computation is crucial to identify the guest-code which produced the receipt with its unique hash.
With a public repo anyone can re-produce the hash thus we can validate the code which produced the proof. 
With the receipt (STARK-proof), the hash of the proofing code ("guest-code") and the source of the guest-code, 
we are able to check non-interactively the output of the receipt - in our case the balance of a 
specific bank account at a specific time. 


```bash
host --verify -verbose --response=./mytest/mytest.xml 
# or with docker: 
TODO: wasa
```

The receipt is stored in `mytest/mytest.xml-Receipt`. I you want to modify the payload as well, see [further down](#generate-new-test-data).

### Validate the Receipt

We added validator which has no dependencies to hyperfridge - but the `host` program also 
does validation with parameter `--validate`.

Download the validator from: TODO. Copy the my
```bash
TODO
# or with docker: 
docker run TODO ./verifier verify ../data/mytest/mytest.xml-Receipt
```



### Proofing workflow with provided test data

The test data was taken from the productive systems (Hypo Lenzburg), decrypted and
encrypted again with generated keys as it can be seen in scripts `data/createTestResponse.sh`
and 'data/checkResponse'. A productive sample has been added to `data/test/test.xml (prod).zip`,
the payload of test data remained unchanged from the productive system.

Assumptions:

- Ebics response has been downloaded and stored under 'data/test/test.xml'.
- Working directory `./data` - change directory into that.
- All examples use [`RISC0_DEV_MODE=true`][r0-dev-mode] - the parameter can be reomved, but creating the proof will
take substantial amount of time (about 2 hours depending on your machine).
- For the examples with docker working directory is `/`.

### Simulate Ebics Response

Copy the test data into a new directory.
Remmark: In production the file would be provided by an Ebics client.

```bash
mkdir ./data/mytest
cp ./data/test/test.xml ./data/mytest.xml
```
Now you may create a new receipt as [shown before](#creating-the-receipt).



[ebics-java-client2]: [references.json#ebics-java-client]
[r0-dev-mode]: [references.json#r0-dev-mode]