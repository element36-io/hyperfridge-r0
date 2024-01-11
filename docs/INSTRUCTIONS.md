# Intro

This document describes in-depth our rust-modules and the zero-knowledge proof, and how to test it out.

The roundtrip looks like this:

1. Request and retrieval of banking documents with daily statements (Ebics request and response)
  through an Ebics banking client, e.g. [ebics-java-client]. 
2. Pre-Processing of the Ebics Response, which is an XML document. Pre-processing is necessary to
  off-load as much as possible from expensive proof-generation and to keep the proof-code flexible.
  Pro-processing is done with script 'data/checkResponse.sh'
3. Present data from previous step and the private key of the client to the proover, and generate
  proof of computation (a STARK) and produce the [Receipt] which contains
  balance, currency date and accountnumber.
4. A generic risc0 based verifier can check the proof, thus the above account data can be trusted.


## Releases and installation


## Test the installation

We included all test data which is necessary to run a quick shake-down test to generate
and validate a proof in one go:

```bash
host --validate test 
# or with docker: 
TODO: wasa
# or with cargo: 

```


## Proofing workflows


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
# or with docker: 
TODO: wasa
```

### Pre-processing of Ebics Response

Call the pre-processing script to pre-process the Ebics response:

```bash
xml_file="mytest.xml" pem_file="bank_public.pem"  private_pem_file="client.pem" ./checkResponse.sh
# or with docker: 
TODO: wasa
# or with cargo: 

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

The receipt is stored in `mytest/mytest.xml-Receipt`.

### Validate the Receipt

We added validator which has no dependencies to hyperfridge - but the `host` program also 
does validation with parameter `--validate`.

Download the validator from: TODO. Copy the my
```bash
TODO
# or with docker: 
docker run TODO ./verifier verify ../data/mytest/mytest.xml-Receipt
```

## Generate new test data


## Use with productive data

[test][ebics-java-client2]

[ebics-java-client2]: [links.json#ebics-java-client]
[r0-dev-mode]: [links.json#r0-dev-mode]


[ebics-java-client2]: [references.json#ebics-java-client]
[r0-dev-mode]: [references.json#r0-dev-mode]


