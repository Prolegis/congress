#!/bin/bash

log_file="bill_status_codes_import_log.txt" # Log file
echo "Bill Status Codes Import started at $(date '+%Y-%m-%d %H:%M:%S')" >> log_file

# Validate Production Key
curl -s -H "Authorization: $API_KEY_PRODUCTION" https://www.prolegis.com/api/congress_repo/validate_key
if [ "$response" -ne 200 ]; then
  echo "Production key is invalid. HTTP status: $response" >> log_file
  exit 1
fi

# Validate Staging Key
curl -s -H "Authorization: $API_KEY_STAGING" https://stg.prolegis.com/api/congress_repo/validate_key
if [ "$response" -ne 200 ]; then
  echo "Staging key is invalid. HTTP status: $response" >> log_file
  exit 1
fi

# Validate Demo Key
curl -s -H "Authorization: $API_KEY_DEMO" https://stg.prolegis.com/api/congress_repo/validate_key
if [ "$response" -ne 200 ]; then
  echo "Demo key is invalid. HTTP status: $response" >> log_file
  exit 1
fi

# Send a log message that the import has started
response=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://www.prolegis.com/api/congress_repo/log_message \
-H "Authorization: $API_KEY_PRODUCTION" \
-H "Content-Type: application/json" \
-d "{\"message\": \"Bill Status Codes Import started at $(date '+%Y-%m-%d %H:%M:%S')\", \"level\": \"info\"}")

cd ~

# Clone from GitHub if not already cloned.
git clone "https://$GITHUB_PERSONAL_ACCESS_TOKEN@github.com/Prolegis/congress.git"

# Check if git clone failed
if [ $? -ne 0 ]; then
  echo "Git clone failed, logging the error."  >> log_file

  # Send a log message indicating the failure
  curl -X POST https://www.prolegis.com/api/congress_repo/log_message \
  -H "Authorization: $API_KEY_PRODUCTION" \
  -H "Content-Type: application/json" \
  -d '{"message": "Git clone failed for the congress repository", "level": "error"}'

  # Exit the script since the clone failed
  exit 1
fi

cd congress
git pull # Fetch the latest version of the congress repository from GitHub

output_file="bill_status_codes.json" # Output JSON file
echo "Bill Status Codes Import started at $(date '+%Y-%m-%d %H:%M:%S')" >> log_file

# Use the Rails API to fetch the current congress
CURRENT_CONGRESS=$(curl -s -H "Authorization: $API_KEY_PRODUCTION" https://www.prolegis.com/api/congress_repo/current_congress | jq -r '.current_congress')

# Download the data
usc-run govinfo --cached --bulkdata=BILLSTATUS --congress=$CURRENT_CONGRESS
usc-run bills --congress=$CURRENT_CONGRESS

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

# Check if the AWS S3 copy command was successful
if [ $? -ne 0 ]; then
  # Log an error message and exit if the S3 copy fails
  echo "AWS S3 copy failed for bill_status_codes.json" >> $log_file

  # Optionally send the log message via the API
  curl -X POST https://www.prolegis.com/api/congress_repo/log_message \
  -H "Authorization: $API_KEY_PRODUCTION" \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"AWS S3 copy failed for bill_status_codes.json at $(date '+%Y-%m-%d %H:%M:%S')\", \"level\": \"error\"}"

  # Exit the script with a non-zero exit code
  exit 1
fi

# Trigger Async Bill Status Codes Import in Rails Application
curl -X POST https://www.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_PRODUCTION"
curl -X POST https://stg.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_STAGING"
curl -X POST https://demo.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_DEMO"

# Log that the import has completed
echo "Import finished at $(date '+%Y-%m-%d %H:%M:%S')" >> log_file

response=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://www.prolegis.com/api/congress_repo/log_message \
-H "Authorization: $API_KEY_PRODUCTION" \
-H "Content-Type: application/json" \
-d "{\"message\": \"Bill Status Codes Import finished at $(date '+%Y-%m-%d %H:%M:%S')\", \"level\": \"info\"}")

exit 0