export LOCATION="westeurope"
export ACI="dbtaci"
export RG="DC-internship-2025"
export ACR_REGISTRY_NAME="unitycatalogprojectacr"
export STORAGE_ACCT_NAME="unitycatalogprojectsa"
export ACR_LOGIN_SERVER="$(az acr show --name $ACR --query loginServer --output tsv)"
export ACR_USERNAME="$(az acr credential show --name $ACR --query username --output tsv)"
export IMAGE_NAME="$ACR_REGISTRY_NAME.azurecr.io/dbt-server:latest"
export ACR_PASSWORD="$(az acr credential show -n $ACR_REGISTRY_NAME --query 'passwords[0].value' -o tsv)"
export STORAGE_KEY="$(az storage account keys list -g $RG -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)"
export VNET_NAME="unitycatalogprojectvnet"
export SUBNET_NAME="unitycatalogprojectsnet"
export KEY_VAULT_NAME="unitycatalogprojectkv"
export AZ_CLIENT_ID="$(az keyvault secret show --name azclient --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export AZ_CLIENT_SECRET="$(az keyvault secret show --name azclientsecret --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export AZ_TENANT_ID="$(az keyvault secret show --name aztenant --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export UC_ADMIN_TOKEN=$(az container exec --resource-group $RG --name "unitycatalogaci" --exec-command "cat /app/unitycatalog/etc/conf/token.txt")
export UC_ENDPOINT="http://10.0.0.4:8080/"


"abfss://deltatables@unitycatalogprojectsa.dfs.core.windows.net/uc-data"

echo "Creating container..."
az container create \
--resource-group $RG \
--name $ACI \
--image $IMAGE_NAME \
--registry-login-server $ACR_LOGIN_SERVER  \
--registry-username $ACR_USERNAME \
--registry-password $ACR_PASSWORD \
--ip-address Private \
--vnet $VNET_NAME \
--vnet-address-prefix 10.0.0.0/16 \
--subnet $SUBNET_NAME \
--subnet-address-prefix 10.0.0.0/24 \
--protocol TCP \
--os-type  Linux \
--cpu 1 --memory 1 \
--environment-variables \
    STORAGE_PATH="$STORAGE_PATH_VALUE" \
    UC_ENDPOINT="" \
    AZURE_CLIENT_ID=$AZ_CLIENT_ID \
    AZURE_CLIENT_SECRET=$AZ_CLIENT_SECRET \
    AZURE_STORAGE_ACCOUNT=$STORAGE_ACCT_NAME \
    AZURE_TENANT_ID=$AZ_TENANT_ID \
    UC_ADMIN_TOKEN=$UC_ADMIN_TOKEN \
--command-line "sleep infinity"