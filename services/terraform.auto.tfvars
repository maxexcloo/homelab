# Non-sensitive services configuration
# This file is safe to commit to version control

# Default values
default_deployment   = "all"
default_email        = "max@excloo.com"
default_external_dns = true
default_internal_dns = true

# Organization settings
organization = "excloo"

# Platform defaults
docker_network   = "proxy"
fly_region       = "syd"
vercel_framework = "nextjs"