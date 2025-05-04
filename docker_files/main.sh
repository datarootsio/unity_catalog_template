#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
echo "--- Configuration ---"
RESOURCE_GROUP="DC_internship_2025"
LOCATION="westeurope"
PROJECT_NAME="unitycatalogproject"
UAMI_NAME="dbt-job-identity"          # Name for the User Assigned Managed Identity
DBT_MEMORY_GB="1"                     # ACI Resource Allocation
DBT_CPU_CORES="1"                     # ACI Resource Allocation
DBT_PROJECT_LOCAL_PATH="./dbt-project" # Local path to dbt project for initial upload
UC_CONFIG_LOCAL_PATH="./uc-config-for-upload" # <<< ADDED: Local path for UC config files
FUNCTION_CODE_FOLDER="./function"     # Folder containing function_app.py, requirements.txt, etc.
STORAGE_KEY_SECRET_NAME="dbt-storage-account-key" # Name for the secret in Key Vault
TOKEN_SECRET_NAME="uc-admin-key" # Name for the secret in Key Vault

# --- Bicep File Paths ---
CORE_BICEP_FILE="./core-infra.bicep"
UC_ACI_BICEP_FILE="./unityCatalogContainer.bicep" # Using the public IP version
FUNCTION_APP_BICEP_FILE="./function-app.bicep"
DBT_JOB_BICEP_FILE="${FUNCTION_CODE_FOLDER}/dbt-job.bicep" # Bicep file relative to function folder

# --- Function App Specific Config ---
FUNCTION_OS_TYPE="Linux"
FUNCTION_PLAN_SKU="Y1" # Consumption
FUNCTION_RUNTIME="python"
FUNCTION_RUNTIME_VERSION="PYTHON|3.11" # Match your Python version

# --- Deployment Names ---
# Using project name for predictability and potential cleanup
CORE_INFRA_DEPLOYMENT_NAME="core-infra-${PROJECT_NAME}"
UC_ACI_DEPLOYMENT_NAME="uc-aci-${PROJECT_NAME}" # Will deploy using this name
FUNCTION_APP_DEPLOYMENT_NAME="func-app-${PROJECT_NAME}"

# --- Get Subscription ID ---
# AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
AZURE_SUBSCRIPTION_ID="bb6dad89-33c6-423b-a68c-384a77718986" # Use static ID from logs if preferred
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then echo "ERROR: Could not determine Azure Subscription ID."; exit 1; fi
echo "Using Subscription ID: $AZURE_SUBSCRIPTION_ID"
echo "Using Resource Group: $RESOURCE_GROUP"
echo "Using Location: $LOCATION"
echo "Using Project Name: $PROJECT_NAME"

#=======================================================================
# --- 1. Deploy Core Infrastructure (ACR, Storage, VNet, KV, UAMI) ---
#=======================================================================
echo "--- [1/7] Deploying Core Infrastructure ($CORE_BICEP_FILE)..."
core_deployment_output=$(az deployment group create \
    --name $CORE_INFRA_DEPLOYMENT_NAME \
    --resource-group $RESOURCE_GROUP \
    --template-file $CORE_BICEP_FILE \
    --parameters projectName=$PROJECT_NAME location=$LOCATION uamiName=$UAMI_NAME \
    --output json)
if [ $? -ne 0 ]; then echo "ERROR: Core Bicep deployment failed."; exit 1; fi
echo "Core infrastructure deployment successful."

# --- Extract Core Outputs ---
echo "Extracting core outputs..."
ACR_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrName.value // empty')
ACR_LOGIN_SERVER=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrLoginServer.value // empty')
ACR_RESOURCE_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrId.value // empty')
STORAGE_ACCT_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageAccountName.value // empty')
STORAGE_ACCOUNT_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageAccountId.value // empty')
BLOB_CONTAINER_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageBlobContainerName.value // empty')
DBT_PROJECT_FILE_SHARE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageDbtFileShareName.value // empty') # Get dbt share name
ACI_SUBNET_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.aciSubnetId.value // empty')
KEY_VAULT_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.keyVaultName.value // empty')
KEY_VAULT_URI=$(echo "$core_deployment_output" | jq -r '.properties.outputs.keyVaultUri.value // empty')
UAMI_RESOURCE_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiResourceId.value // empty')
UAMI_PRINCIPAL_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiPrincipalId.value // empty')
UAMI_CLIENT_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiClientId.value // empty')
UC_FILE_SHARE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageUcFileShareName.value') # <<< Get UC share name

