@description('Target scope for the deployment.')
targetScope = 'resourceGroup'

@description('Name of the resource group where resources exist/will be deployed.')
param resourceGroupName string = resourceGroup().name

@description('Azure region where resources exist/will be deployed.')
param location string = resourceGroup().location

@description('Name of the pre-existing Azure Storage Account.')
param storageAccountName string

@description('Name of the pre-existing Azure File Share for Unity Catalog persistence (e.g., "uc-etc-share"). Assumed to contain the necessary UC config structure or be empty for UC to initialize.')
param ucFileShareName string

@description('Name of the pre-existing Azure Key Vault.')
param keyVaultName string

@description('Name of the secret in Key Vault holding the manually obtained UC Admin Token.')
param ucAdminTokenSecretName string = 'uc-admin-token' // IMPORTANT: You must create/update this secret manually after UC starts

@description('Name of the secret in Key Vault holding the Azure Storage Account Key (needed to mount file share for UC).')
param storageAccountKeySecretName string // e.g., 'storage-account-key' - Ensure this secret exists in KV

@description('Name of the secret in Key Vault holding the Azure Client ID for ADLS SPN.')
param adlsClientIdSecretName string = 'adls-client-id'

@description('Name of the secret in Key Vault holding the Azure Client Secret for ADLS SPN.')
param adlsClientSecretSecretName string = 'adls-client-secret'

@description('Name of the secret in Key Vault holding the Azure Tenant ID for ADLS SPN.')
param adlsTenantIdSecretName string = 'adls-tenant-id'

@description('Name of the pre-existing Azure Container Registry.')
param acrName string

@description('Name (and tag) of the Unity Catalog container image in ACR (e.g., "my-uc-image:latest").')
param ucImageName string

@description('Name (and tag) of the DBT container image in ACR (e.g., "my-dbt-image:latest").')
param dbtImageName string

@description('Resource ID of the subnet where the Container Instances should be deployed.')
param subnetId string

@description('AWS Region string expected by the dbt-duckdb-uc plugin (as seen in profiles.yml).')
param awsRegionForPlugin string = 'us-east-2' // Default matches your profiles.yml, make adjustable if needed

@description('CPU cores allocated to the Unity Catalog container.')
param ucCpuCores int = 1

@description('Memory (in GB) allocated to the Unity Catalog container.')
param ucMemoryInGb real = 1.5

@description('CPU cores allocated to the DBT container.')
param dbtCpuCores int = 1 // Adjust based on dbt workload

@description('Memory (in GB) allocated to the DBT container.')
param dbtMemoryInGb real = 2 // Adjust based on dbt workload

@description('Optional command to run in the dbt container (e.g., ["sleep", "infinity"] or ["dbt", "run"]). Leave empty to use image default.')
param dbtCommand array = []

// --- Variables ---
var acrLoginServer = '${acrName}.azurecr.io'
var ucContainerGroupName = 'aci-unitycatalog-${uniqueString(resourceGroup().id)}'
var dbtContainerGroupName = 'aci-dbt-runner-${uniqueString(resourceGroup().id)}'
var ucContainerName = 'unitycatalog'
var dbtContainerName = 'dbt-runner'
// var kvSecretsVolumeName = 'kv-secrets-volume' // No longer mounting secrets volume for dbt
var ucEtcVolumeName = 'uc-etc-fileshare-volume' // Volume definition for UC file share mount

// --- Resources ---

