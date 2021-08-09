//
// Common settings
//

var dnsZone = 'bogus.com'
var profileName = 'mypremfd1'
var wafPolicy = 'myPremiumFrontdoorWAF'
var globalRG = 'my-global-rg'

// 
// environment settings
// 

var envName = 'sre'
var staticWebSiteRegionCode = 'z22'
var sreDomain = 'mydomain.com'
var sreUIOriginGroupName = '${envName}-ui-origingroup'
var sreWebBffOriginGroupName = '${envName}-bff-origingroup'
var sreWebBffOriginHost = '${envName}.azurewebsites.net'
var wafResourceName = 'PremiumFrontdoorWAF-${uniqueString(resourceGroup().location)}'

//
// Do Not Use: 'core.windows.net' as hard coded url. Replace with environment().suffixes.storage for url suffix
// Ref: https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/template-functions-deployment?tabs=json#environment
//
var sreUIOriginHost = '${envName}uistg.${staticWebSiteRegionCode}.web.${environment().suffixes.storage}'
var trackUIOriginName = 'ui-origin'
var webbffOriginName = 'bff-origin'
var routeToTrackUI = 'routeTokUI'
var routeToWebBff = 'routeToBff'

var envData = {
    name: envName
    frontDoor: {
      // example: 'sre'.  Endpoint name will be: sre.z01.azurefd.net'
      endPointName: envName
      customDomainName: replace(sreDomain,'.','-')
      hostName: sreDomain
      routes: {
        trackUiRoute: {
          name: routeToTrackUI
          domain: sreDomain
          queryStringCachingBehavior: 'IgnoreQueryString'
          forwardingProtocol: 'HttpsOnly'
          linkToDefaultDomain: 'Enabled'
          httpsRedirect: 'Enabled'
          enabledState: 'Enabled'
          patternsToMatch: [
            '/*'
          ]
          originPath: '/api/'
          acceptedProtocol: 'HTTPS only'
          supportedProtocol: [
            'Https'
          ]
          redirectTraffic: true
          enableCaching: true
          enableCompression: true
          /*
          originGroup: {
            groupName: sreUIOriginGroupName
            originPath: ''
            forwardingProtocol: 'HTTPS only'          
          } */       
        }
        webBffRoute: {
          name: routeToWebBff
          domain: sreDomain
          queryStringCachingBehavior: 'IgnoreQueryString'
          forwardingProtocol: 'HttpsOnly'
          linkToDefaultDomain: 'Disabled'
          httpsRedirect: 'Enabled'
          enabledState: 'Enabled'
          patternsToMatch: [
            '/webff/*'
          ]
          originPath: '/api/'      
          acceptedProtocol: 'HTTPS only'
          supportedProtocol: [
            'Https'
          ]
          redirectTraffic: true          
          enableCaching: true
          enableCompression: true
          /*
          originGroup: {
            groupName: sreWebBffOriginGroupName
            originPath: '/api/'
            forwardingProtocol: 'HTTPS only'          
          } */
        }
      }
      originGroups: {
        uiGroup: {
          name: sreUIOriginGroupName
          // 'Disabled' | 'Enabled'
          sessionAffinityState: 'Disabled'
          loadBalancingSettings: {
            sampleSize: 4
            successfulSamplesRequired: 3
            additionalLatencyInMilliseconds: 50
          }          
          healthProbeSettings: {
            probePath: '/'
            probeRequestType: 'HEAD'
            probeProtocol: 'Https'
            probeIntervalInSeconds: 100
          }
          origins: {
            origin_1: {
              name: trackUIOriginName
              hostName: sreUIOriginHost
              originHostHeader: sreUIOriginHost
              httpPort: 80
              httpsPort: 443
              Priority: 1
              Weight: 50
              enabledState: 'Enabled'
            }
          }                    
        }
        bffGroup: {
          name: sreWebBffOriginGroupName
          // 'Disabled' | 'Enabled'
          sessionAffinityState: 'Disabled'
          loadBalancingSettings: {
            sampleSize: 4
            successfulSamplesRequired: 3
            additionalLatencyInMilliseconds: 50
          }
          healthProbeSettings: {
            probePath: '/'
            probeRequestType: 'GET'
            probeProtocol: 'Https'
            probeIntervalInSeconds: 100
          }
          origins: {
            origin_1: {
              name: webbffOriginName
              hostName: sreWebBffOriginHost
              originHostHeader: sreWebBffOriginHost
              httpPort: 80
              httpsPort: 443
              Priority: 1
              Weight: 50
              enabledState: 'Enabled'
            }            
          }          
        } 
      }
    }
}

