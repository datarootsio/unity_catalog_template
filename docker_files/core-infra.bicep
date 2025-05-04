// === core-infra.bicep ===
// Deploys ACR, Storage Account (ADLS Gen2 + Files), VNet, Subnet (ACI delegated),
// Private DNS Zone, User Assigned Managed Identity, and Key Vault.
targetScope = 'resourceGroup'

// === Parameters ===
@description('Specifies the base name for resources. Used to generate resource names.')
param projectName string

@description('Specifies the location for the resources. Defaults to the resource group location.')
param location string = resourceGroup().location

// --- ACR Parameters ---
@description('Specifies the SKU for the Azure Container Registry.')
@allowed([ 'Basic', 'Standard', 'Premium' ])
param acrSku string = 'Standard' // Defaulting to Standard for potential networking features later

@description('Specifies whether the admin user is enabled for the ACR. Recommended to be false.')
param adminUserEnabled bool = true // Default to false for better security

// --- Storage Parameters ---
@description('Specifies the SKU for the Storage Account.')
@allowed([ 'Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS', 'Premium_ZRS' ])
param storageSku string = 'Standard_LRS'

// --- Networking Parameters ---
@description('Specifies the address space for the Virtual Network.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Specifies the address space for the Subnet where ACIs will be deployed.')
param aciSubnetAddressPrefix string = '10.50.1.0/24'

@description('Specifies the name for the Azure Private DNS Zone.')
param privateDnsZoneName string = '${toLower(projectName)}.internal'

// --- Identity Parameters ---
@description('Specifies the name for the User-Assigned Managed Identity.')
param uamiName string = 'dbt-job-identity' // Use the name consistently

// --- Key Vault Parameters ---
@description('Specifies the SKU for the Key Vault.')
@allowed([ 'standard', 'premium' ])
param keyVaultSkuName string = 'standard'

@description('Enable RBAC authorization for Key Vault data plane operations. Recommended.')
param enableVaultRbacAuthorization bool = true





// === Variables ===
var tenantId = subscription().tenantId // Get the tenant ID for the current subscription

// --- ACR Variables ---
var acrName = toLower('${take(projectName, 47)}acr')

// --- Storage Variables ---
var storageAccountName = toLower('${take(projectName, 22)}sa')
var storageBlobContainerName = 'unitycatalog-data' // For ADLS
var storageUcFileShareName = 'uc-etc-share' // For UC config? From original template
var storageDbtFileShareName = 'dbt-project-share' // For dbt project files

// --- Networking Variables ---
var vnetName = '${projectName}-vnet'
var aciSubnetName = '${projectName}-aci-snet'
var vnetLinkName = '${projectName}-vnetlink'

// --- Key Vault Variables ---
var keyVaultName = toLower('${take(projectName, 22)}key')





// === Resources ===

// --- User-Assigned Managed Identity ---
@description('Deploys the User-Assigned Managed Identity used by Function App and ACIs.')
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'Identity for dbt orchestration'
  }
}

