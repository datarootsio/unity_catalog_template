export LOCATION="westeurope"
export ACI="unitycatalogaci"  
export RG="DC-internship-2025"
export ACR_REGISTRY_NAME="unitycatalogprojectacr"
export STORAGE_ACCT_NAME="unitycatalogprojectsa"
export UC_ETC_SHARE="uc-etc-share"
export ACR_LOGIN_SERVER="$(az acr show --name $ACR --query loginServer --output tsv)"
export ACR_USERNAME="$(az acr credential show --name $ACR --query username --output tsv)"
export UC_IMAGE_NAME="$ACR_REGISTRY_NAME.azurecr.io/uc-server:latest"
export ACR_PASSWORD="$(az acr credential show -n $ACR_REGISTRY_NAME --query 'passwords[0].value' -o tsv)"
export STORAGE_KEY="$(az storage account keys list -g $RG -n $STORAGE_ACCT_NAME --query '[0].value' -o tsv)"
export VNET_NAME="unitycatalogprojectvnet" 
export SUBNET_NAME="unitycatalogprojectsnet"


az container create \
  --resource-group $RG \
  --name $ACI \
  --image $UC_IMAGE_NAME \
  --registry-login-server $ACR_LOGIN_SERVER \
  --registry-username $ACR_REGISTRY_NAME \
  --registry-password $ACR_PASSWORD \
  --ip-address Private \
  --vnet $VNET_NAME \
  --vnet-address-prefix 10.0.0.0/16 \
  --subnet $SUBNET_NAME \
  --subnet-address-prefix 10.0.0.0/24 \
  --ports 8080 \
  --protocol TCP \
  --os-type Linux \
  --cpu 1 --memory 1.5 \
  --azure-file-volume-account-name $STORAGE_ACCT_NAME \
  --azure-file-volume-account-key $STORAGE_KEY \
  --azure-file-volume-share-name "uc-etc-share" \
  --azure-file-volume-mount-path "/app/unitycatalog/etc" \
  --command-line "bin/start-uc-server"