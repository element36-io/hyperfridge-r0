#[allow(unused_imports)]
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};

use risc0_zkvm::Receipt;
#[allow(unused_imports)]
use risc0_zkvm::{default_prover, ExecutorEnv};
use std::fs;
use std::env;

const DEFAULT_PROOF_JSON: &str = "../data/test/test.xml-Receipt";


fn main() {
    println!("Start Verify");
    // Get the first argument from command line, if available
    let args: Vec<String> = env::args().collect();
    let proof_json_path = if args.len() > 1 {
        &args[1]
    } else {
        DEFAULT_PROOF_JSON
    };

    let receipt_json: Vec<u8> = fs::read(proof_json_path)
        .unwrap_or_else(|_| panic!("Failed to read file at {}", proof_json_path));

    let receipt: Receipt = serde_json::from_slice(&receipt_json)
        .expect("Failed to parse proof JSON");
    let result_string = String::from_utf8(receipt.journal.bytes)
        .expect("Failed to convert bytes to string");
    println!("Commitments in receipt: {}", result_string);
}
