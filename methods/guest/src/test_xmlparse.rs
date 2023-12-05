use rsa::BigUint;
use super::*;


// public keys hypi lenzburg - taken from keystore which was inspected after
// INI and HPB key exchange
// Extracted from serialized java objects 
const BANK_X002_EXP:&str="65537";
const BANK_X002_MOD:&str="21524090256724430753141164535357196193197829951773396673897149554944452950696866451970472861932763191193568445765183992099613636142795752374489379772370669343448213653821892000554946389960903517318221964264342975374422650695173463691448081485863523220580649377592018038535843425153118082871773276341994344926781918685214779262529224767198147117671197644390419910537282768483198192468651239846388201830260805724659049813611048312053230240344724275567263285752460071116825269841133210376606159417744932436820868948917671457457542670698470415229193578914058282452054113544823576233190357144856848176044816602959795687329";


#[test]
fn test_signature_x( ) {
  let exp:BigUint = BigUint::parse_bytes(BANK_X002_EXP.as_bytes(), 10).unwrap();//BigUint::from_bytes_be(EXP.as_bytes()); // Commonly used exponent
  let modu:BigUint = BigUint::parse_bytes(BANK_X002_MOD.as_bytes(), 10).unwrap();  //from_bytes_be(MOD.as_bytes()); // Your modulus as a BigUint
  let _public_key = RsaPublicKey::new(modu, exp).expect("Failed to create public key");
}

const USER_PRIVATE_KEY_E002_PEM: &str = include_str!("../../../secrets/e002_private_key.pem");
 
macro_rules! include_resource {
  ($file:expr) => {
      include_str!(concat!("../../../data/er3.xml-orig-", $file))
  };
}
const SIGNED_INFO_XML_C14N: &str = include_resource!("SignedInfo");
const AUTHENTICATED_XML_C14N: &str = include_resource!("authenticated");
const SIGNATURE_VALUE_XML: &str = include_resource!("SignatureValue");
const ORDER_DATA_XML: &str = include_resource!("OrderData");

#[test]
fn test_print_imports( ) {
  println!("{}",SIGNED_INFO_XML_C14N);
  println!("{}",AUTHENTICATED_XML_C14N);
  println!("{}",SIGNATURE_VALUE_XML);
}

#[test]
fn test_parse_signed_info( ) {

  // <ds:DigestValue>VkdMpq9P+oYx7NUp0JhQnZw/17yulOzmAzqJQvvnT0w=</ds:DigestValue>
  // <ds:SignatureValue>YmozAQZ66YHSqx0m68vlmWhjxV7KoFGlkn3oUTXnvdw6QnyYnlLCEgtoNPnoI9GIeuPVUZ1nQ4uz/P4G9hX/Gx6brf+6JSMy5DqIRaISmBN/BjmmGjM+cSlTpGBut0SDxNbf8H5fY2oLBzdwapI4LrTP9GwzPXuD+8nUqObLVDOL/tBXW3AIpf+0SmS8n80uJBADFdV3/u80+pLDZYaE+cId1Y9QvUBoew297cw+ZZiAy1Vt7FZFBA7RnIjL64ohdcYHKrjrtDI5EOk5rA39Iu0ANmMJsBfHchjnsUeBSOC3Lok8r1r3mb7C9c1OgaOOgLQy5k/pItAXemfGCNqcbg==</ds:SignatureValue>
  // <TransactionKey>ZX9km6Rg0Fghizh42Z+5VMoyGz9MFtPoBhmzDZq4V1TdBbraESTEpgXusr9vPiOx8uOJ097LWshc7uUNMK44KIo6+n4auaHUgUPnfDY9dsiqYTzdp7W7yZBXNcgWYKDxGOwCK9TZqQEgu+OdXv9GM8JEeT6AqaQwRMALzAaIZVFgxuVnJFc1HqESeoTon4jdPU38JsXSc9ukEVqFkDfYh+DCFYf0moxeBQ6WjJMuAM1GtHZHDXL3UyCoNkInmh3+zucshwcv70d2EcaDT7uHzR8MwFdjYAiLL8urQZcsPF/FNSzUZyWG0kDJWwxFR3G7nxWsF4Dn5s482UELLkJIJg==</TransactionKey>

  let res=parse_ebics_response(AUTHENTICATED_XML_C14N,SIGNED_INFO_XML_C14N,SIGNATURE_VALUE_XML,ORDER_DATA_XML);
  assert_eq!("VkdMpq9P+oYx7NUp0JhQnZw/17yulOzmAzqJQvvnT0w=",
        res.digest_value_b64,"res.digest_value_b64");
  assert_eq!("YmozAQZ66YHSqx0m68vlmWhjxV7KoFGlkn3oUTXnvdw6QnyYnlLCEgtoNPnoI9GIeuPVUZ1nQ4uz/P4G9hX/Gx6brf+6JSMy5DqIRaISmBN/BjmmGjM+cSlTpGBut0SDxNbf8H5fY2oLBzdwapI4LrTP9GwzPXuD+8nUqObLVDOL/tBXW3AIpf+0SmS8n80uJBADFdV3/u80+pLDZYaE+cId1Y9QvUBoew297cw+ZZiAy1Vt7FZFBA7RnIjL64ohdcYHKrjrtDI5EOk5rA39Iu0ANmMJsBfHchjnsUeBSOC3Lok8r1r3mb7C9c1OgaOOgLQy5k/pItAXemfGCNqcbg==",
        res.signature_value_b64,"res.signature_value_b64");
  assert_eq!("ZX9km6Rg0Fghizh42Z+5VMoyGz9MFtPoBhmzDZq4V1TdBbraESTEpgXusr9vPiOx8uOJ097LWshc7uUNMK44KIo6+n4auaHUgUPnfDY9dsiqYTzdp7W7yZBXNcgWYKDxGOwCK9TZqQEgu+OdXv9GM8JEeT6AqaQwRMALzAaIZVFgxuVnJFc1HqESeoTon4jdPU38JsXSc9ukEVqFkDfYh+DCFYf0moxeBQ6WjJMuAM1GtHZHDXL3UyCoNkInmh3+zucshwcv70d2EcaDT7uHzR8MwFdjYAiLL8urQZcsPF/FNSzUZyWG0kDJWwxFR3G7nxWsF4Dn5s482UELLkJIJg==",
        res.transaction_key_b64, "res.transaction_key_b64");
  
  let sha = *Impl::hash_bytes(SIGNED_INFO_XML_C14N.as_bytes());
  println!("sha {}",bytes_to_base64(sha.as_bytes()));

}