// Loading external/existing resources not deployed with this template
resource dnsZone_resource 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZone
  scope: resourceGroup(globalRG)
}

resource afdWaf_resource 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2020-11-01' existing = {
  name: wafPolicy
}

output dnsZoneID string = dnsZone_resource.id
                          
//
// resource definitions
//
resource cdnProfile_resource 'Microsoft.Cdn/profiles@2020-09-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {}
}

resource afd_Resource 'Microsoft.Cdn/profiles/afdEndpoints@2020-09-01' = {
  parent: cdnProfile_resource
  name: envData.frontDoor.endPointName
  location: 'global'
  properties: {
    originResponseTimeoutSeconds: 60
    enabledState: 'Enabled'
  }
}

resource customDomain_resource 'Microsoft.Cdn/profiles/customdomains@2020-09-01' = {
  parent: cdnProfile_resource
  name: envData.frontDoor.customDomainName
  properties: {
    hostName: envData.frontDoor.hostName
    tlsSettings: {
      // Microsoft recommends using Azure managed certificate
      certificateType: 'ManagedCertificate'
      minimumTlsVersion: 'TLS12'        
    }
    azureDnsZone: {
      id: dnsZone_resource.id
    }
  }
}


/*
resource domainCertificate_resource 'Microsoft.Cdn/profiles/secrets@2020-09-01' = {
  parent: cdnProfile_resource
  name: '${uniqueString(resourceGroup().location)}-${envData.frontDoor.customDomainName}'
  properties: {
    parameters: {
      type: 'ManagedCertificate'
    }
  }
}
*/
resource trackUiOriginGroup_resource 'Microsoft.Cdn/profiles/originGroups@2020-09-01' = {
  parent: cdnProfile_resource
  name: envData.frontDoor.originGroups.uiGroup.name
  properties: {    
    healthProbeSettings: {
      probePath: envData.frontDoor.originGroups.uiGroup.healthProbeSettings.probePath
      probeRequestType: envData.frontDoor.originGroups.uiGroup.healthProbeSettings.probeRequestType
      probeProtocol: envData.frontDoor.originGroups.uiGroup.healthProbeSettings.probeProtocol
      probeIntervalInSeconds: envData.frontDoor.originGroups.uiGroup.healthProbeSettings.probeIntervalInSeconds
    }
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: envData.frontDoor.originGroups.uiGroup.loadBalancingSettings.additionalLatencyInMilliseconds
      sampleSize: envData.frontDoor.originGroups.uiGroup.loadBalancingSettings.sampleSize
      successfulSamplesRequired: envData.frontDoor.originGroups.uiGroup.loadBalancingSettings.successfulSamplesRequired
    }
    sessionAffinityState: envData.frontDoor.originGroups.uiGroup.sessionAffinityState    
  }  
}

resource trackUIOrigin_resource 'Microsoft.Cdn/profiles/originGroups/origins@2020-09-01' = {
  parent: trackUiOriginGroup_resource
  name: envData.frontDoor.originGroups.uiGroup.origins.origin_1.name
  properties: {    
    hostName: envData.frontDoor.originGroups.uiGroup.origins.origin_1.hostName
    httpPort: envData.frontDoor.originGroups.uiGroup.origins.origin_1.httpPort
    httpsPort: envData.frontDoor.originGroups.uiGroup.origins.origin_1.httpsPort
    originHostHeader: envData.frontDoor.originGroups.uiGroup.origins.origin_1.originHostHeader
    priority: envData.frontDoor.originGroups.uiGroup.origins.origin_1.Priority
    weight: envData.frontDoor.originGroups.uiGroup.origins.origin_1.Weight
    enabledState: envData.frontDoor.originGroups.uiGroup.origins.origin_1.enabledState
  }
}


resource trackUIOrigin2_resource 'Microsoft.Cdn/profiles/originGroups/origins@2020-09-01' = {
  parent: trackUiOriginGroup_resource
  name: 'trackui-origin2'
  properties: {    
    hostName: envData.frontDoor.originGroups.uiGroup.origins.origin_1.hostName
    httpPort: envData.frontDoor.originGroups.uiGroup.origins.origin_1.httpPort
    httpsPort: envData.frontDoor.originGroups.uiGroup.origins.origin_1.httpsPort
    originHostHeader: envData.frontDoor.originGroups.uiGroup.origins.origin_1.originHostHeader
    priority: envData.frontDoor.originGroups.uiGroup.origins.origin_1.Priority
    weight: envData.frontDoor.originGroups.uiGroup.origins.origin_1.Weight
    enabledState: envData.frontDoor.originGroups.uiGroup.origins.origin_1.enabledState
  }
}

