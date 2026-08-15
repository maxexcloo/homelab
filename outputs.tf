output "installer_image" {
  description = "Talos installer image for the home node."
  value       = data.talos_image_factory_urls.home.urls.installer
}
output "iso_url" {
  description = "Talos ISO URL for the home VM."
  value       = data.talos_image_factory_urls.home.urls.iso
}

output "schematic_id" {
  description = "Content-addressed Talos Image Factory schematic ID."
  value       = talos_image_factory_schematic.home.id
}

output "virtual_machine_iso_paths" {
  description = "TrueNAS ISO paths attached to managed virtual machines."
  value = {
    for name, virtual_machine in local.virtual_machines : name => virtual_machine.boot.iso_path
  }
}

output "virtual_machine_mac_addresses" {
  description = "Fixed MAC addresses for managed virtual-machine DHCP reservations."
  value = {
    for name, virtual_machine in local.virtual_machines : name => virtual_machine.network.mac_address
  }
}
