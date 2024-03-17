# Development on MacOS

Development for the rust code of hyperfridge is same as on other platform. Preparing the Input for the `host` program to create proofs uses Bash-Scripts, which need additional installations and e.g. updating bash to 5.3 in order to make it work. We currently do not support script development on MacOS because it is not likely that MacOS runs on a backend, but here we collected instructions how to cover most functionality. 

## Building Hyperfridge

```bash
RISC0_DEV_MODE=true cargo build --release 
mkdir -p ./bin
cp ./target/release/host ./bin
cp ./target/release/verifier ./bin
cp ./target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge ./bin
ls -la ./bin
# you should have host, verifier and hyperfridge executables. 
```

## Additional packages to with scrips

If you are using the binary distribution make sure you are running a glibc compatible environment and necessary tools are installed to run the scripts for pre-processing the EBICS Response. On debian based systems you may use `apt install -y openssl perl qpdf xxd libxml2-utils` - versions are given only as FYI, we are not aware of any version related dependencies. 

Install rust and risc-zero toolchain. Check if those commands are available/installed on our OS: 

```bash
brew install bash
bash --version # 5.x
brew install openssl
opennssl version # output, e.g. OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
brew install qpdf
zlib-flate --version # zlib-flate from qpdf version 10.6.3
brew install libxml
xmllint --version # xmllint: using libxml version 20913
brew install perl
perl --version # 5 Version 34
brew install zip
brew install base64
rustup toolchain list --verbose | grep risc0 # risc-zero installed: risc0 (...path...) 
```