// Retrieve Key Vault reference
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Unity Catalog Container Instance (Unchanged from previous version)
resource ucAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: ucContainerGroupName
  location: location
  properties: {
    containers: [
      {
        name: ucContainerName
        properties: {
          image: '${acrLoginServer}/${ucImageName}'
          ports: [
            {
              port: 8080
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: ucCpuCores
              memoryInGB: ucMemoryInGb
            }
          }
          volumeMounts: [
            {
              name: ucEtcVolumeName
              mountPath: '/app/unitycatalog/etc'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Private'
      ports: [
        {
          port: 8080
          protocol: 'TCP'
        }
      ]
    }
    volumes: [
      {
        name: ucEtcVolumeName
        azureFile: {
          shareName: ucFileShareName
          storageAccountName: storageAccountName
          storageAccountKey: keyVault.getSecret(storageAccountKeySecretName) // Or use Managed Identity + RBAC
        }
      }
    ]
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        // Add identity or username/password if needed for ACR pull
      }
    ]
    subnetIds: [
      {
        id: subnetId
      }
    ]
    // Optional Managed Identity for UC ACI (e.g., for keyless file share mount or ACR pull)
    // identity: {
    //   type: 'SystemAssigned'
    // }
  }
}

// DBT Runner Container Instance (Modified for direct env var secret injection)
resource dbtAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: dbtContainerGroupName
  location: location
  // Assign System Assigned Managed Identity - Required for secure env var injection from Key Vault
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    containers: [
      {
        name: dbtContainerName
        properties: {
          image: '${acrLoginServer}/${dbtImageName}'
          resources: {
            requests: {
              cpu: dbtCpuCores
              memoryInGB: dbtMemoryInGb
            }
          }
          // No volumeMounts needed for Key Vault secrets anymore

          // Pass necessary info directly as environment variables
          // Secure values are injected from Key Vault using Managed Identity
          environmentVariables: [
            {
              // UC Endpoint from the FQDN of the deployed UC ACI
              name: 'UC_ENDPOINT'
              value: 'http://${ucAci.properties.ipAddress.fqdn}:8080'
            }
            {
              // UC Admin Token injected directly from Key Vault
              name: 'UC_ADMIN_TOKEN'
              secureValue: keyVault.getSecret(ucAdminTokenSecretName) // Reference the secret directly
            }
            {
              // ADLS Client ID injected directly from Key Vault
              name: 'AZURE_CLIENT_ID'
              secureValue: keyVault.getSecret(adlsClientIdSecretName)
            }
            {
              // ADLS Client Secret injected directly from Key Vault
              name: 'AZURE_CLIENT_SECRET'
              secureValue: keyVault.getSecret(adlsClientSecretSecretName)
            }
            {
              // ADLS Tenant ID injected directly from Key Vault
              name: 'AZURE_TENANT_ID'
              secureValue: keyVault.getSecret(adlsTenantIdSecretName)
            }
            {
              // Storage Account Name (not secret)
              name: 'AZURE_STORAGE_ACCOUNT'
              value: storageAccountName
            }
            {
              // AWS Region needed by plugin (from profiles.yml)
              name: 'AWS_REGION' // Assuming the plugin reads this exact name
              value: awsRegionForPlugin
            }
            // Add other non-secret environment variables needed by your dbt image/project
            // {
            //   name: 'DBT_PROFILES_DIR'
            //   value: '/path/in/container'
            // }
          ]
          // Optionally override the container's default command
          command: (empty(dbtCommand) ? null : dbtCommand)
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Never' // Or 'OnFailure'. Keep 'Never' for truly on-demand execution.
    // No 'volumes' needed specifically for Key Vault secret mounting anymore

    imageRegistryCredentials: [
      {
        server: acrLoginServer
        // Add identity or username/password if needed for ACR pull
      }
    ]
    subnetIds: [
      {
        id: subnetId
      }
    ]
    // Consider setting 'startOnCreate: false' if the manual token step MUST happen before first start
    // startOnCreate: false
  }
  dependsOn: [
    ucAci // Ensure UC ACI resource definition is processed first
  ]
}

// --- Outputs ---

@description('The private IP Address assigned to the Unity Catalog ACI.')
output ucAciPrivateIpAddress string = ucAci.properties.ipAddress.ip

@description('The fully qualified domain name (FQDN) for the Unity Catalog ACI. Use this as the UC_ENDPOINT.')
output ucAciFqdn string = ucAci.properties.ipAddress.fqdn

@description('The principal ID of the DBT ACI\'s Managed Identity. Grant this ID "Key Vault Secrets User" role (or specific GET permissions) on the Key Vault.')
output dbtAciManagedIdentityPrincipalId string = dbtAci.identity.principalId

@description('Reminder about the manual step required after deployment.')
output manualActionRequired string = 'MANUAL STEP: After deployment, retrieve the admin token from the UC container (${ucContainerGroupName}) and store it in Key Vault secret "${ucAdminTokenSecretName}" in vault "${keyVaultName}". Then ensure the DBT ACI Managed Identity (${dbtAci.identity.principalId}) has GET permissions on all required secrets in Key Vault.'