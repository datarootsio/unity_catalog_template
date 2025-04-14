export LOCATION="westeurope"
export CONTAINER_GROUP_NAME="ucDbtGroup"
export ACI_NAME="unity-catalogz"     # Name of the container you will create
export RG="internship-2025"
export ACR_REGISTRY_NAME="unitycatalogdbt"
export STORAGE_ACCT_NAME="unitycataloginternship"
export UC_CONFIG_SHARE="uc-config-share"
export UC_DATA_SHARE="uc-data-share"
export UC_DB_SHARE="uc-db-share"
export ACR_LOGIN_SERVER="unitycatalogdbt.azurecr.io"
export ACR_USERNAME="unitycatalogdbt"
export UC_IMAGE_NAME="unitycatalogdbt.azurecr.io/uc-server:latest"
export ACR_PASSWORD="$(az acr credential show -n $ACR_REGISTRY_NAME --query 'passwords[0].value' -o tsv)"
export STORAGE_KEY="$(az storage account keys list -g $RG -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)"


az container create --resource-group $RG \
--name $ACI_NAME \
--image $UC_IMAGE_NAME \
--registry-login-server $ACR_LOGIN_SERVER \
--registry-username $ACR_USERNAME \
--registry-password $ACR_PASSWORD \
--ip-address Public \
--ports 8080 \
--protocol TCP \
--os-type  Linux \
--cpu 1 --memory 1 \
--azure-file-volume-account-name $STORAGE_ACCT_NAME \
--azure-file-volume-account-key $STORAGE_KEY \
--azure-file-volume-share-name $UC_CONFIG_SHARE \
--azure-file-volume-mount-path "/app/unitycatalog/etc/conf" \
--azure-file-volume-share-name $UC_DATA_SHARE \
--azure-file-volume-mount-path "/uc-internal-data" \
--azure-file-volume-share-name "$UC_DB_SHARE" \
--azure-file-volume-mount-path "/app/unitycatalog/etc/db" \
--command-line "bin/start-uc-server"