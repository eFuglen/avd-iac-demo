using '../bicep/main.bicep'

param location = 'denmarkeast'
param avdResourceLocation = 'northeurope'
param secondaryLocation = 'swedencentral'
param resourcePrefix = 'newavd'
param vnetAddressPrefix = '10.0.0.0/16'
param subnetAddressPrefix = '10.0.0.0/24'
param adminUsername = 'eskev'
param adminPassword = 'ChangeMe!P@ssw0rd'
param vmSize = 'Standard_D4s_v5'
param numberOfVMs = 2
param maxSessionLimit = 10
param useCustomImage = false
param customImageId = ''
param deploymentNumber = '02'
param avdUserGroupId = 'd50d30d7-319d-4f97-8f78-c95807fbf0c8'
