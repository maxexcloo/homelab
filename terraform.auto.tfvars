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
  description     = null
  management_port = null
  parent          = null
  private_ipv4    = null
  public_address  = null
  public_ipv4     = null
  public_ipv6     = null
  resources       = null
}

service_defaults = {
  api_key           = null
  database_password = null
  deploy_to         = null
  description       = null
  icon              = null
  port              = null
  resources         = null
  secret_hash       = null
  service           = null
}