# Validate key outputs necessary for subsequent steps
if [[ -z "$ACR_NAME" || -z "$ACR_LOGIN_SERVER" || -z "$ACR_RESOURCE_ID" || \
      -z "$STORAGE_ACCT_NAME" || -z "$STORAGE_ACCOUNT_ID" || -z "$BLOB_CONTAINER_NAME" || \
      -z "$DBT_PROJECT_FILE_SHARE_NAME" || -z "$ACI_SUBNET_ID" || -z "$KEY_VAULT_NAME" || \
      -z "$KEY_VAULT_URI" || -z "$UAMI_RESOURCE_ID" || -z "$UAMI_PRINCIPAL_ID" || -z "$UAMI_CLIENT_ID" || \
      -z "$UC_FILE_SHARE_NAME" ]]; then # <<< Added UC_FILE_SHARE_NAME check
    echo "ERROR: Failed to extract one or more required outputs from core Bicep deployment. Check output names in core-infra.bicep."
    # echo "$core_deployment_output" # Print raw output for debugging
    exit 1
fi
echo "Core outputs parsed."

#=======================================================================
# --- 2. Assign Required RBAC Roles to UAMI ---
#=======================================================================
# (Keep this section as is - ensures UAMI has permissions before it's used)
echo "--- [2/7] Assigning RBAC roles to UAMI ($UAMI_NAME - Principal ID: $UAMI_PRINCIPAL_ID)..."

# Role for Function App to manage resources in the RG (Deployments, ACI Get/Exec)
echo "  Assigning 'Contributor' on Resource Group '$RESOURCE_GROUP'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Contributor" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}" --only-show-errors || echo "    WARN: RG Contributor role assignment might already exist or failed."

# Role for Function App to access Key Vault Secrets via SDK
echo "  Assigning 'Key Vault Secrets User' on Key Vault '$KEY_VAULT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" --only-show-errors || echo "    WARN: KV Secrets User role assignment might already exist or failed."

# Role for dbt ACI (using same UAMI) to pull from ACR
echo "  Assigning 'AcrPull' on ACR '$ACR_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "AcrPull" --scope $ACR_RESOURCE_ID --only-show-errors || echo "    WARN: ACR Pull role assignment might already exist or failed."

# Role for dbt ACI & UC ACI (if using MI Mount) to mount File Share
echo "  Assigning 'Storage File Data SMB Share Contributor' on Storage Account '$STORAGE_ACCT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Storage File Data SMB Share Contributor" --scope $STORAGE_ACCOUNT_ID --only-show-errors || echo "    WARN: Storage File Data role assignment might already exist or failed."

# Role for dbt ACI (using same UAMI) to access ADLS Gen2 data
echo "  Assigning 'Storage Blob Data Contributor' on Storage Account '$STORAGE_ACCT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $STORAGE_ACCOUNT_ID --only-show-errors || echo "    WARN: Storage Blob Data role assignment might already exist or failed."

echo "UAMI roles assignment attempts complete."
echo "Waiting 60 seconds for RBAC propagation..."
sleep 60 # Add delay to allow permissions to propagate

#=======================================================================
# --- 3. Prepare Storage (Add Key to KV, Prepare Shares) ---
#=======================================================================
echo "--- [3/7] Preparing Storage Account ($STORAGE_ACCT_NAME)..."
# Get Storage Key (Required for ACI volume mount via key & file share prep)
STORAGE_ACCOUNT_KEY=$(az storage account keys list --account-name $STORAGE_ACCT_NAME --resource-group $RESOURCE_GROUP --query '[0].value' -o tsv)
if [ -z "$STORAGE_ACCOUNT_KEY" ]; then echo "ERROR: Failed to retrieve storage key."; exit 1; fi
echo "Storage key retrieved."

# Add key to Key Vault (used by Function App SDK method)
echo "Adding storage key to Key Vault '$KEY_VAULT_NAME' as secret '$STORAGE_KEY_SECRET_NAME'..."
az keyvault secret set --vault-name $KEY_VAULT_NAME --name $STORAGE_KEY_SECRET_NAME --value "$STORAGE_ACCOUNT_KEY" --output none
echo "Secret added to Key Vault."

