import {
  to = truenas_init_script.host["kimbap/crucial-x9-trim"]
  id = "1"
}

moved {
  from = talos_machine_configuration_apply.container["bento"]
  to   = talos_machine_configuration_apply.node["bento"]
}

moved {
  from = cloudflare_dns_record.managed["machine/bento/a"]
  to   = cloudflare_dns_record.managed["machine/venus/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/bento/aaaa"]
  to   = cloudflare_dns_record.managed["machine/venus/aaaa"]
}

moved {
  from = onepassword_item.tailscale_auth_key["bento"]
  to   = onepassword_item.tailscale_auth_key["venus"]
}

moved {
  from = tailscale_tailnet_key.server["bento"]
  to   = tailscale_tailnet_key.server["venus"]
}

moved {
  from = talos_machine_configuration_apply.node["bento"]
  to   = talos_machine_configuration_apply.node["venus"]
}

moved {
  from = talos_image_factory_schematic.node["bento"]
  to   = talos_image_factory_schematic.node["venus"]
}
