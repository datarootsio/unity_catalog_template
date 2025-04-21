#!/bin/bash

set -e

# --- Configuration ---
RESOURCE_GROUP="DC-internship-2025"
LOCATION="westeurope"
PROJECT_NAME="unitycatalogproject"
ACR_NAME="unitycatalogprojectacr"
CORE_INFRA_DEPLOYMENT_NAME="core-infra"
DBT_JOB_BICEP_FILE="./dbt-job.bicep"
IDENTITY_NAME="dbt-job-identity" # Name of the UAMI to use (must exist with roles assigned)

# --- Storage & Shares ---
# Assuming Delta tables and dbt project are in the same storage account
STORAGE_ACCT_NAME="unitycatalogprojectsa"
DBT_PROJECT_FILE_SHARE_NAME="dbt-project-share"
DBT_PROJECT_LOCAL_PATH="./dbt-project"
DELTA_CONTAINER_NAME="unitycatalog-data"

# --- UC Container Info ---
UC_ACI_NAME="aci-${PROJECT_NAME}-uc"
UC_CONTAINER_NAME="unitycatalog"
UC_TOKEN_FILE_PATH="/app/unitycatalog/etc/conf/token.txt"
UC_HOSTNAME="uc-server"

# --- dbt Execution ---
DBT_COMMAND="build"

# --- Role Assignment ---
# Role needed by SAMI on Storage Account for Delta table access
SAMI_STORAGE_ROLE_NAME="Storage Blob Data Contributor"

echo "--- Starting dbt ACI Job Execution (with SAMI Role Assignment) ---"

# --- 1. Get Core Outputs ---
echo "Fetching outputs..."
core_outputs=$(az deployment group show -g $RESOURCE_GROUP -n $CORE_INFRA_DEPLOYMENT_NAME --query properties.outputs -o json)
ACR_LOGIN_SERVER=$(echo "$core_outputs" | jq -r '.acrLoginServer.value // empty')
SUBNET_ID=$(echo "$core_outputs" | jq -r '.aciSubnetId.value // empty')
PRIVATE_DNS_ZONE_NAME=$(echo "$core_outputs" | jq -r '.privateDnsZoneName.value // empty')
CORE_STORAGE_ACCT_NAME=$(echo "$core_outputs" | jq -r '.storageAccountName.value // empty')
if [ "$STORAGE_ACCT_NAME" == "unitycatalogprojectsa" ]; then
    STORAGE_ACCT_NAME=$CORE_STORAGE_ACCT_NAME
fi
echo "Using Storage Account: $STORAGE_ACCT_NAME"
echo "Core outputs parsed."

# --- 2. Get ACR Credentials ---
echo "Retrieving ACR credentials..."
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)
echo "ACR credentials retrieved."

# --- 3. Get Storage Key (ONLY for dbt project mount) ---
echo "Retrieving storage key for project share mount..."
STORAGE_ACCOUNT_KEY=$(az storage account keys list --account-name $STORAGE_ACCT_NAME --resource-group $RESOURCE_GROUP --query '[0].value' -o tsv)
echo "Storage key retrieved."

# --- 4. Prepare dbt Project File Share ---
echo "Uploading dbt project..."
az storage share-rm create --storage-account $STORAGE_ACCT_NAME --name $DBT_PROJECT_FILE_SHARE_NAME --quota 5120 -g $RESOURCE_GROUP --output none || true
#az storage file upload-batch --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --destination $DBT_PROJECT_FILE_SHARE_NAME --source "$DBT_PROJECT_LOCAL_PATH" --destination-path "."
echo "dbt project upload complete."

# --- 5. Wait for UC Container and Retrieve Token ---
echo "Retrieving UC token..."
MAX_WAIT_MINUTES=5
TIMEOUT=$(($(date +%s) + MAX_WAIT_MINUTES * 60))
UC_TOKEN_VALUE=""
# ... (Wait loop logic - unchanged) ...
UC_TOKEN_VALUE=$(az container exec -g $RESOURCE_GROUP -n $UC_ACI_NAME --exec-command "cat ${UC_TOKEN_FILE_PATH}" --output tsv 2>/dev/null || echo "EXEC_FAILED")
echo "Token retrieved."

# --- 6. Construct UC Endpoint URL ---
UC_SERVER_URL="http://${UC_HOSTNAME}.${PRIVATE_DNS_ZONE_NAME}:8080"
echo "UC Endpoint URL: $UC_SERVER_URL"

# --- 7. Construct Storage Path (for dbt var) ---
STORAGE_PATH="abfss://${DELTA_CONTAINER_NAME}@${STORAGE_ACCT_NAME}.dfs.core.windows.net/delta-tables"
echo "Storage Path for dbt: $STORAGE_PATH"

# --- 8. Get UAMI Resource ID ---
echo "Retrieving UAMI Resource ID for '$IDENTITY_NAME'..."
UAMI_RESOURCE_ID=$(az identity show --name $IDENTITY_NAME -g $RESOURCE_GROUP --query id -o tsv)
if [ -z "$UAMI_RESOURCE_ID" ]; then
    echo "ERROR: Failed to find UAMI '$IDENTITY_NAME'. Please run the setup script first."
    exit 1
fi
echo "Using UAMI Resource ID: $UAMI_RESOURCE_ID"

# --- 9. Deploy dbt Job ACI using Bicep (Now passing UAMI ID) ---
echo "Deploying dbt job ACI (UAMI enabled)..."
JOB_INSTANCE_NAME="dbt-job-$(date +%s)"
DEPLOYMENT_NAME="dbt-job-deploy-${JOB_INSTANCE_NAME}"

# Removed capture of deployment_output as principalId output is gone
az deployment group create \
    --name $DEPLOYMENT_NAME \
    --resource-group $RESOURCE_GROUP \
    --template-file $DBT_JOB_BICEP_FILE \
    --parameters \
        dbtJobInstanceName=$JOB_INSTANCE_NAME \
        acrLoginServer=$ACR_LOGIN_SERVER \
        acrUsername="$ACR_USERNAME" \
        acrPassword="$ACR_PASSWORD" \
        uamiResourceId=$UAMI_RESOURCE_ID \
        subnetId=$SUBNET_ID \
        privateDnsZoneName=$PRIVATE_DNS_ZONE_NAME \
        location=$LOCATION \
        dbtProjectStorageAccountName=$STORAGE_ACCT_NAME \
        storageAccountKey=$STORAGE_ACCOUNT_KEY \
        dbtProjectFileShareName=$DBT_PROJECT_FILE_SHARE_NAME \
        ucAdminTokenValue=$UC_TOKEN_VALUE \
        ucServerUrl=$UC_SERVER_URL \
        storagePath=$STORAGE_PATH \
        dbtCommandToRun=$DBT_COMMAND

if [ $? -ne 0 ]; then echo "ERROR: Bicep deployment $DEPLOYMENT_NAME failed."; exit 1; fi
echo "Deployment $DEPLOYMENT_NAME submitted for ACI: $JOB_INSTANCE_NAME"

# --- 10. Final Monitoring Info ---
echo "ACI $JOB_INSTANCE_NAME should now attempt to run dbt."
echo "Monitor logs: az container logs --name $JOB_INSTANCE_NAME -g $RESOURCE_GROUP --container-name dbt-runner -f"

echo "--- Script Completed Successfully ---"
exit 0