// --- Azure Key Vault ---
@description('Deploys the Azure Key Vault for storing secrets.')
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: { family: 'A', name: keyVaultSkuName }
    tenantId: tenantId // Associate KV with the correct Azure AD tenant
    enableRbacAuthorization: enableVaultRbacAuthorization // Use RBAC for permissions is recommended
    // networkAcls: { // Consider adding network restrictions for production
    //   bypass: 'AzureServices'
    //   defaultAction: 'Deny'
    //   ipRules: []
    //   virtualNetworkRules: [] // You might add the ACI subnet here if Function needs direct SDK access
    // }
    enabledForDeployment: false // Typically false unless using ARM template deployment secrets
    enabledForDiskEncryption: false // Typically false unless using for VM disk encryption
    enabledForTemplateDeployment: false // Typically false unless using ARM template deployment secrets
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'Secret Management'
  }
}


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
    // publicNetworkAccess: 'Enabled' // Or 'Disabled' if using private endpoints
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
    // networkAcls: { // Consider network restrictions for production
    //   bypass: 'AzureServices'
    //   defaultAction: 'Deny' // Start with Deny for production
    //   ipRules: []
    //   virtualNetworkRules: [] // Add specific subnet IDs (like aciSubnet.id) if needed
    // }
    allowSharedKeyAccess: true // Required if using storageAccountKey for file share mount in ACI
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'ADLS Gen2 and File Shares'
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

  // Nested File Service and Shares
  resource fileService 'fileServices' = {
    name: 'default'
    // Share for UC config (from original template)
    resource ucShare 'shares' = {
      name: storageUcFileShareName
      properties: {
        shareQuota: 1024 // Example: 1 GiB
        enabledProtocols: 'SMB'
      }
    }
    // Share for dbt project
    resource dbtShare 'shares' = {
      name: storageDbtFileShareName // Use the dedicated variable
      properties: {
        shareQuota: 5120 // Example: 5 GiB
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
        name: aciSubnetName
        properties: {
          addressPrefix: aciSubnetAddressPrefix
          delegations: [
            {
              name: 'aciDelegation'
              properties: {
                serviceName: 'Microsoft.ContainerInstance/containerGroups'
              }
            }
          ]
          // Add service endpoints if needed for storage/acr/keyvault access from ACI
          // serviceEndpoints: [
          //   { service: 'Microsoft.Storage' }
          //   { service: 'Microsoft.ContainerRegistry' }
          //   { service: 'Microsoft.KeyVault' }
          // ]
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
  location: 'global'
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
  }
}

// --- Private DNS Zone VNet Link ---
@description('Links the Private DNS Zone to the Virtual Network.')
resource dnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: vnetLinkName
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
  dependsOn: [
    vnet
  ]
}


// === Outputs ===

// --- Identity Outputs ---
@description('The resource ID of the created User-Assigned Managed Identity.')
output uamiResourceId string = uami.id

@description('The principal ID (Object ID) of the created User-Assigned Managed Identity. Used for RBAC assignments.')
output uamiPrincipalId string = uami.properties.principalId

@description('The client ID of the created User-Assigned Managed Identity. Used by applications authenticating as the identity.')
output uamiClientId string = uami.properties.clientId

// --- Key Vault Outputs ---
@description('The name of the created Key Vault.')
output keyVaultName string = keyVault.name

@description('The URI of the created Key Vault. Used for accessing secrets.')
output keyVaultUri string = keyVault.properties.vaultUri

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

@description('The resource ID of the created Storage Account.')
output storageAccountId string = storageAccount.id // Useful for RBAC scope

@description('The primary endpoint for the Blob service.')
output storageBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The primary endpoint for the Data Lake Storage (DFS) service.')
output storageDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('The primary endpoint for the File service.')
output storageFileEndpoint string = storageAccount.properties.primaryEndpoints.file

@description('The name of the Blob container created for delta tables.')
output storageBlobContainerName string = storageBlobContainerName // Output the variable used

@description('The name of the File Share created for UC config.')
output storageUcFileShareName string = storageUcFileShareName // Output the variable used

@description('The name of the File Share created for the dbt project.')
output storageDbtFileShareName string = storageDbtFileShareName // Output the variable used

// --- Networking Outputs ---
@description('The name of the created Virtual Network.')
output vnetName string = vnet.name

@description('The resource ID of the created Virtual Network.')
output vnetId string = vnet.id

@description('The name of the created Subnet for ACI.')
output aciSubnetName string = aciSubnetName // Output the variable used

@description('The resource ID of the created Subnet for ACI. This is needed for ACI deployment.')
// Reference the subnet resource explicitly for clarity and robustness
output aciSubnetId string = vnet.properties.subnets[0].id // Assuming it's always the first subnet

@description('The name of the created Azure Private DNS Zone.')
output privateDnsZoneName string = privateDnsZone.name

@description('The resource ID of the created Azure Private DNS Zone.')
output privateDnsZoneId string = privateDnsZone.id