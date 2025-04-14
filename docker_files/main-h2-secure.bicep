//-------------------------------------------------------------------------------------
// Bicep template for deploying Open Source Unity Catalog (H2 on Azure Files)
// Uses EXISTING Storage Account & EXISTING Shares passed as parameters
// Version: 18 (Shortening Key Vault name generation)
//-------------------------------------------------------------------------------------

@description('The Azure region where the resources will be deployed (ACI, KV, VNet).')
param location string = resourceGroup().location

@description('Base name for NEW resources (KV, VNet, ACI Group, DNS Zone). MUST be relatively short to avoid naming conflicts.')
param baseName string

@description('Name for the container inside the ACI group.')
param containerName string = 'unity-catalog'

@description('The name of the Azure Container Registry.')
param acrRegistryName string

@description('The username for the ACR. Defaults to registry name.')
param acrUsername string = acrRegistryName

@secure()
@description('Password for the ACR. Managed Identity/Token recommended.')
param acrPassword string

@description('Full image name, including registry.')
param imageName string = '${acrRegistryName}.azurecr.io/uc-server:latest'

@description('CPU cores for the container.')
param cpuCores int = 1

@description('Memory in GB for the container.')
param memoryInGb int = 1

// --- Parameters for Existing Storage & Shares ---
@description('Name of the EXISTING Azure Storage Account.')
param existingStorageAccountName string = 'unitycataloginternship'

@description('Resource Group of the EXISTING Storage Account.')
param existingStorageAccountRgName string = 'internship-2025'

@description('Name of the EXISTING File Share for /conf.')
param existingConfigShareName string = 'uc-config-share'

@description('Name of the EXISTING File Share for /uc-internal-data.')
param existingDataShareName string = 'uc-data-share'

@description('Name of the EXISTING File Share for /db.')
param existingDbShareName string = 'uc-db-share'

// --- Variables for new resources ---
// MODIFIED Key Vault Name generation for shorter length
var keyVaultName = '${toLower(baseName)}kv${uniqueString(baseName, location)}' // Hash based on basename + location (shorter)
var vnetName = '${baseName}-vnet'
var subnetName = 'default'
var ucConfigMountPath = '/app/unitycatalog/etc/conf'
var ucDataMountPath = '/uc-internal-data'
var ucdbMountPath = '/app/unitycatalog/etc/db'
var ucContainerGroupName = '${baseName}-uc-aci'

// Define Key Vault Secret Names
var googleClientSecretKvName = 'googleClientSecret'
var ucServerAdlsClientSecretKvName = 'ucServerAdlsClientSecret'

// --- Existing Resource References ---
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrRegistryName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: existingStorageAccountName
  scope: resourceGroup(existingStorageAccountRgName)
}

// --- Networking ---
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [ '10.1.0.0/16' ] }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.1.1.0/24'
          delegations: [ { name: 'aciDelegation', properties: { serviceName: 'Microsoft.ContainerInstance/containerGroups' } } ]
          serviceEndpoints: [ { service: 'Microsoft.Storage' }, { service: 'Microsoft.KeyVault' } ]
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: vnet
  name: subnetName
}

// --- Key Vault ---
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  // Use the shortened name variable
  name: keyVaultName
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [ { id: subnet.id } ]
    }
  }
  dependsOn: [ subnet ]
}

// --- Private DNS Zone and Record ---
resource ucPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${toLower(baseName)}.uc.internal'
  location: 'global'
}

resource ucVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: ucPrivateDnsZone
  name: '${vnetName}-uc-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

// --- Main Resource Definition: ACI Group ---
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: ucContainerGroupName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    imageRegistryCredentials: [ { server: acr.properties.loginServer, username: acrUsername, password: acrPassword } ]
    ipAddress: { type: 'Private', ports: [ { protocol: 'TCP', port: 8080 } ] }
    volumes: [
      { name: 'configsharevol', azureFile: { shareName: existingConfigShareName, storageAccountName: storageAccount.name, storageAccountKey: storageAccount.listKeys().keys[0].value } }
      { name: 'datasharevol', azureFile: { shareName: existingDataShareName, storageAccountName: storageAccount.name, storageAccountKey: storageAccount.listKeys().keys[0].value } }
      { name: 'dbsharevol', azureFile: { shareName: existingDbShareName, storageAccountName: storageAccount.name, storageAccountKey: storageAccount.listKeys().keys[0].value } }
    ]
    containers: [
      {
        name: containerName
        properties: {
          image: imageName
          resources: { requests: { cpu: cpuCores, memoryInGB: memoryInGb } }
          ports: [ { protocol: 'TCP', port: 8080 } ]
          volumeMounts: [
            { name: 'configsharevol', mountPath: ucConfigMountPath, readOnly: false }
            { name: 'datasharevol', mountPath: ucDataMountPath, readOnly: false }
            { name: 'dbsharevol', mountPath: ucdbMountPath, readOnly: false }
          ]
          environmentVariables: [
            { name: 'KEY_VAULT_NAME', value: keyVault.name }
            { name: 'GOOGLE_CLIENT_SECRET_KV_NAME', value: googleClientSecretKvName }
            { name: 'UC_SERVER_ADLS_CLIENT_SECRET_KV_NAME', value: ucServerAdlsClientSecretKvName }
          ]
        }
      }
    ]
    subnetIds: [ { id: subnet.id } ]
    dnsConfig: { nameServers: [ '168.63.129.16' ] }
  }
  dependsOn: [ subnet, ucVnetLink, storageAccount ]
}

// --- Grant UC ACI Managed Identity access to Key Vault Secrets ---
resource ucAciKvSecretReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, containerGroup.id, 'KVSecretsUser')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: containerGroup.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [ containerGroup ] // Keep necessary dependency
}

// --- DNS Record ---
resource ucDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: ucPrivateDnsZone
  name: 'unitycatalog'
  properties: {
    ttl: 300
    aRecords: [ { ipv4Address: containerGroup.properties.ipAddress.ip } ]
  }
  dependsOn: [ containerGroup ] // Keep necessary dependency
}

// --- Outputs ---
output keyVaultName string = keyVault.name
output deployedContainerGroupName string = containerGroup.name
output ucInternalFqdn string = '${ucDnsRecord.name}.${ucPrivateDnsZone.name}'
output usedStorageAccountName string = storageAccount.name
output ucAciPrincipalId string = containerGroup.identity.principalId