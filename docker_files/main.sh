#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
echo "--- Configuration ---"
RESOURCE_GROUP="DC_internship_2025"
LOCATION="westeurope"
PROJECT_NAME="unitycatalogproject" #All the resource group names will be derived from this project name



# ---Container Resource Config ---
UC_CPU_CORES="1"                     # CPU for UC container
UC_MEMORY_GB="1"                    # Memory for UC container
PM_CPU_CORES="1"                  #  CPU for Permissions Manager container
PM_MEMORY_GB="1"                  #  Memory for Permissions Manager container
DBT_MEMORY_GB="1"                     # ACI Resource Allocation (for DBT job)
DBT_CPU_CORES="1"                     # ACI Resource Allocation (for DBT job)


# --- NEW: Image Config for Multi-Container Setup ---
UC_IMAGE_NAME="uc-server"             # Name of your UC server image in ACR
UC_IMAGE_TAG="latest"                 # Tag for UC server image
PERMISSIONS_MANAGER_IMAGE_NAME="uc-permissions-manager" # Name for the new image
PERMISSIONS_MANAGER_IMAGE_TAG="latest" # Tag for the new image
PERMISSIONS_MANAGER_SRC_PATH="./permissions-manager-app" # <<< ADDED: Path to Dockerfile, reqs, code for Permissions Manager

# --- NEW: Container Resource Config ---
UC_CPU_CORES="1"                     # CPU for UC container
UC_MEMORY_GB="1"                    # Memory for UC container
PM_CPU_CORES="1"                  #  CPU for Permissions Manager container
PM_MEMORY_GB="1"                  #  Memory for Permissions Manager container

# --- DBT/Function Config (Keep as is) ---
DBT_PROJECT_LOCAL_PATH="./dbt-project" # Local path to dbt project for initial upload
UC_CONFIG_LOCAL_PATH="./uc-config-for-upload" # Local path for UC config files
FUNCTION_CODE_FOLDER="./function"     # Folder containing function_app.py, etc.
STORAGE_KEY_SECRET_NAME="dbt-storage-account-key" # Name for Storage Key secret in Key Vault
TOKEN_SECRET_NAME="uc-admin-key"      # Name for UC Token secret in Key Vault

# --- Bicep File Paths ---
UAMI_NAME="dbt-job-identity"          # Name for the User Assigned Managed Identity
CORE_BICEP_FILE="./core-infra.bicep"
UC_ACI_BICEP_FILE="./unityCatalogContainer.bicep"
FUNCTION_APP_BICEP_FILE="./function-app.bicep"
DBT_JOB_BICEP_FILE="${FUNCTION_CODE_FOLDER}/dbt-job.bicep"

# --- Function App Specific Config (Keep as is) ---
FUNCTION_OS_TYPE="Linux"
FUNCTION_PLAN_SKU="Y1"
FUNCTION_RUNTIME="python"
FUNCTION_RUNTIME_VERSION="PYTHON|3.11"

# --- Deployment Names ---
CORE_INFRA_DEPLOYMENT_NAME="core-infra-${PROJECT_NAME}"
UC_ACI_GROUP_DEPLOYMENT_NAME="uc-aci-group-${PROJECT_NAME}"
FUNCTION_APP_DEPLOYMENT_NAME="func-app-${PROJECT_NAME}"

# --- Get Subscription ID ---
AZURE_SUBSCRIPTION_ID="bb6dad89-33c6-423b-a68c-384a77718986" # Use static ID from logs if preferred
if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then echo "ERROR: Could not determine Azure Subscription ID."; exit 1; fi
echo "Using Subscription ID: $AZURE_SUBSCRIPTION_ID"
echo "Using Resource Group: $RESOURCE_GROUP"
echo "Using Location: $LOCATION"
echo "Using Project Name: $PROJECT_NAME"

#=======================================================================
# --- 1. Deploy Core Infrastructure (ACR, Storage, VNet, KV, UAMI) ---
#=======================================================================
echo "--- [1/8] Deploying Core Infrastructure ($CORE_BICEP_FILE)..." # Step count updated
# --- This section remains unchanged ---
core_deployment_output=$(az deployment group create \
    --name $CORE_INFRA_DEPLOYMENT_NAME \
    --resource-group $RESOURCE_GROUP \
    --template-file $CORE_BICEP_FILE \
    --parameters projectName=$PROJECT_NAME location=$LOCATION uamiName=$UAMI_NAME \
    --output json)
