use chrono::Local;
use clap::{Parser, Subcommand};
// These constants represent the RISC-V ELF and the image ID generated by risc0-build.
// The ELF is used for proving and the ID is used for verification.
use methods::{HYPERFRIDGE_ELF, HYPERFRIDGE_ID};
use pem::parse;
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use rsa::pkcs8::DecodePublicKey;
use rsa::traits::PublicKeyParts;
use rsa::RsaPublicKey;
use serde::Deserialize;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

static mut VERBOSE: bool = false; // print verbose

macro_rules! v {
    ($($arg:tt)*) => {
        unsafe {
            if VERBOSE {
                println!($($arg)*);
            }
        }
    };
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct Commitment {
    hostinfo: String,
    iban: String,
    stmts: Vec<Stmt>,
}

#[derive(Deserialize, Debug)]
#[allow(dead_code)]
struct Stmt {
    elctrnc_seq_nb: String,
    fr_dt_tm: String,
    to_dt_tm: String,
    amt: String,
    ccy: String,
    cd: String,
}

fn main() {
    let cli = parse_cli();

    if cli.markdown_help {
        clap_markdown::print_help_markdown::<Cli>();
        std::process::exit(0);
    }

    let pub_bank_pem_filename: String;
    let client_pem_filename: String;
    let pub_witness_pem_filename: String;
    let iban: String;
    let camt53_filename: String;

    match &cli.command {
        Some(Commands::ProveCamt53 {
            script,
            bankkey,
            clientkey,
            witnesskey,

            clientiban,
            request,
        }) => {
            pub_bank_pem_filename = (*bankkey
                .as_ref()
                .expect("extracting path for file")
                .clone()
                .into_os_string())
            .to_str()
            .unwrap()
            .to_string();

            client_pem_filename = (*clientkey
                .as_ref()
                .expect("extracting path for file")
                .clone()
                .into_os_string())
            .to_str()
            .unwrap()
            .to_string();

            pub_witness_pem_filename = (*witnesskey
                .as_ref()
                .expect("extracting path for file")
                .clone()
                .into_os_string())
            .to_str()
            .unwrap()
            .to_string();

            iban = clientiban.clone();

            camt53_filename = (*request
                .as_ref()
                .expect("extracting path for file")
                .clone()
                .into_os_string())
            .to_str()
            .unwrap()
            .to_string();

            // calls checkResponse.sh
            if let Some(script_path) = script {
                let script_dir = script_path
                    .parent()
                    .expect("Script path has no parent directory");
                let script_file_stem = request
                    .as_ref()
                    .and_then(|req| req.file_stem())
                    .expect("Script path has no file stem")
                    .to_str()
                    .expect("Failed to convert file stem to string");

                let script_full_path = script_dir.join(script_file_stem);

                v!(
                    "calling {} {} {} {}",
                    &camt53_filename,
                    &pub_bank_pem_filename,
                    &client_pem_filename,
                    &pub_witness_pem_filename,
                );

                let output = Command::new(script_path)
                    // .current_dir(&script_dir)
                    .env("dir_name", &script_full_path)
                    .env("xml_file", &camt53_filename)
                    .env("pem_file", &pub_bank_pem_filename)
                    .env("private_pem_file", &client_pem_filename)
                    .output()
                    .expect("failed to execute script");

                if output.status.success() {
                    v!("Script {:?} executed successfully.", script_path.clone());
                } else {
                    eprintln!("Script output ----------------------------------------");
                    eprintln!("stdout:\n{}", String::from_utf8_lossy(&output.stdout));
                    eprintln!("stderr:\n{}", String::from_utf8_lossy(&output.stderr));
                    panic!(
                        "Script {:?} failed with exit code {} - see output above",
                        script_path.clone(),
                        output.status.code().unwrap()
                    );
                }
            }
        }
        Some(Commands::Test) => {
            v!("Proofing with test data.");
            pub_bank_pem_filename = TEST_BANKKEY.to_string();
            client_pem_filename = TEST_CLIENTKEY.to_string();
            pub_witness_pem_filename = TEST_WITNESSKEY.to_string();

            iban = TEST_IBAN.to_string();
            camt53_filename = TEST_EBICS_FILE.to_string();
        }
        None => {
            panic!(" no command given")
        }
    }

    let bank_public_key_x002_pem =
        fs::read_to_string(&pub_bank_pem_filename).expect("Failed to read bank_public_key file");
    let user_private_key_e002_pem =
        fs::read_to_string(&client_pem_filename).expect("Failed to read user_private_key file");
    let pub_witness_pem = fs::read_to_string(&pub_witness_pem_filename)
        .expect("Failed to read pub_witness_pem_filename file");

    let iban = iban.clone();
    let camt53_filename: String = camt53_filename.to_string();
    //<SignedInfo> <authenticated> <SignatureValue> <OrderData>
    // Load files based on command-line arguments

    // we decrypting the transaction key add around 75k cycles, but the reverse function
    // encrypting with privte key is much faster. So we expect the decrypted transaction
    // key, encrypt it and check if it matches with the encrypted transaction key
    // in the XML file.
    let decrypted_tx_key_bin: Vec<u8> =
        fs::read(format!("{}-TransactionKeyDecrypt.bin", camt53_filename))
            .unwrap_or_else(|_| panic!("Failed to read decrypted transaction key file (ends with -TransactionKeyDecript.bin) {}",camt53_filename));

    // other pre-processed files, mainly to c14n for XML
    let signed_info_xml_c14n = fs::read_to_string(format!("{}-SignedInfo", camt53_filename))
        .expect("Failed to read SignedInfo file (ends with -SignedInfo)");
    let authenticated_xml_c14n = fs::read_to_string(format!("{}-authenticated", camt53_filename))
        .expect("Failed to read authenticated file (ends with -Tauthenticated)");
    let signature_value_xml = fs::read_to_string(format!("{}-SignatureValue", camt53_filename))
        .expect("Failed to read SignatureValue file (ends with -SignatureValue)");
    let order_data_xml = fs::read_to_string(format!("{}-OrderData", camt53_filename))
        .expect("Failed to read OrderData file (ends with -OrderData)");
    let witness_signature_hex = fs::read_to_string(format!("{}-Witness.hex", camt53_filename))
        .expect("Failed to read Witness.hex signature (ends with -Witness.hex)");

    let image_id_hex = get_image_id_hex();

    let receipt_result = proove_camt53(
        &signed_info_xml_c14n,
        &authenticated_xml_c14n,
        &signature_value_xml,
        &order_data_xml,
        &bank_public_key_x002_pem,
        &user_private_key_e002_pem,
        &decrypted_tx_key_bin,
        &iban,
        &witness_signature_hex,
        &pub_witness_pem,
        "host:main",
    );

    match &receipt_result {
        Ok(_val) => {
            let receipt_file_id;
            let receipt = receipt_result.unwrap();
            let receipt_json_string =
                serde_json::to_string(&receipt).expect("Failed to serialize receipt in main");
            v!("Receipt result: {:?}", &receipt_json_string);

            // let commitment_string = std::str::from_utf8(receipt.journal.bytes.clone())
            //          .expect("Failed to convert bytes to string from journal in main");
            // for some reason there are other characters at the beginning of the commitment remove that
            let commitment_string = {
                let bytes = &receipt.journal.bytes;
                let start_index = bytes.iter().position(|&b| b == b'{').unwrap_or(0);
                let end_index = bytes
                    .iter()
                    .rposition(|&b| b == b'}')
                    .unwrap_or(bytes.len());
                String::from_utf8(bytes[start_index..=end_index].to_vec())
                    .expect("Failed to convert bytes to string from journal in main")
            };

            v!("Receipt with public commitment: {} ", &(commitment_string));

            let commitment: Result<Commitment, serde_json::Error> =
                serde_json::from_str(&commitment_string);

            match commitment {
                Ok(commitment) => {
                    // collect the sequence numbers from the camt53 files to use them in the filename of the receipt json
                    let joined_elctrnc_seq_nb = commitment
                        .stmts
                        .iter()
                        .map(|data| data.elctrnc_seq_nb.to_string()) // Convert &String to &str
                        .collect::<Vec<String>>() // Collect as Vec<&str>
                        .join("_");
                    receipt_file_id = joined_elctrnc_seq_nb.clone();

                    print!("{:#?}", commitment)
                }
                Err(e) => {
                    receipt_file_id = "commit_json_error".to_owned();
                    v!("Receipt successful generated, but deserializing JSON for commitment failed. Error: {}., Json: {}.", e,commitment_string)
                }
            }

            // write result file
            let now = Local::now();
            let timestamp_string = format!("{}T{}", now.format("%Y-%m-%d"), now.format("%H:%M:%S"));
            // write the result in a file with runtime info

            let file_name = format!(
                "{}-Receipt-{}-{}-{}.json",
                &camt53_filename, &image_id_hex, &receipt_file_id, &timestamp_string
            );
            let mut file = File::create(&file_name)
                .unwrap_or_else(|_| panic!("Unable to create file {}", &file_name));

            file.write_all(receipt_json_string.as_bytes())
                .unwrap_or_else(|_| panic!("Unable to write data in file {}", &file_name));

            v!(" wrote receipt to {}", &file_name);
        }
        Err(e) => {
            v!("Receipt error in proove_camt53 {:?}", e);
            panic!("Creating the proof failed {}", e)
        }
    }
}

fn is_verbose() -> String {
    match std::env::var("FRIDGE_VERBOSE") {
        Ok(value) if value == "1" || value.eq_ignore_ascii_case("true") => "verbose".to_string(),
        _ => {
            unsafe {
                if VERBOSE {
                    "verbose".to_string()
                } else {
                    "".to_string()
                }
            }
        }
    }
}

/// Generates the proof of computation and returning the receipt as JSON
#[allow(clippy::too_many_arguments)]
fn proove_camt53(
    signed_info_xml_c14n: &str,
    authenticated_xml_c14n: &str,
    signature_value_xml: &str,
    order_data_xml: &str,
    bank_public_key_x002_pem: &str,
    user_private_key_e002_pem: &str,
    decrypted_tx_key_bin: &Vec<u8>,
    iban: &str,
    witness_signature_hex: &str,
    pub_witness_pem: &str,
    host_info: &str
) -> Result<Receipt, anyhow::Error> {
    v!("start: {}", Local::now().format("%Y-%m-%d %H:%M:%S"));
    // write image ID to filesystem
    let _ = write_image_id();

    // Todo:wasa
    // Using r0 implementation crypto-bigint does not work with RsaPUblicKey?
    // ==> Research shows not - needs reimplementation of RSA modue which might speed things up.

    // let exp_bigint = BigInt::from_str_radix(&BANK_X002_EXP, 10)
    // .expect("error parsing EXP of public bank key");
    // let modu_bigint = BigInt::from_str_radix(&BANK_X002_MOD, 10)
    // .expect("error parsing MODULUS of public bank key");

    // let exp_hex = format!("{:x}", exp_bigint);
    // let modu_hex = format!("{:x}", modu_bigint);

    // .write(&exp_hex).unwrap()
    // .write(&modu_hex).unwrap()

    // https://docs.rs/risc0-zkvm/latest/risc0_zkvm/struct.ExecutorEnvBuilder.html
    v!("Starting guest code, load environment");
    env_logger::init();
    let pem = parse(bank_public_key_x002_pem).expect("Failed to parse bank public key PEM");
    let bank_public_key = RsaPublicKey::from_public_key_pem(&pem::encode(&pem))
        .expect("Failed to create bank public key");
    let modulus_str = bank_public_key.n().to_str_radix(10);
    let exponent_str = bank_public_key.e().to_str_radix(10);

    let mut profiler = risc0_zkvm::Profiler::new("./profile-output", methods::HYPERFRIDGE_ELF).unwrap();

    let env = ExecutorEnv::builder()
        .write(&signed_info_xml_c14n)
        .unwrap()
        .write(&authenticated_xml_c14n)
        .unwrap()
        .write(&signature_value_xml)
        .unwrap()
        .write(&order_data_xml)
        .unwrap()
        .write(&modulus_str)
        .unwrap()
        .write(&exponent_str)
        .unwrap()
        .write(&user_private_key_e002_pem)
        .unwrap()
        .write(&decrypted_tx_key_bin)
        .unwrap()
        .write(&iban)
        .unwrap()
        .write(&host_info)
        .unwrap()
        .write(&witness_signature_hex)
        .unwrap()
        .write(&pub_witness_pem)
        .unwrap()
        .write(&is_verbose())
        .unwrap()  
        .trace_callback(profiler.make_trace_callback())
        .build().unwrap();

    // Obtain the default prover.
    let prover = default_prover();
    v!("prove hyperfridge elf ");
    // generate receipt
    let receipt_result = prover.prove_elf(env, HYPERFRIDGE_ELF);
    profiler.finalize();
    let report = profiler.encode_to_vec();
    v!("write profile size {}",report.len());
    std::fs::write("./profile-output", &report).expect("Unable to write profiling output");

    let image_id_hex = get_image_id_hex();
    v!(
        "got the receipt of the prove , id first 32u {} binary size of ELF binary {}k",
        image_id_hex,
        HYPERFRIDGE_ELF.len() / 1000
    );
    receipt_result
}

use std::fs::File;
use std::io::{Error, Write};

fn write_image_id() -> Result<(), Error> {
    // Write hex string to IMAGE_ID.hex
    let mut hex_file = File::create("./out/IMAGE_ID.hex")?;
    hex_file.write_all(get_image_id_hex().as_bytes())?;

    Ok(())
}

/// get image_id to a hexadecimal string
fn get_image_id_hex() -> String {
    HYPERFRIDGE_ID
        .iter()
        .fold(String::new(), |acc, &num| acc + &format!("{:08x}", num))
}

const TEST_EBICS_FILE: &str = "../data/test/test.xml";
const TEST_IBAN: &str = "CH4308307000289537312";
const TEST_BANKKEY: &str = "../data/pub_bank.pem";
const TEST_CLIENTKEY: &str = "../data/client.pem";
const TEST_WITNESSKEY: &str = "../data/pub_witness.pem";

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
#[clap(version = "1.0", author = "Hyperfridge")]
#[command(arg_required_else_help(true))]
struct Cli {
    #[arg(
        long,
        default_value = "false",
        help = "Verbose mode, false will only print the commitment as json."
    )]
    verbose: bool,

    #[arg(
        short,
        long,
        default_value = "true",
        help = "Call verify after creating the proof."
    )]
    verify: bool,

    #[arg(long, hide = true)]
    markdown_help: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

