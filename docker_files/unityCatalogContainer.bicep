// === uc-aci-multicontainer-acrpw-FIXED.bicep === // Indicate fix
targetScope = 'resourceGroup'

// === Parameters ===
@description('Base project name for resource naming consistency.')
param projectName string
// ... (acrLoginServer, acrUsername, acrPassword, etc. - keep all existing parameters) ...
param location string
param acrLoginServer string
param acrUsername string
@secure()
param acrPassword string
param storageAccountName string
param storageFileShareName string // e.g., 'uc-etc-share'
param ucImageName string = 'uc-server'
param ucImageTag string = 'latest'
param permissionsManagerImageName string = 'uc-permissions-manager'
param permissionsManagerImageTag string = 'latest'
param ucCpuCores int = 1
param ucMemoryInGB int = 1
param pmCpuCores int = 1
param pmMemoryInGB int = 1
param publicDnsNameLabel string = '${toLower(projectName)}-uc-${uniqueString(resourceGroup().id)}'


// === Variables ===
var containerGroupName = 'aci-${projectName}-uc-group'
var volumeName = 'uc-etc-volume'

// --- UC Container Specific ---
var ucContainerName = 'unitycatalog'
// <<< *** FIX: Revert mount path to match previous working config *** >>>
var ucMountPath = '/app/unitycatalog/etc'
var ucPort = 8080

// --- Permissions Manager Container Specific ---
var pmContainerName = 'permissions-manager'
var pmMountPath = '/uc-config' // Mount point inside the permissions manager container
var fastApiPort = 8000
var streamlitPort = 8501
// Where the token file will be located *on the share* (relative to the share root)
var tokenRelativePathOnShare = 'conf/token.txt'


// === Resources ===
@description('Reference to the existing Storage Account.')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

@description('Deploys the ACI Container Group with UC Server and Permissions Manager containers.')
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [
      // --- Unity Catalog Server Container ---
      {
        name: ucContainerName
        properties: {
          image: '${acrLoginServer}/${ucImageName}:${ucImageTag}'
          ports: [ { port: ucPort, protocol: 'TCP' } ]
          resources: { requests: { cpu: ucCpuCores, memoryInGB: ucMemoryInGB } }
          environmentVariables: []
          // <<< Mount uses the corrected ucMountPath >>>
          volumeMounts: [ { name: volumeName, mountPath: ucMountPath, readOnly: false } ]
        }
      }
      // --- Permissions Manager Container ---
      {
        name: pmContainerName
        properties: {
          image: '${acrLoginServer}/${permissionsManagerImageName}:${permissionsManagerImageTag}'
          ports: [
            { port: fastApiPort, protocol: 'TCP' }
            { port: streamlitPort, protocol: 'TCP' }
          ]
          resources: { requests: { cpu: pmCpuCores, memoryInGB: pmMemoryInGB } }
          environmentVariables: [
            // <<< Path uc_service.py reads MUST point to where the token is on the mounted volume >>>
            // pmMountPath (/uc-config) + relative path on share (conf/token.txt)
            { name: 'UC_TOKEN_PATH', value: '${pmMountPath}/${tokenRelativePathOnShare}' } // Should resolve to /uc-config/conf/token.txt
            { name: 'UC_API_ENDPOINT', value: 'http://localhost:${ucPort}/api/2.1/unity-catalog' }
          ]
          // <<< Mount point inside this container is still /uc-config >>>
          volumeMounts: [ { name: volumeName, mountPath: pmMountPath, readOnly: false } ]
          command: [ '/bin/bash', '/app/start.sh' ]
        }
      }
    ]
    // Use ACR Credentials
    imageRegistryCredentials: [
      {
        server: acrLoginServer
        username: acrUsername
        password: acrPassword
      }
    ]
    // Define the shared volume
    volumes: [
      {
        name: volumeName
        azureFile: {
          shareName: storageFileShareName
          storageAccountName: storageAccountName
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'OnFailure'
    ipAddress: {
      type: 'Public'
      ports: [
        { port: ucPort, protocol: 'TCP' }
        { port: fastApiPort, protocol: 'TCP' }
        { port: streamlitPort, protocol: 'TCP' }
      ]
      dnsNameLabel: publicDnsNameLabel
    }
  }
  tags: {
    Project: projectName
    ManagedBy: 'Bicep'
    Purpose: 'Unity Catalog Server + Permissions UI Group (ACR PW Auth)'
  }
}

// === Outputs (Keep as before) ===
// ... aciGroupName, aciGroupId, aciPublicFqdn, ucApiUrl, permissionsManagerUiUrl, permissionsManagerApiUrl ...
@description('The name of the deployed Azure Container Instance Group.')
output aciGroupName string = containerGroup.name
@description('The resource ID of the deployed Azure Container Instance Group.')
output aciGroupId string = containerGroup.id
@description('The public Fully Qualified Domain Name (FQDN) of the Container Group.')
output aciPublicFqdn string = containerGroup.properties.ipAddress.fqdn
@description('URL for the Unity Catalog API (via public FQDN).')
output ucApiUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${ucPort}'
@description('URL for the Permissions Manager UI (Streamlit).')
output permissionsManagerUiUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${streamlitPort}'
@description('URL for the Permissions Manager API (FastAPI).')
output permissionsManagerApiUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${fastApiPort}'