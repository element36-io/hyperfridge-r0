# Create new Test Data


### Test with new Ebics Request document

To simulate step "1." of the roundtrip (new data arrives) we copy the existing data to a new file:

```bash
# copy the data into a new ebics response

# create the STARK - parameters (certificats) need to match

docker run fridge sh -c "cd /data && cp response_template.xml mydata.xml  && cd /app && \
RISC0_DEV_MODE=true  host --verbose prove-camt53  --clientiban CH4308307000289537312 \
       --request=/data/mydata.xml --bankkey /data/pub_bank.pem \
       --clientkey /data/client.pem --witnesskey /data/pub_witness.pem \
       --script /data/checkResponse.sh"

# verify the STARK

```

Hint: Further down are instructions how to create arbitrary payload and test data in the developemnt environment.

### Create new payload for Ebics Request

Modify ISO20022 Camt53 files in `data/response_template/camt53` and potentially `data/respone_template.xml`. In data dir call:

```bash
./createTestResponse.sh 
# will create a response_template-generated.xml
ls -la ../data/response_template-generated.xml
```

Generate the proof in `/host/`:

```bash
RISC0_DEV_MODE=true  cargo run  --verbose prove-camt53  --clientiban CH4308307000289537312 \
       --request=/data/mynewdata.xml --bankkey /data/pub_bank.pem \
       --clientkey /data/client.pem --witnesskey /data/pub_witness.pem 
# check the receipt
cat ../data/mynew

# m verifier
cd ../verifier/
RISC0_DEV_MODE=true  cargo run  --verbose prove-camt53  --clientiban CH4308307000289537312 \
       --request=/data/mynewdata.xml --bankkey /data/pub_bank.pem \
       --clientkey /data/client.pem --witnesskey /data/pub_witness.pem 

```


To redeploy your modifcations as new test data (to be check as default data) you may use the script `./deploy_new_testdata.sh`.

