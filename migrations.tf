moved {
  from = talos_machine_configuration_apply.container
  to   = talos_machine_configuration_apply.container["kimbap"]
}

moved {
  from = tailscale_tailnet_key.talos_container
  to   = tailscale_tailnet_key.talos_container["kimbap"]
}

moved {
  from = truenas_app.talos_container
  to   = truenas_app.talos_container["kimbap"]
}

moved {
  from = unifi_client.talos_container
  to   = unifi_client.talos_container["kimbap"]
}
