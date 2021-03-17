terraform {
  required_version = ">= 0.13"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "hub_rg" {
  name     = "${var.prefix}-${var.environment}-hub-rg"
  location = var.location
}

resource "azurerm_resource_group" "spoke_rg" {
  name     = "${var.prefix}-${var.environment}-spoke-rg"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "log" {
  name                = "${var.prefix}-${var.environment}-log"
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  sku               = "PerGB2018"
  retention_in_days = 30
}

module "hub_vnet" {
  source              = "./modules/virtual_network"
  name                = "${var.prefix}-${var.environment}-hub-vnet"
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  address_space = ["10.100.0.0/24"]
  subnets = [
    {
      name : "GatewaySubnet"
      address_prefixes : ["10.100.0.0/27"]
    },
    {
      name : "AzureBastionSubnet"
      address_prefixes : ["10.100.0.32/27"]
    },
    {
      name : "ApplicationGatewaySubnet"
      address_prefixes : ["10.100.0.64/27"]
    }
  ]
}

module "spoke_vnet" {
  source              = "./modules/virtual_network"
  name                = "${var.prefix}-${var.environment}-spoke-vnet"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location

  address_space = ["10.240.0.0/16"]
  subnets = [
    {
      name : "AzureFirewallSubnet"
      address_prefixes : ["10.240.0.0/26"]
    },
    {
      name : "VMSubnet"
      address_prefixes : ["10.240.0.64/26"]
    },
    {
      name : "AKSNodeSubnet"
      address_prefixes : ["10.240.0.128/26"]
    },
    {
      name : "AKSIngressSubnet"
      address_prefixes : ["10.240.0.192/26"]
    }
  ]
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "hub_to_spoke"
  resource_group_name          = azurerm_resource_group.hub_rg.name
  virtual_network_name         = module.hub_vnet.vnet_name
  remote_virtual_network_id    = module.spoke_vnet.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "spoke_to_hub"
  resource_group_name          = azurerm_resource_group.spoke_rg.name
  virtual_network_name         = module.spoke_vnet.vnet_name
  remote_virtual_network_id    = module.hub_vnet.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

module "firewall" {
  source              = "./modules/firewall"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location
  fw_name             = "${var.prefix}-${var.environment}-az-fw"
  fwpip_name          = "${var.prefix}-${var.environment}-az-fw-pip"
  fw_subnet_id        = module.spoke_vnet.subnet_ids["AzureFirewallSubnet"]
}

resource "azurerm_monitor_diagnostic_setting" "firewalldiagnostic" {
  name                       = "send_to_log_analytics"
  target_resource_id         = module.firewall.firewall_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id

  log {
    category = "AzureFirewallApplicationRule"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AzureFirewallNetworkRule"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AzureFirewallDnsProxy"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

module "routetable" {
  source              = "./modules/route_table"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location
  route_table_name    = "${var.prefix}-${var.environment}-rt"
  firewall_private_ip = module.firewall.firewall_private_ip
  firewall_public_ip  = module.firewall.firewall_public_ip
  subnet_id           = module.spoke_vnet.subnet_ids["AKSNodeSubnet"]
}

resource "azurerm_user_assigned_identity" "aksidentity" {
  name                = "${var.prefix}-${var.environment}-aks"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location
}

resource "azurerm_role_assignment" "aksidentityassignment" {
  scope                = azurerm_resource_group.spoke_rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aksidentity.principal_id
}

####################################################################################################
# Azure Kubernetes Service
####################################################################################################
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-${var.environment}-aks"
  resource_group_name = azurerm_resource_group.spoke_rg.name
  location            = azurerm_resource_group.spoke_rg.location

  dns_prefix         = "${var.prefix}-${var.environment}-aks"
  kubernetes_version = "1.18.10"

  linux_profile {
    admin_username = var.admin_user

    ssh_key {
      key_data = var.ssh_key
    }
  }

  node_resource_group = "${var.prefix}-${var.environment}-aks-nodes"

  network_profile {
    network_plugin     = "kubenet"
    pod_cidr           = "172.40.0.0/16"
    service_cidr       = "172.41.0.0/16"
    dns_service_ip     = "172.41.0.10"
    docker_bridge_cidr = "172.42.0.1/16"
    load_balancer_sku  = "Standard"
    outbound_type      = "userDefinedRouting"
  }

  default_node_pool {
    name                  = "${var.prefix}${var.environment}aks"
    vm_size               = "Standard_B2ms"
    type                  = "VirtualMachineScaleSets"
    availability_zones    = [1, 2, 3]
    node_count            = 3
    os_disk_size_gb       = 128
    vnet_subnet_id        = module.spoke_vnet.subnet_ids["AKSNodeSubnet"]
    max_pods              = 110
    enable_auto_scaling   = false
    enable_node_public_ip = false
    tags                  = null
  }


  identity {
    type                      = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.aksidentity.id
  }


  /* 
  service_principal {
    client_id     = var.client_id
    client_secret = var.client_secret
  }
*/

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.log.id
    }

    kube_dashboard {
      enabled = false
    }
  }

  role_based_access_control {
    enabled = true

    /*  
    azure_active_directory {
      managed                = true
      admin_group_object_ids = [var.aad_admin_group]
    } 
    */
  }

  tags = null

  depends_on = [
    module.routetable
  ]
}

####################################################################################################
# Application Gateway
####################################################################################################
locals {
  gateway_ip_configuration       = "${var.prefix}-${var.environment}"
  backend_address_pool_name      = "${var.prefix}-${var.environment}-appgw-beap"
  frontend_port_name             = "${var.prefix}-${var.environment}-appgw-feport"
  frontend_ip_configuration_name = "${var.prefix}-${var.environment}-appgw-feip"
  http_setting_name              = "${var.prefix}-${var.environment}-appgw-be-httpst"
  https_setting_name             = "${var.prefix}-${var.environment}-appgw-be-httpsst"
  listener_name                  = "${var.prefix}-${var.environment}-appgw-httplstn"
  request_routing_rule_name      = "${var.prefix}-${var.environment}-appgw-rqrt"
  redirect_configuration_name    = "${var.prefix}-${var.environment}-appgw-rdrcfg"
}

resource "azurerm_public_ip" "appgwpip" {
  name                = "${var.prefix}-${var.environment}-appgw-pip"
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "appgw" {
  name                = "${var.prefix}-${var.environment}-appgw"
  resource_group_name = azurerm_resource_group.hub_rg.name
  location            = azurerm_resource_group.hub_rg.location

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = 0
    max_capacity = 2
  }

  enable_http2 = false

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = module.hub_vnet.subnet_ids["ApplicationGatewaySubnet"]
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgwpip.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }
}

resource "azurerm_frontdoor" "fd" {
  name                                         = "${var.prefix}-${var.environment}-fd"
  resource_group_name                          = azurerm_resource_group.hub_rg.name
  enforce_backend_pools_certificate_name_check = false

  frontend_endpoint {
    name                              = "${var.prefix}-${var.environment}-fd-fe"
    host_name                         = "${var.prefix}-${var.environment}-fd.azurefd.net"
    custom_https_provisioning_enabled = false
  }

  backend_pool {
    name = "${var.prefix}-${var.environment}-fd-bepool"
    backend {
      address     = azurerm_public_ip.appgwpip.ip_address
      host_header = ""
      http_port   = 80
      https_port  = 443
      priority    = 1
      weight      = 50
    }

    load_balancing_name = "${var.prefix}-${var.environment}-fd-loadBalancingSettings"
    health_probe_name   = "${var.prefix}-${var.environment}-fd-healthProbeSettings"
  }

  routing_rule {
    name               = "https-redirect"
    accepted_protocols = ["Http"]
    patterns_to_match  = ["/*"]
    frontend_endpoints = ["${var.prefix}-${var.environment}-fd-fe"]

    redirect_configuration {
      redirect_protocol = "HttpsOnly"
      redirect_type     = "Found"
    }
  }

  backend_pool_load_balancing {
    name = "${var.prefix}-${var.environment}-fd-loadBalancingSettings"
  }

  backend_pool_health_probe {
    name = "${var.prefix}-${var.environment}-fd-healthProbeSettings"
  }
}