# --- Prepare UC File Share (${UC_FILE_SHARE_NAME}) --- <<< MODIFIED SECTION
echo "Preparing Unity Catalog file share '$UC_FILE_SHARE_NAME'..."
# Create directories within the UC file share
echo "  Creating 'conf' directory..."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "conf" --output none
echo "  Creating 'db' directory..."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "db" --output none
echo "  Creating 'logs' directory..."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "logs" --output none

# Upload initial UC config files from local path to the 'conf' directory
echo "Uploading initial UC config files from '$UC_CONFIG_LOCAL_PATH' to share '$UC_FILE_SHARE_NAME/conf'..."
if [ -d "$UC_CONFIG_LOCAL_PATH" ]; then
    az storage file upload-batch \
        --account-name "$STORAGE_ACCT_NAME" \
        --account-key "$STORAGE_ACCOUNT_KEY" \
        --destination "$UC_FILE_SHARE_NAME" \
        --destination-path "conf" \
        --source "$UC_CONFIG_LOCAL_PATH" \
        --output none
    if [ $? -ne 0 ]; then echo "ERROR: UC config file upload failed."; exit 1; fi
    echo "  UC config files upload complete."
else
    echo "  WARNING: Local UC config path '$UC_CONFIG_LOCAL_PATH' not found. Skipping UC config upload."
fi
# --- End of UC File Share Preparation ---

# --- Prepare DBT File Share (${DBT_PROJECT_FILE_SHARE_NAME}) ---
# Note: File share $DBT_PROJECT_FILE_SHARE_NAME is created by core-infra.bicep
echo "Uploading initial dbt project files from '$DBT_PROJECT_LOCAL_PATH' to share '$DBT_PROJECT_FILE_SHARE_NAME'..."
# (Keep this commented/uncommented based on your need for initial dbt upload)
#if [ -d "$DBT_PROJECT_LOCAL_PATH" ]; then
#    az storage file upload-batch \
#        --account-name "$STORAGE_ACCT_NAME" \
#        --account-key "$STORAGE_ACCOUNT_KEY" \
#        --destination "$DBT_PROJECT_FILE_SHARE_NAME" \
#        --source "$DBT_PROJECT_LOCAL_PATH" \
#        --destination-path "." \
#        --output none
#    if [ $? -ne 0 ]; then echo "ERROR: dbt project file upload failed."; exit 1; fi
#    echo "dbt project upload complete."
#else
#    echo "WARNING: Local dbt project path '$DBT_PROJECT_LOCAL_PATH' not found. Skipping dbt upload."
#fi

#=======================================================================
# --- 4. Deploy Unity Catalog ACI (Public IP) ---
#=======================================================================
# This section now depends on the UC_FILE_SHARE_NAME being prepared in Step 3
echo "--- [4/7] Deploying Unity Catalog ACI ($UC_ACI_BICEP_FILE)..."

# Recommendation: Use UAMI instead of ACR credentials if possible (requires Bicep change)
# For now, using credentials as per original script and Bicep file
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)
if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then echo "ERROR: Could not retrieve ACR credentials."; exit 1; fi
echo "ACR credentials retrieved (for UC ACI)."

# Deploy the UC ACI Bicep template
uc_deployment_output=$(az deployment group create \
  --name $UC_ACI_DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --template-file $UC_ACI_BICEP_FILE \
  --parameters \
    projectName=$PROJECT_NAME \
    location=$LOCATION \
    acrLoginServer=$ACR_LOGIN_SERVER \
    acrUsername="$ACR_USERNAME" \
    acrPassword="$ACR_PASSWORD" \
    storageAccountName=$STORAGE_ACCT_NAME \
    storageFileShareName=$UC_FILE_SHARE_NAME \
  --output json)
if [ $? -ne 0 ]; then echo "ERROR: UC ACI Bicep deployment command failed."; exit 1; fi

# Extract UC ACI Name from output (more robust than hardcoding)
UC_ACI_NAME=$(echo "$uc_deployment_output" | jq -r '.properties.outputs.aciName.value // empty')
UC_ACI_FQDN=$(echo "$uc_deployment_output" | jq -r '.properties.outputs.aciPublicFqdn.value // empty') # If needed later

if [ -z "$UC_ACI_NAME" ]; then
    echo "ERROR: Failed to get UC ACI Name from deployment output. Using fallback name."
    UC_ACI_NAME="aci-${PROJECT_NAME}-uc" # Fallback if output fails
else
    echo "UC ACI deployed with name: $UC_ACI_NAME"
fi
if [ -n "$UC_ACI_FQDN" ]; then
    echo "UC ACI FQDN: $UC_ACI_FQDN"
