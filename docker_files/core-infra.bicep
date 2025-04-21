// === core-infra.bicep ===
// Deploys ACR, Storage Account (ADLS Gen2 + Files), VNet, Subnet (ACI delegated), Private DNS Zone
targetScope = 'resourceGroup'

// === Parameters ===
@description('Specifies the base name for resources. Used to generate resource names.')
param projectName string

@description('Specifies the location for the resources. Defaults to the resource group location.')
param location string = resourceGroup().location

// --- ACR Parameters ---
@description('Specifies the SKU for the Azure Container Registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Basic'

@description('Specifies whether the admin user is enabled for the ACR. Recommended to be false for production.')
param adminUserEnabled bool = true

// --- Storage Parameters ---
@description('Specifies the SKU for the Storage Account.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageSku string = 'Standard_LRS'

// --- Networking Parameters ---
@description('Specifies the address space for the Virtual Network.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Specifies the address space for the Subnet where ACIs will be deployed.')
param aciSubnetAddressPrefix string = '10.50.1.0/24' // Renamed slightly for clarity

@description('Specifies the name for the Azure Private DNS Zone.')
param privateDnsZoneName string = '${toLower(projectName)}.internal'

// === Variables ===

// --- ACR Variables ---
@description('Generates the Azure Container Registry name based on the project name.')
// WARNING: This name MUST be globally unique across Azure. Deployment may fail if the name is taken.
var acrName = toLower('${take(projectName, 47)}acr')

// --- Storage Variables ---
// WARNING: This name MUST be globally unique across Azure, 3-24 chars, lowercase alphanumeric. Deployment may fail if the name is taken.
var storageAccountName = toLower('${take(projectName, 22)}sa')
var storageBlobContainerName = 'unitycatalog-data'
var storageFileShareName = 'uc-etc-share'

// --- Networking Variables ---
var vnetName = '${projectName}-vnet'
var aciSubnetName = '${projectName}-aci-snet' // Renamed slightly for clarity
var vnetLinkName = '${projectName}-vnetlink'

// === Resources ===

// --- Azure Container Registry ---
@description('Deploys the Azure Container Registry.')
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'Container Registry'
  }
}

// --- Azure Storage Account (ADLS Gen2 Enabled) ---
@description('Deploys the Azure Storage Account with ADLS Gen2 enabled.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: true // ADLS Gen2
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'ADLS Gen2 and File Share'
  }

  // Nested Blob Service and Container
  resource blobService 'blobServices' = {
    name: 'default'
    resource container 'containers' = {
      name: storageBlobContainerName
      properties: {
        publicAccess: 'None'
      }
    }
  }

  // Nested File Service and Share
  resource fileService 'fileServices' = {
    name: 'default'
    resource share 'shares' = {
      name: storageFileShareName
      properties: {
        shareQuota: 5120
        enabledProtocols: 'SMB'
      }
    }
  }
}

// --- Virtual Network and Subnet ---
@description('Deploys the Virtual Network.')
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: aciSubnetName // Use the specific subnet name variable
        properties: {
          addressPrefix: aciSubnetAddressPrefix
          // Crucial: Delegate the subnet to Azure Container Instances
          delegations: [
            {
              name: 'aciDelegation'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
        }
      }
      // Add other subnets here if needed
    ]
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
  }
}

// --- Private DNS Zone ---
@description('Deploys the Azure Private DNS Zone.')
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global' // Private DNS zones are global resources
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
  }
}

// --- Private DNS Zone VNet Link ---
@description('Links the Private DNS Zone to the Virtual Network.')
resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone // Link is a child resource of the DNS Zone
  name: vnetLinkName
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id // Reference the ID of the VNet created above
    }
    // Set registrationEnabled to false as ACI doesn't automatically register
    registrationEnabled: false
  }
  // Explicit dependency to ensure VNet exists before linking
  dependsOn: [
    vnet
  ]
}


// === Outputs ===

// --- ACR Outputs ---
@description('The name of the created Azure Container Registry.')
output acrName string = acr.name

@description('The login server endpoint of the created Azure Container Registry.')
output acrLoginServer string = acr.properties.loginServer

@description('The resource ID of the created Azure Container Registry.')
output acrId string = acr.id

// --- Storage Outputs ---
@description('The name of the created Storage Account.')
output storageAccountName string = storageAccount.name

@description('The primary endpoint for the Blob service.')
output storageBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The primary endpoint for the Data Lake Storage (DFS) service.')
output storageDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('The primary endpoint for the File service.')
output storageFileEndpoint string = storageAccount.properties.primaryEndpoints.file

@description('The name of the Blob container created for delta tables.')
output storageBlobContainerName string = storageBlobContainerName

@description('The name of the File Share created for UC config.')
output storageFileShareName string = storageFileShareName

// --- Networking Outputs ---
@description('The name of the created Virtual Network.')
output vnetName string = vnet.name

@description('The resource ID of the created Virtual Network.')
output vnetId string = vnet.id

@description('The name of the created Subnet for ACI.')
output aciSubnetName string = aciSubnetName // Output the variable used

@description('The resource ID of the created Subnet for ACI. This is needed for ACI deployment.')
// Ensure we reference the correct subnet if more are added later
output aciSubnetId string = vnet.properties.subnets[0].id

@description('The name of the created Azure Private DNS Zone.')
output privateDnsZoneName string = privateDnsZone.name

@description('The resource ID of the created Azure Private DNS Zone.')
output privateDnsZoneId string = privateDnsZone.id