if [ $? -ne 0 ]; then echo "ERROR: Core Bicep deployment failed."; exit 1; fi
echo "Core infrastructure deployment successful."
echo "Extracting core outputs..."
ACR_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrName.value // empty')
ACR_LOGIN_SERVER=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrLoginServer.value // empty')
ACR_RESOURCE_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.acrId.value // empty')
STORAGE_ACCT_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageAccountName.value // empty')
STORAGE_ACCOUNT_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageAccountId.value // empty')
BLOB_CONTAINER_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageBlobContainerName.value // empty')
DBT_PROJECT_FILE_SHARE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageDbtFileShareName.value // empty')
ACI_SUBNET_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.aciSubnetId.value // empty')
KEY_VAULT_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.keyVaultName.value // empty')
KEY_VAULT_URI=$(echo "$core_deployment_output" | jq -r '.properties.outputs.keyVaultUri.value // empty')
UAMI_RESOURCE_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiResourceId.value // empty')
UAMI_PRINCIPAL_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiPrincipalId.value // empty')
UAMI_CLIENT_ID=$(echo "$core_deployment_output" | jq -r '.properties.outputs.uamiClientId.value // empty')
UC_FILE_SHARE_NAME=$(echo "$core_deployment_output" | jq -r '.properties.outputs.storageUcFileShareName.value')
if [[ -z "$ACR_NAME" || -z "$ACR_LOGIN_SERVER" || -z "$ACR_RESOURCE_ID" || \
      -z "$STORAGE_ACCT_NAME" || -z "$STORAGE_ACCOUNT_ID" || -z "$BLOB_CONTAINER_NAME" || \
      -z "$DBT_PROJECT_FILE_SHARE_NAME" || -z "$ACI_SUBNET_ID" || -z "$KEY_VAULT_NAME" || \
      -z "$KEY_VAULT_URI" || -z "$UAMI_RESOURCE_ID" || -z "$UAMI_PRINCIPAL_ID" || -z "$UAMI_CLIENT_ID" || \
      -z "$UC_FILE_SHARE_NAME" ]]; then
    echo "ERROR: Failed to extract one or more required outputs from core Bicep deployment. Check output names in core-infra.bicep."
    exit 1
fi
echo "Core outputs parsed."

#=======================================================================
# --- 2. Assign Required RBAC Roles to UAMI ---
#=======================================================================
echo "--- [2/8] Assigning RBAC roles to UAMI ($UAMI_NAME - Principal ID: $UAMI_PRINCIPAL_ID)..." # Step count updated
# --- This section remains unchanged ---
echo "  Assigning 'Contributor' on Resource Group '$RESOURCE_GROUP'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Contributor" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups/${RESOURCE_GROUP}" --only-show-errors || echo "    WARN: RG Contributor role assignment might already exist or failed."
echo "  Assigning 'Key Vault Secrets User' on Key Vault '$KEY_VAULT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" --only-show-errors || echo "    WARN: KV Secrets User role assignment might already exist or failed."
echo "  Assigning 'AcrPull' on ACR '$ACR_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "AcrPull" --scope $ACR_RESOURCE_ID --only-show-errors || echo "    WARN: ACR Pull role assignment might already exist or failed."
echo "  Assigning 'Storage File Data SMB Share Contributor' on Storage Account '$STORAGE_ACCT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Storage File Data SMB Share Contributor" --scope $STORAGE_ACCOUNT_ID --only-show-errors || echo "    WARN: Storage File Data role assignment might already exist or failed."
echo "  Assigning 'Storage Blob Data Contributor' on Storage Account '$STORAGE_ACCT_NAME'..."
az role assignment create --assignee-object-id $UAMI_PRINCIPAL_ID --assignee-principal-type ServicePrincipal --role "Storage Blob Data Contributor" --scope $STORAGE_ACCOUNT_ID --only-show-errors || echo "    WARN: Storage Blob Data role assignment might already exist or failed."
echo "UAMI roles assignment attempts complete."
echo "Waiting 60 seconds for RBAC propagation..."
sleep 60

