targetScope = 'resourceGroup'

// === Parameters ===
@description('Specifies the base project name used for generating resource names.')
param projectName string

@description('Specifies the location for the resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Specifies the OS for the Function App and App Service Plan.')
@allowed([ 'Windows', 'Linux' ])
param osType string = 'Linux'

@description('Specifies the pricing tier for the App Service Plan. Y1 is Consumption for Linux.')
@allowed([ 'Y1', 'B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2', 'P1v3', 'P2v3', 'P3v3', 'EP1', 'EP2', 'EP3' ])
param appServicePlanSkuName string = 'Y1'

@description('Specifies the runtime stack for the Function App.')
param functionWorkerRuntime string // MUST BE PROVIDED e.g., 'python'

@description('Specifies the runtime version.')
param functionRuntimeVersion string // MUST BE PROVIDED e.g., 'PYTHON|3.11'

// REMOVED environmentVariables parameter

@description('Resource ID of the User-Assigned Managed Identity to assign.')
param uamiResourceId string // Still needed for identity block

// === Variables ===
var aspSuffix = 'asp'
var funcSuffix = 'func'
var appServicePlanName = '${projectName}-${aspSuffix}'
var functionAppName = '${projectName}-${funcSuffix}'
var planKind = (osType == 'Linux') ? 'linux' : 'app'
var planReserved = (osType == 'Linux')
var functionAppKind = (osType == 'Linux') ? 'functionapp,linux' : 'functionapp'
var isConsumptionPlan = (appServicePlanSkuName == 'Y1')
var alwaysOnSetting = !isConsumptionPlan
var fxVersionObject = ((osType == 'Linux') ? { linuxFxVersion: functionRuntimeVersion } : { windowsFxVersion: functionRuntimeVersion })

// === Resources ===

@description('App Service Plan for hosting the Function App.')
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  kind: planKind
  sku: {
    name: appServicePlanSkuName
  }
  properties: {
    reserved: planReserved
  }
  tags: {
    Project: projectName
    Purpose: 'Function App Service Plan'
    ManagedBy: 'Bicep'
  }
}

@description('The Azure Function App resource.')
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: functionAppKind
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: union( // Merge runtime version with other basic site config
      fxVersionObject,
      {
        // NO appSettings defined here - set entirely via script later
        minTlsVersion: '1.2'
        alwaysOn: alwaysOnSetting // This still makes sense to set via Bicep
        ftpsState: 'FtpsOnly'
        http20Enabled: true
      }
    )
    clientAffinityEnabled: false
  }
  tags: {
    Project: projectName
    Purpose: 'Function App'
    ManagedBy: 'Bicep'
  }
}

// === Outputs ===
@description('The name of the created Function App.')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App.')
output functionAppDefaultHostName string = functionApp.properties.defaultHostName

@description('The principal ID of the Function App Managed Identity (will be assigned post-deployment).')
output functionAppPrincipalId string = 'Managed Identity assigned via script post-deployment' // Or reference uami.properties.principalId if passing UAMI resource/name