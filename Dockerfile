# Base stage for building
FROM debian:12.5-slim as build
# Install required dependencies

RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    git \
    pkg-config \
    libssl-dev \
    cmake \
    python3  \
    ninja-build \
    perl qpdf xxd libxml2-utils

# Install Rust 1.75
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.75
ENV PATH="/root/.cargo/bin:${PATH}"

# Install the RISC0 toolchain
RUN cargo install cargo-binstall  --version 1.6.2
RUN cargo binstall cargo-risczero -y --version 0.19.1

# Conditionally install the cargo risczero toolchain based on the platform depending on build argument
ARG PLATFORM
RUN echo "PLATFORM: $PLATFORM"
RUN if [ "$PLATFORM" != "linux/amd64" ]; then \
        cargo risczero build-toolchain; \
    else \
        cargo risczero install; \
    fi

# Test toolchain installation
RUN rustup toolchain list --verbose | grep risc0

# Copy build files 
COPY data data
COPY host host
COPY verifier verifier
COPY methods methods
COPY Cargo.toml Cargo.lock /
COPY rust-toolchain.toml /
RUN rustup toolchain install .

# create directory holding generated Image Id of Computation which will be proved. 
RUN mkdir -p /host/out
# remove test data / receipts
RUN rm -R /data/test/*.json

# build the project
WORKDIR /
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo build --release 


# creates fake proof for test data, so that calling "verifier" without parameters works
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true ./target/release/host --verbose prove-camt53  \
        --request=/data/test/test.xml \
        --bankkey /data/pub_bank.pem \
        --clientkey /data/client.pem \
        --witnesskey /data/pub_witness.pem --clientiban CH4308307000289537312

RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true ./target/release/host show-image-id > /host/out/IMAGE_ID.hex

#RUN cat /host/out/IMAGE_ID.hex &&  find /data -type f -name "*-Receipt-*.json" 
#COPY host/out/IMAGE_ID.hex /data/IMAGE_ID.hex
#RUN ls && ls /data/test/ && ls data/test/test.xml-Receipt-$(cat ./host/out/IMAGE_ID.hex)-latest.json

# Final Stage - Build the executable image
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

# Create symbolic links to the binaries in /usr/local/bin which is in the PATH
RUN ln -s /app/verifier /usr/local/bin/verifier
RUN ln -s /app/host /usr/local/bin/host
RUN ln -s /app/host /usr/local/bin/fridge

# Check if the proof and testdata is there
RUN ls -la /data/test/test.xml-Receipt-$(cat /app/IMAGE_ID.hex)-latest.json 

WORKDIR /app
CMD ["/app/host", "--help"]