#=======================================================================
# --- 3. Prepare Storage (Add Key to KV, Prepare Shares) ---
#=======================================================================
echo "--- [3/8] Preparing Storage Account ($STORAGE_ACCT_NAME)..." # Step count updated
# --- This section remains unchanged ---
STORAGE_ACCOUNT_KEY=$(az storage account keys list --account-name $STORAGE_ACCT_NAME --resource-group $RESOURCE_GROUP --query '[0].value' -o tsv)
if [ -z "$STORAGE_ACCOUNT_KEY" ]; then echo "ERROR: Failed to retrieve storage key."; exit 1; fi
echo "Storage key retrieved."
echo "Adding storage key to Key Vault '$KEY_VAULT_NAME' as secret '$STORAGE_KEY_SECRET_NAME'..."
az keyvault secret set --vault-name $KEY_VAULT_NAME --name $STORAGE_KEY_SECRET_NAME --value "$STORAGE_ACCOUNT_KEY" --output none
echo "Secret added to Key Vault."
echo "Preparing Unity Catalog file share '$UC_FILE_SHARE_NAME'..."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "conf" --output none || echo "WARN: 'conf' dir might already exist."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "db" --output none || echo "WARN: 'db' dir might already exist."
az storage directory create --account-name $STORAGE_ACCT_NAME --account-key $STORAGE_ACCOUNT_KEY --share-name $UC_FILE_SHARE_NAME --name "logs" --output none || echo "WARN: 'logs' dir might already exist."
echo "Uploading initial UC config files from '$UC_CONFIG_LOCAL_PATH' to share '$UC_FILE_SHARE_NAME/conf'..."
if [ -d "$UC_CONFIG_LOCAL_PATH" ]; then
    az storage file upload-batch --account-name "$STORAGE_ACCT_NAME" --account-key "$STORAGE_ACCOUNT_KEY" --destination "$UC_FILE_SHARE_NAME" --destination-path "conf" --source "$UC_CONFIG_LOCAL_PATH" --output none
    if [ $? -ne 0 ]; then echo "ERROR: UC config file upload failed."; exit 1; fi
    echo "  UC config files upload complete."
else
    echo "  WARNING: Local UC config path '$UC_CONFIG_LOCAL_PATH' not found. Skipping UC config upload."
fi
echo "Uploading initial dbt project files from '$DBT_PROJECT_LOCAL_PATH' to share '$DBT_PROJECT_FILE_SHARE_NAME'..."
# (Keep dbt upload commented/uncommented as needed)
#=======================================================================
# --- 4. Build and Push Permissions Manager Image --- <<< NEW STEP
#=======================================================================
echo "--- [4/8] Building and Pushing Permissions Manager Image to ACR ($ACR_NAME)..."
if [ ! -d "$PERMISSIONS_MANAGER_SRC_PATH" ]; then
    echo "ERROR: Permissions manager source code directory not found at '$PERMISSIONS_MANAGER_SRC_PATH'"
    exit 1
fi
if [ ! -f "${PERMISSIONS_MANAGER_SRC_PATH}/dockerfile.streamlit" ]; then
    echo "ERROR: Dockerfile not found at '${PERMISSIONS_MANAGER_SRC_PATH}/dockerfile.streamlit'"
    exit 1
fi

# Use ACR Build for simplicity (builds in the cloud)
echo "Submitting ACR build task for ${PERMISSIONS_MANAGER_IMAGE_NAME}:${PERMISSIONS_MANAGER_IMAGE_TAG}..."
#az acr build \
#    --registry $ACR_NAME \
#    --resource-group $RESOURCE_GROUP \
#    --image "${PERMISSIONS_MANAGER_IMAGE_NAME}:${PERMISSIONS_MANAGER_IMAGE_TAG}" \
#    --file "${PERMISSIONS_MANAGER_SRC_PATH}/dockerfile.streamlit" \
#    "$PERMISSIONS_MANAGER_SRC_PATH" \
#    --output table

if [ $? -ne 0 ]; then
    echo "ERROR: ACR build failed for permissions manager image."
    exit 1
fi
echo "Permissions manager image build submitted/completed successfully."



#=======================================================================
# --- 5. Deploy Unity Catalog ACI Group (Multi-container) --- <<< MODIFIED STEP
#=======================================================================
echo "--- [5/8] Deploying Multi-Container ACI Group ($UC_ACI_BICEP_FILE)..." # Step count updated

ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query "passwords[0].value" -o tsv)
if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then echo "ERROR: Could not retrieve ACR credentials."; exit 1; fi
echo "ACR credentials retrieved (for UC ACI Group)."

