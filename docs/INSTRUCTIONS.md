# Testing Guide

This document describes in-depth our rust-modules and the zero-knowledge proof, and how to run various tests.

For better understanding, lets look at roundtrip of the proofing system:

1. Request and retrieval of banking documents with daily statements (EBICS request and response) through an EBICS banking client, e.g. [ebics-java-client]. The client
2. Pre-Processing of the EBICS Response, which is an XML document. Pre-processing is necessary to off-load as much as possible from expensive proof-generation and to keep the proof-code flexible. Pre-processing is done with script 'data/checkResponse.sh'
3. Present data from the previous step and the private key of the client to the prover, and generate proof of computation (a STARK) and produce the [Receipt] which contains balance, currency date and account-number.
4. A generic risc0 based verifier can check the proof, thus the above account data can be trusted.
5. On-chain integration (validation) of the proof-system using the Substrate Off-Chain-Worker. 

**Important note**: [Milestone 1](https://github.com/w3f/Grants-Program/blob/master/applications/hyperfridge.md#milestone-1---risk-zero-zkp-implementation-based-on-static-test-data) only covers work around generating and validating the STARK with the Risk-Zero framework - so "1." is not included yet - this will be done in milestone 2. Starting with milestone 3 integration with substrate gets implemented.


## Releases and installation

The binary distribution can be downloaded from [github](https://github.com/element36-io/hyperfridge-r0/releases). Docker containers are on [dockerhub](https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general). It is crucial to understand the concept of a "sealed" binary. Means, that the (RiscV) binary producing the STARK is pinned by its hash ("Image-ID"). Proofs can only be validated if you know the Image-Id, that is why we included the Image-ID in the releases and docker tags and as a file (IMAGE_ID.hex) in the distributions.


### Preparations

If you are using the binary distribution make sure you are running a glibc compatible environment and necessary tools are installed to run the scripts for pre-processing the EBICS Response. On debian based systems you may use `apt install -y openssl perl qpdf xxd libxml2-utils` - versions are given only as FYI.

```bash
ldd /bin/bash #  linux-vdso.so.1 (0x00007ffc33bee000) ....
opennssl version # output, e.g. OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
xxd --version # xxd 2021-10-22 by Juergen Weigert et al.
zlib-flate --version # zlib-flate from qpdf version 10.6.3
xmllint --version # xmllint: using libxml version 20913
perl --version # 5 Version 34


***Note:*** You may remove `RISC0_DEV_MODE=true` variable to create a real proof, expect the execution time to be several hours to create the STARK. You may add `--verbose` after each command (host or verifier) to see what is going on. Use `RUST_BACKTRACE=1` to debug.

#### Use with docker

```
Using docker, make sure its installed:
```bash
docker --version # output, e.g. Docker version 24.0.7, build afdd53b
```

Label the [hyperfridge container from dockerhub](https://hub.docker.com/r/e36io/hyperfridge-r0/tags) you want to use with a shortcut "fridge" for later usage:
```bash
docker pull e36io/hyperfridge-r0:latest
docker tag  e36io/hyperfridge-r0:latest fridge
# no output is given by docker
```

Or test with docker using your local container build:

```bash
docker  build . -t fridge
```

#### Use with command line

Download binary realease from this repo, unzip the realese. Test your installation by showing the command line help:

```bash
host --help
# or with docker
docker run fridge host --help
# output should show command line parameters: Usage: host [OPTIONS] [COMMAND] ...
```

### Integration tests with provided test data

We included all test data which is necessary to run a quick shake-down test to generate and validate a proof in one go. This creates a proof based on test data, prints the JSON-receipt which is the STARK-proof and contains public and committed data. Steps "3." and "4." of the roundtrip are tested in that way.


```bash
# The test generates a proof and validates it
RISC0_DEV_MODE=true host test 
# or with docker: 
docker run --env RISC0_DEV_MODE=true  fridge host test
```

You may create new keys, additional test data and payload which is described [here](testdata.md).

### Create dev receipt (STARK proof)

With binaries:

```bash
# show help
host prove-camt53 --help

# create the proof
RISC0_DEV_MODE=true ./host prove-camt53 \
    --request="../data/test.xml" --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem \
    --clientiban CH4308307000289537312
```

Using docker:

```bash
# show help
docker run fridge host prove-camt53 --help

# create the proof
docker run --env RISC0_DEV_MODE=true  fridge host prove-camt53 \
    --request=../data/test/test.xml --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem \
    --clientiban CH4308307000289537312
```


### Check Receipt (STARK proof)

With binaries:

```bash
# show help
./verifier verify  --help

# we need the image id and the receipt
imageid=$(cat IMAGE_ID.hex)
proof=../data/test/test.xml-Receipt-$imageid-latest.json
      ../data/test/test.xml-Receipt-6bb958072180ccc56d839bb0931c58552dc2ae4d30e44937a09d3489e839edfb-latest.json 

./verifier verify --imageid-hex=$imageid --proof-json=$proof

# also host program can verify: 

```

With docker:

```bash
# show help
docker run fridge verifier verify  --help

# we need the image id and the receipt
imageid=$(docker run fridge cat /app/IMAGE_ID.hex)
proof=/data/test/test.xml-Receipt-test.json

# check the proof
docker run --env RISC0_DEV_MODE=true  fridge verifier verify --imageid-hex=$imageid --proof-json=$proof
```


## Tests in rust environment

We assume you have [installed rust](https://github.com/element36-io/ocw-ebics/blob/main/docs/rust-setup.md) and [risk zero environment](https://dev.risczero.com/api/zkvm/install).


### Unit tests

Unit tests for the host program in `host` will create receipt for the test data:

```bash
cd host
RISC0_DEV_MODE=true cargo test  -- --nocapture
```

Most important, run unit test for the guest code in directory `methods/guest`:

```bash
cd methods/guest
RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture 
```

For running the tests with a new ebics response, lets copy the existing into a new file, then we create the proof for it: 

```bash
# simulates the download of ebics file
cd data
mkdir myrequest
cp response_template.xml myrequest.xml
cp -r response_template/camt53 myrequest
# you may edit the myrequest and payload in ../data/myrequest/camt53 now

# Data above needs to be compressed, signed etc.
# Create the signed ebics response and pre-process data for proofing:
xml_file=myrequest.xml ./createTestResponse.sh

# now create the proof
# note that the proof needs the singed file:  --request="../data/myrequest-generated/myrequest-generated.xml"
cd ../host
RISC0_DEV_MODE=true \
cargo run  -- --verbose prove-camt53  \
   --request="../data/myrequest-generated/myrequest-generated.xml"  --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312

# You see receipt in output of the command and serialized in a json file: 
 ls -la ../data/myrequest-generated/*.json
 cat ../data/myrequest-generated/*.json
```

Now let's try to create a fake proof - we will point to a wrong public keys where the verification of signatures should fail:

```bash
# note that we use witness key for bank: --bankkey ../data/pub_witness.pem
cd host
RISC0_DEV_MODE=true \
cargo run  -- --verbose prove-camt53  \
    --request="../data/myrequest-generated/myrequest-generated.xml" --bankkey ../data/pub_witness.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
# panics, output: 
# verify bank signature
# ---> error Verification

# note that we use bank key for witness: --witnesskey ../data/pub_bank.pem 
RISC0_DEV_MODE=true \
cargo run  -- --verbose prove-camt53  \
    --request="../data/myrequest-generated/myrequest-generated.xml" --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_bank.pem --clientiban CH4308307000289537312
# panics, output: 
# verify the verify_order_data_signature by witness
# ---> error Verification

```

### Create real receipt with CUDA (hardware acceleration)

Note that `RISC0_DEV_MODE=false` and add feature "cuda" to `host/Cargo.toml`.
```bash
cd ../host
RISC0_DEV_MODE=false \
cargo run -f cuda -- --verbose prove-camt53  \
   --request="../data/myrequest-generated/myrequest-generated.xml"  --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
```

Use verifier to check the receipt, move to `verifier` directory:

```bash
cd verifier
# we need the image ID which is part of the binary package name and versioning, but
# here we take it from the host
imageid=$(cat ../host/out/IMAGE_ID.hex)
# get the filename of the proof
proof=$(find ../data/myrequest-generated/ -type f -name "*.json" | head -n 1)

# verifies the proofs and shows public inputs and commitments:
RISC0_DEV_MODE=true \
cargo run  -- --verbose verify  \
    --imageid-hex=$imageid --proof-json=$proof

```

### Notes on provided test data

The test data was taken from the productive systems (Hypo Lenzburg), decrypted and encrypted again with generated keys as it can be seen in scripts `data/createTestResponse.sh` and `data/checkResponse.sh`. A productive sample has been added to `data/test/test.xml (prod).zip`, the payload of test data remained unchanged from the productive system.

[ebics-java-client2]: [references.json#ebics-java-client]
[r0-dev-mode]: [references.json#r0-dev-mode]