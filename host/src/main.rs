
// These constants represent the RISC-V ELF and the image ID generated by risc0-build.
// The ELF is used for proving and the ID is used for verification.
use methods::{
    HYPERFRIDGE_ELF, // TODO: does not work, why? HYPERFRIDGE_ID
};
use risc0_zkvm::{default_prover, ExecutorEnv};

macro_rules! include_resource {
    ($file:expr) => {
        include_str!(concat!("../../data/er3.xml-orig-", $file))
    };
}

const SIGNED_INFO_XML_C14N: &str = include_resource!("SignedInfo");
const AUTHENTICATED_XML_C14N: &str = include_resource!("authenticated");
const SIGNATURE_VALUE_XML: &str = include_resource!("SignatureValue");
const ORDER_DATA_XML: &str = include_resource!("OrderData");
const USER_PRIVATE_KEY_E002_PEM: &str = include_str!("../../secrets/e002_private_key.pem");
const BANK_X002_MOD:&str="21524090256724430753141164535357196193197829951773396673897149554944452950696866451970472861932763191193568445765183992099613636142795752374489379772370669343448213653821892000554946389960903517318221964264342975374422650695173463691448081485863523220580649377592018038535843425153118082871773276341994344926781918685214779262529224767198147117671197644390419910537282768483198192468651239846388201830260805724659049813611048312053230240344724275567263285752460071116825269841133210376606159417744932436820868948917671457457542670698470415229193578914058282452054113544823576233190357144856848176044816602959795687329";
const BANK_X002_EXP:&str="65537";


// #[cfg(not(feature = "debug_mode"))]

risc0_zkvm::guest::entry!(main);

fn main() {
    env_logger::init();

    // Using crypto-bigint does not work with RsaPUblicKey

    // let exp_bigint = BigInt::from_str_radix(&BANK_X002_EXP, 10)
    // .expect("error parsing EXP of public bank key");
    // let modu_bigint = BigInt::from_str_radix(&BANK_X002_MOD, 10)
    // .expect("error parsing MODULUS of public bank key");

    // let exp_hex = format!("{:x}", exp_bigint);
    // let modu_hex = format!("{:x}", modu_bigint);

    // .write(&exp_hex).unwrap()
    // .write(&modu_hex).unwrap()

    // https://docs.rs/risc0-zkvm/latest/risc0_zkvm/struct.ExecutorEnvBuilder.html
    println!("Starting gues code, load environment");
    let env = ExecutorEnv::builder()
        .write(&SIGNED_INFO_XML_C14N).unwrap()
        .write(&AUTHENTICATED_XML_C14N).unwrap()
        .write(&SIGNATURE_VALUE_XML).unwrap()
        .write(&ORDER_DATA_XML).unwrap()
        .write(&BANK_X002_MOD).unwrap()
        .write(&BANK_X002_EXP).unwrap()
        .write(&USER_PRIVATE_KEY_E002_PEM).unwrap()
        .build().unwrap();

    // Obtain the default prover.
    let prover = default_prover();
    println!("prove hyperfridge elf"); 
    let receipt_result = prover.prove_elf(env, HYPERFRIDGE_ELF);
    println!("got the receipt of the prove ");
    // println!("----- got result {} ",receipt_result);

     match &receipt_result {
        Ok(_val) => {
            // println!("Receipt result: {}", val);_
            
            let receipt = receipt_result.unwrap();
            let journal= receipt.journal;
            println!("Receipt result - balance information {}", journal.decode::<String>().unwrap());
            //println!("Receipt result: {:?}", receipt.journal.decode().unwrap());

        },
        Err(e) => {
            println!("Receipt error: {:?}", e);
            //None
        },
    }
    // 31709.14

}

#[cfg(test)]
mod tests {
    use crate::main;
    #[test]
    fn do_main() {
        main();
        assert_eq!(1,1);
        // let data = include_str!("../res/example.json");
        // let outputs = super::search_json(data);
        // assert_eq!(
        //     outputs.data, 47,
        //     "Did not find the expected value in the critical_data field"
        // );
    }
}



// fn main() {
//         // Initialize tracing. In order to view logs, run `RUST_LOG=info cargo run`
//         env_logger::init();
    
//         // An executor environment describes the configurations for the zkVM
//         // including program inputs.
//         // An default ExecutorEnv can be created like so:
//         // `let env = ExecutorEnv::builder().build().unwrap();`
//         // However, this `env` does not have any inputs.
//         //
//         // To add add guest input to the executor environment, use
//         // ExecutorEnvBuilder::write().
//         // To access this method, you'll need to use ExecutorEnv::builder(), which
//         // creates an ExecutorEnvBuilder. When you're done adding input, call
//         // ExecutorEnvBuilder::build().
    
//         // For example:
//         let input: u32 = 15*2^27 + 1;
//         let env = ExecutorEnv::builder().write(&input).unwrap().build().unwrap();
    
//         // Obtain the default prover.
//         let prover = default_prover();
    
//         // Produce a receipt by proving the specified ELF binary.
//         let receipt = prover.prove_elf(env, HYPERFRIDGE_ELF).unwrap();
    
//         // TODO: Implement code for retrieving receipt journal here.
    
//         // For example:
//         let _output: u32 = receipt.journal.decode().unwrap();
    
//         // Optional: Verify receipt to confirm that recipients will also be able to
//         // verify your receipt
//         receipt.verify(HYPERFRIDGE_ID).unwrap();
//     }