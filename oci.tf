data "oci_identity_availability_domain" "default" {
  for_each = local.oci_networks

  ad_number      = 1
  compartment_id = var.oci_tenancy_ocid
}

data "oci_objectstorage_namespace" "default" {
  for_each = local.oci_talos_images

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

resource "oci_core_image" "talos" {
  for_each = local.oci_talos_images

  compartment_id = var.oci_tenancy_ocid
  display_name   = "Talos ${each.value.talos_version} ${each.value.image.platform} ${each.value.image.architecture}"

  image_source_details {
    bucket_name              = oci_objectstorage_bucket.talos_images[each.key].name
    namespace_name           = data.oci_objectstorage_namespace.default[each.key].namespace
    object_name              = oci_objectstorage_object.talos_image[each.key].object
    operating_system         = each.value.image.operating_system
    operating_system_version = trimprefix(each.value.talos_version, "v")
    source_image_type        = "QCOW2"
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
    nsg_ids                   = [oci_core_network_security_group.node[each.key].id]
    private_ip                = local.machines[each.key].address
    subnet_id                 = oci_core_subnet.default[each.value.network].id
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
    source_id               = oci_core_image.talos[each.value.cluster].id
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

    precondition {
      condition = (
        sum(concat([0], [for node in values(local.oci_nodes) : node.oci.shape == "VM.Standard.A1.Flex" ? node.compute.cores : 0])) <= 2 &&
        sum(concat([0], [for node in values(local.oci_nodes) : node.oci.shape == "VM.Standard.A1.Flex" ? node.compute.memory_mib : 0])) <= 12288 &&
        sum(concat([0], [for node in values(local.oci_nodes) : node.oci.shape == "VM.Standard.A1.Flex" ? node.boot.size_mib : 0])) <= 204800
      )
      error_message = "OCI Ampere A1 deployments must stay within the Always Free envelope of 2 OCPUs, 12288 MiB memory, and 204800 MiB of boot storage."
    }
  }

  depends_on = [onepassword_item.talos_recovery]
}

resource "oci_core_internet_gateway" "default" {
  for_each = local.oci_networks

  compartment_id = var.oci_tenancy_ocid
  display_name   = each.value.display_name
  vcn_id         = oci_core_vcn.default[each.key].id
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

resource "oci_core_subnet" "default" {
  for_each = local.oci_networks

  cidr_block     = each.value.subnet_cidr
  compartment_id = var.oci_tenancy_ocid
  display_name   = each.value.display_name
  dns_label      = each.key
  ipv6cidr_block = each.value.ipv6_enabled ? cidrsubnet(one(oci_core_vcn.default[each.key].ipv6cidr_blocks), 8, 0) : null
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

resource "oci_objectstorage_bucket" "talos_images" {
  for_each = local.oci_talos_images

  access_type    = "NoPublicAccess"
  compartment_id = var.oci_tenancy_ocid
  name           = each.value.image.bucket_name
  namespace      = data.oci_objectstorage_namespace.default[each.key].namespace
  storage_tier   = "Standard"
  versioning     = "Enabled"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_objectstorage_object" "talos_image" {
  for_each = local.oci_talos_images

  bucket       = oci_objectstorage_bucket.talos_images[each.key].name
  content_type = "application/octet-stream"
  namespace    = data.oci_objectstorage_namespace.default[each.key].namespace
  object       = "talos-${each.value.talos_version}-${each.value.image.platform}-${each.value.image.architecture}.qcow2"
  source       = var.oci_talos_image_path

  lifecycle {
    prevent_destroy = true
  }
}
