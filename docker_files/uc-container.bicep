// === uc-aci.bicep ===
// Deploys the Unity Catalog ACI using explicit ACR Credentials & Storage Key for File Share access
targetScope = 'resourceGroup'

// === Parameters ===
// (projectName, location, subnetId, acrLoginServer, acrUsername, acrPassword, storageAccountName, storageFileShareName parameters...)
param projectName string
param location string
param subnetId string
param acrLoginServer string
param acrUsername string
@secure()
param acrPassword string
param storageAccountName string
param storageFileShareName string

// *** Re-added DNS Parameters needed for FQDN output ***
@description('The name of the Private DNS Zone (e.g., myproject.internal). Required for FQDN output.')
param privateDnsZoneName string

@description('The desired hostname for the Unity Catalog server within the Private DNS Zone (e.g., uc-server). Required for FQDN output.')
param ucHostName string = 'uc-server'

// (cpuCores, memoryInGB parameters...)
param cpuCores int = 1
param memoryInGB int = 1

// === Variables ===
var containerGroupName = 'aci-${projectName}-uc'
var volumeName = 'uc-etc-volume'
var containerMountPath = '/app/unitycatalog/etc'

// === Resources ===

@description('Reference to the existing Storage Account.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
  scope: resourceGroup()
}

@description('Deploys the Azure Container Instance for Unity Catalog.')
resource unityCatalogAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  // (ACI definition using explicit ACR creds and Storage Key...)
  name: containerGroupName
  location: location
  // No Managed Identity needed for this approach
  properties: {
    containers: [ {
        name: 'unitycatalog'
        properties: {
          image: '${acrLoginServer}/uc-server:latest'
          ports: [ { port: 8080, protocol: 'TCP' } ]
          resources: { requests: { cpu: cpuCores, memoryInGB: memoryInGB } }
          environmentVariables: []
          volumeMounts: [ { name: volumeName, mountPath: containerMountPath, readOnly: false } ]
        }
    } ]
    imageRegistryCredentials: [ { server: acrLoginServer, username: acrUsername, password: acrPassword } ]
    volumes: [ {
        name: volumeName
        azureFile: { shareName: storageFileShareName, storageAccountName: storageAccountName, storageAccountKey: storageAccount.listKeys().keys[0].value }
    } ]
    osType: 'Linux'
    subnetIds: [ { id: subnetId } ]
    ipAddress: { type: 'Public', ports: [ { port: 8080, protocol: 'TCP' } ] }
    restartPolicy: 'Always'
  }
  tags: { Project: projectName, ManagedBy: 'Bicep', Purpose: 'Unity Catalog Server ACI' }
}

// Role Assignments REMOVED

// Private DNS Record definition REMOVED - Created via CLI script

// === Outputs ===
output aciName string = unityCatalogAci.name
output aciId string = unityCatalogAci.id
output aciPrivateIpAddress string = unityCatalogAci.properties.ipAddress.ip
// *** Re-added FQDN output using the parameters ***
output ucInternalFqdn string = '${ucHostName}.${privateDnsZoneName}'