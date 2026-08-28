moved {
  from = cloudflare_dns_record.all
  to   = cloudflare_dns_record.managed
}

moved {
  from = data.cloudflare_zone.default
  to   = data.cloudflare_zone.configured
}

moved {
  from = data.onepassword_vault.default
  to   = data.onepassword_vault.configured
}

moved {
  from = data.unifi_network.default
  to   = data.unifi_network.configured
}

moved {
  from = onepassword_item.backblaze
  to   = onepassword_item.backblaze_host
}

moved {
  from = terraform_data.onepassword_backblaze_password_version
  to   = terraform_data.onepassword_backblaze_host_password_version
}

moved {
  from = truenas_dataset.managed
  to   = truenas_dataset.root
}
