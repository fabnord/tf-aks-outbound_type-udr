provider "azurerm" {
  features {}
}

resource "azurerm_public_ip" "fwpip" {
  name                = var.fwpip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "fw" {
  name                = var.fw_name
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = var.fw_subnet_id
    public_ip_address_id = azurerm_public_ip.fwpip.id
  }
}

resource "azurerm_firewall_network_rule_collection" "aks-egress-network-rules" {
  name                = "aks-egress-network-rules"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 100
  action              = "Allow"

  rule {
    name                  = "hcp-worker"
    source_addresses      = ["*"]
    destination_addresses = ["AzureCloud.${var.location}"]
    destination_ports     = ["443","1194","9000"]
    protocols             = ["UDP","TCP"]
  }

  rule {
    name                  = "ntp"
    source_addresses      = ["*"]
    destination_addresses = ["*"]
    destination_ports     = ["123"]
    protocols             = ["UDP"]
  }
}

resource "azurerm_firewall_network_rule_collection" "monitor-egress-network-rules" {
  name                = "monitor-egress-fqdn-tags"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 101
  action              = "Allow"

  rule {
    name                  = "monitor-fqdn-tag"
    source_addresses      = ["*"]
    destination_addresses = ["AzureMonitor"]
    destination_ports     = ["443"]
    protocols             = ["TCP"]
  }
}

resource "azurerm_firewall_application_rule_collection" "aks-egress-application-rules" {
  name                = "aks-egress-fqdn-tags"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 100
  action              = "Allow"

  rule {
    name             = "aks-fqdn-tag"
    source_addresses = ["*"]
    fqdn_tags        = ["AzureKubernetesService"]
  }
}

resource "azurerm_firewall_application_rule_collection" "os-updates-application-rules" {
  name                = "os-updates"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 101
  action              = "Allow"

  rule {
    name             = "os-updates"
    source_addresses = ["*"]
    target_fqdns = [
      "security.ubuntu.com",
      "azure.archive.ubuntu.com",
      "changelogs.ubuntu.com"
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "docker-application-rules" {
  name                = "docker"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 102
  action              = "Allow"

  rule {
    name             = "docker"
    source_addresses = ["*"]

    target_fqdns = [
      "auth.docker.io",
      "registry-1.docker.io",
      "production.cloudflare.docker.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "google-application-rules" {
  name                = "google"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = var.resource_group_name
  priority            = 103
  action              = "Allow"

  rule {
    name             = "google"
    source_addresses = ["*"]

    target_fqdns = [
      "k8s.gcr.io",
      "storage.googleapis.com"
    ]

    protocol {
      port = "80"
      type = "Http"
    }

    protocol {
      port = "443"
      type = "Https"
    }
  }
}
