# Guest progroam (hyperfridge)

## Overview

This module provides the logic to check the soundness of data coming from the banking backend - in Risc-Zero terminology the [guest][guest] code of hyperfridge. Risc-Zero framework creates a [seal][seal] around a specific compilation unit and version. Executingthis binary is used to create a [stark] (captured in a JSON) which can be validated automatically in any Rust module (e.g. on Polkadot) but also on EVM based ledgers (using [eth-verifier-contract]) - but the usage is not limited to blockchain technologies.

The proof aims for following properties:

- **Proofing soundness**: We want to prove that the presented data is correct and relyable and has not been tempered with.
We achieve this by checking signatures in the data which are provided by multiple entities. No entity alone should be able
to generate (or fake) the proof on its own. So either the bank or the banks client is able to generate fake proofs,
because you would need the private keys of both parties. The EBICS protocol (Electronic Banking Internet Communication Standard)
defines the key ceremony which has been used for many years.
- **Privacy**: Financial data - like medical data - is prone to highest data security standards. Bank documents contain names
and bank details of clients, which should not be leaked. With Zerko-Knowledge technology we are able generate proofs that.
e.g. a client has sent a specific amount, without revealing the data.
- **Low execution time**: Most banking backends still operate on a daily basis, thus generated proofs is not time critical.
But banking is [moving rapidly towards instant payments][sepa-instant], means time of finality for transaction will be
close to what can be achieved on blockchain today. Then proofing time may become a limiting factor.

How were the goals achieved whith this implementation?

- **Proofing soundness**: Singing payload data is still optional in the Ebics standard, so a bank backend needs to
support that explicitly, and we cannot fully rely on the standard. As alternative we introduce the concept
of a "data processor" as an additional entitiy next to the bank and the client. The data processor downloads
and signs the document (and payload) and acts as third-party witness.
- **Privacy**: Fully achieved - its trivial so include or not include data in proofs ([receipts][receipt]).
- **Low execution time**: Execution time is around 45 minutes to generate a proof. This is sufficient for
current scenarios but too much in case of instant payments.

## Fundamental properties of the banking interface (ISO20022 and Ebics)

[ebics-25-cfonb]:

The basic idea is the following: Whenever the bank (the banking API) is transmitting documents, it sends its data with a signature - using [XML encryption standards](https://www.w3.org/TR/xmlenc-core1/). For example a response document for a daily statement of balance and transactions would contain a section like this:

```xml
<ebicsRequest xmlns="http://www.ebics.org/H003" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Revision="1" Version="H003">
  <header authenticate="true">
    <static> ...
      <!-- Signature of the bank. "Z53" refers to which kind document was requested (and signed) -->
      <OrderDetails><OrderType>Z53</OrderType> ...
      </OrderDetails>
      <BankPubKeyDigests>
        <Authentication Version="X002" Algorithm="http://www.w3.org/2001/04/xmlenc#sha256">__some_base64_=</Authentication>
        <Encryption Version="E002" Algorithm="http://www.w3.org/2001/04/xmlenc#sha256">__some_base64_=</Encryption>
      </BankPubKeyDigests> ...
    </static> ...
  </header>
  <AuthSignature>
  <!-- Hashed and signature of Z53 document (usually a ZIP) -->
    <ds:SignedInfo>
      <ds:CanonicalizationMethod Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315" />
      <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" />
      <ds:Reference URI="#xpointer(//*[@authenticate='true'])">
        <ds:Transforms>
          <ds:Transform Algorithm="http://www.w3.org/TR/2001/REC-xml-c14n-20010315" />
        </ds:Transforms>
        <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256" />
        <ds:DigestValue>PQxx__some_base64_aaaa=</ds:DigestValue>
      </ds:Reference>
    </ds:SignedInfo>
    <ds:SignatureValue>__some_base64_</ds:SignatureValue>
  </AuthSignature>
  <body />
</ebicsRequest>
```

A wrapped Z53 document containing the daily statement showing 30191.23 as CHF balance would look similar to this:

```xml
  <BkToCstmrStmt>
    <Stmt>
      <Id>5e9ea1005fe64f1b924e968898bcfa7c</Id>
      <ElctrncSeqNb>146</ElctrncSeqNb>
      <CreDtTm>2023-06-30T19:24:46.387</CreDtTm>
      <Acct><Id><IBAN>CH4323432442432537312</IBAN></Id> </Acct>
      <Bal><Amt Ccy="CHF">30191.23</Amt><Dt><Dt>2023-06-30</Dt></Dt></Bal>
      <Ntry>...</Ntry>
    </Stmt>
  </BkToCstmrStmt>
```

The hash of the (zipped) Z53 documents needs to be validated with the data given in the ebicsRequest. "X002" refers to RSA signature key with a key length of 2048 bits, "E002" defines RSA algorithm for encryption using  ECB (Electronic Codebook) and PKCS#1 v1.5 padding ([Also see here](https://www.ibm.com/docs/en/b2b-integrator/5.2?topic=eckf-managing-certificates-keys-users)) or take a look at standardization page on [Ebics](https://www.ebics.org/en/home) and [ISO20022](https://www.iso20022.org/) or a better readable [national page](https://www.six-group.com/dam/download/banking-services/standardization/ebics/market-practice-guidelines-ebics3.0-v1.2-en.pdf). Remark: A typical question is "what is the difference between Ebics and ISO20022?" An analogy might be that EBICS is to ISO20022 what HTTP is to HTML; that is, EBICS serves as the communication protocol while ISO20022 defines the message format structure.

We use zero-knowledge proofs (circuits) to check signatures so that we do not have to publish bank statements, because this would reveal identities of transactions in clear-text. This allows us to veryfiy the data and its claim (a certain balance in our case). It is trustless to the extend that we use both secrets of the bank and the account owner to generate the proof (MPC - multi-party-computation).

Now we can shift the trust from the bank account owner to the bank itself. But can we trust the keys of the bank? Here we would rely on the processes and the key ceremonies between a bank and its client and between a bank and its national bank. Hashes of banks are published - just google for *ebics hash*. Note that each bank uses [same keys for the communication with their clients and their respective national bank](https://www.bundesbank.de/resource/blob/868928/0d72f44f05be86cf78de84138a73d837/mL/verfahrensregeln-ebics-2021-data.pdf). Thus we only need to trust the top of the authorities, not individual banks. Thus the trust can be moved further up to the nation authorities who are auditing its nations' banks.

But can we trust a nation or a government? The nations are monitored and measured by an independent international organisation called [FATF](https://www.fatf-gafi.org/en/home.html) who is responsible in setting worldwide standards on anti-money-laundering and evaluates the execution of these standards [regularly](https://www.fatf-gafi.org/en/publications/Mutualevaluations/Assessment-ratings.html) for each nation, which are usually [incorporated into local (e.g. Swiss) financial regulations](https://www.finma.ch/en/finma/international-activities/policy-and-regulation/fatf/). A system like hyperfridge can easily exclude certificates from banks from high risk countries.

To sum up: Even if you are not trusting the banking system or governments; technically hyperfridge is "as good as it can get" for integrating the traditional system on a zero-trust basis. We do not aim to improve the legacy banking systems but use protocols with a wide adoption.

For this grant we would aim at implementing *step &alpha;* of the [whitepaper](https://github.com/element36-io/ocw-ebics/blob/main/docs/hyperfridge-draft.pdf). This includes validation of account balance and validating hash and signature of the bank within the ZKP. This already creates a trustless information-exchange setup with the account holder. But we will not aim for *step &beta;* of the paper to prove "transaction inclusion". An example for transaction inclusion is that the bank statement contains a transaction which shows that Alice has sent 5 CHF to the bank account- again without revealing any transaction data publicly. Reason is that we do not want to overload the delivery with complexity and we still at the beginning of your zero-knowledge learning curve.

### Proof system implementation

As a library we will use [Risk-Zero](https://www.risczero.com/). Reasons are:

- The risc0-verifier got [formally](https://www.github.com/risc0/risc0-lean4) verified.
- It allows complex computing (e.g. unzipping files) with existing libraries using its Risc-5 architecture. It would be much harder to use a [Rank-1 constraint system](https://www.zeroknowledgeblog.com/index.php/the-pinocchio-protocol/r1cs) like [Circom](https://docs.circom.io/).
- Its an actual ZKP library written in Rust and supporting 'no_std'.
- It is based on STARKs (not SNARKs as the Hyperfridge paper suggests). SNARKs are cheap to validate (therefore good for EVM based systems) but the of STARKs be can automated (non-interactive). As we use Off-Chain-Workers the disadvantages of SNARKs do not matter for us and we can benefit from an easy setup to reach a "trustless" state.
- But Risk-Zero provided a framework to wrap the STARK in a SNARK which can be validated with EVM based Smart Contracts.
- Risk-Zero is very efficient - which is important if we want to process large XML documents. We expect that generating a single proof based on an XML document could take several hours without [CUDA](https://en.wikipedia.org/wiki/CUDA) acceleration or using [Bonsai](https://dev.risczero.com/bonsai).
- Risk-Zero supports hardware acceleration and is offering validation as-a-service, which lowers adaption complexity.  
- We had first experiences with working with it (a proof-of-reserve system for a bank) and we like the fact to be able to implement our circuits in Rust rather than another language.

As disadvantages we see:

- Still a young framework - limitations (e.g. new ZK-vm version would likely require new proofs) and unstable APIs, especially "waiting time" for library developments need to be taken into account.
- Potentially high proofing time; but we only need one proof a day.
- Proof-size: Proof size may be too large for on-chain verification; This can be solved by snarking the STARK which would be likely solved by risc-zero framework, which we would include at a later stage.

The library will be used generate the proof on our bankend to create a *receipt* - a document which contains the proof. We will change the existing Off-Chain-Worker (OCW) crate to validate the receipt before updating any state of the OCW. See [risk zero proofing system](https://dev.risczero.com/proof-system/) for details.

Specification of proof system (see [Hyperfridge whitepaper](https://github.com/element36-io/ocw-ebics/blob/main/docs/hyperfridge-draft.pdf) for more details):

- Secret input: Ebics envelope as XML and Z53/Camt53 as ZIP binary. See XMLs above.
- Public input: Public Certificate of the Bank or name of bank, bank account number,  balance and date.

The prof system consists of (see [for details](https://dev.risczero.com/proof-system/proof-system-sequence-diagram)):

- The circuit (for risk-zero an ELF lib) including its hash.
- Client code which generates a Receipt (ZKP) as a modification to the [Ebics-Backend](https://github.com/element36-io/ebics-java-service) from our first grant.
- The modifications of the [FIAT-ramp Off-Chain-Worker](https://github.com/element36-io/ocw-ebics/blob/main/INSTRUCTIONS.md) which validates the receipt.

### Bank signature validation

XML sigantures:
<https://datatracker.ietf.org/doc/html/rfc3275#section-3.1.2>
Signature Generation
<https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf>

#### Pre-processing

5.5.1.2.1 Processing in the initialisation phase

   1. Create SignedInfo element with SignatureMethod,
      CanonicalizationMethod and Reference(s).
   2. Canonicalize and then calculate the SignatureValue over SignedInfo
      based on algorithms specified in SignedInfo.
      3. Construct the Signature element that includes SignedInfo,
      Object(s) (if desired, encoding may be different than that used
      for signing), KeyInfo (if required), and SignatureValue.

   Note, if the Signature includes same-document references, [XML] or
   [XML-schema] validation of the document might introduce changes that
   break the signature.  Consequently, applications should be careful to
   consistently process the document or refrain from using external
   contributions (e.g., defaults and entities).

#### Signature Validation

   1. Obtain the keying information from KeyInfo or from an external
      source.
   2. Obtain the canonical form of the SignatureMethod using the
      CanonicalizationMethod and use the result (and previously obtained
      KeyInfo) to confirm the SignatureValue over the SignedInfo
      element.

   Note, KeyInfo (or some transformed version thereof) may be signed via
   a Reference element.  Transformation and validation of this reference
   (3.2.1) is orthogonal to Signature Validation which uses the KeyInfo
   as parsed.

   Additionally, the SignatureMethod URI may have been altered by the
   canonicalization of SignedInfo (e.g., absolutization of relative
   URIs) and it is the canonical form that MUST be used.  However, the
   required canonicalization [XML-C14N] of this specification does not
   change URIs.

[receipt]: https://dev.risczero.com/api/zkvm/developer-guide/receipts
[ebics-25-cfonb]: https://www.cfonb.org/fichiers/20130612170023_6_4_EBICS_Specification_2.5_final_2011_05_16_2012_07_01.pdf
[guest]: https://dev.risczero.com/api/zkvm/developer-guide/guest-code-101
[seal]: https://dev.risczero.com/terminology#seal
[stark]: https://dev.risczero.com/reference-docs/about-starks
[eth-verifier-contract]: https://dev.risczero.com/api/bonsai/bonsai-on-eth#verifier-contract
[sepa-instant]: https://www.europeanpaymentscouncil.eu/what-we-do/sepa-instant-credit-transfer