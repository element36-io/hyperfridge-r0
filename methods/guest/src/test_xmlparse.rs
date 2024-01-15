use super::*;
use pem::parse;
use rsa::pkcs8::DecodePublicKey;

#[test]
fn test_signature_x() {
    // let exp:BigUint = BigUint::parse_bytes(BANK_X002_EXP.as_bytes(), 10).unwrap();//BigUint::from_bytes_be(EXP.as_bytes()); // Commonly used exponent
    // let modu:BigUint = BigUint::parse_bytes(BANK_X002_MOD.as_bytes(), 10).unwrap();  //from_bytes_be(MOD.as_bytes()); // Your modulus as a BigUint
    // let _public_key = RsaPublicKey::new(modu, exp).expect("Failed to create public key");

    // https://cryptoballot.com/doc/rsa/struct.RSAPublicKey.html
    let pem = parse(BANK_PUBLIC_KEY_X002_PEM).expect("Failed to parse PEM");
    let _public_key =
        RsaPublicKey::from_public_key_pem(&pem::encode(&pem)).expect("Failed to create public key");
}

const BANK_PUBLIC_KEY_X002_PEM: &str = include_str!("../../../data/pub_bank.pem");
const USER_PRIVATE_KEY_E002_PEM: &str = include_str!("../../../data/client.pem");
const TX_KEY_DECRYPTED: &[u8] =
    include_bytes!("../../../data/test/test.xml-TransactionKeyDecrypt.bin");

macro_rules! include_resource {
    ($file:expr) => {
        include_str!(concat!("../../../data/test/test.xml-", $file))
    };
}
const SIGNED_INFO_XML_C14N: &str = include_resource!("SignedInfo");
const AUTHENTICATED_XML_C14N: &str = include_resource!("authenticated");
const SIGNATURE_VALUE_XML: &str = include_resource!("SignatureValue");
const ORDER_DATA_XML: &str = include_resource!("OrderData");
const WITNESS_SIGNATURE_HEX: &str = include_resource!("Witness.hex");

#[test]
fn test_print_imports() {
    println!(" => {}", SIGNED_INFO_XML_C14N);
    println!(" => {}", AUTHENTICATED_XML_C14N);
    println!(" => {}", SIGNATURE_VALUE_XML);
}

#[test]
fn test_digest() {
    //A SHA-256 digest is a 256-bit string.
    //The content of the DigestValue element shall be the base64
    //encoding of this bit string viewed as a 32-octet octet stream.
    let res = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );
    let authenticated = AUTHENTICATED_XML_C14N.as_bytes();
    println!("  authenticated file length {:?}", &authenticated.len());

    let sha = *Impl::hash_bytes(authenticated);
    // println!("  digest object {:?}",&sha);
    // println!("  digest calculated b64 {:?}",bytes_to_base64(sha.as_bytes()));
    // println!("  digest should be in b64  {:?}",res.digest_value_b64);
    // println!("  digest calculated hex {:?}",bytes_to_hex(sha.as_bytes()));
    // println!("  digest should be in hex  {:?}",base64_to_hex(&res.digest_value_b64));

    assert_eq!(
        res.digest_value_b64,
        general_purpose::STANDARD.encode(sha.as_bytes())
    );
}

#[test]
fn test_validate_signature() {
    //-> Result<bool, Box<dyn Error>> {
    //openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"
    //-pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"

    let pem = parse(BANK_PUBLIC_KEY_X002_PEM).expect("Failed to parse bank public key PEM");
    let bank_public_key = RsaPublicKey::from_public_key_pem(&pem::encode(&pem))
        .expect("Failed to create bank public key");
    let request = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );

    verify_bank_signature(&bank_public_key, &request);
}

#[test]
fn test_validate_orderdata() {
    // openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file"
    //       -pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"

    let pem = parse(BANK_PUBLIC_KEY_X002_PEM).expect("Failed to parse bank public key PEM");
    let bank_public_key = RsaPublicKey::from_public_key_pem(&pem::encode(&pem))
        .expect("Failed to create bank public key");
    let request = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );

    let witness_signature_bytes= Vec::from_hex(&WITNESS_SIGNATURE_HEX).unwrap();

    verify_order_data_signature(&bank_public_key, &request, &witness_signature_bytes);
}

