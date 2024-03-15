# Highlevel cryptographic process description


## Entities

1. **Client ($C$)**:
   - Private Key: $C_{{priv}}$
   - Public Key: $C_{{pub}}$
2. **Bank ($B$)**:
   - Private Key: $B_{{priv}}$
   - Public Key: $B_{{pub}}$
3. **Witness ($W$)**:
   - Private Key: $W_{{priv}}$
   - Public Key: $W_{{pub}}$

## Transaction membership

For example Alice wire-transfers to Bob and amount x. As soon as the amount is booked on Bobs bank account and Bob generates a proof with hyperfridge (automatically), Alice is able to prove that the money arrived on Bobs account.

We want to prove that a transaction (defined as $Statement$) is part of $Payload$ with has following properties:

- A $Payload$ has a least one transaction $Statement$.
- A transaction is either a credit or debit - means it add or reduces a balance of a bank account.
- A $Payload$ is implemented as an [ISO20022 camt.053 (Cash management) XML message](https://www.iso20022.org/message/mdr/22714/download).
- For later use we simplify the $Payload$ the message as:
    - $Payload = {GroupHeader} \, \| \ ({Statement})^*$, where
    -  ${GroupHeader}={StatementSequenceNumber}  \, \| \ Account \, \| \ Currency$
    -  ${Statemnet}= StmtAccount \, \| \,  StmtAmount \, \| \,  StmtDbtrCdrAddress \, \| \, StmtAddionalTxInfo $


### Process Description for proofing transaction membership

1. When Client $C$ generates a random number $r$ and adds the number wire transfer as "additional information" which will go into the field $StmtAddionalTxInfo$.

1. We modify the ***STARK Proof*** of step 6 above. For each $Statement$ in $Payload$, we add to the public commitment: $hash( StmtAccount \, \| \,  StmtAmount \, \| \,  StmtAddionalTxInfo)$

1. Only the client $C$ knows $r$ and is able to generate a proof for transaction inclusion and present it to Smart Contract. 


## ZK proofing system

### Process Description

The witness uses hyperfridge and the HSM to create a SNARK proof with:
- $`{Payload}_{enc}, {SymKey}_{enc}, {XMLSignature}`$
- $`{Signature}_{w_{priv}}`$
-  And decrypted transaction key ${SymKey}$ by calling $hsmDecrypt_{hsmtoken}(Symkey_{enc})$

6. **Create STARK Proof**: ${ZKProof}_{ImageID}({PrivateInput}, {PublicInput}) \rightarrow {Commitment}$
    - Private Inputs:
        - Extracted form from ${EbicsRequest}$:  
            - ${Payload}_{enc}$: Encrypted payload, decrypt payload with ${SymKey}$ to extract the commitments.
            - ${SymKey}_{enc}$: Encrypted symetric transaction key, assert that the HSM-decrypted symetrical key is identical to the symetrical key of the document.
            - ${XMLSignature}, {}$: Signatures by the bank cover ${SymKey}$
        - ${Symkey}$: Decrypted symetric key which is used for speeding up decryption of ${Payload}$ and integrity check for the $Payload$
    - Public Inputs: 
      - IBAN, $B_{pub}$, $W_{pub}$

    - Commitment: Public input and data from  $Payload$ and $EbicsResponse$: ${extractCommitment}({EbicsRequest}, {Payload})$ presented as a JSON document.

The STARK presents a proof of computation. The computation is sealed (using Risk-Zero framework) and contains:

  a. **Validate $SymKey$**: The Bank has generated $SymKey$ to encrypt the $Payload$ (clients data)
   - Verify $XMLSignature$ which contains $Symkey_{enc}$.
   - Decrypt $Symkey_{enc}$ with $C_{priv}$ which proves the document was sent to the specific client.
 
  b. **Validate integrity of $Payload$**:
   - Validate ${Signature}_{w_{priv}}$ of $Payload$ so the client is not able to tamper the $Payload$ to present a fake balance.
  
  c. **Create commitment from decrypted $Payload$**:
   - Decrypt $Payload$ with $Symkey$.
   - Extract the data from payload and create the commitment. 
   - Add public input to the commitment.
  
  d. **A seal for the proofing algorithm - the $ImageID$**
   - The seal (exact version and code) is identified by an $ImageID$. 
   - See [Risk-Zero Proof System](https://dev.risczero.com/proof-system/).

### Verification

7. **Verification using Risk-Zero Recipe**: Other parties (like the Bank or external verifiers) can verify the zero-knowledge proof.
   - Verify proof with: ${VerifyZKProof_{ImageID}}() \rightarrow Commitment$.
   - Check the public input (IBAN, $B_{pub}$, $W_{pub}$).


(8.) **On-Chain verification with Groth16 SNARK**:
   - Risk-Zero privides a STARK to SNARK wrapper to support [on-chain verfication](https://www.risczero.com/news/on-chain-verification).


## Key Benefits
   - **Privacy**: The Client's private key remain confidential throughout the process. No party has access to any of the others private keys. The witness is not able to see the payload. 
   - **Security**: The signature from the Witness and the zero-knowledge proof mechanism ensure the security and integrity of the transaction without compromising sensitive information (transaction data).
- **Verifiability**: External parties can verify a bank statements legitimacy without accessing private keys or sensitive transaction details - on-chain or off-chain. 

## Security Considerations

- The witness also acts as a signing proxy to create the $EbicsRequest$ which is necessary to trigger the download of $EbicsResponse$ which contains the $Payload$. 
- The zero-knowledge proof allows the Client to prove knowledge of certain information without revealing the information itself.
- The use of digital signatures by the Witness ensures the integrity and authenticity of the payload, which might not be necessary if the Ebics Standard implements its planned feature and will actually sign its payload.
- The HSM must be tamper-resistant and capable of securely managing cryptographic keys and operations.


## Execution time

[See here](runtime.md).

## Outlook and use cases

### Proof transaction inclusion and Instant Payments

As we are able to prove the payload, we can create a proof for transaction inclusion. Means we can prove FIAT payments incoming and outgoing, both on-chain - similar to how cross-blockchain bridges work today. Most banks are operating on a daily basis which prevents interactive use-cases or would ask e.g. for optimistic implementation and addition funds to secure the FIAT bridge. But the EU is working on instant payments which would even allow instant interactive and non-interactive applications. This does not only apply to FIAT assets but also to any TradFi assets. For example, Maker DAO has invested 400 mUSD in a Blackrock ETF for traditional assets. Hyperfridge would be able to create proof of assets and do balancing of investments (invest and divest) automatically. Note that using Ebics and standard banking functionality comes at no cost or transaction fees.

### Open-API Banking and Payment-API (e.g. Stripe)

The principles presented here can be applied to other Open Banking Standards as well like India's UPI or the PSD2 standard. Integrating payment platforms like Stripe would add fees to payments but is widely used. Payments on Stripe are easy to set up and may be processed withing a few minutes which makes interactive use cases possible.


### Witness, HSM and other secure modules

The Witness for hyperfridge needs an HSM to sign data. One might think of Apple Secure Enclave  to enable new use cases where a simple Phone or Laptop can act as a witness.

