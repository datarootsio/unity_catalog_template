@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Unique name for the dbt ACI job instance')
param dbtJobInstanceName string = 'dbt-job-${uniqueString(resourceGroup().id, utcNow())}'

param cpuCores int = 1
param memoryInGB int = 1

@description('ACR login server')
param acrLoginServer string

// Keep explicit ACR creds for image pull for now (MI pull recommended later)
@secure()
@description('ACR Admin Username for image pull')
param acrUsername string
@secure()
@description('ACR Admin Password for image pull')
param acrPassword string

@description('Resource ID of the pre-created User-Assigned Managed Identity')
param uamiResourceId string // Used for ACI identity + data access

@description('ID of the Subnet to deploy the ACI into')
param subnetId string

//@description('Private DNS Zone name (needed for dnsConfig searchDomains)')
//param privateDnsZoneName string

// dbt Project Share Params
@description('Name of the Storage Account containing the dbt project Azure File Share')
param dbtProjectStorageAccountName string
@secure()
@description('Storage Account Key for the dbt project Azure File Share mount')
param storageAccountKey string // Needed ONLY for the file share mount
@description('Name of the Azure File Share containing the dbt project')
param dbtProjectFileShareName string

@secure()
@description('The bearer token value retrieved from the UC container')
param ucAdminTokenValue string

@description('The fully qualified URL for the Unity Catalog server endpoint (should be the PRIVATE URL like http://uc-server...)')
param ucServerUrl string

@description('The ABFSS path for the Delta storage location base')
param storagePath string // Passed from script, used by dbt_project.yml

@description('The dbt command to execute')
param dbtCommandToRun string = 'build'

// === Variables ===
var imageName = '${acrLoginServer}/dbt-server:latest'
var containerName = 'dbt-runner'
var dbtProjectVolumeName = 'dbt-project-volume'
var dbtProjectMountPath = '/dbt_project'      // Where the share is mounted
var dbtProjectDir = dbtProjectMountPath       // Variable defining project dir relative to container root

// === Resources ===

resource dbtContainerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: dbtJobInstanceName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {} // Use the pre-configured UAMI
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
             { name: 'UC_ADMIN_TOKEN', secureValue: ucAdminTokenValue } // Used by profiles.yml
             { name: 'UC_ENDPOINT', value: ucServerUrl }             // Used by profiles.yml (should be private URL)
             { name: 'STORAGE_PATH', value: storagePath }             // Used by dbt_project.yml var
             { name: 'DBT_PROJECT_DIR', value: dbtProjectDir }         // Used by command string below
             // REMOVED AZURE_STORAGE_KEY/ACCOUNT env vars to force MI usage for data access
          ]
          // *** Restore Robust Command Execution ***
          command: ['dbt', 'build' ]
          // **************************************
        }
      }
    ]

    imageRegistryCredentials: [ { server: acrLoginServer, username: acrUsername, password: acrPassword } ]
    volumes: [ { name: dbtProjectVolumeName, azureFile: { shareName: dbtProjectFileShareName, storageAccountName: dbtProjectStorageAccountName, storageAccountKey: storageAccountKey } } ]
    osType: 'Linux'
    restartPolicy: 'Never'
    subnetIds: [ { id: subnetId } ]
    dnsConfig: {
        nameServers: [ '168.63.129.16' ]
      }
    sku: 'Standard'
  }
}

// === Outputs ===
output dbtJobAciName string = dbtContainerGroup.name
output dbtJobAciId string = dbtContainerGroup.id