export LOCATION="westeurope"
export ACI_NAME="dbt-runner"     # Name of the container you will create
export RG="internship-2025"
export ACR_REGISTRY_NAME="unitycatalogdbt"
export STORAGE_ACCT_NAME="unitycataloginternship"
export UC_CONFIG_SHARE="uc-config-share"
export UC_DATA_SHARE="uc-data-share"
export ACR_LOGIN_SERVER="unitycatalogdbt.azurecr.io"
export ACR_USERNAME="unitycatalogdbt"
export IMAGE_NAME="unitycatalogdbt.azurecr.io/dbt:latest"
export ACR_PASSWORD="$(az acr credential show -n $ACR_REGISTRY_NAME --query 'passwords[0].value' -o tsv)"
export STORAGE_KEY="$(az storage account keys list -g $RG -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)"
export KEY_VAULT_NAME="azureunitycatalogsecrets"
export AZ_CLIENT_ID="$(az keyvault secret show --name azclient --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export AZ_CLIENT_SECRET="$(az keyvault secret show --name azclientsecret --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export AZ_STORAGE_ACCOUNT="$(az keyvault secret show --name azstorageaccount --vault-name $KEY_VAULT_NAME --query value  -o tsv)"
export AZ_TENANT_ID="$(az keyvault secret show --name aztenantid --vault-name $KEY_VAULT_NAME --query value  -o tsv)"



export UC_ADMIN_TOKEN="eyJraWQiOiI1OGI5OTIzNGM2ZjIxYWI5Y2UzZjAyNmEwOTEzOWE1N2U3Yjg2NDc2YWQ2NjEyMzQ0NTVmNTE5ZWMzYmI2MmRjIiwiYWxnIjoiUlM1MTIiLCJ0eXAiOiJKV1QifQ.eyJzdWIiOiJhZG1pbiIsImlzcyI6ImludGVybmFsIiwiaWF0IjoxNzQ0MzgyMzkzLCJqdGkiOiJjZDlkZWJhNC1lOGM2LTQ3ZDctODEzNS05MjIyY2QyODg4ZWMiLCJ0eXBlIjoiU0VSVklDRSJ9.W9WzCArthpjFVxsmrPTMO_6EZdN2eHxLY4aFFhauo1_iRwCvfklmUPh4nLzsY85WVl6uhCY6RqdIUkvG5kAFtA-M2lcqf4ocRv_GtjCIWmw3NaqctMFzzIydF6GBFC-EQsSXJs7vD_XhZzFWZEUyaZ3VKwhAN3_SdaMPtq0LDU_vHz2ZHrra_FZIb0MqLS2j_BL2lVDQR91BuPJhDvXOKF00Q7Czl8SyNFhC6ibes9eo05vgMnLwQ9r1Fb-3a1n260Rp1GPmgChjcRvm7asuxWU3Wq0MSk-P8opEg9e80H3oPrqaibyuMp6Si9CubNM_f-xrzsT1S9JWfqXb8u7lxQ"
export UC_ENDPOINT="http://20.8.48.234:8080/"


echo "Creating container..."
az container create --resource-group $RG \
--name $ACI_NAME \
--image $IMAGE_NAME \
--registry-login-server $ACR_LOGIN_SERVER  \
--registry-username $ACR_USERNAME \
--registry-password $ACR_PASSWORD \
--protocol TCP \
--os-type  Linux \
--cpu 1 --memory 1 \
--environment-variables \
    STORAGE_PATH="$STORAGE_PATH_VALUE" \
    UC_ENDPOINT="" \
    AZURE_CLIENT_ID=$AZ_CLIENT_ID \
    AZURE_CLIENT_SECRET=$AZ_CLIENT_SECRET \
    AZURE_STORAGE_ACCOUNT=$AZ_STORAGE_ACCOUNT \
    AZURE_TENANT_ID=$AZ_TENANT_ID \
    UC_ADMIN_TOKEN=$UC_ADMIN_TOKEN \
--command-line "sleep infinity"