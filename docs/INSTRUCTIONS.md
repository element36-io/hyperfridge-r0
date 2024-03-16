# Testing Guide

This document describes in-depth our rust-modules and the zero-knowledge proof, and how to run various tests.

For better understanding, lets look at roundtrip of the proofing system:

1. Request and retrieval of banking documents with daily statements (EBICS request and response) through an EBICS banking client, e.g. [ebics-java-client]. The client
2. Pre-Processing of the EBICS Response, which is an XML document. Pre-processing is necessary to off-load as much as possible from expensive proof-generation and to get a small footprint of the proof-code. Pre-processing is done with script 'data/checkResponse.sh'
3. Present data from the previous step and the private key of the client to the prover, and generate proof of computation (a STARK) and produce the [Receipt] which contains balance, currency date and account-number.
4. A generic risc0 based verifier can check the proof, thus the above account data can be trusted.
5. On-chain integration (validation) of the proof-system using the Substrate Off-Chain-Worker.

**Important note**: [Milestone 1](https://github.com/w3f/Grants-Program/blob/master/applications/hyperfridge.md#milestone-1---risk-zero-zkp-implementation-based-on-static-test-data) only covers step 2. and 3., generating and validating the STARK with the Risk-Zero framework - other steps will be done in later milestones. Starting with milestone 3 integration with substrate gets implemented.

***Note:*** You may remove `RISC0_DEV_MODE=true` variable to create a real proof, expect the execution time to be several hours to create the STARK. You may add `--verbose` after each command (host or verifier) to see what is going on. Use `RUST_BACKTRACE=1` to debug.

***Note for MacOS***: Images on Dockerhub are built locally and pushed to dockerhub due to restriction of github-actions. If a certain version is needed on MacOs which was not pushed to dockerhub, build the image locally with `docker  build . -t fridge` or using the Script `buildPublish.sh` to pushlish a release to github or dockerhub. See [MacOS Development](macos.md) for help to give some guidance for the development environment in MacOS. 


[![codecov](https://codecov.io/gh/element36-io/hyperfridge-r0/graph/badge.svg?token=JNQZL1G2OM)](https://codecov.io/gh/element36-io/hyperfridge-r0) 
Remark on code coverage: Module `methods/guest` can not be shown because the Risc-Zero framework compiles to Risc V instruction set.

## Test with Docker

Docker containers are on [dockerhub](https://hub.docker.com/repository/docker/e36io/hyperfridge-r0/general). It is crucial to understand the concept of a "sealed" binary. Means, that the (RiscV) binary producing the STARK is pinned by its hash ("Image-ID"). Proofs can only be validated if you know the Image-Id, that is why we included the Image-ID in the releases and docker tags and as a file (IMAGE_ID.hex) in the distributions.

### Preparations for using Docker

Use bash: 

```bash
bash
echo $0 
# output: bash ..
```

We are using docker, make sure its installed:

```bash
docker --version 
# output, e.g. Docker version 24.0.7, build afdd53b
```

Label the [hyperfridge container from dockerhub](https://hub.docker.com/r/e36io/hyperfridge-r0/tags) you want to use with a shortcut "fridge" for later usage:

On **Linux**:

```bash
docker pull e36io/hyperfridge-r0:latest
docker tag  e36io/hyperfridge-r0:latest fridge
# no output is given by docker
```

On **MacOS**:

```bash
docker pull e36io/hyperfridge-r0:macos-latest
docker tag  e36io/hyperfridge-r0:macos-latest fridge
# no output is given by docker
```

Or test with docker using your local container build if your machine is not supported by our docker images:

```bash
# optional, don't do this for first tests unless you know what you are doing
docker  build . -t fridge
```

### Integration tests with provided test data

We included all test data which is necessary to run a quick shake-down test to generate and validate a proof in one go. This creates a proof based on test data, prints the JSON-receipt which is the STARK-proof and contains public and committed data. Steps "3." and "4." of the roundtrip are tested in that way.

```bash
# The test generates a proof and validates it
docker run --env RISC0_DEV_MODE=true  fridge host test
```

The output 

### Create a receipt (STARK proof)

Show help output: 

```bash
# show help
docker run fridge host prove-camt53 --help
```

Create the proof as JSON file, which can be deserialized and verified in Rust:

```bash
# create the proof
docker run --env RISC0_DEV_MODE=true  fridge host prove-camt53 \
    --request=../data/test/test.xml --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem \
    --clientiban CH4308307000289537312
```


### Check Receipt (STARK proof)

Show help:

```bash
# show help
docker run fridge verifier verify  --help
```

Verify a receipt (json-file) and show its contents (public commitments):

```bash
# we need the image id and the receipt
imageid=$(docker run fridge cat /app/IMAGE_ID.hex)
proof=/data/test/test.xml-Receipt-$imageid-latest.json

# check the proof
docker run --env RISC0_DEV_MODE=true  fridge verifier verify --imageid-hex=$imageid --proof-json=$proof
```

## Only Linux: Test with binary Release and command line

The binary distribution can be downloaded from [github](https://github.com/element36-io/hyperfridge-r0/releases). To understand versioning concept, is crucial to understand the concept of a "sealed" binary. Means, that the (RiscV) binary producing the STARK is pinned by its hash ("Image-ID"). Proofs can only be validated if you know the Image-Id, that is why we included the Image-ID in the releases and docker tags and as a file (IMAGE_ID.hex) in the distributions.

### Preparations for command line and scripts

Download binary realease from this repo, unzip the release to ./bin. Test your installation by cd-ing to bin and showing the command line help:

```bash
./host --help
# output should show command line parameters: Usage: host [OPTIONS] [COMMAND] ...
```

Get Image-ID of the linked guest code:

```bash
./host show-image-id
# output, e.g.: a54af3e5a903cc5d80f900f12785a337c1872098c2aacf0b7de28d7b8d6c3fe6
```

We included all test data in `data` directory which is necessary to run a quick shake-down test to generate and validate a proof in one go. This creates a proof based on test data, prints the JSON-receipt which is the STARK-proof and contains public and committed data. Steps "3." and "4." of the roundtrip are tested in that way.

```bash
# The test generates a proof and validates it
RISC0_DEV_MODE=true ./host test 
```

You may create new keys, additional test data and payload which is described [here](testdata.md).

### Create dev receipt (STARK proof)

In the app directory:

```bash
# show help
./host prove-camt53 --help
```

```bash
# create the proof
RISC0_DEV_MODE=true ./host prove-camt53 \
    --request ../data/test/test.xml --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem \
    --clientiban CH4308307000289537312
```

### Check Receipt (STARK proof)

In the app directory of the binary distribution:

```bash
# show help
./verifier verify  --help
```

Verify the proof:

```bash
# we need the image id and the receipt
./host show-image-id > IMAGE_ID.hex
imageid=$(cat IMAGE_ID.hex)
proof=../data/test/test.xml-Receipt-$imageid-latest.json
echo verify with $imageid
RISC0_DEV_MODE=true  ./verifier verify --imageid-hex=$imageid --proof-json=$proof
```

## Tests in Rust-development environment (Linux and MacOs)

We assume you have [installed rust](https://github.com/element36-io/ocw-ebics/blob/main/docs/rust-setup.md) and [risk zero environment](https://dev.risczero.com/api/zkvm/install). Check with `rustup toolchain list --verbose | grep risc0`. Clone project: `git clone git@github.com:element36-io/hyperfridge-r0.git`.

### Unit tests

Unit tests for the host program in `host` will create receipt for the test data:

```bash
cd hyperfridge-r0
cd host
RISC0_DEV_MODE=true cargo test  -- --nocapture
```

Most important, run unit test for the guest code in directory `methods/guest`:

```bash
cd ..
cd methods/guest
RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture 
```

## Create own test data

### Use local development environment on Linux

If you are using the binary distribution make sure you are running a glibc compatible environment and necessary tools are installed to run the scripts for pre-processing the EBICS Response. On debian based systems you may use `apt install -y openssl perl qpdf xxd libxml2-utils inotify-tools` - versions are given only as FYI, we are not aware of any version related dependencies. 
 
Check if those commands are available/installed on **Linux**

```bash
apt install -y openssl perl qpdf xxd libxml2-utils inotify-tools`
ldd /bin/bash #  linux-vdso.so.1 (0x00007ffc33bee000) ....
opennssl version # output, e.g. OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
xxd --version # xxd 2021-10-22 by Juergen Weigert et al.
zlib-flate --version # zlib-flate from qpdf version 10.6.3
xmllint --version # xmllint: using libxml version 20913
perl --version # 5 Version 34
rustup toolchain list --verbose | grep risc0 # risc-zero installed: risc0 (...path...) 
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
```

Lets check the output:

```bash
# You see receipt in output of the command and serialized in a json file: 
 ls -la ../data/myrequest-generated/*.json
 cat ../data/myrequest-generated/*.json
```

Now let's try to create a fake proof - we will use wrong public keys where the verification of signatures should fail:

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
```

Wrong witness:

```bash
# note that we use bank key for witness: --witnesskey ../data/pub_bank.pem 
RISC0_DEV_MODE=true \
cargo run  -- --verbose prove-camt53  \
    --request="../data/myrequest-generated/myrequest-generated.xml" --bankkey ../data/pub_bank.pem \
    --clientkey ../data/client.pem --witnesskey ../data/pub_bank.pem --clientiban CH4308307000289537312
# panics, output: 
# verify the verify_order_data_signature by witness
# ---> error Verification
```

### Use docker environment on MacOS

Bash into the container: 
```bash
docker run -it --rm --entrypoint /bin/bash fridge
```

For running the tests with a new ebics response, lets copy the existing into a new file, then we create the proof for it: 

```bash
# simulates the download of ebics file
cd /data
rm -R -f /data/myrequest && mkdir -p myrequest
cp response_template.xml myrequest.xml
cp -r response_template/camt53 myrequest
# you may edit the myrequest and payload in ../data/myrequest/camt53 now

# Data above needs to be compressed, signed etc.
# Create the signed ebics response and pre-process data for proofing,
# should result in "Secret Input Data generated."
xml_file=myrequest.xml ./createTestResponse.sh

# now create the proof
# note that the proof needs the singed file:  --request="../data/myrequest-generated/myrequest-generated.xml"
cd /app
RISC0_DEV_MODE=true \
    host  prove-camt53  \
   --request="/data/myrequest-generated/myrequest-generated.xml"  --bankkey /data/pub_bank.pem \
    --clientkey /data/client.pem --witnesskey /data/pub_witness.pem --clientiban CH4308307000289537312
```

Lets check the output:

```bash
# You see receipt in output of the command and serialized in a json file: 
 ls -la /data/myrequest-generated/*.json
 cat /data/myrequest-generated/*.json
```

Now let's try to create a fake proof - we will use wrong public keys where the verification of signatures should fail:

```bash
# note that we use witness key for bank: --bankkey ../data/pub_witness.pem
cd /app
RISC0_DEV_MODE=true \
    host prove-camt53  \
        --request="../data/myrequest-generated/myrequest-generated.xml" --bankkey ../data/pub_witness.pem \
        --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
# panics, output: 
# verify bank signature
# ---> error Verification
```

Wrong witness:

```bash
# note that we use bank key for witness: --witnesskey ../data/pub_bank.pem 
RISC0_DEV_MODE=true \
    host prove-camt53  \
        --request="/data/myrequest-generated/myrequest-generated.xml" --bankkey /data/pub_bank.pem \
        --clientkey /data/client.pem --witnesskey /data/pub_bank.pem --clientiban CH4308307000289537312
# panics, output: 
# verify the verify_order_data_signature by witness
# ---> error Verification
```

## Create real receipt with CUDA hardware acceleration on **Linux** dev environment

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

## Notes on provided test data

The test data was taken from the productive systems (Hypo Lenzburg), decrypted and encrypted again with generated keys as it can be seen in scripts `data/createTestResponse.sh` and `data/checkResponse.sh`. A productive sample has been added to `data/test/test.xml (prod).zip`, the payload of test data remained unchanged from the productive system.