// https://docs.rs/clap/latest/clap/struct.Arg.html
// test locally with cargo:
// RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose prove-camt53  --request="../data/test/test.xml" --bankkey ../data/pub_bank.pem --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
// RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose test
// cargo run  -- --help
// cargo run  -- --verbose prove-camt53 --help
#[derive(Subcommand, Debug)]
enum Commands {
    /// Creates a proof for a camt53 file - show help with host prove-camt53 --help.
    /// Using provided test data, this is how it is used:
    /// host prove-camt53  --request="../data/test/test.xml" --bankkey ../data/pub_bank.pem --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
    ProveCamt53 {
        #[arg(
            short,
            long,
            help = "The ebics response file (XML) - assumes that the response has been pre-processed; or use --script=\"./data/checkResponse.sh\" to pre-process data.",
            value_name = "FILE",
            required = true
        )]
        request: Option<PathBuf>,

        #[arg(
            short,
            long,
            help = "PEM for the public key of the bank.",
            value_name = "FILE",
            required = true
        )]
        bankkey: Option<PathBuf>,

        #[arg(
            short,
            long,
            help = "PEM for the private key of the client.",
            value_name = "FILE",
            required = true
        )]
        clientkey: Option<PathBuf>,

        #[arg(
            short,
            long,
            help = "PEM for the public key of the witness.",
            value_name = "FILE",
            required = true
        )]
        witnesskey: Option<PathBuf>,

        #[arg(
            short = 'i',
            long,
            help = "IBAN of the account as used in camt53 files. Account statements not referring to this IBAN will be ignored when generating the proof.",
            required = true
        )]
        clientiban: String,

        #[arg(
            short,
            long,
            help = "Path to Shell Script which does pre-processing - if omitted, we assume pre-processing already happened.",
            required = false
        )]
        script: Option<PathBuf>,
    },
    /// Uses test data - sample call is:
    /// RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo run  -- --verbose test
    Test,
}

