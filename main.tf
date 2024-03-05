locals {
  ddos_pp_id = var.enable_ddos_pp ? azurerm_network_ddos_protection_plan.example[0].id : ""
}

module "labels" {

  source = "git::git@github.com:slovink/terraform-azure-labels.git?ref=1.0.0"

  name        = var.name
  environment = var.environment
  managedby   = var.managedby
  label_order = var.label_order
  repository  = var.repository
}

resource "azurerm_virtual_network" "vnet" {
  count               = var.enable == true ? 1 : 0
  name                = format("%s-vnet", module.labels.id)
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = length(var.address_spaces) == 0 ? [var.address_space] : var.address_spaces
  dns_servers         = var.dns_servers
  dynamic "ddos_protection_plan" {
    for_each = local.ddos_pp_id != "" ? ["ddos_protection_plan"] : []
    content {
      id     = local.ddos_pp_id
      enable = true
    }
  }
  tags = module.labels.tags
}

resource "azurerm_network_ddos_protection_plan" "example" {
  count               = var.enable_ddos_pp && var.enable == true ? 1 : 0
  name                = format("%s-ddospp", module.labels.id)
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = module.labels.tags
}

resource "azurerm_subnet" "subnet" {
  count                                         = var.enable && var.default_name_subnet == true ? length(var.subnet_names) : 0
  name                                          = "${var.name}-${var.subnet_names[count.index]}"
  resource_group_name                           = var.resource_group_name
  address_prefixes                              = [var.subnet_prefixes[count.index]]
  virtual_network_name                          = join("", azurerm_virtual_network.vnet[*].name)
  private_endpoint_network_policies_enabled     = lookup(var.subnet_enforce_private_link_endpoint_network_policies, var.subnet_names[count.index], false)
  service_endpoints                             = lookup(var.subnet_service_endpoints, var.subnet_names[count.index], [])
  private_link_service_network_policies_enabled = var.subnet_enforce_private_link_service_network_policies

  dynamic "delegation" {
    for_each = var.private_delegation
    content {
      name = lookup(each.value.private_delegation, "name", null)
      service_delegation {
        name    = lookup(each.value.private_delegation.service_delegation, "name", null)
        actions = lookup(each.value.private_delegation.service_delegation, "actions", null)
      }
    }
  }
}

resource "azurerm_subnet" "subnet2" {
  count                                          = var.enable && var.specific_name_subnet == true ? 1 : 0
  name                                           = var.specific_subnet_names
  resource_group_name                            = var.resource_group_name
  address_prefixes                               = [var.subnet_prefixes[count.index]]
  virtual_network_name                           = join("", azurerm_virtual_network.vnet[*].name)
  enforce_private_link_endpoint_network_policies = lookup(var.subnet_enforce_private_link_endpoint_network_policies, var.specific_subnet_names, false)
  service_endpoints                              = lookup(var.subnet_service_endpoints, var.specific_subnet_names, [])
  enforce_private_link_service_network_policies  = var.subnet_enforce_private_link_service_network_policies

  dynamic "delegation" {
    for_each = var.private_delegation
    content {
      name = lookup(each.value.private_delegation, "name", null)
      service_delegation {
        name    = lookup(each.value.private_delegation.service_delegation, "name", null)
        actions = lookup(each.value.private_delegation.service_delegation, "actions", null)
      }
    }
  }
}

resource "azurerm_route_table" "rt" {
  count               = var.enable && var.enabled_route_table ? 1 : 0
  name                = format("%s-route-table", module.labels.id)
  location            = var.location
  resource_group_name = var.resource_group_name
  dynamic "route" {
    for_each = var.routes
    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }
  disable_bgp_route_propagation = var.disable_bgp_route_propagation
  tags                          = module.labels.tags
}

resource "azurerm_subnet_route_table_association" "main" {
  count          = var.enable && var.enabled_route_table && var.default_name_subnet ? length(var.subnet_prefixes) : 0
  subnet_id      = element(azurerm_subnet.subnet[*].id, count.index)
  route_table_id = join("", azurerm_route_table.rt[*].id)
}

resource "azurerm_subnet_route_table_association" "main2" {
  count          = var.enable && var.enabled_route_table && var.specific_name_subnet ? length(var.subnet_prefixes) : 0
  subnet_id      = element(azurerm_subnet.subnet2[*].id, count.index)
  route_table_id = join("", azurerm_route_table.rt[*].id)
}
