#!/bin/bash

# TODO - Make a cURL request to the Rails endpoint and store the result in a variable
# For now, we will store it as a hard-coded variable
CURRENT_CONGRESS=118
echo "The current congress is: $CURRENT_CONGRESS"

# Download the data
usc-run govinfo --cached --bulkdata=BILLSTATUS --congress=$CURRENT_CONGRESS
usc-run bills --congress=$CURRENT_CONGRESS

# Output JSON file at the top level
output_file="bill_status_codes.json"

# File for where our logging information will go
log_file="bill_status_codes_import_log.txt"

# Initialize an empty JSON array
echo "[" > $output_file

# Flag to track whether we need to add a comma before the next element
first_entry=true

# Define the root data directory with the current congress
data_directory="data/$CURRENT_CONGRESS"

# Recursively search for data.json files within the subdirectories under <ROOT>/data/$CURRENT_CONGRESS
find "$data_directory" -type f -name "data.json" | while read -r file; do
  # Extract the "bill_id" and "status" values from each data.json
  bill_id=$(jq -r '.bill_id' "$file")
  bill_status=$(jq -r '.status | ascii_upcase' "$file")  # Convert status to uppercase

  # Skip if bill_id is null or empty
  if [ "$bill_id" = "null" ] || [ -z "$bill_id" ]; then
    echo "Skipping null or empty bill_id in file: $file"
    continue
  fi

  echo "bill_data_id: $bill_id, status: $bill_status"

  # Add a comma before the next entry unless it's the first one
  if [ "$first_entry" = false ]; then
    echo "," >> $output_file
  fi

  # Append the values to the output file in JSON format
  echo "  { \"bill_data_id\": \"$bill_id\", \"status\": \"$bill_status\" }" >> $output_file

  # Set the flag to false after the first entry
  first_entry=false
done

# Close the JSON array
echo "]" >> $output_file

# AWS S3 Copy with variable interpolation for CURRENT_CONGRESS
aws s3 cp bill_status_codes.json s3://content.prolegis.com/bill_status_codes/${CURRENT_CONGRESS}_congress_bill_status_codes.json --acl public-read

# # TODO - Trigger Async Bill Status Codes Import in Rails Application

# Log that the import has completed
echo "Import finished at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
