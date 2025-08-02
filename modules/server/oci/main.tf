# OCI Server Module

variable "name" {
  description = "Server name"
  type        = string
}

variable "short_name" {
  description = "Short server name"
  type        = string
}

variable "region" {
  description = "Server region"
  type        = string
}

variable "hostname" {
  description = "Server hostname"
  type        = string
}

variable "config" {
  description = "Server configuration"
  type        = any
}

locals {
  # Parse configuration sections
  sections = {
    for section in try(var.config.section, []) :
    section.label => {
      for field in section.field :
      field.label => field.value
    }
  }

  inputs = try(local.sections.inputs, {})
  oci    = try(local.sections.oci, {})

  # OCI Configuration
  shape          = try(local.oci.shape, "VM.Standard.A1.Flex")
  cpus           = try(tonumber(local.oci.cpus), 4)
  memory         = try(tonumber(local.oci.memory), 8)
  boot_disk_size = try(tonumber(local.oci.boot_disk_size), 128)

  # Get compartment from OCI config
  compartment_id = try(local.oci.compartment_id, local.oci.tenancy_ocid, "")
}



# Get Ubuntu image
data "oci_core_images" "ubuntu" {
  compartment_id = local.compartment_id

  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = local.shape

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-22.04-([\\.0-9-]+)$"]
    regex  = true
  }
}

# Get subnet
data "oci_core_subnets" "main" {
  compartment_id = local.compartment_id

  filter {
    name   = "display_name"
    values = ["*public*"]
    regex  = true
  }
}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

# Create instance
resource "oci_core_instance" "server" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = var.name
  shape               = local.shape

  shape_config {
    ocpus         = local.cpus
    memory_in_gbs = local.memory
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = local.boot_disk_size
  }

  create_vnic_details {
    subnet_id        = data.oci_core_subnets.main.subnets[0].id
    display_name     = "${var.name}-vnic"
    assign_public_ip = true
    hostname_label   = var.hostname
  }

  metadata = {
    ssh_authorized_keys = try(local.inputs.ssh_public_key, "")
    user_data = base64encode(templatefile("${path.module}/../cloud-init.yaml", {
      hostname = var.hostname
      region   = var.region
      config   = var.config
    }))
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}

# Outputs
output "public_ip" {
  value = oci_core_instance.server.public_ip
}

output "private_ip" {
  value = oci_core_instance.server.private_ip
}

output "instance_id" {
  value = oci_core_instance.server.id
}