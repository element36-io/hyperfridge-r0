 # Performance measurements

Conclusions:

- With hardware acceleration (CUDA) we have execution times for a proof around **10-20 minutes**. We could not test hardware acceleration due to lack of memory, but testing with other examples shows dramatic speed-up. 
- Cost is estimated around 0.5 USD per proof with hardware acceleration. Upper bound (no hardware acceleration) is around 2-6 USD per proof (Cost basis AWS EC2 instance c5d.12xlarge, no CUDA)
- RSA framework is biggest bottleneck. It might be interesting to apply the [Big-Integer Patch](https://github.com/risc0/RustCrypto-crypto-bigint/tree/risczero) of Risc0 to the RSA crate, but this was not investigated further.

### Reference Hardware

Hardware: Gaming Laptop, Lenovo Legion 5 Pro, 32 GB RAM, Geforce 4070 (8GB)
vendor_id	: GenuineIntel
cpu family	: 6
model		: 183
model name	: 13th Gen Intel(R) Core(TM) i7-13700HX
cpu MHz		: 1984.575
cache size	: 30720 KB
cpu cores	: 16

Comparising with Risk Zero benchmarks [here](https://dev.risczero.com/datasheet.pdf):

|     Cycles |   Duration |        RAM |       Seal |      Speed |
|     ---- |   ---- |        ---- |       ---- |      ---- |
|        64k |      8.14s |    472.4MB |    215.3kB |     8.1khz |
|       128k |     20.95s |    944.8MB |    238.3kB |     6.3khz |
|       256k |     46.62s |     1.89GB |      250kB |     5.6khz |
|       512k |     1:34.3 |     3.78GB |    262.2kB |     5.6khz |
|      1024k |     3:10.3 |     7.56GB |    275.5kB |     5.5khz |
|      2048k |     6:21.2 |     7.56GB |      551kB |     5.5khz |
|      4096k |    12:41.5 |     7.56GB |      1.1MB |     5.5khz |


With CUDA enabled we see roughly 10-20x speedup until memory runs out:

|     Cycles |   Duration |        RAM |       Seal |      Speed |
|     ---- |   ---- |        ---- |       ---- |      ---- |
|        64k |    794.7ms |    472.4MB |    215.3kB |    82.5khz |
|       128k |      1.36s |    944.8MB |    238.3kB |    96.3khz |
|       256k |       2.8s |     1.89GB |      250kB |    93.7khz |



Running a roundtrip of proof generation of validation gives following numbers on the reference hardware (no CUDA):

```
RUST_LOG="executor=info" RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test   -- --nocapture

[2024-01-16T14:29:18Z INFO  executor] total_cycles = 507098
[2024-01-16T14:29:18Z INFO  executor] session_cycles = 39265237
[2024-01-16T14:29:18Z INFO  executor] segment_count = 37
[2024-01-16T14:29:18Z INFO  executor] execution_time = 3.117812573s
```

Runtime for genation of Proof: 12055.32s - around ***200 minutes*** without hardware acceleration.

Cycle most expensive calculations:

- **Cycle count verify_bank_signature 10687k**: Checking RSA signature of Bank.
- **Cycle count decrypt_transaction_key 10660k**: Encrypt provided session key, compare result with encrypted session in the EbicsResponse. Plain decryption of the session key with RSA key of Client would add around 80000k cycles, therefore we decrypt outside of guest do the cheaper reverse function to check integritiy.
- **Cycle count decrypt_order_data 24061k**: decrypting payload with symetric key and RSA check for witness signature.


## Create profiling data on your own

 Follwing the instructions [here](https://dev.risczero.com/api/zkvm/benchmarks). Install pprof profiling tool and run:

```bash
RUST_LOG="executor=info" RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test profid  -- --nocapture
pprof -http=127.0.0.1:8089 ./host/target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge host/profile-output
```

This will generate an overview like this, which shows that bottlenecks are related to RSA decryption and signature validation. This generates a cycle overview ([full image](./hyperfridge-cycles.html)): 
![plot](./cycles.png)


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
