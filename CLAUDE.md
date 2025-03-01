# Hyperfridge Commands and Guidelines

## Build and Test Commands
- Build project: `cargo build`
- Run tests with dev mode: `RISC0_DEV_MODE=1 cargo test`
- Run guest tests: `cd methods/guest && RISC0_DEV_MODE=1 cargo test --features debug_mode -- --nocapture`
- Generate documentation: `cargo doc --no-deps --open`
- Run host with logging: `cd host && RUST_LOG="executor=info" RISC0_DEV_MODE=1 cargo run [COMMAND]`
- Run single test: `RISC0_DEV_MODE=1 cargo test test_name -- --nocapture`

## Code Style Guidelines
- Use the Rust 2018 edition
- Follow standard Rust naming conventions (snake_case for functions/variables, CamelCase for types)
- Organize imports: std first, then external crates alphabetically
- Document all public functions and modules with rustdoc
- Use Result<T, E> for error handling with descriptive error types
- Prefer strong typing over primitive types
- Use Clippy and rustfmt: `cargo clippy` and `cargo fmt`
- Respect the risc0 zkVM architecture (host/guest separation)
- Consider zero-knowledge patterns when implementing crypto operations