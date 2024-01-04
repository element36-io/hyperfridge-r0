// #![no_main]
// #![forbid(unsafe_code)]
#![cfg_attr(not(feature = "debug_mode"), no_main)]

// If you want to try std support, also update the guest Cargo.toml file
// #![no_std]  // std support is experimental

// #[cfg(not(feature = "debug_mode"))]
// #[cfg_attr(not(feature = "debug_mode"), no_main)]


use core::panic;
use miniz_oxide::inflate::decompress_to_vec_zlib;
use risc0_zkvm::{
    guest::env,
    sha::{Impl, Sha256},
};
use rsa::{RsaPublicKey,RsaPrivateKey,Pkcs1v15Sign};
use rsa::{traits::PublicKeyParts, Pkcs1v15Encrypt, pkcs8::DecodePrivateKey};
use rsa::BigUint;

use xmlparser::{Tokenizer,Token,ElementEnd};
use sha2::Sha256 as RsaSha256;
use base64::{Engine as _, engine::general_purpose};

use hex::encode as hex_encode;


#[cfg(not(feature = "debug_mode"))]
risc0_zkvm::guest::entry!(main);

#[cfg(test)]
mod test_xmlparse;

#[allow(dead_code)]
#[derive(Debug)]
struct EbicsRequestData {
    host_id: String,
    timestamp:String,
    order_type:String,
    x002: String,
    e002: String,
    digest_value: String,
    signature_value: String,
}

pub fn main() {
    let signed_info_xml_c14n:String = env::read();
    let authenticated_xml_c14n :String= env::read();
    let signature_value_xml:String  = env::read();
    let order_data_xml:String  = env::read();
    let order_data_digest_xml:String  = env::read();
    let public_key_mod:String = env::read();
    let public_key_exp:String = env::read();
    let private_key_pem:String = env::read();
    let decrypted_tx_key_bin:Vec<u8>=env::read();

    let exp:BigUint = BigUint::parse_bytes(public_key_exp.as_bytes(),10).expect("error parsing EXP of public bank key");//BigUint::from_bytes_be(EXP.as_bytes()); // Commonly used exponent
    let modu:BigUint = BigUint::parse_bytes(public_key_mod.as_bytes(),10).expect("error parsing MODULUS of public bank key");  //from_bytes_be(MOD.as_bytes()); // Your modulus as a BigUint


    // U256, use crypto_bigint::U256; does not work with RsaPublicKey
    // let exp = U256::from_be_hex(&public_key_exp);
    // let modu = U256::from_be_hex(&public_key_mod);

    let public_key = RsaPublicKey::new( modu,exp).expect("Failed to create public key");
    let private_key = RsaPrivateKey::from_pkcs8_pem(&private_key_pem).expect("Failed to create private key form pem");

    // do the actual work
    let document=load(&authenticated_xml_c14n,&signed_info_xml_c14n,
            &signature_value_xml,&order_data_xml, &order_data_digest_xml, &public_key,&private_key,&decrypted_tx_key_bin);

    println!(">>> cycle count {}k", (env::get_cycle_count())/1000);
    env::log("proof done walter"); // writes to journal
    env::log(&document.stmts[0].balances[0].amt);

    // public committed data, that is what we want to prove
    env::commit(&document.stmts[0].elctrnc_seq_nb);
    env::commit(&document.stmts[0].iban);
    env::commit(&document.stmts[0].fr_dt_tm);
    env::commit(&document.stmts[0].to_dt_tm);
    env::commit(&document.stmts[0].balances[0].amt);
}

