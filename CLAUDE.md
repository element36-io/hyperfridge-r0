# CLAUDE.md

## Project Overview

Hyperfridge is a zero-knowledge proof (ZKP) system built on **RISC Zero** that bridges traditional banking (EBICS/ISO20022) with blockchain. It enables proving bank account balances and transactions without revealing sensitive financial data. Supported by the Web3 Foundation.

**Core flow**: Bank EBICS XML response → Host orchestrator → RISC Zero guest (STARK proof) → Verifiable receipt (JSON)

## Architecture

Three Rust crates in a Cargo workspace:

| Crate | Path | Purpose |
|-------|------|---------|
| **host** | `host/` | CLI orchestrator — reads EBICS XML, feeds data to zkVM prover, outputs receipt JSON |
| **methods** | `methods/` | Build system + guest program — guest runs inside RISC Zero VM, validates signatures, decrypts payload, parses CAMT.053, generates commitments |
| **verifier** | `verifier/` | Standalone proof verification against IMAGE_ID |

Guest code lives in `methods/guest/src/main.rs`. The build script (`methods/build.rs`) compiles it to RISC-V and generates `IMAGE_ID`.

### Key directories

- `data/` — Test XML files, PEM keys, pre-processor scripts, EBICS schema files
- `data/test/` — Pre-generated test fixtures (XML, keys, pre-processed components)
- `data/schematas/` — EBICS protocol schemas (H003, H004, H005)
- `docs/` — Detailed documentation (crypto, host, guest, runtime, milestones)

## Toolchain & Dependencies

- **Rust**: 1.85 (pinned in `rust-toolchain.toml`)
- **RISC Zero**: v2.3.2 (zkVM, build, and prover)
- **Components**: clippy, rustfmt, rust-src
- **System packages** (Linux): `clang`, `llvm`, `libssl-dev`, `pkg-config`, `cmake`, `protobuf-compiler`, `libxml2-utils`

Install RISC Zero toolchain:
```bash
curl -L https://risczero.com/install | bash
rzup install
```

## Build & Run

```bash
# Dev mode build (fast, simulated proofs — use for development)
RISC0_DEV_MODE=true cargo build

# Release build (real STARK proofs — takes hours)
cargo build --release

# Quick test with bundled test data
RISC0_DEV_MODE=true cargo run -- test

# Generate proof from EBICS response
RISC0_DEV_MODE=true cargo run --release -- prove-camt53 \
  --request=data/test/test.xml \
  --bankkey=data/pub_bank.pem \
  --clientkey=data/client.pem \
  --witnesskey=data/pub_witness.pem \
  --clientiban=CH4308307000289537312

# Verify a proof
cargo run --release -p verifier -- verify \
  --imageid-hex=<IMAGE_ID> \
  --proof-json=<RECEIPT_PATH>

# Show guest IMAGE_ID
cargo run -- show-image-id
```

**Important**: Always use `RISC0_DEV_MODE=true` for local development and testing. Without it, proof generation takes hours.

## Testing

```bash
# Run workspace tests (dev mode)
RISC0_DEV_MODE=true cargo test

# Run guest-specific tests with debug features
cd methods/guest && RISC0_DEV_MODE=true cargo test --features debug_mode

# Format check
cargo fmt --all -- --check

# Lint
cargo clippy --all-targets --all-features
```

Guest code coverage cannot be measured by tarpaulin due to RISC-V cross-compilation. Coverage target is 80% (configured in `.codecov.yml`).

## Build Profiles

Both `dev` and `release` profiles use `opt-level = 3` because guest compilation is extremely slow without optimization. Release additionally enables LTO.

```toml
[profile.dev]
opt-level = 3

[profile.release]
debug = 1
lto = true
```

## CI/CD (GitHub Actions)

- **`checks.yml`** (push to main / PRs): Build, test, coverage (tarpaulin), fmt, clippy
- **`docker-build.yml`** (push to main): Builds Docker image, creates GitHub release with semantic versioning, pushes to DockerHub
- **`docker-build-macos.yml`** (manual): macOS Docker build

CI always runs with `RISC0_DEV_MODE=true` for fast feedback.

## Docker

```bash
# Linux build
docker build -f DockerfileLinux -t fridge .

# Run test in container
docker run --env RISC0_DEV_MODE=true fridge host test
```

## Cryptography & Standards

- **EBICS**: Electronic Banking Internet Communication Standard (bank-to-client protocol)
- **ISO20022 CAMT.053**: Bank statement format
- **RSA-2048**: Bank signature verification (A005) and transaction key encryption (E002)
- **AES-128-CBC**: Payload encryption
- **SHA-256**: Signature hashing
- **XML C14N**: Canonical XML for signature validation
- **STARK**: Proof system (via RISC Zero)

### Trust Model

Three entities: **Bank** (signs responses), **Client** (requests statements), **Witness** (third-party co-signer preventing tampering). The witness signs the encrypted payload before the client can access it, preventing both bank-only and client-only forgery.

## Code Conventions

- Standard Rust formatting (`rustfmt`) — no custom config
- Clippy linting with all targets and features
- Guest code uses `#[cfg(feature = "debug_mode")]` for test-only paths
- Error handling: `anyhow` in host/verifier, direct panics in guest (zkVM convention)
- CLI parsing via `clap` derive macros
- Logging via `env_logger` (host and verifier)

## Key Files Reference

| File | Description |
|------|-------------|
| `host/src/main.rs` | Host CLI — proof orchestration, `prove-camt53` / `test` / `show-image-id` commands |
| `methods/guest/src/main.rs` | Guest ZKP logic — XML parsing, RSA verification, AES decryption, CAMT.053 parsing |
| `methods/guest/src/test_xmlparse.rs` | Guest unit tests |
| `methods/build.rs` | RISC Zero guest build script |
| `verifier/src/main.rs` | Proof verification CLI |
| `data/checkResponse.sh` | Pre-processor: canonicalizes XML, extracts signed info |
| `data/createTestResponse.sh` | Generates test EBICS responses |
| `rust-toolchain.toml` | Rust 1.75 toolchain pin |

## Common Issues

- **Slow builds**: Guest compilation to RISC-V is inherently slow. Always use `RISC0_DEV_MODE=true` for development.
- **Missing RISC Zero toolchain**: Install via `rzup install` (see https://risczero.com/install).
- **Coverage gaps**: Guest code running in zkVM cannot be instrumented by tarpaulin — this is expected.
- **XML test data**: Test fixtures in `data/test/` are pre-generated. Regenerate with `data/createTestResponse.sh` if needed (requires `openssl`, `xmllint`, etc.).
