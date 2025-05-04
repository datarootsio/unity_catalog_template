// === uc-aci.bicep (Public IP Version) ===
targetScope = 'resourceGroup'

// === Parameters ===
param projectName string
param location string
param acrLoginServer string
param acrUsername string
@secure()
param acrPassword string
param storageAccountName string
param storageFileShareName string

param cpuCores int = 1
param memoryInGB int = 1
@description('Unique DNS name label for the public IP address.')
param publicDnsNameLabel string = '${toLower(projectName)}-uc-${uniqueString(resourceGroup().id)}'

// === Variables ===
var containerGroupName = 'aci-${projectName}-uc'
var volumeName = 'uc-etc-volume'
var containerMountPath = '/app/unitycatalog/etc'
var ucPort = 8080

// === Resources ===
@description('Reference to the existing Storage Account.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = { name: storageAccountName, scope: resourceGroup() }

@description('Deploys the Azure Container Instance for Unity Catalog with Public IP.')
resource unityCatalogAci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [ {
        name: 'unitycatalog'
        properties: {
          image: '${acrLoginServer}/uc-server:latest'
          ports: [ { port: ucPort, protocol: 'TCP' } ]
          resources: { requests: { cpu: cpuCores, memoryInGB: memoryInGB } }
          environmentVariables: []
          volumeMounts: [ { name: volumeName, mountPath: containerMountPath, readOnly: false } ]
        }
    } ]
    imageRegistryCredentials: [ { server: acrLoginServer, username: acrUsername, password: acrPassword } ]
    volumes: [ { name: volumeName, azureFile: { shareName: storageFileShareName, storageAccountName: storageAccountName, storageAccountKey: storageAccount.listKeys().keys[0].value } } ]
    osType: 'Linux'

    ipAddress: {
      type: 'Public'
      ports: [ { port: ucPort, protocol: 'TCP' } ]
      dnsNameLabel: publicDnsNameLabel
    }
    restartPolicy: 'Always'
  }
  tags: { Project: projectName, ManagedBy: 'Bicep', Purpose: 'Unity Catalog Server ACI (Public)' }
}

// === Outputs ===
output aciName string = unityCatalogAci.name
output aciId string = unityCatalogAci.id
//output aciPublicIpAddress string = unityCatalogAci.properties.ipAddress.ip // Public IP
output aciPublicFqdn string = unityCatalogAci.properties.ipAddress.fqdn // Public FQDN