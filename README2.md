
error: linking with `cc` failed: exit status: 1 
apt install gcc-multilib
sudo apt-get install gcc-riscv64-linux-gnu

w@w-l5:~/workspace/hyperfridge-r0/host$ RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run