fi


# Write UC Admin Token to Key vault
echo "Writing admin token to $TOKEN_SECRET_NAME in :$KEY_VAULT_NAME  "
ADMIN_TOKEN=$(az container exec --resource-group $RESOURCE_GROUP  --name $UC_ACI_NAME  --exec-command "cat etc/conf/token.txt")
az keyvault secret set --vault-name $KEY_VAULT_NAME --name $TOKEN_SECRET_NAME --value $ADMIN_TOKEN


#=======================================================================
# --- 5. Compile dbt Bicep Template to JSON ---
#=======================================================================
# (Keep this section as is)
echo "--- [5/7] Compiling dbt Bicep template ($DBT_JOB_BICEP_FILE)..."
DBT_JOB_JSON_FILE_NAME="dbt-job.json" # Just the filename
DBT_JOB_JSON_FILE_PATH="${FUNCTION_CODE_FOLDER}/${DBT_JOB_JSON_FILE_NAME}" # Full path for output

mkdir -p "$FUNCTION_CODE_FOLDER" # Ensure function code folder exists

az bicep build --file "$DBT_JOB_BICEP_FILE" --outfile "$DBT_JOB_JSON_FILE_PATH"
if [ $? -ne 0 ]; then echo "ERROR: Failed to compile dbt Bicep template."; exit 1; fi
echo "dbt Bicep template compiled to '$DBT_JOB_JSON_FILE_PATH'."


#=======================================================================
# --- 6. Deploy Azure Function App Infrastructure & Settings ---
#=======================================================================
echo "--- [6/7] Deploying Function App Infrastructure & Settings..."

# --- 6a. Deploy Minimal Function App Bicep ---
echo "  Deploying Function App Bicep ($FUNCTION_APP_BICEP_FILE)..."
function_deployment_output=$(az deployment group create \
    --name "$FUNCTION_APP_DEPLOYMENT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$FUNCTION_APP_BICEP_FILE" \
    --parameters \
      projectName="$PROJECT_NAME" \
      location="$LOCATION" \
      osType="$FUNCTION_OS_TYPE" \
      appServicePlanSkuName="$FUNCTION_PLAN_SKU" \
      functionWorkerRuntime="$FUNCTION_RUNTIME" \
      functionRuntimeVersion="$FUNCTION_RUNTIME_VERSION" \
      uamiResourceId="$UAMI_RESOURCE_ID" \
    --output json)

if [ $? -ne 0 ]; then echo "ERROR: Function App Bicep deployment failed."; exit 1; fi

FUNCTION_APP_NAME=$(echo "$function_deployment_output" | jq -r '.properties.outputs.functionAppName.value // empty')
APPINSIGHTS_INSTRUMENTATIONKEY=$(echo "$function_deployment_output" | jq -r '.properties.outputs.appInsightsInstrumentationKey.value // empty') # <<< Assuming output exists
if [ -z "$FUNCTION_APP_NAME" ]; then echo "ERROR: Failed to get Function App name from deployment output."; exit 1; fi
echo "  Function App infrastructure deployed: $FUNCTION_APP_NAME"

FUNCTION_APP_NAME_LOWER=$(echo "$FUNCTION_APP_NAME" | tr '[:upper:]' '[:lower:]')

# --- 6b. Set Function App Application Settings via CLI ---
echo "  Setting Function App Application Settings for '$FUNCTION_APP_NAME'..."

KEY_VAULT_URI_NO_SLASH=${KEY_VAULT_URI%/}
STORAGE_KEY_KV_REFERENCE="@Microsoft.KeyVault(SecretUri=${KEY_VAULT_URI_NO_SLASH}/secrets/${STORAGE_KEY_SECRET_NAME})"
# Required for WEBSITE_CONTENTSHARE on Linux Consumption
STORAGE_CONN_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};EndpointSuffix=core.windows.net"

DBT_COMMAND="dbt run" # <<< DEFINE: Example dbt command

