// These constants represent the RISC-V ELF and the image ID generated by risc0-build.
// The ELF is used for proving and the ID is used for verification.
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};
use pem::parse;
use risc0_zkvm::{default_prover, ExecutorEnv};
use rsa::pkcs8::DecodePublicKey;
use rsa::traits::PublicKeyParts;
use rsa::RsaPublicKey;
use std::fs;

use chrono::Local;
#[cfg(not(test))]
use std::env;

#[cfg(not(test))]
fn main() {
    let args: Vec<String> = env::args().collect();
    // Ensure there are enough arguments
    if args.len() < 3 {
        eprintln!("Usage: program<bank_public_key> <user_private_key> <ebics_response_xml> ");
        eprintln!("To use with test data use parameters: ../data/test/test.xml ../data/bank_public.pem ../data/client.pem ");
        return;
    }

    //<SignedInfo> <authenticated> <SignatureValue> <OrderData>
    // Load files based on command-line arguments
    let bank_public_key_x002_pem =
        fs::read_to_string(&args[2]).expect("Failed to read bank_public_key file");
    let user_private_key_e002_pem =
        fs::read_to_string(&args[3]).expect("Failed to read user_private_key file");

    // we decrypting the transaction key add around 75k cycles, but the reverse function
    // encrypting with privte key is much faster. So we expect the decrypted transaction
    // key, encrypt it and check if it matches with the encrypted transaction key
    // in the XML file.
    let decrypted_tx_key = fs::read(args[1].to_string() + "-decrypted_tx_key.binary")
        .expect("Failed to read decrypted transaction key file");
    let signed_info_xml_c14n = fs::read_to_string(args[1].to_string() + "-SignedInfo")
        .expect("Failed to read SignedInfo file");
    let authenticated_xml_c14n = fs::read_to_string(args[1].to_string() + "-authenticated")
        .expect("Failed to read authenticated file");
    let signature_value_xml = fs::read_to_string(args[1].to_string() + "-SignatureValue")
        .expect("Failed to read SignatureValue file");
    let order_data_xml = fs::read_to_string(args[1].to_string() + "-OrderData")
        .expect("Failed to read OrderData file");
    let order_data_digest_xml = fs::read_to_string(args[1].to_string() + "-DataDigest")
        .expect("Failed to read OrderData file");

    let json = proove_camt53(
        &signed_info_xml_c14n,
        &authenticated_xml_c14n,
        &signature_value_xml,
        &order_data_xml,
        &order_data_digest_xml,
        &bank_public_key_x002_pem,
        &user_private_key_e002_pem,
        &decrypted_tx_key,
    );
    println!("Receipt  {}", json);
}

/// Generates the proof of computation and returning the receipt as JSON
#[allow(clippy::too_many_arguments)]
fn proove_camt53(
    signed_info_xml_c14n: &str,
    authenticated_xml_c14n: &str,
    signature_value_xml: &str,
    order_data_xml: &str,
    order_data_digest_xml: &str,

    bank_public_key_x002_pem: &str,
    user_private_key_e002_pem: &str,
    decrypted_tx_key: &Vec<u8>, // Todo: remove this later
) -> String {
    println!("start: {}", Local::now().format("%Y-%m-%d %H:%M:%S"));
    let _ = write_image_id();
    // Todo:
    // Using r0 implementation crypto-bigint does not work with RsaPUblicKey

    // let exp_bigint = BigInt::from_str_radix(&BANK_X002_EXP, 10)
    // .expect("error parsing EXP of public bank key");
    // let modu_bigint = BigInt::from_str_radix(&BANK_X002_MOD, 10)
    // .expect("error parsing MODULUS of public bank key");

    // let exp_hex = format!("{:x}", exp_bigint);
    // let modu_hex = format!("{:x}", modu_bigint);

    // .write(&exp_hex).unwrap()
    // .write(&modu_hex).unwrap()

    // https://docs.rs/risc0-zkvm/latest/risc0_zkvm/struct.ExecutorEnvBuilder.html
    println!("Starting guest code, load environment");
    env_logger::init();
    let pem = parse(bank_public_key_x002_pem).expect("Failed to parse bank public key PEM");
    let bank_public_key = RsaPublicKey::from_public_key_pem(&pem::encode(&pem))
        .expect("Failed to create bank public key");
    let modulus_str = bank_public_key.n().to_str_radix(10);
    let exponent_str = bank_public_key.e().to_str_radix(10);

    let env = ExecutorEnv::builder()
        .write(&signed_info_xml_c14n)
        .unwrap()
        .write(&authenticated_xml_c14n)
        .unwrap()
        .write(&signature_value_xml)
        .unwrap()
        .write(&order_data_xml)
        .unwrap()
        .write(&order_data_digest_xml)
        .unwrap()
        .write(&modulus_str)
        .unwrap()
        .write(&exponent_str)
        .unwrap()
        .write(&user_private_key_e002_pem)
        .unwrap()
        .write(&decrypted_tx_key)
        .unwrap()
        .build()
        .unwrap();

    // Obtain the default prover.
    let prover = default_prover();
    println!("prove hyperfridge elf ");
    let receipt_result = prover.prove_elf(env, HYPERFRIDGE_ELF);
    println!(
        "got the receipt of the prove , id first 32u {} binary size of ELF binary {}k",
        HYPERFRIDGE_ID[0],
        HYPERFRIDGE_ELF.len() / 1000
    );

    // println!("----- got result {} ",receipt_result);

    let mut result = String::new();
    match &receipt_result {
        Ok(_val) => {
            // println!("Receipt result: {}", val);_
            let receipt = receipt_result.unwrap();
            result = serde_json::to_string(&receipt).expect("Failed to serialize receipt");
            println!("Receipt result: {:?}", &result);
            println!("verify receipt: ");
            receipt.verify(HYPERFRIDGE_ID).expect("verify failed");
            let journal = receipt.journal;
            println!(
                "Receipt result (commitment) - first element {}. ",
                &(journal.decode::<String>().unwrap())
            );
        }
        Err(e) => {
            println!("Receipt error: {:?}", e);
            //None
        }
    }
    println!("end: {}", Local::now().format("%Y-%m-%d %H:%M:%S"));
    result
    // 31709.14
}

