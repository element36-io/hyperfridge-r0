FROM rust:1.74-bookworm as build

RUN cargo install cargo-binstall
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo binstall cargo-risczero -y
RUN cargo risczero install

COPY data data
COPY host host
COPY methods methods
COPY Cargo.toml /
COPY rust-toolchain.toml /

WORKDIR /host
RUN mkdir out; touch out/test.touch
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test  -- --nocapture

WORKDIR /methods/guest
RUN RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode -- --nocapture

RUN ls -la /host

#COPY host/out host/out

CMD ["RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --nocapture "]