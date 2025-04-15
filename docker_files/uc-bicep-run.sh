#!/bin/bash

# --- Configuration ---
export RG="internship-2025"
export LOCATION="westeurope"
export ACI_NAME="unity-catalogz-$(openssl rand -hex 4)" # Or your desired name
export ACR_REGISTRY_NAME="unitycatalogdbt"
export ACR_USERNAME="unitycatalogdbt" # Usually same as registry name
export UC_IMAGE_NAME="${ACR_REGISTRY_NAME}.azurecr.io/uc-server:latest"
export STORAGE_ACCT_NAME="unitycataloginternship"
export UC_ETC_SHARE="uc-etc-share"
export SUBNET_ID="/subscriptions/2c6c60ea-bfd7-40cc-8da2-5437ee25d5f5/resourceGroups/internship-2025/providers/Microsoft.Network/virtualNetworks/vnet-ucdbt-project/subnets/snet-aci-delegated"
# Optional overrides for Bicep params
# export CPU_CORES=1
# export MEMORY_GB='1.5'
# export CONTAINER_PORT=8080
# export COMMAND_LINE='["bin/start-uc-server"]' # JSON array format

# --- Retrieve Credentials ---
echo "Retrieving ACR Password..."
ACR_PASSWORD_VALUE="$(az acr credential show -n $ACR_REGISTRY_NAME --query 'passwords[0].value' -o tsv)"
if [[ -z "$ACR_PASSWORD_VALUE" ]]; then echo "Error retrieving ACR password."; exit 1; fi

echo "Retrieving Storage Key..."
STORAGE_KEY_VALUE="$(az storage account keys list -g $RG -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)"
if [[ -z "$STORAGE_KEY_VALUE" ]]; then echo "Error retrieving Storage key."; exit 1; fi
echo "Credentials retrieved."

# --- Deploy using Bicep ---
echo "Starting Bicep deployment..."
az deployment group create \
  --resource-group $RG \
  --template-file create-uc-aci.bicep \
  --parameters \
    location=$LOCATION \
    aciName=$ACI_NAME \
    acrName=$ACR_REGISTRY_NAME \
    acrUsername=$ACR_USERNAME \
    acrPassword="$ACR_PASSWORD_VALUE" \
    ucImageName=$UC_IMAGE_NAME \
    storageAccountName=$STORAGE_ACCT_NAME \
    storageAccountKeyValue="$STORAGE_KEY_VALUE" \
    ucEtcShareName=$UC_ETC_SHARE \
    subnetId=$SUBNET_ID \
    # --- Add optional parameters below if overriding defaults ---
    # cpuCores=$CPU_CORES \
    # memoryInGb=$MEMORY_GB \
    # containerPort=$CONTAINER_PORT \
    # commandLine=$COMMAND_LINE

# Check deployment status
if [ $? -eq 0 ]; then
    echo "Bicep deployment completed successfully."
    echo "Run 'az container show -g $RG -n $ACI_NAME --query \"{ip:ipAddress.ip, fqdn:ipAddress.fqdn, state:instanceView.state}\" -o table' to check status and IP."
else
    echo "Bicep deployment failed."
    exit 1
fi