use std::fs::File;
use std::io::{Error, Write};

fn write_image_id() -> Result<(), Error> {
    // Convert image_id to a hexadecimal string
    let hex_string = HYPERFRIDGE_ID
        .iter()
        .fold(String::new(), |acc, &num| acc + &format!("{:08x}", num));

    // Write hex string to IMAGE_ID.hex
    let mut hex_file = File::create("./out/IMAGE_ID.hex")?;
    hex_file.write_all(hex_string.as_bytes())?;

    Ok(())
}

#[cfg(test)]
mod tests {
    // use std::result;
    use risc0_zkvm::Receipt;

    use crate::fs;
    use crate::proove_camt53;
    use std::fs::File;
    use std::io::Write;
    use chrono::Local;

    #[test]
    fn do_main() {
        const EBICS_FILE: &str = "../data/test/test.xml";

        let decrypted_tx_key: Vec<u8> =
            fs::read(EBICS_FILE.to_string() + "-decrypted_tx_key.binary")
                .expect("Failed to read transaction key file");

        let receipt_json = proove_camt53(
            fs::read_to_string(EBICS_FILE.to_string() + "-SignedInfo")
                .unwrap()
                .as_str(),
            fs::read_to_string(EBICS_FILE.to_string() + "-authenticated")
                .unwrap()
                .as_str(),
            fs::read_to_string(EBICS_FILE.to_string() + "-SignatureValue")
                .unwrap()
                .as_str(),
            fs::read_to_string(EBICS_FILE.to_string() + "-OrderData")
                .unwrap()
                .as_str(),
            fs::read_to_string(EBICS_FILE.to_string() + "-DataDigest")
                .unwrap()
                .as_str(),
            fs::read_to_string("../data/bank_public.pem")
                .unwrap()
                .as_str(),
            fs::read_to_string("../data/client.pem").unwrap().as_str(),
            &decrypted_tx_key,
        );
        println!(" receipt_json {}", &receipt_json);
        let receipt_parsed: Receipt =
            serde_json::from_str(&receipt_json).expect("Failed to parse JSON");
        let result_string = String::from_utf8(receipt_parsed.journal.bytes)
            .expect("Failed to convert bytes to string");
        print!(" commitments in receipt {}", result_string);
        assert!(result_string.ends_with("31709.14"));

        // create file with latest proof
        let mut file =File::create(EBICS_FILE.to_string() + "-Receipt").expect("Unable to create file");
        file.write_all(receipt_json.as_bytes())
            .expect("Unable to write data");

        // create a copy with timestamp.
        let now = Local::now();
        let formatted_date = format!("{}", now.format("%Y-%m-%d"));
        let formatted_time = format!("{}", now.format("%H:%M:%S"));
        let timestamp_string = format!("{}_{}", formatted_date, formatted_time);

        file = File::create(EBICS_FILE.to_string() + "-Receipt-" + &timestamp_string)
            .expect("Unable to create file with timestamp");
        file.write_all(receipt_json.as_bytes())
            .expect("Unable to write data");
        
        //         // verify your receipt
        //         receipt.verify(HYPERFRIDGE_ID).unwrap();
        // let data = include_str!("../res/example.json");
        // let outputs = super::search_json(data);
        // assert_eq!(
        //     outputs.data, 47,
        //     "Did not find the expected value in the critical_data field"
        // );
    }
}
