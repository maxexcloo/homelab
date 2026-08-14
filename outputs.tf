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