/// Calls all the steps necessary for the proof.
fn load(authenticated_xml_c14n: &str,
    signed_info_xml_c14n: &str, 
    signature_value_xml: &str,
    order_data_xml :&str, 
    order_data_digest_xml: &str,
    public_key: &RsaPublicKey, 
    private_key: &RsaPrivateKey,
    encrypted_tx_key:&Vec<u8> ,
    ) -> Document {
    // star is with 1586k
    println!(" >>>>> Cycle count start {}k",(env::get_cycle_count())/1000);

    // cycle count 1864k (plus 3k)
    let request=parse_ebics_response(&authenticated_xml_c14n,
                    &signed_info_xml_c14n, 
                    &signature_value_xml,
                    &order_data_xml,
                    &order_data_digest_xml,);
    println!(" >>>>>  Cycle count parse_ebics_response {}k",(env::get_cycle_count())/1000);

    // cycle count 12635k (plus 10k)
    verify_bank_signature( &public_key, &request);
    println!(" >>>>> Cycle count verify_bank_signature {}k",(env::get_cycle_count())/1000);

    // cycle count 23336k (plus 10k)
    verify_order_data_signature( &public_key, &request);
    println!(" >>>>> Cycle count verify_order_data_signature {}k",(env::get_cycle_count())/1000);
    
    // cycle count 33979k (plus 10k)
    let transaction_key=decrypt_transaction_key(&request,private_key,encrypted_tx_key);
    println!(" >>>>> Cycle count decrypt_transaction_key {}k",(env::get_cycle_count())/1000);

    // cycle count 35906k (plus 2k)
    let order_data=decrypt_order_data(&request, &transaction_key);
    println!(" >>>>> Cycle count decrypt_order_data {}k",(env::get_cycle_count())/1000);

    // cycle count 36330k (plus 1k)
    let document=parse_camt53(std::str::from_utf8(&order_data[1].to_vec()).unwrap());
    println!(" >>>>> Cycle count parse_camt53 {}k",(env::get_cycle_count())/1000);
    document
}


///
/// Returns the digest value of a given public key - needs to match  with published hash
///
///
/// <p>In Version “H003” of the EBICS protocol the ES of the financial:
///
/// <p>The SHA-256 hash values of the financial institution's public keys for X002 and E002 are
/// composed by concatenating the exponent with a blank character and the modulus in hexadecimal
/// representation (using lower case letters) without leading zero (as to the hexadecimal
/// representation). The resulting string has to be converted into a byte array based on US ASCII
/// code.
///
#[allow(dead_code)]
fn get_private_key_hex(pk: &RsaPublicKey) -> String {
    let exponent = pk.e().to_bytes_be(); // Convert exponent to big-endian bytes
    let modulus = pk.n().to_bytes_be(); // Convert modulus to big-endian bytes

    // Convert bytes to lower case hexadecimal string
    let exponent_hex = hex::encode(exponent).trim_start_matches('0').to_lowercase();
    let modulus_hex = hex::encode(modulus).trim_start_matches('0').to_lowercase();
    
    // Verify that all characters are ASCII
    if !exponent_hex.is_ascii() || !modulus_hex.is_ascii() {
        panic!("Non-ASCII characters found in hexadecimal strings");
    }
    // Concatenate with a blank space
    let combined = format!("{} {}", exponent_hex, modulus_hex);

    // Convert to ASCII byte array
    let ascii_bytes = combined.as_bytes();

    // Compute SHA-256 hash
    let sha = *Impl::hash_bytes(&ascii_bytes);

    // Convert hash to hexadecimal string
    hex::encode(sha.as_bytes())

}


