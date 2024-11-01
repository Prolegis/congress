#!/bin/bash

#### STEP 1 - SETUP
#

source ~/.bash_profile

cd ~

cd congress || git clone "https://$GITHUB_PERSONAL_ACCESS_TOKEN@github.com/Prolegis/congress.git" && cd congress
git pull # Fetch the latest version of the congress repository from GitHub


output_file="bill_status_codes.json" # Output JSON file
rm -f output_file # rm the old output file

log_file="bill_status_codes_import_log.txt" # Log file
echo "Bill Status Codes Import started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

# Use the Rails API to fetch the current congress
echo "Fetch current congress at started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
CURRENT_CONGRESS=$(curl -s -H "Authorization: $API_KEY_PRODUCTION" https://www.prolegis.com/api/congress_repo/current_congress | jq -r '.current_congress')
echo "Fetch current congress at completed at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

#### STEP 2 - DOWNLOAD BILL STATUS CODES DATA
#

echo "Download data (usc-run govinfo) started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
usc-run govinfo --cached --bulkdata=BILLSTATUS --congress=$CURRENT_CONGRESS
echo "Download data (usc-run govinfo) completed at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

echo "Download data (usc-run bills) started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
usc-run bills --congress=$CURRENT_CONGRESS
echo "Download data (usc-run bills) completed at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

#### STEP 3 - PARSE BILL STATUS CODES DATA INTO A JSON FILE
#

echo "Parse data started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

# Initialize an empty JSON array
echo "[" > $output_file

# Flag to track whether we need to add a comma before the next element
first_entry=true

# Define the root data directory with the current congress
data_directory="data/$CURRENT_CONGRESS"

# Recursively search for data.json files within the subdirectories under <ROOT>/data/$CURRENT_CONGRESS
find "$data_directory/bills" -type f -name "data.json" | while read -r file; do
  # Extract the "bill_id" and "status" values from each data.json
  bill_id=$(jq -r '.bill_id' "$file")
  bill_status=$(jq -r '.status | ascii_upcase' "$file")  # Convert status to uppercase

  # Skip if bill_id is null or empty
  if [ "$bill_id" = "null" ] || [ -z "$bill_id" ]; then
    echo "Skipping null or empty bill_id in file: $file" >> $log_file
    continue
  fi

  # Append the values to the output file in JSON format
  echo "  { \"bill_data_id\": \"$bill_id\", \"status\": \"$bill_status\" }," >> $output_file
done

# Remove the trailing space and comma from the file
truncate -s -2 $output_file

# Close the JSON array
echo "]" >> $output_file

echo "Parse data ended at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

#### STEP 4 - UPLOAD DATA TO AWS S3 BUCKET
#

echo "AWS Upload Started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

aws s3 cp bill_status_codes.json s3://content.prolegis.com/bill_status_codes/${CURRENT_CONGRESS}_congress_bill_status_codes.json --acl public-read
echo "AWS Upload Completed at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

#### STEP 5 - TRIGGER ASYNC BILL STATUS CODES IMPORT IN RAILS APPLICATIONS
#

echo "Trigger async import in Production started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
curl -X POST https://www.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_PRODUCTION"
echo "Trigger async import in Production ended at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

echo "Trigger async import in Staging started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
curl -X POST https://stg.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_STAGING"
echo "Trigger async import in Staging ended at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

echo "Trigger async import in Demo started at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
curl -X POST https://demo.prolegis.com/api/congress_repo/trigger_import_bill_status_codes -H "Authorization: $API_KEY_DEMO"
echo "Trigger async import in Demo ended at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file

#### STEP 6 - LOG THAT THE IMPORTER HAS BEEN COMPLETED
#

echo "Import finished at $(date '+%Y-%m-%d %H:%M:%S')" >> $log_file
