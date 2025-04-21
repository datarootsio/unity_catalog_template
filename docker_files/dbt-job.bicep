@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Unique name for the dbt ACI job instance')
param dbtJobInstanceName string = 'dbt-job-${uniqueString(resourceGroup().id, utcNow())}'

@description('ACR login server')
param acrLoginServer string

// Keep explicit ACR creds for image pull for now
@secure()
@description('ACR Admin Username for image pull')
param acrUsername string
@secure()
@description('ACR Admin Password for image pull')
param acrPassword string

// *** NEW Parameter for UAMI ***
@description('Resource ID of the pre-created User-Assigned Managed Identity')
param uamiResourceId string
// ***************************

@description('ID of the Subnet to deploy the ACI into')
param subnetId string

@description('Private DNS Zone name')
param privateDnsZoneName string

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

@description('The ABFSS path for the Delta storage location')
param storagePath string

@description('The dbt command to execute')
param dbtCommandToRun string = 'build'

// === Variables ===
var imageName = '${acrLoginServer}/dbt-server:latest'
var containerName = 'dbt-runner'
var dbtProjectVolumeName = 'dbt-project-volume'
var dbtProjectMountPath = '/dbt_project'
var dbtProjectDir = dbtProjectMountPath
var dbtProfilesDir = '/root/.dbt' // Or wherever profiles.yml expects it

// === Resources ===

resource dbtContainerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: dbtJobInstanceName
  location: location
  // *** Use User Assigned Managed Identity ***
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      // Key is the UAMI Resource ID, value is empty object
      '${uamiResourceId}': {}
    }
  }
  // ***************************************
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: imageName
          resources: { requests: { cpu: 1, memoryInGB: 2 } }
          volumeMounts: [ { name: dbtProjectVolumeName, mountPath: dbtProjectMountPath, readOnly: false } ]
          environmentVariables: [
             { name: 'UC_ADMIN_TOKEN', secureValue: ucAdminTokenValue }
             { name: 'UC_ENDPOINT', value: ucServerUrl }
             { name: 'STORAGE_PATH', value: storagePath }
             // We will rely on dbt finding profiles.yml in the project dir by default
             // { name: 'DBT_PROFILES_DIR', value: dbtProfilesDir }
             { name: 'DBT_PROJECT_DIR', value: dbtProjectDir }
             // REMOVED AZURE_STORAGE_KEY/ACCOUNT env vars to force MI usage
          ]
          // *** Command to run dbt ***
          // Ensure your image has az cli if keeping the login attempt
          command: ['dbt', 'build']
          // **************************
        }
      }
    ]
    // Keep explicit creds for pull for now
    imageRegistryCredentials: [ { server: acrLoginServer, username: acrUsername, password: acrPassword } ]
    // Keep storage key for mount for now
    volumes: [ { name: dbtProjectVolumeName, azureFile: { shareName: dbtProjectFileShareName, storageAccountName: dbtProjectStorageAccountName, storageAccountKey: storageAccountKey } } ]
    osType: 'Linux'
    restartPolicy: 'Never'
    subnetIds: [ { id: subnetId } ]
    // Removed ipAddress block
    dnsConfig: { nameServers: [ '168.63.129.16' ], searchDomains: privateDnsZoneName }
    sku: 'Standard'
  }
}

// === Outputs ===
// REMOVED aciPrincipalId output
output dbtJobAciName string = dbtContainerGroup.name
output dbtJobAciId string = dbtContainerGroup.id