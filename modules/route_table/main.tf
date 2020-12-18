resource "azurerm_route_table" "rt" {
  name                = var.route_table_name
  location            = var.location
  resource_group_name = var.resource_group_name

  route {
    name                   = "route_to_fw"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.firewall_private_ip
  }

  route {
    name           = "fw_host_route"
    address_prefix = "${var.firewall_public_ip}/32"
    next_hop_type  = "Internet"
  }

  lifecycle {
    ignore_changes = [route]
  }
}

resource "azurerm_subnet_route_table_association" "subnet_association" {
  subnet_id      = var.subnet_id
  route_table_id = azurerm_route_table.rt.id
}
