data "oci_core_vnic" "server" {
  for_each = local.oci_vms

  vnic_id = one(data.oci_core_vnic_attachments.server[each.key].vnic_attachments).vnic_id
}

data "oci_core_vnic_attachments" "server" {
  for_each = local.oci_vms

  compartment_id = var.oci_tenancy_ocid
  instance_id    = oci_core_instance.server[each.key].id
}

data "oci_identity_availability_domain" "default" {
  for_each = local.oci_regions

  ad_number      = 1
  compartment_id = var.oci_tenancy_ocid
}

locals {
  # Protocol/family combinations used when expanding ingress ports.
  oci_ingress_protocols = [
    {
      family   = "ipv4"
      name     = "tcp"
      protocol = "6"
      source   = "0.0.0.0/0"
    },
    {
      family   = "ipv4"
      name     = "udp"
      protocol = "17"
      source   = "0.0.0.0/0"
    },
    {
      family   = "ipv6"
      name     = "tcp"
      protocol = "6"
      source   = "::/0"
    },
    {
      family   = "ipv6"
      name     = "udp"
      protocol = "17"
      source   = "::/0"
    },
  ]

  # OCI network primitives are created once per region used by managed OCI VMs.
  oci_regions = toset(distinct([
    for vm_key, vm in local.oci_vms : vm.identity.region
  ]))

  # OCI resources in this root manage VM servers only.
  oci_vms = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.platform == "oci" &&
      server.type == "vm"
    )
  }

  # Each configured ingress port expands to TCP/UDP and IPv4/IPv6 rules; ICMP is
  # always allowed for basic reachability diagnostics.
  oci_vms_ingress_rules = merge([
    for vm_key, vm in local.oci_vms : merge(
      {
        for rule in [
          {
            family   = "ipv4"
            port     = null
            protocol = "1"
            source   = "0.0.0.0/0"
            vm_key   = vm_key
          },
          {
            family   = "ipv6"
            port     = null
            protocol = "1"
            source   = "::/0"
            vm_key   = vm_key
          },
        ] : "${rule.vm_key}-icmp-${rule.family}" => rule
      },
      {
        for rule in flatten([
          for port in vm.platform_config.oci.ingress_ports : [
            for combo in local.oci_ingress_protocols : merge(combo, {
              port   = port
              vm_key = vm_key
            })
          ]
        ]) : "${rule.vm_key}-${rule.name}-${rule.family}-${rule.port}" => rule
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

  create_vnic_details {
    assign_ipv6ip             = true
    assign_private_dns_record = true
    assign_public_ip          = each.value.platform_config.oci.assign_public_ip
    display_name              = each.key
    hostname_label            = each.value.identity.name
    nsg_ids                   = [oci_core_network_security_group.server[each.key].id]
    subnet_id                 = oci_core_subnet.default[each.value.identity.region].id
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }

  metadata = {
    user_data = base64encode(local.cloud_config[each.key])
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
  ipv6cidr_block = replace(one(oci_core_vcn.default[each.value].ipv6cidr_blocks), "/56", "/64")
  vcn_id         = oci_core_vcn.default[each.value].id
}

resource "oci_core_vcn" "default" {
  for_each = local.oci_regions

  cidr_blocks    = ["10.0.0.0/16"]
  compartment_id = var.oci_tenancy_ocid
  display_name   = "${each.value}.${local.defaults.domains.external}"
  dns_label      = regex("^[^.]+", local.defaults.domains.external)
  is_ipv6enabled = true
}
