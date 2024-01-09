#!/bin/bash
set -e

# copies new template files to test data 
for file in response_template-generated/response_template-generated.xml*; do
    cp "$file" "test/test.xml-${file##*-}"
done
