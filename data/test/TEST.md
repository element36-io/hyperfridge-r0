How to redeploy this directory: 

- run "createResonse.sh" - defaults should work
- rename all new generated files from "productive_example-generated" to "test". Ignore Camt53 directory, 
- Copy into to test directory
- run test in methods/guest  RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test --features debug_mode