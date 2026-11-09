moved {
  from = b2_application_key.host["kimbap"]
  to   = b2_application_key.host["saturn"]
}

moved {
  from = b2_bucket.host["kimbap"]
  to   = b2_bucket.host["saturn"]
}

moved {
  from = cloudflare_account_token.acme["kimbap"]
  to   = cloudflare_account_token.acme["saturn"]
}

moved {
  from = cloudflare_dns_record.managed["machine/kimbap/a"]
  to   = cloudflare_dns_record.managed["machine/saturn/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/kimbap/aaaa"]
  to   = cloudflare_dns_record.managed["machine/saturn/aaaa"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.cluster["kimbap"]
  to   = cloudflare_zero_trust_tunnel_cloudflared.cluster["saturn"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["kimbap"]
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["saturn"]
}

moved {
  from = onepassword_item.backblaze_host["kimbap"]
  to   = onepassword_item.backblaze_host["saturn"]
}

moved {
  from = onepassword_item.cloudflare_acme["kimbap"]
  to   = onepassword_item.cloudflare_acme["saturn"]
}

moved {
  from = onepassword_item.cloudflare_tunnel["kimbap"]
  to   = onepassword_item.cloudflare_tunnel["saturn"]
}

moved {
  from = onepassword_item.machine_access["kimbap"]
  to   = onepassword_item.machine_access["saturn"]
}

moved {
  from = onepassword_item.resend_host["kimbap"]
  to   = onepassword_item.resend_host["saturn"]
}

moved {
  from = onepassword_item.tailscale_auth_key["kimbap"]
  to   = onepassword_item.tailscale_auth_key["saturn"]
}

moved {
  from = resend_api_key.host["kimbap"]
  to   = resend_api_key.host["saturn"]
}

moved {
  from = tailscale_tailnet_key.server["kimbap"]
  to   = tailscale_tailnet_key.server["saturn"]
}

moved {
  from = tailscale_tailnet_key.talos_container["kimbap"]
  to   = tailscale_tailnet_key.talos_container["saturn"]
}

moved {
  from = talos_machine_bootstrap.control_plane["kimbap"]
  to   = talos_machine_bootstrap.control_plane["saturn"]
}

moved {
  from = talos_machine_configuration_apply.container["kimbap"]
  to   = talos_machine_configuration_apply.container["saturn"]
}

moved {
  from = truenas_app.talos_container["kimbap"]
  to   = truenas_app.talos_container["saturn"]
}

moved {
  from = truenas_cronjob.host["kimbap/icloud-photos-check"]
  to   = truenas_cronjob.host["saturn/icloud-photos-check"]
}

moved {
  from = truenas_cronjob.host["kimbap/icloud-photos-copy"]
  to   = truenas_cronjob.host["saturn/icloud-photos-copy"]
}

moved {
  from = truenas_cronjob.host["kimbap/smart-long"]
  to   = truenas_cronjob.host["saturn/smart-long"]
}

moved {
  from = truenas_cronjob.host["kimbap/smart-short"]
  to   = truenas_cronjob.host["saturn/smart-short"]
}

moved {
  from = truenas_dataset.child["kimbap/truenas/time-machine/ginny.koh"]
  to   = truenas_dataset.child["saturn/truenas/time-machine/ginny.koh"]
}

moved {
  from = truenas_dataset.child["kimbap/truenas/time-machine/max.schaefer"]
  to   = truenas_dataset.child["saturn/truenas/time-machine/max.schaefer"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/beets"]
  to   = truenas_dataset.root["saturn/truenas-nvme/beets"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/bichon"]
  to   = truenas_dataset.root["saturn/truenas-nvme/bichon"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/bookorbit"]
  to   = truenas_dataset.root["saturn/truenas-nvme/bookorbit"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/immich"]
  to   = truenas_dataset.root["saturn/truenas-nvme/immich"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/papra"]
  to   = truenas_dataset.root["saturn/truenas-nvme/papra"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/romm"]
  to   = truenas_dataset.root["saturn/truenas-nvme/romm"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/studio"]
  to   = truenas_dataset.root["saturn/truenas-nvme/studio"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas-nvme/talos"]
  to   = truenas_dataset.root["saturn/truenas-nvme/talos"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/ai"]
  to   = truenas_dataset.root["saturn/truenas/ai"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/backups"]
  to   = truenas_dataset.root["saturn/truenas/backups"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/documents"]
  to   = truenas_dataset.root["saturn/truenas/documents"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/games"]
  to   = truenas_dataset.root["saturn/truenas/games"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/home-assistant"]
  to   = truenas_dataset.root["saturn/truenas/home-assistant"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/icloud-photos"]
  to   = truenas_dataset.root["saturn/truenas/icloud-photos"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/music"]
  to   = truenas_dataset.root["saturn/truenas/music"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/pictures"]
  to   = truenas_dataset.root["saturn/truenas/pictures"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/projects"]
  to   = truenas_dataset.root["saturn/truenas/projects"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/public"]
  to   = truenas_dataset.root["saturn/truenas/public"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/s3"]
  to   = truenas_dataset.root["saturn/truenas/s3"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/time-machine"]
  to   = truenas_dataset.root["saturn/truenas/time-machine"]
}

moved {
  from = truenas_dataset.root["kimbap/truenas/unsorted"]
  to   = truenas_dataset.root["saturn/truenas/unsorted"]
}

moved {
  from = truenas_init_script.host["kimbap/crucial-x9-trim"]
  to   = truenas_init_script.host["saturn/crucial-x9-trim"]
}

moved {
  from = truenas_mail_config.host["kimbap"]
  to   = truenas_mail_config.host["saturn"]
}

moved {
  from = truenas_network_config.host["kimbap"]
  to   = truenas_network_config.host["saturn"]
}

moved {
  from = truenas_network_interface.services_bridge["kimbap"]
  to   = truenas_network_interface.services_bridge["saturn"]
}

moved {
  from = truenas_network_interface.services_physical["kimbap"]
  to   = truenas_network_interface.services_physical["saturn"]
}

moved {
  from = truenas_service.host["kimbap/cifs"]
  to   = truenas_service.host["saturn/cifs"]
}

moved {
  from = truenas_service.host["kimbap/ssh"]
  to   = truenas_service.host["saturn/ssh"]
}

moved {
  from = truenas_service.host["kimbap/ups"]
  to   = truenas_service.host["saturn/ups"]
}

moved {
  from = truenas_service.s3["kimbap"]
  to   = truenas_service.s3["saturn"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/backups"]
  to   = truenas_share_smb.dataset["saturn/truenas/backups"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/documents"]
  to   = truenas_share_smb.dataset["saturn/truenas/documents"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/games"]
  to   = truenas_share_smb.dataset["saturn/truenas/games"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/home-assistant"]
  to   = truenas_share_smb.dataset["saturn/truenas/home-assistant"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/icloud-photos"]
  to   = truenas_share_smb.dataset["saturn/truenas/icloud-photos"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/music"]
  to   = truenas_share_smb.dataset["saturn/truenas/music"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/pictures"]
  to   = truenas_share_smb.dataset["saturn/truenas/pictures"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/projects"]
  to   = truenas_share_smb.dataset["saturn/truenas/projects"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/public"]
  to   = truenas_share_smb.dataset["saturn/truenas/public"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/time-machine/ginny.koh"]
  to   = truenas_share_smb.dataset["saturn/truenas/time-machine/ginny.koh"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/time-machine/max.schaefer"]
  to   = truenas_share_smb.dataset["saturn/truenas/time-machine/max.schaefer"]
}

moved {
  from = truenas_share_smb.dataset["kimbap/truenas/unsorted"]
  to   = truenas_share_smb.dataset["saturn/truenas/unsorted"]
}

moved {
  from = truenas_smb_config.host["kimbap"]
  to   = truenas_smb_config.host["saturn"]
}

moved {
  from = truenas_snapshot_task.pool["kimbap/truenas-daily"]
  to   = truenas_snapshot_task.pool["saturn/truenas-daily"]
}

moved {
  from = truenas_snapshot_task.pool["kimbap/truenas-monthly"]
  to   = truenas_snapshot_task.pool["saturn/truenas-monthly"]
}

moved {
  from = truenas_snapshot_task.pool["kimbap/truenas-nvme-daily"]
  to   = truenas_snapshot_task.pool["saturn/truenas-nvme-daily"]
}

moved {
  from = truenas_snapshot_task.pool["kimbap/truenas-nvme-monthly"]
  to   = truenas_snapshot_task.pool["saturn/truenas-nvme-monthly"]
}

moved {
  from = truenas_ssh_config.host["kimbap"]
  to   = truenas_ssh_config.host["saturn"]
}

moved {
  from = truenas_tunable.host["kimbap/net.core.rmem_max"]
  to   = truenas_tunable.host["saturn/net.core.rmem_max"]
}

moved {
  from = truenas_tunable.host["kimbap/net.core.wmem_max"]
  to   = truenas_tunable.host["saturn/net.core.wmem_max"]
}

moved {
  from = truenas_tunable.host["kimbap/net.ipv4.conf.all.forwarding"]
  to   = truenas_tunable.host["saturn/net.ipv4.conf.all.forwarding"]
}

moved {
  from = truenas_tunable.host["kimbap/net.ipv6.conf.all.forwarding"]
  to   = truenas_tunable.host["saturn/net.ipv6.conf.all.forwarding"]
}

moved {
  from = truenas_ups_config.host["kimbap"]
  to   = truenas_ups_config.host["saturn"]
}

moved {
  from = truenas_user.s3["kimbap"]
  to   = truenas_user.s3["saturn"]
}

moved {
  from = unifi_client.talos_container["kimbap"]
  to   = unifi_client.talos_container["saturn"]
}
