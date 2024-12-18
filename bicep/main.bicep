param databricksResourceName string

var deploymentId = guid(resourceGroup().id)
var deploymentIdShort = substring(deploymentId, 0, 8)

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'dbw-id-${deploymentIdShort}'
  location: resourceGroup().location
}

resource databricks 'Microsoft.Databricks/workspaces@2024-09-01-preview' existing = {
  name: databricksResourceName
}

resource contributorRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: 'Contributor'
}

resource databricksRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedIdentity.id, databricks.id)
  properties: {
    principalId: managedIdentity.id
    principalType: 'ServicePrincipal'
    roleDefinitionId: contributorRole.id
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'setup-databricks-script'
  location: resourceGroup().location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: 'azurelinux3.0'
    scriptContent: '''
      cd ~
      tdnf install -yq unzip
      curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
      databricks repos create https://github.com/southworks/anti-money-laundering gitHub
      databricks workspace export /Users/${ARM_CLIENT_ID}/anti-money-laundering/bicep/job-template.json > job-template.json
      sed "s/<username>/${ARM_CLIENT_ID}/g" job-template.json > job.json
      databricks jobs submit --json @./job.json
    '''
    environmentVariables: [
      {
        name: 'DATABRICKS_AZURE_RESOURCE_ID'
        value: databricks.id
      }
      {
        name: 'ARM_CLIENT_ID'
        secureValue: managedIdentity.properties.clientId
      }
      {
        name: 'ARM_USE_MSI'
        value: 'true'
      }
    ]
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}
