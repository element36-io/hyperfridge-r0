[![codecov](https://codecov.io/gh/element36-io/hyperfridge-r0/graph/badge.svg?token=JNQZL1G2OM)](https://codecov.io/gh/element36-io/hyperfridge-r0)

# Todos

- check for libs, eg. serde is double
- use risc0 sha --> check for more
- Paper: plug-in TradFi assets like Fiat accounts, and portfolios. Sepa, Indian, british

# How to run with test data

```bash
cd host
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo build  -- 
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo build  --release -- 
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  --
RUST_BACKTRACE=1 RISC0_DEV_MODE=true RISC0_DEV_MODE=true cargo test  -- --nocapture

RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose proveraw -r "../data/test/test.xml" -b "../data/bank_public.pem" -c "../data/client.pem" -i CH4308307000289537312

RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose prove-camt -r "./test/test.xml" -b "./bank_public.pem" -c "./client.pem" -i CH4308307000289537312

 -r "../data/test/test.xml" -b "../data/bank_public.pem" -c "../data/client.pem" -i CH4308307000289537312 --script "../data/checkResponse.sh"

RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose test 

date && RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- ../data/test/test.xml ../data/bank_public.pem ../data/client.pem CH4308307000289537312 > "create-receipt-$(date).log" && date

```


Run tests for verifier - need to enable main function with feature flag, use RUST_LOG="executor=info" as needed.  

```bash
cd methods/guest
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode
# with output 
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture
```

When pushing run clippy and fmt: 

```bash
cargo fmt --all
cargo fmt --all -- --check
RISC0_SKIP_BUILD=1  cargo clippy

cargo doc --no-deps --open
```

Generate coverage data

```bash
cd methods/guest
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo tarpaulin --features debug_mode 
# with output 
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture

RISC0_SKIP_BUILD=1 RISC0_DEV_MODE=true cargo tarpaulin 

RISC0_SKIP_BUILD=1 RISC0_DEV_MODE=true cargo +stable tarpaulin --verbose --all-features --workspace --timeout 600 --out xml

     RUSTFLAGS="-C link-arg=-fuse-ld=lld"  RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo tarpaulin --packages=hyperfridge --skip-clean  --features debug_mode


 "-C", "link-arg=-fuse-ld=lld",

custom.rs:109: undefined reference to `__getrandom_custom'

```

## gernate documentation

```bash

(cd host && \
     cargo run -- --markdown-help > ../docs/verifier-cli.md && \
     cargo doc --no-deps --document-private-items --open
)

# with output 
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture
```

# Generate witness keys or new test keys

```bash
# password "witness"
openssl genpkey -algorithm RSA -out witness.pem -aes256
openssl rsa -pubout -in witness.pem -out witness-pub.pem
openssl rsa -in witness.pem -out witness-unencrypted.pem
```

# Unstructured notes

xmllint --schema yourxsd.xsd yourxml.xml --noout

xmllint --schema schematas/ebics_response_H004.xsd response_template.xml


cd /host
pprof -http=127.0.0.1:8089 ../target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge ./profile-output 

error: linking with `cc` failed: exit status: 1 
apt install gcc-multilib
sudo apt-get install gcc-riscv64-linux-gnu

w@w-l5:~/workspace/hyperfridge-r0/host$ RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run

rm /home/w/workspace/risc0/examples/target/debug/.cargo-lock

Here are the best places to get started:
https://dev.risczero.com/bonsai/quickstart
https://github.com/risc0/risc0/tree/main/templates/rust-starter
https://api.bonsai.xyz/swagger-ui/
And our Discord is the best place to find development support:
https://discord.gg/risczero 

API Key: XXXX
API URL: https://api.bonsai.xyz/

BONSAI_API_KEY="XXX" BONSAI_API_URL="https://api.bonsai.xyz/" cargo run --release
export BONSAI_API_URL="https://api.bonsai.xyz/"

RISC0_DEV_MODE=true cargo run --release
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  --release

Feature debug_mode allow mains function
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  --features debug_mode --release
RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode --release -- --nocapture
RUST_LOG="executor=info" RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  --release

RUST_LOG="executor=info"   BONSAI_API_KEY="XXX" BONSAI_API_URL="https://api.bonsai.xyz/" RUST_BACKTRACE=1 cargo test

RUST_LOG="executor=info"   BONSAI_API_KEY="XXX" BONSAI_API_URL="https://api.bonsai.xyz/" RUST_BACKTRACE=1 cargo test

cd /home/w/workspace/risc0/examples/xml/res
cp /home/w/ebics/client_before_keepass/users/28953700/traces/Z53493m2onmc3c3c3litqeddb659t.xml ./ebics-request.xml-orig
xmllint --c14n ./ebics-request.xml-orig > ./ebics-request.xml-orig-canon
xmllint --c14n ./ebics-request.xml-orig > ./header.xml-orig-canon
gedit ./header.xml-orig-canon


     Running `/home/w/workspace/risc0/target/release/examples/loop`
|     Cycles |   Duration |        RAM |       Seal |      Speed |
|        64k |     1:21.7 |    472.4MB |    215.3kB |    802.6hz |
|       128k |     3:06.2 |    944.8MB |    238.3kB |    704.1hz |
|       256k |     5:11.6 |     1.89GB |      250kB |    841.3hz |
|       512k |      10:27 |     3.78GB |    262.2kB |    836.2hz |
|      1024k |    20:12.6 |     7.56GB |    275.5kB |    864.8hz |
|      2048k |      40:31 |     7.56GB |      551kB |    862.7hz |
|      4096k |    1:18:33 |     7.56GB |      1.1MB |    889.9hz |
