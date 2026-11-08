moved {
  from = cloudflare_dns_record.managed["machine/mandu/a"]
  to   = cloudflare_dns_record.managed["machine/mars/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/mandu/aaaa"]
  to   = cloudflare_dns_record.managed["machine/mars/aaaa"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared.cluster["mandu"]
  to   = cloudflare_zero_trust_tunnel_cloudflared.cluster["mars"]
}

moved {
  from = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["mandu"]
  to   = cloudflare_zero_trust_tunnel_cloudflared_config.cluster["mars"]
}

moved {
  from = onepassword_item.cloudflare_tunnel["mandu"]
  to   = onepassword_item.cloudflare_tunnel["mars"]
}

moved {
  from = onepassword_item.machine_access["mandu"]
  to   = onepassword_item.machine_access["mars"]
}

moved {
  from = onepassword_item.resend_host["mandu"]
  to   = onepassword_item.resend_host["mars"]
}

moved {
  from = onepassword_item.tailscale_auth_key["mandu"]
  to   = onepassword_item.tailscale_auth_key["mars"]
}

moved {
  from = resend_api_key.host["mandu"]
  to   = resend_api_key.host["mars"]
}

moved {
  from = tailscale_tailnet_key.server["mandu"]
  to   = tailscale_tailnet_key.server["mars"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hsp/a"]
  to   = cloudflare_dns_record.managed["machine/neptune/a"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hsp/aaaa"]
  to   = cloudflare_dns_record.managed["machine/neptune/aaaa"]
}

moved {
  from = cloudflare_dns_record.managed["machine/hsp/public-a"]
  to   = cloudflare_dns_record.managed["machine/neptune/public-a"]
}

moved {
  from = oci_core_instance.node["hsp"]
  to   = oci_core_instance.node["neptune"]
}

moved {
  from = oci_core_network_security_group.node["hsp"]
  to   = oci_core_network_security_group.node["neptune"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_echo["hsp"]
  to   = oci_core_network_security_group_security_rule.node_echo["neptune"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_egress["hsp/ipv4"]
  to   = oci_core_network_security_group_security_rule.node_egress["neptune/ipv4"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_egress["hsp/ipv6"]
  to   = oci_core_network_security_group_security_rule.node_egress["neptune/ipv6"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_ingress["hsp/web/ipv4/443"]
  to   = oci_core_network_security_group_security_rule.node_ingress["neptune/web/ipv4/443"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_ingress["hsp/web/ipv4/80"]
  to   = oci_core_network_security_group_security_rule.node_ingress["neptune/web/ipv4/80"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_ingress["hsp/web/ipv6/443"]
  to   = oci_core_network_security_group_security_rule.node_ingress["neptune/web/ipv6/443"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_ingress["hsp/web/ipv6/80"]
  to   = oci_core_network_security_group_security_rule.node_ingress["neptune/web/ipv6/80"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_path_mtu["hsp"]
  to   = oci_core_network_security_group_security_rule.node_path_mtu["neptune"]
}

moved {
  from = oci_core_network_security_group_security_rule.node_path_mtu_ipv6["hsp"]
  to   = oci_core_network_security_group_security_rule.node_path_mtu_ipv6["neptune"]
}

moved {
  from = onepassword_item.tailscale_auth_key["hsp"]
  to   = onepassword_item.tailscale_auth_key["neptune"]
}

moved {
  from = tailscale_tailnet_key.server["hsp"]
  to   = tailscale_tailnet_key.server["neptune"]
}

moved {
  from = talos_machine_configuration_apply.node["hsp"]
  to   = talos_machine_configuration_apply.node["neptune"]
}
