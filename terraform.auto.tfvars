# Non-sensitive infrastructure configuration
# This file is safe to commit to version control

server_resources  = ["b2", "cloudflare", "docker", "komodo", "resend", "tailscale"]
service_resources = ["b2", "resend", "tailscale"]

defaults = {
  domain_external = "excloo.net"
  domain_internal = "excloo.dev"
  email           = "max@excloo.com"
  organization    = "excloo"
  timezone        = "Australia/Sydney"
}

server_defaults = {
  description     = { type = "STRING", value = null }
  management_port = { type = "STRING", value = null }
  parent          = { type = "STRING", value = null }
  private_ipv4    = { type = "STRING", value = null }
  public_address  = { type = "STRING", value = null }
  public_ipv4     = { type = "STRING", value = null }
  public_ipv6     = { type = "STRING", value = null }
  resources       = { type = "STRING", value = null }
}

service_defaults = {
  api_key           = { type = "CONCEALED", value = null }
  database_password = { type = "CONCEALED", value = null }
  deploy_to         = { type = "STRING", value = null }
  description       = { type = "STRING", value = null }
  icon              = { type = "STRING", value = null }
  port              = { type = "STRING", value = null }
  resources         = { type = "STRING", value = null }
  secret_hash       = { type = "CONCEALED", value = null }
  service           = { type = "STRING", value = null }
}