uc_deployment_output=$(az deployment group create \
  --name $UC_ACI_GROUP_DEPLOYMENT_NAME \
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
    ucImageName=$UC_IMAGE_NAME \
    ucImageTag=$UC_IMAGE_TAG \
    permissionsManagerImageName=$PERMISSIONS_MANAGER_IMAGE_NAME \
    permissionsManagerImageTag=$PERMISSIONS_MANAGER_IMAGE_TAG \
    ucCpuCores=$UC_CPU_CORES \
    ucMemoryInGB=$UC_MEMORY_GB \
    pmCpuCores=$PM_CPU_CORES \
    pmMemoryInGB=$PM_MEMORY_GB \
  --output json)
if [ $? -ne 0 ]; then echo "ERROR: UC ACI Group Bicep deployment command failed."; exit 1; fi

UC_ACI_GROUP_NAME=$(echo "$uc_deployment_output" | jq -r '.properties.outputs.aciGroupName.value // empty')
UC_ACI_FQDN=$(echo "$uc_deployment_output" | jq -r '.properties.outputs.aciPublicFqdn.value // empty')
PERMISSIONS_MANAGER_UI_URL=$(echo "$uc_deployment_output" | jq -r '.properties.outputs.permissionsManagerUiUrl.value // empty') # Extract new output

if [ -z "$UC_ACI_GROUP_NAME" ]; then
    echo "ERROR: Failed to get UC ACI Group Name from deployment output."
    exit 1
else
    echo "UC ACI Group deployed with name: $UC_ACI_GROUP_NAME"
fi
if [ -n "$UC_ACI_FQDN" ]; then
    echo "UC ACI Group FQDN: $UC_ACI_FQDN"
    echo "Permissions Manager UI URL: $PERMISSIONS_MANAGER_UI_URL"
fi


#=======================================================================
# --- 6. Retrieve UC Admin Token & Store in Key Vault --- <<< MODIFIED STEP
#=======================================================================
echo "--- [6/8] Retrieving UC Admin Token and Storing in Key Vault..." # Step count updated

# This MUST match the 'name' of the UC server container defined in your multi-container Bicep file
UC_SERVER_CONTAINER_NAME="unitycatalog" # Adjust if your Bicep uses a different name

echo "Attempting to retrieve admin token via exec..."
ADMIN_TOKEN=$(az container exec \
  --resource-group $RESOURCE_GROUP \
  --name $UC_ACI_GROUP_NAME \
  --container-name $UC_SERVER_CONTAINER_NAME \
  --exec-command "cat etc/conf/token.txt" \
  --output tsv 2>/dev/null)

if [[ -z "$ADMIN_TOKEN" ]]; then
     echo "WARNING: Failed to retrieve admin token or token is empty. Check container '$UC_SERVER_CONTAINER_NAME' logs in group '$UC_ACI_GROUP_NAME'."

     echo "Attempting to proceed without storing token in Key Vault..."
else
    echo "Admin token retrieved. Writing to Key Vault '$KEY_VAULT_NAME' as secret '$TOKEN_SECRET_NAME'..."
    az keyvault secret set --vault-name $KEY_VAULT_NAME --name $TOKEN_SECRET_NAME --value "$ADMIN_TOKEN" --output none
    echo "Secret '$TOKEN_SECRET_NAME' added to Key Vault."
fi


#=======================================================================
# --- 7. Compile dbt Bicep Template to JSON ---
#=======================================================================
echo "--- [7/8] Compiling dbt Bicep template ($DBT_JOB_BICEP_FILE)..." # Step count updated
DBT_JOB_JSON_FILE_NAME="dbt-job.json"
DBT_JOB_JSON_FILE_PATH="${FUNCTION_CODE_FOLDER}/${DBT_JOB_JSON_FILE_NAME}"
mkdir -p "$FUNCTION_CODE_FOLDER"
az bicep build --file "$DBT_JOB_BICEP_FILE" --outfile "$DBT_JOB_JSON_FILE_PATH"
if [ $? -ne 0 ]; then echo "ERROR: Failed to compile dbt Bicep template."; exit 1; fi
echo "dbt Bicep template compiled to '$DBT_JOB_JSON_FILE_PATH'."


#=======================================================================
# --- 8. Deploy Azure Function App Infrastructure & Settings ---
#=======================================================================
echo "--- [8/8] Deploying Function App Infrastructure & Settings..." # Step count updated

