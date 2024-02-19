#!/bin/bash

# How to test and debug
# Start watchdog in a shell, copy new files to trace directory, 
# e.g in data: cp response_template-generated.xml ./trace/response_template-generatedv2.xml

# to pre-process XML
watch_dir="${IN_DIR:-./trace}"
processing_dir="${WORK_DIR:-./work}"
done_dir="${DONE_DIR:-${processing_dir}/work_done}"
error_dir="${ERROR_DIR:-${processing_dir}/work_error}"
out_dir="${OUT_DIR:-${processing_dir}/work_result}"
hfbin="${HOST_CMD:-../target/release/host}"

# to create the proof
# --request="../data/test/test.xml" --bankkey ../data/pub_bank.pem --clientkey ../data/client.pem --witnesskey ../data/pub_witness.pem --clientiban CH4308307000289537312
# Resolve relative paths to absolute paths
pub_bank="$(realpath "${BANK_PUB_KEY:-./pub_bank.pem}")"
client="$(realpath "${CLIENT_PR_KEY:-./client.pem}")"
pub_client="$(realpath "${CLIENT_PUB_KEY:-./pub_client.pem}")"
pub_witness="$(realpath "${WITNESS_PUB_KEY:-./pub_witness.pem}")"
witness="$(realpath "${WITNESS_PR_KEY:-./witness.pem}")"
iban="CH4308307000289537312"

echo environment: 
echo "watch_dir=$watch_dir"
echo "processing_dir=$processing_dir"
echo "done_dir=$done_dir"
echo "error_dir=$error_dir"
echo "out_dir=$out_dir"
echo "hfbin=$hfbin"
echo "iban=$iban"
echo "pub_bank=$pub_bank"
echo client=$client
echo pub_witness=$pub_witness
echo witness=$witness

# Create processing, done, and error directories if they don't exist

mkdir -p "$processing_dir"
mkdir -p "$done_dir"
mkdir -p "$error_dir"
mkdir -p "$out_dir"

# Function to process a file
process_file() {
    local filename="$1"
    
    # Copy file to processing directory
    cp "$watch_dir/$filename" "$processing_dir/$filename"

    # Call external script to process the file
    echo preparing ebics response for proofing xml "$processing_dir/$filename"
    xml_file="$filename" work_dir="$processing_dir" pub_bank=$pub_bank  client=$client pub_witness=$pub_witness  witness=$witness ./checkResponse.sh
    local exit_code=$?

    # Check exit code for errors
    if [ $exit_code -eq 0 ]; then
        echo "File $filename prepared successfully."
    else
        # Move file to error directory
        mv "$processing_dir/$filename" "$error_dir/$filename"
        echo "Error preparing file $filename."
        return
    fi

    # Call hyperfridge to generate the proof
    output_dir_name="${filename%.xml}"
    echo prepare to proof with: RISC0_DEV_MODE=true $hfbin prove-camt53 --request="$processing_dir/$output_dir_name/$filename" --bankkey $pub_bank --clientkey $client --witnesskey $pub_witness --clientiban $iban
    RISC0_DEV_MODE=true $hfbin prove-camt53 --request="$processing_dir/$output_dir_name/$filename" --bankkey $pub_bank --clientkey $client --witnesskey $pub_witness --clientiban $iban
    # xml_file="$filename" work_dir="$processing_dir" pub_bank=../pub_bank.pem  client=../client.pem pub_witness=../pub_witness.pem  witness=../witness.pem ./checkResponse.sh
    local exit_code=$?

    # Check exit code for errors
    if [ $exit_code -eq 0 ]; then
        # Move file to done directory"$filename"
        echo "Proof from file $filename generated successfully."
    else
        # Move file to error directory
        mv "$processing_dir/$filename" "$error_dir/$filename"
        echo "Error proofing file $filename."
        return
    fi

    # copy result to out directory
    transaction_id=$(grep -oP '<TransactionID>\K[^<]+' $processing_dir/$filename)
    image_id=$(${hfbin} show-image-id)
    out_filename=receipt_${transaction_id}.json

    # If the output filename already exists, append a timestamp to it
    if [ -f "$out_dir/$out_filename" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        out_filename="${out_filename}_${timestamp}"
    fi

    # move result to target dir
    mv $processing_dir/$output_dir_name/${filename}-Receipt-*-latest.json $out_dir/$out_filename

    # Check exit code for errors
    if [ $exit_code -eq 0 ]; then
        # Move file to done directory"$filename"
        mv "$processing_dir/$filename" "$done_dir/$filename"
        echo "Proof is ready in $out_filename"
    else
        # Move file to error directory
        mv "$processing_dir/$filename" "$error_dir/$filename"
        echo "Error post-processing of  file $filename."
    fi
}

# Monitor readonly directory for file creation events
echo start loop
while true; do
    inotifywait -m -e create --format '%f' "$watch_dir" | while read -r filename; do
        fn="$watch_dir/$filename"
        # do some sanity checks on the xml file
        echo "======> got notification of a new file $fn"

        if !(grep -q 'Version="H003"' "$fn" || 
            grep -q 'Version="H004"' "$fn") ; then
            echo "Wrong XML filetype, only processing H003 or H004 in: $fn"
        elif  ! grep -q '<NumSegments>1</NumSegments>' "$fn" ; then
            echo "Currently only processing Ebics Responses with one Segment (< 1 MB) in: $fn"
        elif [[ $filename != *".xml" ]]; then
            echo "no XML file $fn"
        else
            process_file "$filename"
        fi
    done
done