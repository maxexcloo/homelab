data "oci_identity_availability_domain" "default" {
  for_each = local.oci_networks

  ad_number      = 1
  compartment_id = var.oci_tenancy_ocid
}

resource "oci_core_default_dhcp_options" "default" {
  for_each = local.oci_networks

  compartment_id             = var.oci_tenancy_ocid
  display_name               = each.value.display_name
  manage_default_resource_id = oci_core_vcn.default[each.key].default_dhcp_options_id

  options {
    server_type = "VcnLocalPlusInternet"
    type        = "DomainNameServer"
  }

  options {
    search_domain_names = [oci_core_vcn.default[each.key].vcn_domain_name]
    type                = "SearchDomain"
  }
}

resource "oci_core_default_route_table" "default" {
  for_each = local.oci_networks

  display_name               = each.value.display_name
  manage_default_resource_id = oci_core_vcn.default[each.key].default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.default[each.key].id
  }

  dynamic "route_rules" {
    for_each = each.value.ipv6_enabled ? [1] : []

    content {
      destination       = "::/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.default[each.key].id
    }
  }
}

resource "oci_core_default_security_list" "default" {
  for_each = local.oci_networks

  compartment_id             = var.oci_tenancy_ocid
  display_name               = each.value.display_name
  manage_default_resource_id = oci_core_vcn.default[each.key].default_security_list_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  dynamic "egress_security_rules" {
    for_each = each.value.ipv6_enabled ? [1] : []

    content {
      destination = "::/0"
      protocol    = "all"
      stateless   = false
    }
  }
}

resource "oci_core_internet_gateway" "default" {
  for_each = local.oci_networks

  compartment_id = var.oci_tenancy_ocid
  display_name   = each.value.display_name
  vcn_id         = oci_core_vcn.default[each.key].id
}

resource "oci_core_subnet" "default" {
  for_each = local.oci_networks

  cidr_block     = each.value.subnet_cidr
  compartment_id = var.oci_tenancy_ocid
  display_name   = each.value.display_name
  dns_label      = each.key
  ipv6cidr_block = each.value.ipv6_enabled ? replace(one(oci_core_vcn.default[each.key].ipv6cidr_blocks), "/56", "/64") : null
  vcn_id         = oci_core_vcn.default[each.key].id
}

resource "oci_core_vcn" "default" {
  for_each = local.oci_networks

  cidr_blocks    = [each.value.cidr]
  compartment_id = var.oci_tenancy_ocid
  display_name   = each.value.display_name
  dns_label      = each.value.dns_label
  is_ipv6enabled = each.value.ipv6_enabled
}

resource "oci_core_network_security_group" "node" {
  for_each = local.oci_nodes

  compartment_id = var.oci_tenancy_ocid
  display_name   = each.key
  vcn_id         = oci_core_vcn.default[each.value.network].id

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_network_security_group_security_rule" "node_egress" {
  for_each = local.oci_node_egress_rules

  description               = "Allow ${each.key} outbound traffic"
  destination               = each.value.destination
  destination_type          = "CIDR_BLOCK"
  direction                 = "EGRESS"
  network_security_group_id = oci_core_network_security_group.node[each.value.node].id
  protocol                  = "all"
  stateless                 = false
}

data "oci_objectstorage_namespace" "default" {
  compartment_id = var.oci_tenancy_ocid
}

resource "oci_objectstorage_bucket" "talos_images" {
  access_type    = "NoPublicAccess"
  compartment_id = var.oci_tenancy_ocid
  name           = local.oci_image.bucket_name
  namespace      = data.oci_objectstorage_namespace.default.namespace
  storage_tier   = "Standard"
  versioning     = "Enabled"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object" "talos_image" {
  bucket       = oci_objectstorage_bucket.talos_images.name
  content_type = "application/gzip"
  namespace    = data.oci_objectstorage_namespace.default.namespace
  object       = local.oci_object_name
  source       = var.oci_talos_image_path

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_image" "talos" {
  compartment_id = var.oci_tenancy_ocid
  display_name   = "Talos ${local.oci_cluster.talos_version} ${local.oci_image.platform} ${local.oci_image.architecture}"

  image_source_details {
    bucket_name              = oci_objectstorage_object.talos_image.bucket
    namespace_name           = oci_objectstorage_object.talos_image.namespace
    object_name              = oci_objectstorage_object.talos_image.object
    operating_system         = local.oci_image.operating_system
    operating_system_version = trimprefix(local.oci_cluster.talos_version, "v")
    source_type              = "objectStorageTuple"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_instance" "node" {
  for_each = local.oci_nodes

  availability_domain  = data.oci_identity_availability_domain.default[each.value.network].name
  compartment_id       = var.oci_tenancy_ocid
  display_name         = each.key
  preserve_boot_volume = true
  shape                = each.value.oci.shape

  create_vnic_details {
    assign_ipv6ip             = local.oci_networks[each.value.network].ipv6_enabled
    assign_private_dns_record = true
    assign_public_ip          = each.value.oci.assign_public_ip
    display_name              = each.key
    hostname_label            = each.key
    private_ip                = local.machines[each.key].address
    subnet_id                 = oci_core_subnet.default[each.value.network].id
    nsg_ids                   = [oci_core_network_security_group.node[each.key].id]
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  metadata = {
    user_data = base64encode(data.talos_machine_configuration.node[each.key].machine_configuration)
  }

  shape_config {
    memory_in_gbs = each.value.compute.memory_mib / 1024
    ocpus         = each.value.compute.cores
  }

  source_details {
    boot_volume_size_in_gbs = each.value.boot.size_mib / 1024
    source_id               = oci_core_image.talos.id
    source_type             = "image"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = each.value.compute.memory_mib % 1024 == 0
      error_message = "OCI memory_mib must be a whole multiple of 1024 MiB."
    }

    precondition {
      condition     = each.value.boot.size_mib % 1024 == 0
      error_message = "OCI boot size_mib must be a whole multiple of 1024 MiB."
    }
  }

  depends_on = [onepassword_item.talos_recovery]
}
