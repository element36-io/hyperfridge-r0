FROM rust:1.74-bookworm as build

RUN cargo install cargo-binstall
RUN cargo binstall cargo-risczero -y
RUN cargo risczero install

COPY data data
COPY host host
COPY verifier verifier
COPY methods methods
COPY Cargo.toml /
COPY rust-toolchain.toml /

# create directory holding generated Id of Computation which will be proved. 
WORKDIR /host
RUN mkdir out; touch out/test.touch; rm out/test.touch

WORKDIR /
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo build --release 
# creates fake proof for test data, so that calling "verifier" without parameters works
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  --release -- --nocapture

# Final Stage - Alpine Image
FROM rust:1.74-bookworm as runtime
#FROM alpine:latest as runteim
# add glibc 
# RUN apk --no-cache add ca-certificates libgcc gcompat

# Copy the compiled binaries from the build stage
COPY --from=build /target/release/host /app/host
COPY --from=build /target/release/verifier /app/verifier
COPY --from=build /target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge /app/hyperfridge
COPY --from=build /host/out/IMAGE_ID.hex /app/IMAGE_ID.hex
COPY --from=build /data /data

WORKDIR /app

CMD ["./verifier"]