#[test]
fn test_digest() {
  //A SHA-256 digest is a 256-bit string. 
  //The content of the DigestValue element shall be the base64 
  //encoding of this bit string viewed as a 32-octet octet stream.
  let res=parse_ebics_response(AUTHENTICATED_XML_C14N,SIGNED_INFO_XML_C14N,SIGNATURE_VALUE_XML,ORDER_DATA_XML);
  let authenticated=AUTHENTICATED_XML_C14N.as_bytes();
  println!("  authenticated file length {:?}",&authenticated.len());
  
  let sha = *Impl::hash_bytes(&authenticated);
  // println!("  digest object {:?}",&sha);
  // println!("  digest calculated b64 {:?}",bytes_to_base64(sha.as_bytes()));
  // println!("  digest should be in b64  {:?}",res.digest_value_b64);
  // println!("  digest calculated hex {:?}",bytes_to_hex(sha.as_bytes()));
  // println!("  digest should be in hex  {:?}",base64_to_hex(&res.digest_value_b64));
  assert_eq!(res.digest_value_b64, bytes_to_base64(sha.as_bytes()));
}

#[test]
fn test_validate_signature( )  {//-> Result<bool, Box<dyn Error>> {
  //openssl pkeyutl  -verify -in "$signedinfo_digest_file" -sigfile "$signature_file" 
  //-pkeyopt rsa_padding_mode:pk1 -pkeyopt digest:sha256 -pubin -keyform PEM -inkey "$pem_file"
  let exp:BigUint = BigUint::parse_bytes(BANK_X002_EXP.as_bytes(), 10).unwrap();//BigUint::from_bytes_be(EXP.as_bytes()); // Commonly used exponent
  let modu:BigUint = BigUint::parse_bytes(BANK_X002_MOD.as_bytes(), 10).unwrap();  //from_bytes_be(MOD.as_bytes()); // Your modulus as a BigUint

  let bank_public_key = RsaPublicKey::new(modu, exp).expect("Failed to create public key");
  let request=parse_ebics_response(AUTHENTICATED_XML_C14N,SIGNED_INFO_XML_C14N,SIGNATURE_VALUE_XML,ORDER_DATA_XML);

  // let signed_data = base64_to_bytes(SIGNED_INFO_C14N);
  // let signature = base64_to_bytes(SIGNATURE_VALUE);
  //verify_signature(&bank_public_key, request);
    //let data_hash=base64_to_bytes(DIGEST);
  verify_bank_signature(&bank_public_key, &request);
}