#[test]
fn test_decrypt_txkey() {
    // openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
    let request = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );
    // Parse the private key from PEM format
    let private_key = RsaPrivateKey::from_pkcs8_pem(USER_PRIVATE_KEY_E002_PEM).unwrap();
    let transaction_key_bin = decrypt_transaction_key(&request, &private_key, &Vec::new());
    assert_eq!(transaction_key_bin.len(), 16);
    let files = decrypt_order_data(&request, &transaction_key_bin);

    for (index, item) in files.iter().enumerate() {
        if index % 2 == 0 {
            // Odd entries (by zero-based index): Filenames
            let filename = String::from_utf8(item.clone())
                .expect("Failed to convert filename bytes to string");

            assert!(
                filename.ends_with(".xml"),
                "Filename does not end with .xml"
            );
        } else {
            // Even entries: File contents
            let content_start = String::from_utf8(item[0..5].to_vec())
                .expect("Failed to convert content bytes to string");
            //println!(" file {}",String::from_utf8(item.to_vec()).unwrap());
            assert!(
                content_start == "<?xml",
                "File content does not start with <xml>"
            );
        }
    }
}

#[test]
fn test_decrypt_txkey_reverse() {
    //-> Result<bool, Box<dyn Error>> {
    // openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
    let request = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );
    // Parse the private key from PEM format
    let private_key = RsaPrivateKey::from_pkcs8_pem(USER_PRIVATE_KEY_E002_PEM).unwrap();

    let transaction_key_bin =
        decrypt_transaction_key(&request, &private_key, &TX_KEY_DECRYPTED.to_vec());
    assert_eq!(transaction_key_bin.len(), 16);
    let files = decrypt_order_data(&request, &transaction_key_bin);

    for (index, item) in files.iter().enumerate() {
        if index % 2 == 0 {
            // Odd entries (by zero-based index): Filenames
            let filename = String::from_utf8(item.clone())
                .expect("Failed to convert filename bytes to string");

            assert!(
                filename.ends_with(".xml"),
                "Filename does not end with .xml",
            );
        } else {
            // Even entries: File contents
            let content_start = String::from_utf8(item[0..5].to_vec())
                .expect("Failed to convert content bytes to string");
            //println!(" file {}",String::from_utf8(item.to_vec()).unwrap());
            assert!(
                content_start == "<?xml",
                "File content does not start with <xml>"
            );
        }
    }
}

#[test]
fn test_parse() {
    //-> Result<bool, Box<dyn Error>> {
    // openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
    let request = parse_ebics_response(
        AUTHENTICATED_XML_C14N,
        SIGNED_INFO_XML_C14N,
        SIGNATURE_VALUE_XML,
        ORDER_DATA_XML,
    );
    let private_key = RsaPrivateKey::from_pkcs8_pem(USER_PRIVATE_KEY_E002_PEM).unwrap();
    let transaction_key_bin = decrypt_transaction_key(&request, &private_key, &Vec::new());
    let files = decrypt_order_data(&request, &transaction_key_bin);

    for (index, item) in files.iter().enumerate() {
        if index == 1 {
            let camt =
                parse_camt53(std::str::from_utf8(item).expect("Failed to convert to string"));

            // <GrpHdr><MsgId>35e75effeaa74f579f97c8121bfa68ad</MsgId><CreDtTm>2023-11-29T22:54:31.6579278+01:00</CreDtTm>
            // <MsgPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></MsgPgntn></GrpHdr>

            assert_eq!(camt.grp_hdr.msg_id, "35e75effeaa74f579f97c8121bfa68ad");
            assert_eq!(camt.grp_hdr.cre_dt_tm, "2023-11-29T22:54:31.6579278+01:00");
            assert_eq!(camt.grp_hdr.pg_nb, 1);
            assert!(camt.grp_hdr.last_pg_ind);

            assert_eq!(camt.stmts[0].elctrnc_seq_nb, "247");
            assert_eq!(camt.stmts[0].iban, "CH4308307000289537312");
            assert_eq!(camt.stmts[0].cre_dt_tm, "2023-11-29T22:54:12.813");
            assert_eq!(camt.stmts[0].fr_dt_tm, "2023-11-29T00:00:00");
            assert_eq!(camt.stmts[0].to_dt_tm, "2023-11-29T00:00:00");

            //<BkToCstmrStmt> <Stmt>
            //<Bal><Tp> <CdOrPrtry>Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.14</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>
            //<Bal><Tp> CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.09</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>
            assert_eq!(camt.stmts[0].balances[0].cd, "OPBD");
            assert_eq!(camt.stmts[0].balances[0].ccy, "CHF");
            assert_eq!(camt.stmts[0].balances[0].amt, "31709.14");
            assert_eq!(camt.stmts[0].balances[0].cdt_dbt_ind, "CRDT");
            assert_eq!(camt.stmts[0].balances[0].dt, "2023-11-29");

            assert_eq!(camt.stmts[0].balances[1].cd, "CLBD");
            assert_eq!(camt.stmts[0].balances[1].ccy, "CHF");
            assert_eq!(camt.stmts[0].balances[1].amt, "31709.09");
            assert_eq!(camt.stmts[0].balances[1].cdt_dbt_ind, "CRDT");
            assert_eq!(camt.stmts[0].balances[1].dt, "2023-11-29");
        }
    }
}
