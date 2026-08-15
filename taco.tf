resource "truenas_zvol" "taco_boot" {
  comments     = "Talos boot disk for taco.mbk.excloo.net"
  compression  = "LZ4"
  name         = local.taco.boot.zvol
  pool         = local.taco.boot.pool
  volblocksize = "16K"
  volsize      = local.taco.boot.size_gib * 1024 * 1024 * 1024

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_vm" "taco" {
  autostart             = true
  bootloader            = "UEFI"
  cores                 = local.taco.cpu.cores
  cpu_mode              = "HOST-PASSTHROUGH"
  description           = "Talos node taco.mbk.excloo.net"
  ensure_display_device = false
  memory                = local.taco.memory_mib
  name                  = "taco"
  threads               = local.taco.cpu.threads
  time                  = "UTC"
  vcpus                 = local.taco.cpu.sockets

  lifecycle {
    prevent_destroy = true
  }
}

resource "truenas_vm_device" "taco" {
  for_each = local.taco_devices

  attributes = each.value.attributes
  dtype      = each.value.dtype
  order      = each.value.order
  vm         = tonumber(truenas_vm.taco.id)
}
