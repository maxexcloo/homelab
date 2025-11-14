# Non-sensitive infrastructure configuration
# This file is safe to commit to version control

server_resources  = ["b2", "cloudflare", "cloudflared", "docker", "komodo", "resend", "tailscale"]
service_resources = ["b2", "resend", "tailscale"]

defaults = {
  domain_external = "excloo.net"
  domain_internal = "excloo.dev"
  email           = "max@excloo.com"
  locale          = "en_AU"
  managed_comment = "OpenTofu Managed"
  organization    = "excloo"
  shell           = "/bin/bash"
  timezone        = "Australia/Sydney"
}
