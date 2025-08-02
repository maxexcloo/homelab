# Proxmox Server Module

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

  inputs  = try(local.sections.inputs, {})
  proxmox = try(local.sections.proxmox, {})

  # Proxmox Configuration
  node           = try(local.proxmox.node, "proxmox")
  cpus           = try(tonumber(local.proxmox.cpus), 4)
  memory         = try(tonumber(local.proxmox.memory), 8192)
  boot_disk_size = try(tonumber(local.proxmox.boot_disk_size), 128)
  template_id    = try(local.proxmox.template_id, 9000)

  # VM ID - generate from name hash
  vm_id = 100 + (parseint(substr(md5(var.name), 0, 4), 16) % 900)
}

# Create Proxmox VM
resource "proxmox_vm_qemu" "server" {
  name        = var.hostname
  target_node = local.node
  vmid        = local.vm_id

  clone = "ubuntu-22.04-template"

  cores  = local.cpus
  memory = local.memory
  scsihw = "virtio-scsi-pci"

  disk {
    size    = "${local.boot_disk_size}G"
    type    = "scsi"
    storage = "local-lvm"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-init settings
  os_type   = "cloud-init"
  ipconfig0 = "ip=dhcp"

  ciuser  = "ubuntu"
  sshkeys = try(local.inputs.ssh_public_key, "")

  # Custom cloud-init via cicustom
  cicustom = "user=local:snippets/${var.name}-cloud-init.yaml"

  lifecycle {
    ignore_changes = [clone, disk]
  }
}

# Upload cloud-init config
resource "null_resource" "cloud_init" {
  triggers = {
    config = md5(jsonencode(var.config))
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > /tmp/${var.name}-cloud-init.yaml <<'EOF'
      ${templatefile("${path.module}/../cloud-init.yaml", {
    hostname = var.hostname
    region   = var.region
    config   = var.config
})}
      EOF
      
      # Upload to Proxmox snippets storage
      # Note: This requires SSH access to be configured separately
      scp /tmp/${var.name}-cloud-init.yaml root@proxmox:/var/lib/vz/snippets/
      rm /tmp/${var.name}-cloud-init.yaml
    EOT
}
}

# Get VM info for IP
data "proxmox_vm_qemu" "server" {
  name = proxmox_vm_qemu.server.name

  depends_on = [proxmox_vm_qemu.server]
}

# Outputs
output "public_ip" {
  value = try(data.proxmox_vm_qemu.server.default_ipv4_address, "")
}

output "private_ip" {
  value = try(data.proxmox_vm_qemu.server.default_ipv4_address, "")
}

output "vm_id" {
  value = proxmox_vm_qemu.server.vmid
}