/// https://datatracker.ietf.org/doc/html/rfc3275#section-3.1.2
/// Signature Generation
/// https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf
/// 5.5.1.2.1 Processing in the initialisation phase 
///
///    1. Create SignedInfo element with SignatureMethod,
///       CanonicalizationMethod and Reference(s).
///    2. Canonicalize and then calculate the SignatureValue over SignedInfo
///       based on algorithms specified in SignedInfo.
///       3. Construct the Signature element that includes SignedInfo,
///       Object(s) (if desired, encoding may be different than that used
///       for signing), KeyInfo (if required), and SignatureValue.
///
///    Note, if the Signature includes same-document references, [XML] or
///    [XML-schema] validation of the document might introduce changes that
///    break the signature.  Consequently, applications should be careful to
///    consistently process the document or refrain from using external
///    contributions (e.g., defaults and entities).
///
/// Signature Validation
///
///    1. Obtain the keying information from KeyInfo or from an external
///       source.
///    2. Obtain the canonical form of the SignatureMethod using the
///       CanonicalizationMethod and use the result (and previously obtained
///       KeyInfo) to confirm the SignatureValue over the SignedInfo
///       element.
///
///    Note, KeyInfo (or some transformed version thereof) may be signed via
///    a Reference element.  Transformation and validation of this reference
///    (3.2.1) is orthogonal to Signature Validation which uses the KeyInfo
///    as parsed.
///
///    Additionally, the SignatureMethod URI may have been altered by the
///    canonicalization of SignedInfo (e.g., absolutization of relative
///    URIs) and it is the canonical form that MUST be used.  However, the
///    required canonicalization [XML-C14N] of this specification does not
///    change URIs.
fn verify_bank_signature(
    public_key: &RsaPublicKey, 
    request: &Request, 
)  {
    println!(" verify the bank signature");
    // Decode the signature
    let signature_value_bytes =  general_purpose::STANDARD.decode(&request.signature_value_b64).unwrap();

    // Create a signer with PKCS#1 v1.5 padding - from the standard: 
    //     2.3.2 RSA-SHA256
    //    Identifier:
    //         http://www.w3.org/2001/04/xmldsig-more#rsa-sha256

    //    This implies the PKCS#1 v1.5 padding algorithm [RFC3447] as described
    //    in section 2.3.1 but with the ASN.1 BER SHA-256 algorithm designator
    //    prefix. 
    
    let scheme = Pkcs1v15Sign::new::<RsaSha256>();
    // println!("{} {}",request.signed_info_hashed.len(),signature_value_bytes.len());
    // println!("hash digest {} ", &*Impl::hash_bytes(&request.signed_info_hashed)); 
    // println!("hash signature {} ", &*Impl::hash_bytes(&signature_value_bytes));
    
    // Verify the signature
    let res=  public_key.verify( scheme ,// verifying_key.verify(//public_key.verify( scheme ,
        &request.signed_info_hashed,
        &signature_value_bytes
    );
    // println!(" res ---->  {:?}",&res);
    match res {
        Ok(_) => println!("  bank Signature is verified"),
        Err(e) => {eprintln!(" ---> error {:?}",e);panic!("  bank Signature could not be verified")}
    };
}

/// Check Signature of Payload 
fn verify_order_data_signature(
    public_key: &RsaPublicKey, 
    request: &Request, 
)  {
    println!(" verify the bank signature");
    // Decode the signature
    let signature_value_bytes =  general_purpose::STANDARD.decode(&request.signature_data_b64).unwrap();
    let signature_data_hashed =  general_purpose::STANDARD.decode(&request.data_digest_b64).unwrap();

    // We checked for Schema A005  which enforces: 
    let scheme = Pkcs1v15Sign::new::<RsaSha256>();

    // Verify the signature
    let res=  public_key.verify( scheme ,// verifying_key.verify(//public_key.verify( scheme ,
        &signature_data_hashed,
        &signature_value_bytes
    );

    match res {
        Ok(_) => println!(" Order Data is verified"),
        Err(e) => {eprintln!(" ---> error {:?}",e);panic!(" Order Data Signature could not be verified")}
    };
}

#[allow(dead_code)]
#[derive(Debug)]
struct Request {
    digest_value_b64:String,
    autheticated_hashed:Vec<u8>,
    bank_timestamp:String,
    transaction_key_b64:String,
    signature_value_b64:String,
    signed_info_hashed:Vec<u8>,
    order_data_b64:String,
    signature_data_b64:String,
    data_digest_b64:String,
}



/// Parse the XML file, return a structure
/// See  https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf
/// Chapter 5.6.1.1.2