#[allow(dead_code)]
fn parse_cli() -> Cli {
    let cli = Cli::parse();

    unsafe {
        VERBOSE = cli.verbose;
    }
    cli
}

// For profiling, fun the test as follows - it is not activated in the standard tests. 
// RUST_LOG="executor=info" RUST_BACKTRACE=1 RISC0_DEV_MODE=true cargo test profid  -- --nocapture
// pprof -http=127.0.0.1:8089 ./host/target/riscv-guest/riscv32im-risc0-zkvm-elf/release/hyperfridge host/profile-output

#[cfg(test)]
mod tests {
    use crate::fs;
    use crate::{
        get_image_id_hex, proove_camt53, TEST_BANKKEY, TEST_CLIENTKEY, TEST_EBICS_FILE, TEST_IBAN,
        TEST_WITNESSKEY, VERBOSE,
    };

    use chrono::Local;
    use methods::HYPERFRIDGE_ID;
    use std::fs::File;
    use std::io::Write;

    #[test]
    fn do_main() {
        let now = Local::now();
        let timestamp_string = format!(
            "{}T{}",
            format!("{}", now.format("%Y-%m-%d")),
            format!("{}", now.format("%H:%M:%S"))
        );
        let host_info = format!("callinfo: {}, timestamp: {}", "do_main", &timestamp_string);

        let decrypted_tx_key_bin: &Vec<u8> =
            &fs::read(TEST_EBICS_FILE.to_string() + "-TransactionKeyDecrypt.bin")
                .expect("Failed to read transaction key file");

        let receipt_result = proove_camt53(
            fs::read_to_string(TEST_EBICS_FILE.to_string() + "-SignedInfo")
                .unwrap()
                .as_str(),
            fs::read_to_string(TEST_EBICS_FILE.to_string() + "-authenticated")
                .unwrap()
                .as_str(),
            fs::read_to_string(TEST_EBICS_FILE.to_string() + "-SignatureValue")
                .unwrap()
                .as_str(),
            fs::read_to_string(TEST_EBICS_FILE.to_string() + "-OrderData")
                .unwrap()
                .as_str(),
            fs::read_to_string(TEST_BANKKEY).unwrap().as_str(),
            fs::read_to_string(TEST_CLIENTKEY).unwrap().as_str(),
            decrypted_tx_key_bin,
            TEST_IBAN,
            fs::read_to_string(TEST_EBICS_FILE.to_string() + "-Witness.hex")
                .unwrap()
                .as_str(),
            fs::read_to_string(TEST_WITNESSKEY).unwrap().as_str(),
            &host_info,
        );

        match &receipt_result {
            Ok(_val) => {
                // v!("Receipt result: {}", val);_
                let receipt = receipt_result.unwrap();
                receipt
                    .verify(HYPERFRIDGE_ID)
                    .expect("Verification of receipt failed in test");
                let receipt_json =
                    serde_json::to_string(&receipt).expect("Failed to serialize receipt");
                v!("Receipt result: {:?}", &receipt_json);
                let journal = receipt.journal;
                v!(
                    "Receipt result (commitment) {}: ",
                    &(journal.decode::<String>().unwrap())
                );

                let filename = format!(
                    "{}-Receipt-{}-latest.json",
                    TEST_EBICS_FILE.to_string(),
                    get_image_id_hex()
                );
                let mut file =
                    File::create(filename).expect("Unable to create file with timestamp");
                file.write_all(receipt_json.as_bytes())
                    .expect("Unable to write data");
            }
            Err(e) => {
                eprintln!("Receipt error: {:?}", e);
            }
        }
    }
}
