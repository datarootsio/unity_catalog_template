#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
RESOURCE_GROUP="DC-internship-2025"
PROJECT_NAME="unitycatalogproject"
LOCATION="westeurope"
CORE_BICEP_FILE="./core-infra.bicep"          # Path to core infrastructure Bicep
ACI_BICEP_FILE="./unityCatalogContainer.bicep"
UC_CONFIG_SOURCE_FOLDER="./uc-config-for-upload" # Local config files location
UC_HOSTNAME="uc-server"                       # Desired hostname for DNS
ACI_MEMORY_GB=1                               # ACI Memory (integer)
ACI_CPU_CORES=1


# --- 1. Deploy Core Infrastructure using Bicep ---
echo "Starting Bicep deployment..."
core_deployment_output=$(az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file $CORE_BICEP_FILE \
  --parameters projectName=$PROJECT_NAME location=$LOCATION \
  --output json)
if [ $? -ne 0 ]; then echo "Bicep deployment command failed."; exit 1; fi

# --- 2. Extract Required Outputs ---
STORAGE_ACCT_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageAccountName.value')
FILE_SHARE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageFileShareName.value')
ACR_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrName.value')
ACR_LOGIN_SERVER=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrLoginServer.value')
SUBNET_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.aciSubnetId.value')
PRIVATE_DNS_ZONE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.privateDnsZoneName.value')


# Validate extracted values
if [[ -z "$STORAGE_ACCT_NAME" || "$STORAGE_ACCT_NAME" == "null" || \
      -z "$FILE_SHARE_NAME" || "$FILE_SHARE_NAME" == "null" || \
      -z "$ACR_NAME" || "$ACR_NAME" == "null" || \
      -z "$ACR_LOGIN_SERVER" || "$ACR_LOGIN_SERVER" == "null" || \
      -z "$SUBNET_ID" || "$SUBNET_ID" == "null" || \
      -z "$PRIVATE_DNS_ZONE_NAME" || "$PRIVATE_DNS_ZONE_NAME" == "null" ]]; then
    echo "ERROR: Failed to extract one or more required outputs from core Bicep deployment."
    exit 1
fi
echo "Successfully parsed core outputs."


# --- 3. Prepare File Share ---
echo "--- Preparing file share '$FILE_SHARE_NAME'..."
STORAGE_KEY=$(az storage account keys list -g $RESOURCE_GROUP -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)
if [ -z "$STORAGE_KEY" ]; then echo "ERROR: Could not retrieve storage key for $STORAGE_ACCT_NAME."; exit 1; fi

# Create directories
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_KEY --share-name $FILE_SHARE_NAME --name "conf" --output none
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_KEY --share-name $FILE_SHARE_NAME --name "db" --output none
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_KEY --share-name $FILE_SHARE_NAME --name "logs" --output none

# Batch Upload Files to 'conf' (Overwrites)
CONF_DEST_DIR="conf"
if [ -d "./uc-config-for-upload" ]; then
    az storage file upload-batch \
        --account-name $STORAGE_ACCT_NAME \
        --account-key $STORAGE_KEY \
        --destination "$FILE_SHARE_NAME/$CONF_DEST_DIR" \
        --source "$UC_CONFIG_SOURCE_FOLDER" \
        --pattern '*' \
        --output none
else
     echo "Warning: Local source folder './uc-config-for-upload' not found. Skipping file upload."
fi
echo "File share preparation complete."

az storage fs directory create \
  -n "delta-tables" \
  -f "unitycatalog-data" \
  --account-name $STORAGE_ACCT_NAME \
  --account-key $STORAGE_KEY \
  --output none

# --- 4. Build Container Images ---
echo "Building container images in ACR '$ACR_NAME'..."
# Assumes Dockerfiles are in the current directory '.' from where the script is run
#az acr build --registry $ACR_NAME -g $RESOURCE_GROUP --image uc-server:latest --file dockerfile.uc .
#echo "  Built uc-server:latest"