# --- 8a. Deploy Minimal Function App Bicep (Unchanged) ---
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
APPINSIGHTS_INSTRUMENTATIONKEY=$(echo "$function_deployment_output" | jq -r '.properties.outputs.appInsightsInstrumentationKey.value // empty') # Assume output exists
if [ -z "$FUNCTION_APP_NAME" ]; then echo "ERROR: Failed to get Function App name from deployment output."; exit 1; fi
echo "  Function App infrastructure deployed: $FUNCTION_APP_NAME"
FUNCTION_APP_NAME_LOWER=$(echo "$FUNCTION_APP_NAME" | tr '[:upper:]' '[:lower:]')

# --- 8b. Set Function App Application Settings via CLI ---
echo "  Setting Function App Application Settings for '$FUNCTION_APP_NAME'..."
KEY_VAULT_URI_NO_SLASH=${KEY_VAULT_URI%/}
STORAGE_KEY_KV_REFERENCE="@Microsoft.KeyVault(SecretUri=${KEY_VAULT_URI_NO_SLASH}/secrets/${STORAGE_KEY_SECRET_NAME})"
STORAGE_CONN_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCT_NAME};AccountKey=${STORAGE_ACCOUNT_KEY};EndpointSuffix=core.windows.net"
DBT_COMMAND="dbt run"

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
    "UAMI_RESOURCE_ID=${UAMI_RESOURCE_ID}" # UAMI for Function/DBT Job
    # "UC_ACI_GROUP_NAME=${UC_ACI_GROUP_NAME}" # Pass group name if needed by function
    # "UC_API_ENDPOINT=http://${UC_ACI_FQDN}:8080/api/2.1/unity-catalog" # Pass UC endpoint if dbt needs it directly
    "DBT_COMMAND=${DBT_COMMAND}"
    "DBT_MEMORY_GB=${DBT_MEMORY_GB}"
    "DBT_CPU_CORES=${DBT_CPU_CORES}"
    "KEY_VAULT_URI=${KEY_VAULT_URI}" # For Function/DBT to read secrets
    "UC_TOKEN_SECRET_NAME=${TOKEN_SECRET_NAME}" # <<< Name of KV secret holding UC token
    "DBT_STORAGE_KEY_SECRET_NAME=${STORAGE_KEY_SECRET_NAME}"
    "AZURE_CLIENT_ID=${UAMI_CLIENT_ID}"
    "ACI_SUBNET_ID=${ACI_SUBNET_ID}"
    "APPINSIGHTS_INSTRUMENTATIONKEY=${APPINSIGHTS_INSTRUMENTATIONKEY}"
    "PERMISSIONS_MANAGER_UI_URL=${PERMISSIONS_MANAGER_UI_URL}" # <<< Optional info setting
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
# --- 9. Deploy Function App Code ---
#=======================================================================
echo "--- [9/9] Deploying Function App Code from '$FUNCTION_CODE_FOLDER'..." # Step count updated
# --- This section remains unchanged ---
if [ ! -f "$DBT_JOB_JSON_FILE_PATH" ]; then
    echo "ERROR: Compiled dbt job JSON file not found at '$DBT_JOB_JSON_FILE_PATH'. Check Step 7."
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
rm "$ZIP_FILE_PATH"

echo ""
echo "--- Full Deployment Script Completed Successfully ---"
echo "Resources Deployed/Configured in Resource Group: $RESOURCE_GROUP"
echo "  - Core Infra (ACR, Storage, VNet, KV, UAMI)"
echo "  - Permissions Manager image built and pushed to ACR."
echo "  - UC File Share prepared and config uploaded."
echo "  - Multi-container ACI Group: $UC_ACI_GROUP_NAME (FQDN: ${UC_ACI_FQDN:-N/A})"
echo "    - UC Server Container: ${UC_IMAGE_NAME}:${UC_IMAGE_TAG}"
echo "    - Permissions Manager Container: ${PERMISSIONS_MANAGER_IMAGE_NAME}:${PERMISSIONS_MANAGER_IMAGE_TAG}"
echo "    - Permissions Manager UI available at: ${PERMISSIONS_MANAGER_UI_URL:-N/A}"
echo "  - UC Admin Token stored in Key Vault secret: $TOKEN_SECRET_NAME (if retrieval succeeded)"
echo "  - Function App: $FUNCTION_APP_NAME"
echo "  - Function App Code Deployed"
echo ""
echo "Next Steps:"
echo " - Access the Permissions Manager UI: ${PERMISSIONS_MANAGER_UI_URL:-N/A}"
echo " - Ensure the dbt job uses the '$TOKEN_SECRET_NAME' Key Vault secret."
echo " - Check container group logs in Azure portal if issues arise."

exit 0