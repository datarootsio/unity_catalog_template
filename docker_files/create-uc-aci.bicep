// targetScope MUST be the very first line
targetScope = 'resourceGroup'

@description('Required. Azure region where the ACI will be deployed. Should match the VNet region.')
param location string = resourceGroup().location

@description('Required. Name for the Azure Container Instance group.')
param aciName string = 'unity-catalogz-${uniqueString(resourceGroup().id)}' // Default includes uniqueness

@description('Required. Name of the existing Azure Container Registry.')
param acrName string

@description('Required. Username for Azure Container Registry authentication (usually the ACR name).')
param acrUsername string // Typically same as acrName

@description('Required. Password for Azure Container Registry authentication.')
@secure() // Mark as secure, value provided at deployment time
param acrPassword string

@description('Required. Full image name (including tag) for the Unity Catalog server in ACR.')
param ucImageName string // e.g., 'myacr.azurecr.io/uc-server:latest'

@description('Required. Name of the existing Azure Storage Account containing the file shares.')
param storageAccountName string

@description('Required. Access key for the Azure Storage Account.')
@secure() // Mark as secure, value provided at deployment time
param storageAccountKeyValue string

@description('Required. Name of the Azure File Share to mount for UC configuration and data.')
param ucEtcShareName string // e.g., 'uc-etc-share'

@description('Required. Resource ID of the existing VNet subnet where the ACI should be deployed. Subnet must be delegated to Microsoft.ContainerInstance/containerGroups.')
param subnetId string

@description('Optional. CPU cores allocated to the container.')
param cpuCores int = 1

@description('Optional. Memory (in GB) allocated to the container. Provide as string, e.g., "1.5".')
param memoryInGb string = '1.5'

@description('Optional. Port to expose on the container.')
param containerPort int = 8080

@description('Optional. Command line arguments to execute when the container starts.')
param commandLine array = [
  'bin/start-uc-server' // Default command
]

// --- Variables ---
var acrLoginServer = '${acrName}.azurecr.io' // Construct login server from acrName
var ucEtcVolumeName = 'uc-etc-fileshare-volume' // Define a name for the volume resource

// --- Resources ---

resource unityCatalogAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: aciName // Name of the Container Group
  location: location
  properties: {
    containers: [
      {
        // Define the primary container within the group
        name: 'unitycatalog-container' // Internal name for the container
        properties: {
          image: ucImageName
          ports: [
            {
              port: containerPort
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: json(memoryInGb) // Convert string memory value to number for API
            }
          }
          // Mount the defined volume
          volumeMounts: [
            {
              name: ucEtcVolumeName // Reference the volume defined below
              mountPath: '/app/unitycatalog/etc' // Mount path inside the container
            }
          ]
          // Set the command line (must be an array)
          command: commandLine
        }
      }
    ]
    // Networking Configuration
    osType: 'Linux'
    restartPolicy: 'Always' // Typically want UC server to restart automatically
    ipAddress: {
      type: 'Private' // Deploy within the VNet
      ports: [
        {
          port: containerPort
          protocol: 'TCP'
        }
      ]
    }
    // Storage Volume Definition
    volumes: [
      {
        name: ucEtcVolumeName // Define the Azure File volume
        azureFile: {
          shareName: ucEtcShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccountKeyValue // Use the secure parameter
        }
      }
    ]
    // ACR Credentials
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        username: acrUsername
        password: acrPassword // Use the secure parameter
      }
    ]
    // Subnet Integration
    subnetIds: [
      {
        id: subnetId // Reference the subnet resource ID parameter
      }
    ]
  }
}

// --- Outputs ---

@description('The private IP Address assigned to the Unity Catalog ACI.')
output ucAciPrivateIpAddress string = unityCatalogAci.properties.ipAddress.ip

@description('The fully qualified domain name (FQDN) for the Unity Catalog ACI. Use this as the endpoint if Private DNS is configured.')
output ucAciFqdn string = unityCatalogAci.properties.ipAddress.fqdn