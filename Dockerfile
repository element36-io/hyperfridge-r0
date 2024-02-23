FROM rust:1.75-bookworm as build

RUN cargo install cargo-binstall --locked --version 1.6.2
RUN cargo binstall cargo-risczero -y --version 0.19.1
RUN cargo risczero install
RUN rustup toolchain list --verbose  | grep risc0
# qdpf is for zlib flate
RUN apt update && apt install -y perl qpdf xxd libxml2-utils

COPY data data
COPY host host
COPY verifier verifier
COPY methods methods
COPY Cargo.toml Cargo.lock /
COPY rust-toolchain.toml /

# create directory holding generated Id of Computation which will be proved. 
WORKDIR /host
RUN mkdir out; touch out/test.touch; rm out/test.touch

WORKDIR /
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo build --release 


# creates fake proof for test data, so that calling "verifier" without parameters works
# RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  --release -- --nocapture

#RUN RUST_BACKTRACE=2 RISC0_DEV_MODE=true ./target/release/host show-image-id

RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true ./target/release/host --verbose prove-camt53  \
        --request=/data/test/test.xml \
        --bankkey /data/pub_bank.pem \
        --clientkey /data/client.pem \
        --witnesskey /data/pub_witness.pem --clientiban CH4308307000289537312

RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true ./target/release/host show-image-id > /host/out/IMAGE_ID.hex

#RUN cat /host/out/IMAGE_ID.hex &&  find /data -type f -name "*-Receipt-*.json" 
#COPY host/out/IMAGE_ID.hex /data/IMAGE_ID.hex
#RUN ls && ls /data/test/ && ls data/test/test.xml-Receipt-$(cat ./host/out/IMAGE_ID.hex)-latest.json


# Final Stage - 
FROM debian:12.5-slim as runtime
# qdpf is for zlib flate
RUN apt update && apt install -y perl qpdf xxd libxml2-utils openssl inotify-tools unzip

#FROM alpine:latest as runteim
# add glibc 
# RUN apk --no-cache add ca-certificates libgcc gcompat

# Copy the compiled binaries from the build stage
COPY --from=build /target/release/host /app/host
COPY --from=build /target/release/verifier /app/verifier
COPY --from=build /target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge /app/hyperfridge
COPY --from=build /host/out/IMAGE_ID.hex /app/IMAGE_ID.hex
COPY --from=build /data /data
RUN ln -s /app/verifier /usr/local/bin/verifier
RUN ln -s /app/host /usr/local/bin/host
RUN ln -s /app/host /usr/local/bin/fridge

# Check if the proof and testdata is there
RUN ls -la /data/test/test.xml-Receipt-$(cat /app/IMAGE_ID.hex)-latest.json 

WORKDIR /app

CMD ["./host --help"]