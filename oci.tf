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
  # OCI network primitives are created once per region used by managed OCI VMs.
  oci_regions = toset(distinct([
    for k, v in local.oci_vms : v.identity.region
  ]))

  # OCI resources in this root manage VM servers only.
  oci_vms = {
    for k, v in local.servers_desired : k => v
    if v.platform == "oci" && v.type == "vm" && v.platform_config.oci != null
  }

  # Each configured ingress port expands to TCP/UDP and IPv4/IPv6 rules; ICMP is
  # always allowed for basic reachability diagnostics.
  oci_vms_ingress_rules = merge([
    for k, v in local.oci_vms : merge(
      {
        for item in [
          { family = "ipv4", port = null, protocol = "1", source = "0.0.0.0/0", vm_key = k },
          { family = "ipv6", port = null, protocol = "1", source = "::/0", vm_key = k },
        ] : "${item.vm_key}-icmp-${item.family}" => item
      },
      {
        for item in flatten([
          for port in v.platform_config.oci.ingress_ports : [
            for combo in [
              { family = "ipv4", protocol = "6", source = "0.0.0.0/0" },
              { family = "ipv4", protocol = "17", source = "0.0.0.0/0" },
              { family = "ipv6", protocol = "6", source = "::/0" },
              { family = "ipv6", protocol = "17", source = "::/0" },
            ] : merge(combo, { port = port, vm_key = k })
          ]
        ]) : "${item.vm_key}-${item.protocol == "6" ? "tcp" : "udp"}-${item.family}-${item.port}" => item
      }
    )
  ]...)
}

resource "oci_core_default_dhcp_options" "default" {
  for_each = local.oci_regions

  compartment_id             = var.oci_tenancy_ocid
  display_name               = "${each.value}.${local.defaults.domains.external}"
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

  display_name               = "${each.value}.${local.defaults.domains.external}"
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
  display_name               = "${each.value}.${local.defaults.domains.external}"
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
  display_name   = "${each.value}.${local.defaults.domains.external}"
  vcn_id         = oci_core_vcn.default[each.value].id
}

resource "oci_core_network_security_group" "server" {
  for_each = local.oci_vms

  compartment_id = var.oci_tenancy_ocid
  display_name   = each.key
  vcn_id         = oci_core_vcn.default[each.value.identity.region].id
}

resource "oci_core_network_security_group_security_rule" "server_ingress_port" {
  for_each = local.oci_vms_ingress_rules

  direction                 = "INGRESS"
  network_security_group_id = oci_core_network_security_group.server[each.value.vm_key].id
  protocol                  = each.value.protocol
  source                    = each.value.source
  source_type               = "CIDR_BLOCK"

  # OCI models TCP and UDP port options as different nested blocks, so the rule
  # map carries protocol numbers and the resource selects the matching block.
  dynamic "tcp_options" {
    for_each = each.value.protocol == "6" ? [1] : []

    content {
      destination_port_range {
        max = each.value.port
        min = each.value.port
      }
    }
  }

  dynamic "udp_options" {
    for_each = each.value.protocol == "17" ? [1] : []

    content {
      destination_port_range {
        max = each.value.port
        min = each.value.port
      }
    }
  }
}

resource "oci_core_subnet" "default" {
  for_each = local.oci_regions

  cidr_block     = "10.0.0.0/24"
  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domains.external}"
  dns_label      = each.value
  ipv6cidr_block = replace(oci_core_vcn.default[each.value].ipv6cidr_blocks[0], "/56", "/64")
  vcn_id         = oci_core_vcn.default[each.value].id
}

resource "oci_core_vcn" "default" {
  for_each = local.oci_regions

  cidr_blocks    = ["10.0.0.0/16"]
  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domains.external}"
  dns_label      = split(".", local.defaults.domains.external)[0]
  is_ipv6enabled = true
}
