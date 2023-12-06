


error: linking with `cc` failed: exit status: 1 
apt install gcc-multilib
sudo apt-get install gcc-riscv64-linux-gnu

w@w-l5:~/workspace/hyperfridge-r0/host$ RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run

# CUDA

https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Ubuntu&target_version=22.04&target_type=deb_network

NVIDIA Driver Instructions (choose one option)

To install the legacy kernel module flavor:

sudo apt-get install -y cuda-drivers

To install the open kernel module flavor:

sudo apt-get install -y nvidia-kernel-open-545
sudo apt-get install -y cuda-drivers-545


https://docs.nvidia.com/cuda/cuda-installation-guide-linux/#switching-between-driver-module-flavors

Ubuntu

To switch from legacy to open:

sudo apt-get --purge remove nvidia-kernel-source-XXX
sudo apt-get install --verbose-versions nvidia-kernel-open-XXX
sudo apt-get install --verbose-versions cuda-drivers-XXX


To switch from open to legacy:

sudo apt-get remove --purge nvidia-kernel-open-XXX
sudo apt-get install --verbose-versions cuda-drivers-XXX


My machine: 

sudo apt-get remove --purge nvidia-kernel-open-545
sudo apt-get install --verbose-versions cuda-drivers-545