#[test]
fn test_decrypt_txkey( )  {//-> Result<bool, Box<dyn Error>> {
  // openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
  let request=parse_ebics_response(AUTHENTICATED_XML_C14N,SIGNED_INFO_XML_C14N,SIGNATURE_VALUE_XML,ORDER_DATA_XML);
    // Parse the private key from PEM format
  let private_key = RsaPrivateKey::from_pkcs8_pem(USER_PRIVATE_KEY_E002_PEM).unwrap();
  let transaction_key_bin= decrypt_transaction_key(&request,&private_key);
  let files=decrypt_order_data(&request, &transaction_key_bin); 

  for (index, item) in files.iter().enumerate() {
    if index % 2 == 0 {
        // Odd entries (by zero-based index): Filenames
        let filename = String::from_utf8(item.clone())
            .expect("Failed to convert filename bytes to string");
        
        assert!(filename.ends_with(".xml"), "Filename does not end with .xml");
    } else {
        // Even entries: File contents
        let content_start = String::from_utf8(item[0..5].to_vec())
            .expect("Failed to convert content bytes to string");
        //println!(" file {}",String::from_utf8(item.to_vec()).unwrap());
        assert!(content_start == "<?xml", "File content does not start with <xml>");
      
    }
  }
}

#[test]
fn test_parse( )  {//-> Result<bool, Box<dyn Error>> {
  // openssl pkeyutl -decrypt -in ${txkey_file} -out transaction_key.bin -inkey e002_private_key.pem -pkeyopt rsa_padding_mode:pkcs1
  let request=parse_ebics_response(AUTHENTICATED_XML_C14N,SIGNED_INFO_XML_C14N,SIGNATURE_VALUE_XML,ORDER_DATA_XML);
  let private_key = RsaPrivateKey::from_pkcs8_pem(USER_PRIVATE_KEY_E002_PEM).unwrap();
  let transaction_key_bin= decrypt_transaction_key(&request,&private_key);
  let files=decrypt_order_data(&request, &transaction_key_bin); 

  for (index, item) in files.iter().enumerate() {
    if index  == 1 {
      let camt=parse_camt53(std::str::from_utf8(&item).expect("Failed to convert to string"));
    
      // <GrpHdr><MsgId>35e75effeaa74f579f97c8121bfa68ad</MsgId><CreDtTm>2023-11-29T22:54:31.6579278+01:00</CreDtTm>
      // <MsgPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></MsgPgntn></GrpHdr>

      assert_eq!(camt.grp_hdr.msg_id,"35e75effeaa74f579f97c8121bfa68ad");
      assert_eq!(camt.grp_hdr.cre_dt_tm,"2023-11-29T22:54:31.6579278+01:00");
      assert_eq!(camt.grp_hdr.pg_nb,1);
      assert_eq!(camt.grp_hdr.last_pg_ind,true);

      assert_eq!(camt.stmts[0].elctrnc_seq_nb,"247");
      assert_eq!(camt.stmts[0].iban,"CH4308307000289537312");
      assert_eq!(camt.stmts[0].cre_dt_tm,"2023-11-29T22:54:12.813");
      assert_eq!(camt.stmts[0].fr_dt_tm,"2023-11-29T00:00:00");
      assert_eq!(camt.stmts[0].to_dt_tm,"2023-11-29T00:00:00");

      //<BkToCstmrStmt> <Stmt> 
      //<Bal><Tp> <CdOrPrtry>Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.14</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>
      //<Bal><Tp> CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.09</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>
      assert_eq!(camt.stmts[0].balances[0].cd,"OPBD");
      assert_eq!(camt.stmts[0].balances[0].ccy,"CHF");
      assert_eq!(camt.stmts[0].balances[0].amt,"31709.14");
      assert_eq!(camt.stmts[0].balances[0].cdt_dbt_ind,"CRDT");
      assert_eq!(camt.stmts[0].balances[0].dt,"2023-11-29");

      assert_eq!(camt.stmts[0].balances[1].cd,"CLBD");
      assert_eq!(camt.stmts[0].balances[1].ccy,"CHF");
      assert_eq!(camt.stmts[0].balances[1].amt,"31709.09");
      assert_eq!(camt.stmts[0].balances[1].cdt_dbt_ind,"CRDT");
      assert_eq!(camt.stmts[0].balances[1].dt,"2023-11-29");

    }
  }
}

