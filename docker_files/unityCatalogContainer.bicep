@description('The Azure region where the resources will be deployed.')
param location string = 'westeurope'

@description('The name of the Azure Container Instances group to create.')
param containerGroupName string = 'unity-catalogz' // Corresponds to ACI_NAME in script

@description('The name of the Azure Container Registry.')
param acrRegistryName string = 'unitycatalogdbt'

@description('The username for the Azure Container Registry. Defaults to the registry name.')
param acrUsername string = acrRegistryName

@secure()
@description('The password for the Azure Container Registry. NOTE: Using Managed Identity is strongly recommended instead.')
param acrPassword string

@description('The full image name, including the registry.')
param imageName string = '${acrRegistryName}.azurecr.io/uc-server:latest' // Corresponds to UC_IMAGE_NAME

@description('The name of the Azure Storage Account containing the file shares.')
param storageAccountName string = 'unitycataloginternship'

@description('The name of the Azure File Share for configuration.')
param ucConfigShareName string = 'uc-config-share'

@description('The name of the Azure File Share for data.')
param ucDataShareName string = 'uc-data-share'

@description('The name of the Azure File Share for data.')
param ucDbShareName string = 'uc-db-share'

@description('The mount path inside the container for the config share.')
param ucConfigMountPath string = '/app/unitycatalog/etc/conf'

@description('The mount path inside the container for the data share.')
param ucDataMountPath string = '/uc-internal-data'

@description('The mount path inside the container for the config share.')
param ucdbMountPath string = '/app/unitycatalog/etc/db'

@description('CPU cores allocated to the container.')
param cpuCores int = 1

@description('Memory in GB allocated to the container.')
param memoryInGb int = 1

// --- Existing Resource References ---
// Reference the existing Storage Account to get its keys securely at deployment time
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Reference the existing ACR to get its login server dynamically
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrRegistryName
}

// --- Main Resource Definition ---
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always' // Default, but explicit
    // --- Registry Credentials ---
    // Uses parameters including the secure password passed during deployment
    imageRegistryCredentials: [
      {
        server: acr.properties.loginServer // Dynamically get login server from existing ACR
        username: acrUsername
        password: acrPassword // Uses the @secure parameter
      }
    ]
    // --- IP Address Configuration ---
    ipAddress: {
      type: 'Public'
      ports: [
        {
          protocol: 'TCP'
          port: 8080
        }
      ]
    }
    // --- Volumes ---
    // Defines the Azure File volumes available to the group
    volumes: [
      {
        name: 'configshare' // Internal name for the volume mount reference
        azureFile: {
          shareName: ucConfigShareName
          storageAccountName: storageAccountName
          // Securely fetches the storage account key at deployment time
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
      {
        name: 'datashare' // Internal name for the volume mount reference
        azureFile: {
          shareName: ucDataShareName
          storageAccountName: storageAccountName
          // Securely fetches the storage account key at deployment time
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
      {
        name: 'dbshare' // Internal name for the volume mount reference
        azureFile: {
          shareName: ucDbShareName
          storageAccountName: storageAccountName
          // Securely fetches the storage account key at deployment time
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      } 
    ]
    // --- Container Definition ---
    containers: [
      {
        name: containerGroupName // Using the group name for the single container name
        properties: {
          image: imageName
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
          ports: [
            {
              protocol: 'TCP'
              port: 8080 // Container internal port
            }
          ]
          // --- Volume Mounts ---
          // Mounts the volumes defined at the group level into the container
          volumeMounts: [
            {
              name: 'configshare' // References volume defined above
              mountPath: ucConfigMountPath
              readOnly: false // Default
            }
            {
              name: 'datashare' // References volume defined above
              mountPath: ucDataMountPath
              readOnly: false // Default
            }
            {
              name: 'dbshare' // References volume defined above
              mountPath: ucdbMountPath
              readOnly: false // Default
            }
          ]
          // --- Command ---
          command: [
            'bin/start-uc-server'
          ]
        }
      }
    ]
  }
}

// Optional: Output the public IP address after deployment
output containerIPv4Address string = containerGroup.properties.ipAddress.ip