/*
resource webBffOrigin_resource 'Microsoft.Cdn/profiles/originGroups/origins@2020-09-01' = {
  parent: webBffOriginGroup_resource
  name: envData.frontDoor.originGroups.bffGroup.origins.origin_1.name
  properties: {    
    hostName: envData.frontDoor.originGroups.bffGroup.origins.origin_1.hostName
    httpPort: envData.frontDoor.originGroups.bffGroup.origins.origin_1.httpPort
    httpsPort: envData.frontDoor.originGroups.bffGroup.origins.origin_1.httpsPort
    originHostHeader: envData.frontDoor.originGroups.bffGroup.origins.origin_1.originHostHeader
    priority: envData.frontDoor.originGroups.bffGroup.origins.origin_1.Priority
    weight: envData.frontDoor.originGroups.bffGroup.origins.origin_1.Weight
    enabledState: envData.frontDoor.originGroups.bffGroup.origins.origin_1.enabledState
  }
}
*/

/*
resource webBffOriginGroup_resource 'Microsoft.Cdn/profiles/originGroups@2020-09-01' = {
  parent: cdnProfile_resource
  name: envData.frontDoor.originGroups.bffGroup.name
  properties: {    
    healthProbeSettings: {
      probePath: envData.frontDoor.originGroups.bffGroup.healthProbeSettings.probePath
      probeRequestType: envData.frontDoor.originGroups.bffGroup.healthProbeSettings.probeRequestType
      probeProtocol: envData.frontDoor.originGroups.bffGroup.healthProbeSettings.probeProtocol
      probeIntervalInSeconds: envData.frontDoor.originGroups.bffGroup.healthProbeSettings.probeIntervalInSeconds
    }    
    loadBalancingSettings: {
      additionalLatencyInMilliseconds: envData.frontDoor.originGroups.bffGroup.loadBalancingSettings.additionalLatencyInMilliseconds
      sampleSize: envData.frontDoor.originGroups.bffGroup.loadBalancingSettings.sampleSize
      successfulSamplesRequired: envData.frontDoor.originGroups.bffGroup.loadBalancingSettings.successfulSamplesRequired
    }
    sessionAffinityState: envData.frontDoor.originGroups.bffGroup.sessionAffinityState    
  }  
}
*/
//
// Routes resource declaration
//
resource trackUIRoute_resource 'Microsoft.Cdn/profiles/afdEndpoints/routes@2020-09-01' = {
  parent: afd_Resource
  name: 'routeToTrackUI'
  dependsOn: [
    cdnProfile_resource
  ]  
  properties: {
    customDomains: [
      {
        id: customDomain_resource.id
      }
    ]
    originGroup: {
      id: trackUiOriginGroup_resource.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }  
}
/*
resource webBffRoute_resource 'Microsoft.Cdn/profiles/afdEndpoints/routes@2020-09-01' = {
  parent: afd_Resource
  name: envData.frontDoor.routes.webBffRoute.name
  dependsOn: [
    webBffOrigin_resource
    customDomain_resource
  ]
  properties: {
    customDomains: [
      {
        id: customDomain_resource.id
      }
    ]
    originGroup: {
      id: webBffOrigin_resource.id
    }
    originPath: envData.frontDoor.routes.webBffRoute.originPath
    ruleSets: []
    supportedProtocols: envData.frontDoor.routes.webBffRoute.supportedProtocol
    patternsToMatch: envData.frontDoor.routes.webBffRoute.patternsToMatch
    compressionSettings: {
      isCompressionEnabled: false
    }
    queryStringCachingBehavior: envData.frontDoor.routes.webBffRoute.queryStringCachingBehavior
    forwardingProtocol: envData.frontDoor.routes.webBffRoute.forwardingProtocol
    linkToDefaultDomain: envData.frontDoor.routes.webBffRoute.linkToDefaultDomain
    httpsRedirect: envData.frontDoor.routes.webBffRoute.httpsRedirect
    enabledState: envData.frontDoor.routes.webBffRoute.enabledState    
  }  
}
*/

resource waf_resource 'Microsoft.Cdn/profiles/securitypolicies@2020-09-01' = {
  parent: cdnProfile_resource
  name: wafResourceName
  dependsOn: [
    customDomain_resource
  ]
  properties: {
    parameters: {
      wafPolicy: {
        id: afdWaf_resource.id
      }
      associations: [
        {
          domains: [
            {
              id: customDomain_resource.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
      type: 'WebApplicationFirewall'
    }
  }
}