app_settings=(
    "AzureWebJobsStorage=${STORAGE_KEY_KV_REFERENCE}"
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=${STORAGE_CONN_STRING}"
    "WEBSITE_CONTENTSHARE=${FUNCTION_APP_NAME_LOWER}"
    "FUNCTIONS_EXTENSION_VERSION=~4"
    "FUNCTIONS_WORKER_RUNTIME=${FUNCTION_RUNTIME}"
    "AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}"
    "RESOURCE_GROUP=${RESOURCE_GROUP}"
    "LOCATION=${LOCATION}"
    "PROJECT_NAME=${PROJECT_NAME}"
    "ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}"
    "STORAGE_ACCT_NAME=${STORAGE_ACCT_NAME}"
    "DBT_PROJECT_FILE_SHARE_NAME=${DBT_PROJECT_FILE_SHARE_NAME}"
    "DELTA_CONTAINER_NAME=${BLOB_CONTAINER_NAME}"
    "DBT_JOB_JSON_FILE_NAME=${DBT_JOB_JSON_FILE_NAME}"
    "UAMI_RESOURCE_ID=${UAMI_RESOURCE_ID}"
    "UC_ACI_NAME=${UC_ACI_NAME}"
    "DBT_COMMAND=${DBT_COMMAND}"
    "DBT_MEMORY_GB=${DBT_MEMORY_GB}"
    "DBT_CPU_CORES=${DBT_CPU_CORES}"
    "KEY_VAULT_URI=${KEY_VAULT_URI}"
    "DBT_STORAGE_KEY_SECRET_NAME=${STORAGE_KEY_SECRET_NAME}" # Name of KV secret holding storage key
    "AZURE_CLIENT_ID=${UAMI_CLIENT_ID}" # UAMI Client ID for potential SDK auth
    "ACI_SUBNET_ID=${ACI_SUBNET_ID}" # Needed if deploying DBT ACI to VNet
    "APPINSIGHTS_INSTRUMENTATIONKEY=${APPINSIGHTS_INSTRUMENTATIONKEY}" # <<< Now from output (ensure Bicep provides it)
)

az functionapp config appsettings set \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings "${app_settings[@]}" \
    --output none
if [ $? -ne 0 ]; then echo "ERROR: Failed to set Function App application settings."; exit 1; fi
echo "  Function App application settings configured."

echo "  Restarting Function App to apply settings..."
az functionapp restart --name "$FUNCTION_APP_NAME" -g "$RESOURCE_GROUP" --output none


#=======================================================================
# --- 7. Deploy Function App Code ---
#=======================================================================
echo "--- [7/7] Deploying Function App Code from '$FUNCTION_CODE_FOLDER'..."
# (Keep this section as is)

if [ ! -f "$DBT_JOB_JSON_FILE_PATH" ]; then
    echo "ERROR: Compiled dbt job JSON file not found at '$DBT_JOB_JSON_FILE_PATH'. Check Step 5."
    exit 1
fi

ZIP_FILE_PATH="/tmp/${FUNCTION_APP_NAME}_code.zip"
echo "Creating deployment package '$ZIP_FILE_PATH' from '$FUNCTION_CODE_FOLDER'..."
(cd "$FUNCTION_CODE_FOLDER" && zip -r "$ZIP_FILE_PATH" ./* -x "*.pyc" ".venv/*" ".vscode/*" ".git/*")
if [ ! -f "$ZIP_FILE_PATH" ]; then echo "ERROR: Failed to create zip file for deployment."; exit 1; fi
echo "Zip package created."

echo "Submitting zip deployment to '$FUNCTION_APP_NAME'..."
az functionapp deployment source config-zip \
    -g "$RESOURCE_GROUP" \
    -n "$FUNCTION_APP_NAME" \
    --src "$ZIP_FILE_PATH" \
    --build-remote true \
    --output none
if [ $? -ne 0 ]; then echo "ERROR: Function App code deployment failed."; rm "$ZIP_FILE_PATH"; exit 1; fi
echo "Function App code deployment submitted successfully."

rm "$ZIP_FILE_PATH" # Clean up local zip file

echo ""
echo "--- Full Deployment Script Completed Successfully ---"
echo "Resources Deployed/Configured in Resource Group: $RESOURCE_GROUP"
echo "  - Core Infra (ACR, Storage, VNet, KV, UAMI)"
echo "  - UC File Share '$UC_FILE_SHARE_NAME' prepared and config uploaded."
echo "  - Unity Catalog ACI: $UC_ACI_NAME (Public FQDN: ${UC_ACI_FQDN:-N/A})"
echo "  - Function App: $FUNCTION_APP_NAME"
echo "  - Function App Code Deployed"
echo ""
echo "The dbt orchestrator timer function will trigger based on its schedule."
echo "Ensure initial RBAC propagation time was sufficient if encountering permission issues on first run."

exit 0