#[allow(unused_imports)]
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};

use risc0_zkvm::Receipt;
#[allow(unused_imports)]
use risc0_zkvm::{default_prover, ExecutorEnv};
use std::fs;

const PROOF_JSON: &str = "../data/test/test.xml-Receipt";

fn main() {
    println!("Start Verify");
    let receipt_json: Vec<u8> =
        fs::read(PROOF_JSON).expect("Failed to read transaction key file");

    let receipt: Receipt =
        serde_json::from_slice(receipt_json.as_slice()).expect("Failed to parse proof JSON");
    let result_string =
        String::from_utf8(receipt.journal.bytes).expect("Failed to convert bytes to string");
    print!(" commitments in receipt {}", result_string);
}
