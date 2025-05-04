@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Unique name for the dbt ACI job instance')
param dbtJobInstanceName string = 'dbt-job-${uniqueString(resourceGroup().id, utcNow())}'

param cpuCores int = 1
param memoryInGB int = 1

@description('ACR login server')
param acrLoginServer string // Example: myacr.azurecr.io

// NO acrUsername or acrPassword params needed

@description('Resource ID of the pre-created User-Assigned Managed Identity')
param uamiResourceId string // Example: /subscriptions/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/dbt-job-identity

@description('ID of the Subnet to deploy the ACI into')
param subnetId string

// dbt Project Share Params
@description('Name of the Storage Account containing the dbt project Azure File Share')
param dbtProjectStorageAccountName string
@secure()
@description('Storage Account Key for the dbt project Azure File Share mount')
param storageAccountKey string
@description('Name of the Azure File Share containing the dbt project')
param dbtProjectFileShareName string

@secure()
@description('The bearer token value retrieved from the UC container')
param ucAdminTokenValue string

@description('The fully qualified URL for the Unity Catalog server endpoint')
param ucServerUrl string

@description('The ABFSS path for the Delta storage location base')
param storagePath string

@description('The dbt command to execute')
param dbtCommandToRun string = 'build'

// === Variables ===
var imageName = '${acrLoginServer}/dbt-server:latest' // Ensure this matches your actual image
var containerName = 'dbt-runner'
var dbtProjectVolumeName = 'dbt-project-volume'
var dbtProjectMountPath = '/dbt_project'
var dbtProjectDir = dbtProjectMountPath

// === Resources ===
resource dbtContainerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = { // Use a recent API version
  name: dbtJobInstanceName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {} // Assign the UAMI to the ACI itself
    }
  }
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: imageName
          resources: { requests: { cpu: cpuCores, memoryInGB: memoryInGB} }
          volumeMounts: [ { name: dbtProjectVolumeName, mountPath: dbtProjectMountPath, readOnly: false } ]
          environmentVariables: [
             { name: 'UC_ADMIN_TOKEN', secureValue: ucAdminTokenValue }
             { name: 'UC_ENDPOINT', value: ucServerUrl }
             { name: 'STORAGE_PATH', value: storagePath }
             { name: 'DBT_PROJECT_DIR', value: dbtProjectDir }
          ]
          command: [ 'dbt', dbtCommandToRun ] // Use the parameter
        }
      }
    ]

    // *** CORRECTED ACR AUTH USING MANAGED IDENTITY ***
    imageRegistryCredentials: [
      {
        server: acrLoginServer // Your ACR's login server name
        identity: uamiResourceId // The Resource ID of the UAMI assigned above
      }
    ]
    // ************************************************

  volumes: [
    {
      name: dbtProjectVolumeName
      azureFile: {
        shareName: dbtProjectFileShareName
        storageAccountName: dbtProjectStorageAccountName
        storageAccountKey: storageAccountKey
      }
  }
  ]
    osType: 'Linux'
    restartPolicy: 'Never'
    subnetIds: [ { id: subnetId } ]
    dnsConfig: {
      nameServers: [ '168.63.129.16' ] // Azure DNS
    }
    sku: 'Standard'
  }
}

// === Outputs ===
output dbtJobAciName string = dbtContainerGroup.name
output dbtJobAciId string = dbtContainerGroup.id