#az acr build --registry $ACR_NAME -g $RESOURCE_GROUP --image dbt-server:latest --file dockerfile.dbt .
#echo "  Built dbt-server:latest"
echo "Image builds completed."



# --- 5. Get ACR Credentials ---
echo "--- Retrieving ACR credentials..."
# Assumes ACR Admin User is enabled. Use SP creds if Admin User is disabled.
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)
if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then echo "ERROR: Could not retrieve ACR credentials."; exit 1; fi
echo "ACR credentials retrieved."

# --- 6. Deploy Unity Catalog ACI using Bicep ---
echo "--- Starting Bicep deployment for Unity Catalog ACI ($ACI_BICEP_FILE)..."
# Using the version of uc-aci.bicep that expects ACR creds & uses storage key for volume
aci_deployment_output=$(az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file $ACI_BICEP_FILE \
  --parameters \
    projectName=$PROJECT_NAME \
    location=$LOCATION \
    subnetId=$SUBNET_ID \
    acrLoginServer=$ACR_LOGIN_SERVER \
    acrUsername="$ACR_USERNAME" \
    acrPassword="$ACR_PASSWORD" \
    storageAccountName=$STORAGE_ACCT_NAME \
    storageFileShareName=$FILE_SHARE_NAME \
    privateDnsZoneName=$PRIVATE_DNS_ZONE_NAME \
    ucHostName=$UC_HOSTNAME \
    memoryInGB=$ACI_MEMORY_GB \
    cpuCores=$ACI_CPU_CORES \
  --output json)
if [ $? -ne 0 ]; then echo "ERROR: ACI Bicep deployment command failed."; exit 1; fi
echo "ACI Bicep deployment submitted."

# --- 7. Extract ACI IP Address ---
echo "--- Parsing ACI Bicep outputs..."
ACI_PRIVATE_IP=$(echo "$aci_deployment_output" | jq -r '.properties.outputs.aciPrivateIpAddress.value')
if [ -z "$ACI_PRIVATE_IP" ] || [ "$ACI_PRIVATE_IP" == "null" ]; then
    # Fallback: Try getting IP directly if output failed (can happen if deployment registers but ACI errors later)
    ACI_NAME=$(echo "$aci_deployment_output" | jq -r '.properties.outputs.aciName.value // empty')
    if [ -n "$ACI_NAME" ]; then
       echo "Warning: Could not extract IP from deployment output. Trying direct query..."
       sleep 10 # Give ACI time to potentially get an IP
       ACI_PRIVATE_IP=$(az container show -g $RESOURCE_GROUP -n $ACI_NAME --query 'ipAddress.ip' -o tsv 2>/dev/null || echo "")
    fi
    # Final check
    if [ -z "$ACI_PRIVATE_IP" ]; then
       echo "ERROR: Failed to get ACI Private IP Address from Bicep output or direct query."
       exit 1
    fi
fi
echo "Extracted ACI Private IP: $ACI_PRIVATE_IP"

# --- 8. Create Private DNS Record via CLI ---
echo "--- Creating Private DNS A record for $UC_HOSTNAME.$PRIVATE_DNS_ZONE_NAME -> $ACI_PRIVATE_IP ..."
# Delete existing record first to handle IP changes on reruns
az network private-dns record-set a delete \
  --resource-group $RESOURCE_GROUP \
  --zone-name $PRIVATE_DNS_ZONE_NAME \
  --name $UC_HOSTNAME \
  --yes --output none || true # Ignore errors if record doesn't exist

# Create the record set (needed if it was deleted or never existed)
az network private-dns record-set a create \
  --resource-group $RESOURCE_GROUP \
  --zone-name $PRIVATE_DNS_ZONE_NAME \
  --name $UC_HOSTNAME \
  --ttl 300 \
  --output none

# Add the specific A record pointing to the current IP
az network private-dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $PRIVATE_DNS_ZONE_NAME \
  --record-set-name $UC_HOSTNAME \
  --ipv4-address $ACI_PRIVATE_IP \
  --output none
echo "Private DNS record creation complete."



echo "Deployment Script Completed Successfully."
exit 0