data "oci_core_vnic" "server" {
  for_each = oci_core_instance.server

  vnic_id = data.oci_core_vnic_attachments.server[each.key].vnic_attachments[0].vnic_id
}

data "oci_core_vnic_attachments" "server" {
  for_each = oci_core_instance.server

  compartment_id = var.oci_tenancy_ocid
  instance_id    = each.value.id
}

data "oci_identity_availability_domain" "default" {
  for_each = local.oci_regions

  compartment_id = var.oci_tenancy_ocid
  ad_number      = 1
}

locals {
  oci_regions = toset(distinct([
    for k, v in local.oci_vms : v.identity.region
  ]))

  oci_vms = {
    for k, v in local._servers : k => v
    if v.identity.type == "vm" && v.platform == "oci" && v.platform_config.oci != null
  }
}

resource "oci_core_default_dhcp_options" "default" {
  for_each = local.oci_regions

  compartment_id             = var.oci_tenancy_ocid
  display_name               = "${each.value}.${local.defaults.domain_external}"
  manage_default_resource_id = oci_core_vcn.default[each.value].default_dhcp_options_id

  options {
    server_type = "VcnLocalPlusInternet"
    type        = "DomainNameServer"
  }

  options {
    search_domain_names = [oci_core_vcn.default[each.value].vcn_domain_name]
    type                = "SearchDomain"
  }
}

resource "oci_core_default_route_table" "default" {
  for_each = local.oci_regions

  display_name               = "${each.value}.${local.defaults.domain_external}"
  manage_default_resource_id = oci_core_vcn.default[each.value].default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.default[each.value].id
  }

  route_rules {
    destination       = "::/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.default[each.value].id
  }
}

resource "oci_core_default_security_list" "default" {
  for_each = local.oci_regions

  compartment_id             = var.oci_tenancy_ocid
  display_name               = "${each.value}.${local.defaults.domain_external}"
  manage_default_resource_id = oci_core_vcn.default[each.value].default_security_list_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  egress_security_rules {
    destination = "::/0"
    protocol    = "all"
    stateless   = false
  }

  ingress_security_rules {
    protocol  = 1
    source    = "0.0.0.0/0"
    stateless = false
  }

  ingress_security_rules {
    protocol  = 1
    source    = "::/0"
    stateless = false
  }
}

resource "oci_core_instance" "server" {
  for_each = local.oci_vms

  availability_domain = data.oci_identity_availability_domain.default[each.value.identity.region].name
  compartment_id      = var.oci_tenancy_ocid
  display_name        = each.key
  shape               = each.value.platform_config.oci.shape

  metadata = {
    user_data = base64encode(local.cloud_config[each.key])
  }

  create_vnic_details {
    assign_ipv6ip             = true
    assign_private_dns_record = true
    assign_public_ip          = each.value.platform_config.oci.assign_public_ip
    display_name              = each.key
    hostname_label            = each.value.identity.name
    nsg_ids                   = [oci_core_network_security_group.server[each.key].id]
    subnet_id                 = oci_core_subnet.default[each.value.identity.region].id
  }

  shape_config {
    memory_in_gbs = each.value.platform_config.oci.memory
    ocpus         = each.value.platform_config.oci.cpus
  }

  source_details {
    boot_volume_size_in_gbs = each.value.platform_config.oci.disk_size
    source_id               = each.value.platform_config.oci.image_id
    source_type             = "image"
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

resource "oci_core_internet_gateway" "default" {
  for_each = local.oci_regions

  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domain_external}"
  vcn_id         = oci_core_vcn.default[each.value].id
}

resource "oci_core_network_security_group" "server" {
  for_each = local.oci_vms

  compartment_id = var.oci_tenancy_ocid
  display_name   = each.key
  vcn_id         = oci_core_vcn.default[each.value.identity.region].id
}

resource "oci_core_network_security_group_security_rule" "server_ingress_icmp" {
  for_each = local.oci_vms

  direction                 = "INGRESS"
  network_security_group_id = oci_core_network_security_group.server[each.key].id
  protocol                  = "1"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
}

resource "oci_core_network_security_group_security_rule" "server_ingress_tcp" {
  for_each = merge([
    for k, v in local.oci_vms : {
      for port in v.platform_config.oci.ingress_ports : "${k}-tcp-${port}" => {
        vm_key = k
        port   = port
      }
    }
  ]...)

  direction                 = "INGRESS"
  network_security_group_id = oci_core_network_security_group.server[each.value.vm_key].id
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      max = each.value.port
      min = each.value.port
    }
  }
}

resource "oci_core_network_security_group_security_rule" "server_ingress_udp" {
  for_each = merge([
    for k, v in local.oci_vms : {
      for port in v.platform_config.oci.ingress_ports : "${k}-udp-${port}" => {
        vm_key = k
        port   = port
      }
    }
  ]...)

  direction                 = "INGRESS"
  network_security_group_id = oci_core_network_security_group.server[each.value.vm_key].id
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  udp_options {
    destination_port_range {
      max = each.value.port
      min = each.value.port
    }
  }
}

resource "oci_core_subnet" "default" {
  for_each = local.oci_regions

  cidr_block     = "10.0.0.0/24"
  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domain_external}"
  dns_label      = each.value
  ipv6cidr_block = replace(oci_core_vcn.default[each.value].ipv6cidr_blocks[0], "/56", "/64")
  vcn_id         = oci_core_vcn.default[each.value].id
}

resource "oci_core_vcn" "default" {
  for_each = local.oci_regions

  cidr_blocks    = ["10.0.0.0/16"]
  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domain_external}"
  dns_label      = replace(local.defaults.domain_external, "/\\.[^.]*$/", "")
  is_ipv6enabled = true
}
