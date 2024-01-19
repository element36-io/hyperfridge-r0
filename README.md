# Hyperfridge zkVM component!

Welcome to the Hyperfridge RISC Zero component! The idea of hyperfridge is to create a bidirectional bridge to the TradFi world for blockchain applications, secured by Zero-Knowledge tech. This project is supported by [Web3 Foundation](https://web3.foundation/) and lets smart contracts and blockchain Dapps "look inside" a bank account, for example to react on the arrival of a FIAT payment and allows to send FIAT funds through a bank account. All automated, secure, and privacy-preserving. For more information take a look at our [web3 grant application](https://github.com/w3f/Grants-Program/blob/master/applications/hyperfridge.md). Hyperfridge's vision is to create a ZK-based ledger to provide a trustless interfaces to TradFi so that anyone can "plug-in" their own bank-account into the Web3 world, similar as you can do it today with [Stripe](https://en.wikipedia.org/wiki/Stripe,_Inc.) in the Web2 world, but open-sourced and fully trustless.

This repository consists of three modules - a [host](docs/host.md) and [guest](docs/guest-hyperfridge.md) program and a verifier tool which shows how to check the proofs. Look [our testing guide](docs/INSTRUCTIONS.md) to get an idea how it is used.

Check out our [cryptographic overview](docs/crypto.md), [performance benchmarks](docs/runtime.md), also the [hyperfridge whitepaper](https://github.com/element36-io/ocw-ebics/blob/main/docs/hyperfridge-draft.pdf).


## Quick Start with Risc-Zero Framework

As it builds upon Risc-Zero zkVM, make yourself familiar with this framework, otherwise it will be hard to understand what this crate is doing: 

- The [RISC Zero Developer Docs][dev-docs] is a great place to get started.
- Example projects are available in the [examples folder][examples] of
  [`risc0`][risc0-repo] repository.
- Reference documentation is available at [https://docs.rs][docs.rs], including
  [`risc0-zkvm`][risc0-zkvm], [`cargo-risczero`][cargo-risczero], [zkvm-overview][zkvm-overview]
  [`risc0-build`][risc0-build], and [others][crates].
- [excerpt from Risc0 workshop at ZK HACK III][zkhack-iii].


## Development Environment


First, make sure [rustup] is installed. The [`rust-toolchain.toml`][rust-toolchain] file will be used by `cargo` to
automatically install the correct version. To build and execute a quick integration test, use: 

```bash
RISC0_DEV_MODE=1 cargo test
```

This will create a STARK based on the provided test data. Check out [our testing guide](docs/INSTRUCTIONS.md) to run test and play with test data. Note that `cargo test` will not invoke tests in `methods/guest` due to the architecture of Risc-Zero framework - see testing guide how to run tests for the poofer.

To use this crate with your owen bank data, you will need to run a component, which connects with our banking backend and then prepare the input for the Hyperfridge zkVM component. You can use the [ebics-java-client][ebics-java-client], but any Ebics client will do, as long as you get access to the XML files which are exchanged between your client and the banking server.

Open documentation in any module by:

```bash
cargo doc --no-deps --open
```

### Executing the project locally in development mode

During development, faster iteration upon code changes can be achieved by leveraging [dev-mode], we strongly suggest activating it during your early development phase. Furthermore, you might want to get insights into the execution statistics of your project, and this can be achieved by specifying the environment variable `RUST_LOG="executor=info"` before running your project.

Put together, the command to run your project in development mode while getting execution statistics is:

```bash
cd host
# will show usage
RUST_LOG="executor=info" RISC0_DEV_MODE=1 cargo run
# will create a STARK on the test data 
RUST_LOG="executor=info" RISC0_DEV_MODE=1 cargo run test
# add --verbose to see what is going on
RUST_LOG="executor=info" RISC0_DEV_MODE=1 cargo run --verbose test
```

### Running proofs remotely on Bonsai, a Risc-Zero Service

_Note: The Bonsai proving service is still in early Alpha; an API key is
required for access. [Click here to request access][bonsai access]._

If you have access to the URL and API key to Bonsai you can run your proofs
remotely. To prove in Bonsai mode, invoke `cargo run` with two additional
environment variables:

```bash
BONSAI_API_KEY="YOUR_API_KEY" BONSAI_API_URL="BONSAI_URL" cargo run
```

## Directory Structure

It is possible to organize the files for these components in various ways.
However, in this starter template we use a standard directory structure for zkVM
applications, which we think is a good starting point for your applications.

```text
project_name
├── Cargo.toml
├── host
│   ├── Cargo.toml
│   └── src
│       └── main.rs                        <-- [Host code]
├── verifier
│   ├── Cargo.toml
│   └── src
│       └── main.rs                        <-- [Verifier code]
└── methods
    ├── Cargo.toml
    ├── build.rs
    ├── guest
    │   ├── Cargo.toml
    │   └── src
    │       └── bin
    │           └── method_name.rs         <-- [Guest code]
    └── src
        └── lib.rs
```



[bonsai access]: https://bonsai.xyz/apply
[cargo-risczero]: https://docs.rs/cargo-risczero
[crates]: https://github.com/risc0/risc0/blob/main/README.md#rust-binaries
[dev-docs]: https://dev.risczero.com
[dev-mode]: https://dev.risczero.com/api/zkvm/dev-mode
[docs.rs]: https://docs.rs/releases/search?query=risc0
[examples]: https://github.com/risc0/risc0/tree/main/examples
[risc0-build]: https://docs.rs/risc0-build
[risc0-repo]: https://www.github.com/risc0/risc0
[risc0-zkvm]: https://docs.rs/risc0-zkvm
[rustup]: https://rustup.rs
[rust-toolchain]: rust-toolchain.toml
[zkvm-overview]: https://dev.risczero.com/zkvm
[zkhack-iii]: https://www.youtube.com/watch?v=Yg_BGqj_6lg&list=PLcPzhUaCxlCgig7ofeARMPwQ8vbuD6hC5&index=5
[ebics-java-client]: https://bonsai.xyz/apply