resource "talos_image_factory_schematic" "home" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
          "siderolabs/tailscale",
        ]
      }
    }
  })
}
data "talos_image_factory_urls" "home" {
  architecture  = "amd64"
  platform      = "metal"
  schematic_id  = talos_image_factory_schematic.home.id
  talos_version = "v1.13.8"
}
