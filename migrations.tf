moved {
  from = data.onepassword_vault.configured["flylab"]
  to   = data.onepassword_vault.configured["fly"]
}

moved {
  from = onepassword_item.resend_flylab
  to   = onepassword_item.resend_fly
}

moved {
  from = onepassword_item.tailscale_flylab
  to   = onepassword_item.tailscale_fly
}

moved {
  from = resend_api_key.flylab
  to   = resend_api_key.fly
}

moved {
  from = tailscale_oauth_client.flylab
  to   = tailscale_oauth_client.fly
}

moved {
  from = terraform_data.onepassword_resend_flylab_password_version
  to   = terraform_data.onepassword_resend_fly_password_version
}

moved {
  from = terraform_data.onepassword_tailscale_flylab_password_version
  to   = terraform_data.onepassword_tailscale_fly_password_version
}
