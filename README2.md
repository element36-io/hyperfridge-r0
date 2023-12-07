
error: linking with `cc` failed: exit status: 1 
apt install gcc-multilib
sudo apt-get install gcc-riscv64-linux-gnu

w@w-l5:~/workspace/hyperfridge-r0/host$ RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run

RUST_LOG="executor=info" RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test profid  -- --nocapture

pprof -http=127.0.0.1:8089 ./host/target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge host/profile-output