fn parse_ebics_response(authenticated_xml_c14n: &str,
                signed_info_xml_c14n: &str, 
                signature_value_xml: &str,
                order_data_xml:&str,
                order_data_digest_xml:&str) -> Request {

    let mut curr_tag: &str= "";

    let mut digest_value_b64: String=String::new();
    let mut signature_value_b64: String=String::new();
    let mut signature_data_b64: String=String::new();
    let mut data_digest_b64: String=String::new();
    let mut bank_timestamp: String=String::new();
    let mut transaction_key_b64: String=String::new();
    let mut order_data_b64: String=String::new();
    

    // digest over all tags with authenticated=true; later check it with digest_value_b64 
    let calculated_digest_b64 = general_purpose::STANDARD.encode(&*Impl::hash_bytes(authenticated_xml_c14n.as_bytes()).as_bytes());
    let signed_info_hashed: Vec<u8> = (*Impl::hash_bytes(signed_info_xml_c14n.as_bytes())).as_bytes().to_vec();
    //let tokens=Tokenizer::from(xml_data); // use from_fragment so deactive xml checks
    let all_tags=format!("{}{}{}{}{}", 
                    authenticated_xml_c14n, signed_info_xml_c14n,signature_value_xml,order_data_xml,order_data_digest_xml);
    let tokens=Tokenizer::from_fragment(&all_tags,0..all_tags.len());
    //  0..full_text.len()

   
    for token in tokens {
        match token {
            Ok(Token::ElementStart { local, .. }) => {
                //println!("   open tag  as_str {:?}", local.as_str());
                curr_tag=local.as_str();
            },
            Ok(Token::ElementEnd {end,..}) => {
                match end {
                    ElementEnd::Close(.., _local) => {
                        //println!("   close tag  as_str {:?}", _local.as_str());
                        // handling Close variant
                        curr_tag = "";
                
                    },
                    // Handle other variants of ElementEnd if necessary
                    _ => {}
                }
            },            
            //  <SegmentNumber lastSegment="true">1</SegmentNumber> needs to be found
            Ok(Token::Attribute { local, value, .. }) if (curr_tag == "SegmentNumber" )  => {
                if !(local=="lastSegment" && value=="true") {panic!(" not the last segment")};
            },
            
            Ok(Token::Text { text }) if curr_tag == "SegmentNumber" => {
                if !(text == "1") {panic!("only one segment implemented")};
            },
            //  <ds:DigestValue>qcP1kr+olKNTe23cugTwL+76sZEmD7nMQT6SjZwOlyg=</ds:DigestValue>
            Ok(Token::Text { text }) if curr_tag == "DigestValue" => {
                digest_value_b64 = text.to_string();
                assert_eq!(digest_value_b64,calculated_digest_b64, " hash of all c41n-ized tags with authenticate=true do not match the provided hash. 
                                As the XML standard for c14n does not remove blanks between tags, you need to check
                                exactly the same character string which has been used to generate the hash, which is 
                                usually available in the direct response of the banking backend. ");
            },
            // <ds:SignatureValue>WW6VtstkLq+c8YKP6a1i6AijJlAAPEm9WChBDSjKU7zUI3DxKUvRPEGoNpPlJk....zxvIpJSZTSh920UAwZUFy3pmJzZC9AGieIALQ==</ds:SignatureValue>
            Ok(Token::Text { text }) if curr_tag == "SignatureValue" => {
                signature_value_b64 = text.to_string();
            },            
            // <TransactionKey>XTKNSQh2cXKEM4WR/t4fMrl2QnD1YhO6IVDg8ZHz+81rwwd88NNZFr8T6wU8lHs5bj....Z32QDsom6zzEMyedKePYbxxxpAAk0RWhPQG/ZTw==</TransactionKey>
            Ok(Token::Text { text }) if curr_tag == "TransactionKey" => {
                transaction_key_b64 = text.to_string();
            },
            // <TimestampBankParameter authenticate="true">2023-11-25T06:00:54.7545059Z</TimestampBankParameter>
            Ok(Token::Text { text }) if curr_tag == "TimestampBankParameter" => {
                bank_timestamp = text.to_string();
            },
            Ok(Token::Text { text }) if curr_tag == "SignatureData" => {
                signature_data_b64 = text.to_string();
            },
            Ok(Token::Text { text }) if curr_tag == "DataDigest" => {
                data_digest_b64 = text.to_string();
            },
            Ok(Token::Attribute { local, value, .. }) if (curr_tag == "DataDigest" )  => {
                if !(local=="SignatureVersion" && value=="A005") {panic!(" Only Signatures A005 supported.")};
            },
            Ok(Token::Text { text }) if curr_tag == "OrderData" => {
                order_data_b64 = text.to_string();
            },
            Ok(_) => {},
            Err(e) => {
                println!("Error parsing XML: {:?}", e);
                panic!("error parsing ebics response");
            },
        }
    }

    assert_ne!(digest_value_b64.len(),0);
    assert_ne!(transaction_key_b64.len(),0);
    assert_ne!(bank_timestamp.len(),0);
    assert_ne!(signature_value_b64.len(),0);
    assert_ne!(signed_info_hashed.len(),0);
    assert_ne!(order_data_b64.len(),0);
    assert_ne!(signature_data_b64.len(),0);
    assert_ne!(data_digest_b64.len(),0);

    let authenticated_xml_c14n_hashed=*Impl::hash_bytes(authenticated_xml_c14n.as_bytes());

    Request {digest_value_b64:digest_value_b64,
            autheticated_hashed:authenticated_xml_c14n_hashed.as_bytes().to_vec(),
            transaction_key_b64:transaction_key_b64,
            bank_timestamp:bank_timestamp, 
            signature_value_b64:signature_value_b64,
            signed_info_hashed:signed_info_hashed,
            order_data_b64:order_data_b64,
            signature_data_b64:signature_data_b64,
            data_digest_b64:data_digest_b64,
        }
 
   
}


/// The Transaction key is transmitted as base64. 
/// The used this transaction key to encrypt the payload,
/// and is integrated in the Ebics Response file encrypted with the 
/// public key of the client, which is exchanged when setting up the 
/// Ebics connection between bank and client (see HIA and INI requests)
/// 
/// See  https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf
/// Chapter 6.2 and 11.3.2
/// The order data and ES’s of an EBICS transaction are symmetrically encrypted. For each
/// EBICS transaction, a random symmetrical key (transaction key) is generated by the sender
/// of order data and/or ES’s that is used for encryption of both the order data and the ES’s. The
/// symmetrical key is transmitted to the recipient asymmetrically-encoded.
/// Generation of the transaction key (see Appendix, Chapter 15)
/// -AES-128 (key length 128 bit) in CBC mode
/// -ICV (Initial Chaining Value) = 0
/// -Padding process in accordance with ANSI X9.23 / ISO 10126-2.
/// 
/// Encryption of the messages
/// Padding of the message:
/// The method Padding with Octets in accordance with ANSI X9.23 is used for padding the
/// message, i.e. in all cases, data is appended to the message that is to be encrypted.
/// Application of the encryption algorithm:
/// The message is encrypted in CBC mode in accordance with ANSI X3.106 with the secret key
/// DEK according to the 2-key triple DES process as specified in ANSI X3.92-1981.
/// In doing this, the following initialisation value “ICV” is used: X ‘00 00 00 00 00 00 00 00’.

fn decrypt_transaction_key(request: &Request, private_key: &RsaPrivateKey,decrypted_tx_key: &Vec<u8> ) -> Vec<u8> {
    // as RSA decrypting is very expensive, be can provide the decrypted tx key externally. 
    let transaction_key_bin=general_purpose::STANDARD.decode(&request.transaction_key_b64).unwrap();

    if !decrypted_tx_key.is_empty() { // its still padded
        println!("WARNING: binary transaction key was provided - we use this to decrypt");
        let pub_key = RsaPublicKey::from(private_key);
        // https://docs.rs/rsa/latest/rsa/hazmat/fn.rsa_encrypt.html
        // Raw RSA encryption and "hazmat" is considered "OK", because do do not use the encryption.
        // We check if if provided decrypted key was using the decrypted key in the XML as source.
        let encrypted_recreated =  rsa::hazmat::rsa_encrypt(&pub_key, &BigUint::from_bytes_be(&decrypted_tx_key)).unwrap();

        // most important - check if the recreated, encrypted tx key equalx to the one provided by the XML file 
        assert_eq!(BigUint::from_bytes_be(&transaction_key_bin),encrypted_recreated);

        // lets return the decrypted tx key from the provided one - so we do not have to to the expensive RSA.decrypt.
        // remove the padding, return the decrypted key
        // Ensure that the data is long enough and has the correct PKCS#1 v1.5 padding prefix.
        assert!(decrypted_tx_key.len() >= 3, "Invalid data: Too short to contain PKCS#1 v1.5 padding");
        assert!(decrypted_tx_key[0] == 0x00, "Invalid data: Missing initial 0x00 in PKCS#1 v1.5 padding");
        assert!(decrypted_tx_key[1] == 0x02, "Invalid data: Missing 0x02 following the initial 0x00 in PKCS#1 v1.5 padding");

        // look for first 00 which marks the end of the padding - but be aware that the padding always starts with 0002
        match decrypted_tx_key.iter().skip(4).position(|&x| x == 0x00).map(|p| p + 1) {
            Some(padding_end) if padding_end > 2 => {
                return decrypted_tx_key[(padding_end+4)..].to_vec()
            },
            _ => panic!("Invalid data: Padding format incorrect or missing")
        }
    }

    // remove pemm feature, initialize with numbers - less code, more efficent?
    
    println!(" start decrypt transaction key with Pkcs1v15 Rsa");
    // Decrypt with PKCS1 padding
    let decrypted_data = private_key.decrypt(
        Pkcs1v15Encrypt,
        &transaction_key_bin,
    );

    // todo: check error handling (panics)
    match decrypted_data {
        Ok(res) => {
            println!("  transaction key to decrypt payload could be decrypted");
            res
        },
        Err(e) => {
            println!("{}",e);
            panic!(" transaction key to decrypt payload could __NOT__ be decrypted");
                       
        }
    }
}

use aes::cipher::{block_padding::NoPadding, KeyIvInit,BlockDecryptMut};
type Aes128CbcDec = cbc::Decryptor<aes::Aes128>;
// Dastan - can we get rid of this?
use std::io::{Read, Cursor};
use zip::ZipArchive;

/// using the decrypted transaction key, lets decrypt the payload.  
/// The payload is considered a stream which is compressed with the deflate alogrithm. 
/// The stream is actually a ZIP file, which containts the XML documents which hold the 
/// daily statements and account data. 
fn decrypt_order_data(request: &Request, transaction_key_bin: &[u8]) -> Vec<Vec<u8>> {
    println!(" decrypting payload with transaction key");
    
    let order_data_bin =general_purpose::STANDARD.decode(&&request.order_data_b64).unwrap();
    // Todo: walter - check Digest first if it matches the xml
       // Compute SHA-256 hash
    let sha = *Impl::hash_bytes(&order_data_bin);

    // Convert hash to hexadecimal strings
    let sha_hex=hex_encode(sha.as_bytes());
    let sha_hex_xml=hex_encode(general_purpose::STANDARD.decode(&request.data_digest_b64).unwrap());
    assert_eq!(&sha_hex,&sha_hex_xml,"Digest (<DataDigest ..> does not match digest of data");


    // does the following:
    // openssl enc -d -aes-128-cbc -nopad -in orderdata_decoded.bin -out $decrypted_file -K ${transaction_key_hex} -iv 00000000000000000000000000000000
    // Decrypt the AES key using RSA (not shown, replace with your RSA decryption code)
    // Create an AES-128-CBC cipher instance
    let iv: [u8; 16] = [0; 16];

    // https://docs.rs/crate/stegosaurust/latest/source/src/crypto.rs
    // Create an AES-128-CBC cipher instance
    let pt = Aes128CbcDec::new_from_slices(&transaction_key_bin, &iv).unwrap();

    // http://www.ietf.org/rfc/rfc1950.txt http://www.ietf.org/rfc/rfc1951.txt
    let mut result_bytes = vec![0u8; order_data_bin.len()]; // Output buffer with the same size as input

    let decrypted_data=pt.decrypt_padded_b2b_mut::<NoPadding>(&order_data_bin, &mut result_bytes).unwrap();
    let decompressed = decompress_to_vec_zlib(&decrypted_data).expect("Failed to decompress!");
    let cursor = Cursor::new(decompressed);
    let mut archive = ZipArchive::new(cursor).expect("Failed to read ZIP archive");

    let mut file_contents: Vec<Vec<u8>> = Vec::new();
    for i in 0..archive.len() {
        let mut file = archive.by_index(i).expect("Failed to read file in ZIP archive");

        // Convert filename to Vec<u8> and push it to file_contents
        let filename = file.name().to_string().into_bytes();
        file_contents.push(filename);

        // Read file contents into Vec<u8> and push it to file_contents
        let mut contents = Vec::new();
        file.read_to_end(&mut contents).expect("Failed to read file content");
        file_contents.push(contents);
    }

    file_contents
}
/// Root structure of a Camt53 XML respose
#[derive(Debug,Default)]
struct Document{
    grp_hdr:GrpHdr, // creatin time
    stmts: Vec<Stmt>,
}
/// GrpHdr structure of a Camt53 XML respose
#[derive(Debug,Default)]
struct GrpHdr{
    cre_dt_tm:String, // creating time
    msg_id:String,  // unique ebics message id - identifies ebics xml message
    pg_nb:i8,
    last_pg_ind:bool,
}
/// Stmt structure of a Camt53 XML respose
#[derive(Debug,Default)]
struct Stmt {
    elctrnc_seq_nb:String,
    iban:String,
    cre_dt_tm:String, // creatin time
    fr_dt_tm:String,
    to_dt_tm:String,
    balances:Vec<Balance>
}
/// Balance structure of a Camt53 XML respose
/// code or proprietory - OPBD = opening balance,CLBD is closing balance
/// cdt_dbt_ind  - creit or debit indicator - plus or minus of the balance
#[derive(Debug,Default)]
struct Balance {
    cd:String, // code or proprietory - OPBD = opening balance,CLBD is closing balance 
    ccy:String, // currency 
    amt:String,
    dt:String,
    cdt_dbt_ind:String, // cdt_dbt_ind  - creit or debit indicator - plus or minus of the balance
}

/// parses a Camt53 File which is decrypted and decompressed from the payload which is stored 
/// as base64 in the Ebics Response XML.
/// It get information from ISO20022 camt53 which hold bank data.
fn parse_camt53(camt53_file: &str)  -> Document {
    println!(" parsing payload to extract data to commit");
    let mut tag_stack: Vec<String> = Vec::new();
    let mut current_balance=Balance::default();
    let mut grp_header=GrpHdr::default();
    let mut current_stmt=Stmt::default();
    let mut current_tag=String::new();
    let mut doc:Document=Document::default();

    let tokens=Tokenizer::from(camt53_file);

    for token in tokens {
        match token {
            Ok(Token::ElementStart { local, .. }) => {
                current_tag=local.to_string();
                tag_stack.push(local.to_string());
                // println!("   open tag  as_str {:?} ", local.as_str());
            },
            Ok(Token::ElementEnd {end,..}) => {
                match end {
                    ElementEnd::Close(.., local) => {
                        if let Some(_tag) = tag_stack.pop() {
                            // println!("End Tag: {}", _tag);
                        };
                        if local=="Bal" {
                            current_stmt.balances.push(current_balance);
                            current_balance=Balance::default();
                            
                        } else if local=="Stmt" {
                            doc.stmts.push(current_stmt);
                            current_stmt=Stmt::default();
                        }
                    },
                    // Handle other ElementEnd Tags if necessary
                    _ => {}
                }
            },            
            Ok(Token::Text { text })  => {
                if let Some(_current_tag) = tag_stack.last() {
                    //println!("Text for {}: {}", _current_tag, text);
                };

                
                //<GrpHdr><MsgId>35e75effeaa74f579f97c8121bfa68ad</MsgId><CreDtTm>2023-11-29T22:54:31.6579278+01:00</CreDtTm><MsgPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></MsgPgntn></GrpHdr>
                if tag_stack.starts_with(&["Document".to_string(),"BkToCstmrStmt".to_string(), "GrpHdr".to_string()]) {
                    if tag_stack.ends_with(&["MsgId".to_string()]) { 
                        grp_header.msg_id=text.to_string(); 
                    }
                    if tag_stack.ends_with(&["CreDtTm".to_string()]) { 
                        grp_header.cre_dt_tm=text.to_string(); 
                    }
                    if tag_stack.ends_with(&["PgNb".to_string()]) { 
                        grp_header.pg_nb=text.to_string().parse::<i8>().expect("Failed to parse text as integer i8");
                    }
                    if tag_stack.ends_with(&["LastPgInd".to_string()]) { 
                        grp_header.last_pg_ind=text.to_string().parse::<bool>().expect("Failed to parse text as boolean");
                    }
                        
                };
                
                // parse bank account tags - may be multiple. 
                if tag_stack.starts_with(&["Document".to_string(), "BkToCstmrStmt".to_string(), "Stmt".to_string()]) {

                    if tag_stack.ends_with(&["Acct".to_string(), "Id".to_string(), "IBAN".to_string()]) {
                        current_stmt.iban = text.to_string();
                    };
                    // <BkToCstmrStmt> <Stmt> <ElctrncSeqNb>247</ElctrncSeqNb>
                    if tag_stack.ends_with(&[ "ElctrncSeqNb".to_string()]) {
                        current_stmt.elctrnc_seq_nb = text.to_string();
                    };
                    if tag_stack.ends_with(&["CreDtTm".to_string()]) {
                        current_stmt.cre_dt_tm = text.to_string();
                    };
                    //<FrToDt> <FrDtTm>2023-11-29T00:00:00</FrDtTm><ToDtTm>2023-11-29T00:00:00</ToDtTm></FrToD
                    if tag_stack.ends_with(&["FrToDt".to_string(),"FrDtTm".to_string()]) {
                        current_stmt.fr_dt_tm= text.to_string();
                    };
                    if tag_stack.ends_with(&["FrToDt".to_string(),"ToDtTm".to_string()]) {
                        current_stmt.to_dt_tm = text.to_string();
                    };
                    
                    //<BkToCstmrStmt> <Stmt> 
                    //<Bal><Tp> <CdOrPrtry>Cd>OPBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.14</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>
                    //<Bal><Tp> CdOrPrtry><Cd>CLBD</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">31709.09</Amt><CdtDbtInd>CRDT</CdtDbtInd><Dt><Dt>2023-11-29</Dt></Dt></Bal>

                    if tag_stack.ends_with(&["Bal".to_string(),"Tp".to_string(),"CdOrPrtry".to_string(),"Cd".to_string()]) {
                        current_balance.cd= text.to_string();
                    }
                    if tag_stack.ends_with(&["Bal".to_string(),"Amt".to_string()]) {
                        current_balance.amt= text.to_string();
                    }
                    if tag_stack.ends_with(&["Bal".to_string(),"Dt".to_string(),"Dt".to_string()]) {
                        current_balance.dt= text.to_string();
                    }
                    if tag_stack.ends_with(&["Bal".to_string(),"CdtDbtInd".to_string()]) {
                        current_balance.cdt_dbt_ind= text.to_string();
                    }
                };
            },
            Ok(Token::Attribute { local, value, .. }) if (current_tag == "Amt")  => {

                if tag_stack.ends_with(&["BkToCstmrStmt".to_string(), "Stmt".to_string(),"Bal".to_string(),"Amt".to_string()]) {
                    match local.as_str() {
                        "Ccy" => current_balance.ccy = value.to_string(),
                        _ => {},
                    }
                }
            },
            Ok(_) => {},
            Err(e) => {
                println!("Error parsing XML: {:?}", e);
                panic!("error parsing camt53");
            },
        }
    }

    doc.grp_hdr=grp_header;
    doc
}
