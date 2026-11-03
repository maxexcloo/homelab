data "cloudflare_account" "default" {
  filter = {
    name = local.cloudflare.account_name
  }
}

data "cloudflare_account_api_token_permission_groups_list" "configured" {
  for_each = {
    "Access: Apps Write"    = "com.cloudflare.api.account"
    "Access: Policies Read" = "com.cloudflare.api.account"
    "DNS Write"             = "com.cloudflare.api.account.zone"
    "Zone Read"             = "com.cloudflare.api.account.zone"
    "Zone WAF Write"        = "com.cloudflare.api.account.zone"
  }

  account_id = data.cloudflare_account.default.id
  max_items  = 1
  name       = replace(each.key, " ", "%20")
  scope      = each.value
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id
}

data "cloudflare_zone" "configured" {
  for_each = local.cloudflare_zones

  filter = {
    name = each.value
  }
}

locals {
  cloudflare = local.provider_settings.providers.cloudflare

  cloudflare_access_client_secret = one(flatten([
    for section in onepassword_item.cloudflare_access.section : [
      for field in section.field : field.value
      if field.label == "oidc-client-secret"
    ]
  ]))

  # The timer in hosts/common runs this renewal.
  cloudflare_acme_files = {
    for name in keys(local.cloudflare_consumers_acme) : name => {
      "/etc/containers/systemd/cockpit-letsencrypt.container" = {
        content = <<-EOT
          [Unit]
          Description=Renew the Let's Encrypt certificate used by Cockpit

          [Container]
          ContainerName=cockpit-letsencrypt
          Exec=--cron
          Image=${local.versions.images.acme_sh}
          Pull=newer
          Volume=/etc/cockpit/ws-certs.d:/cockpit:Z
          Volume=/var/lib/acme-%H:/acme.sh:Z

          [Service]
          ExecStartPost=/usr/sbin/restorecon -RF /etc/cockpit/ws-certs.d
          ExecStartPost=/usr/bin/systemctl try-restart cockpit.service
          Type=oneshot
        EOT
        mode    = "0644"
      }
    }
    if can(local.sync_hosts[name])
  }

  cloudflare_consumers = {
    for name, consumer in merge(local.machines, local.clusters) : name => consumer.cloudflare
    if can(consumer.cloudflare)
  }

  cloudflare_consumers_access_applications = toset([
    for name, cluster in local.clusters : name
    if try(cluster.cloudflare.access_applications, false)
  ])

  cloudflare_consumers_acme = {
    for name, consumer in local.cloudflare_consumers : name => {
      challenge_hostname = can(local.machines[name]) ? local.machine_fqdns[name] : "${name}.${local.domains.services}"
      challenge_mode     = consumer.acme
      challenge_zone     = can(local.machines[name]) ? local.domains.infrastructure : local.domains.services
      credential_scope   = can(local.machines[name]) ? local.machine_fqdns[name] : name
      dns_write_zone     = consumer.acme == "direct" ? (can(local.machines[name]) ? local.domains.infrastructure : local.domains.services) : local.domains.acme
      target_hostname    = can(local.machines[name]) ? "_acme-challenge.${name}.${local.domains.acme}" : "_acme-challenge.${name}.${local.domains.services}.${local.domains.acme}"
    }
    if can(consumer.acme)
  }

  cloudflare_consumers_external_dns = {
    for name, cluster in local.clusters : name => {
      zones = cluster.cloudflare.external_dns
    }
    if can(cluster.cloudflare.external_dns)
  }

  cloudflare_consumers_tunnel = {
    for name, consumer in local.cloudflare_consumers : name => {
      is_cluster = can(local.clusters[name])
      ingress = concat(
        [
          for route in try(consumer.tunnel.ingress, []) : merge(
            {
              hostname = route.hostname
              service  = route.service
            },
            try(route.path, null) != null ? {
              path = route.path
            } : {},
            try(route.origin_request, null) != null ? {
              origin_request = route.origin_request
            } : {},
          )
        ],
        [
          {
            service = try(
              consumer.tunnel.fallback_service,
              can(local.clusters[name]) ? "http://traefik-tunnel.networking.svc.cluster.local:80" : "http_status:503",
            )
          },
        ],
      )
    }
    if can(consumer.tunnel)
  }

  cloudflare_consumers_waf = toset([
    for name, cluster in local.clusters : name
    if try(cluster.cloudflare.waf, false)
  ])

  cloudflare_permission_group_ids = {
    for name, groups in data.cloudflare_account_api_token_permission_groups_list.configured :
    name => one(groups.result).id
  }

  cloudflare_tunnel_files = {
    for name in keys(local.cloudflare_consumers_tunnel) : name => {
      "/etc/cloudflared/cloudflared.env" = {
        content = "TUNNEL_TOKEN=${data.cloudflare_zero_trust_tunnel_cloudflared_token.cluster[name].token}\n"
        mode    = "0600"
      }
      "/etc/containers/systemd/cloudflared.container" = {
        content = <<-EOT
          [Unit]
          Description=Cloudflare Tunnel
          # Hosts leave Podman's auto-update timer disabled by default.
          Wants=podman-auto-update.timer

          [Container]
          AutoUpdate=registry
          ContainerName=cloudflared
          EnvironmentFile=/etc/cloudflared/cloudflared.env
          Exec=tunnel --no-autoupdate run
          Image=${local.versions.images.cloudflared}
          Network=host

          [Service]
          Restart=always
          RestartSec=5
          TimeoutStartSec=300

          [Install]
          WantedBy=multi-user.target
        EOT
        mode    = "0644"
      }
    }
    if can(local.sync_hosts[name])
  }

  cloudflare_tunnel_mtls_hostnames = {
    for route in local.cloudflare_tunnel_routes : route.zone => route.hostname...
    if anytrue([
      for ingress in local.cloudflare_consumers[route.consumer].tunnel.ingress :
      ingress.hostname == route.hostname && try(ingress.mtls, false)
    ])
  }

  cloudflare_tunnel_route_entries = flatten([
    for consumer_name, consumer in local.cloudflare_consumers : [
      for ingress in try(consumer.tunnel.ingress, []) : {
        consumer = consumer_name
        hostname = ingress.hostname
        zone     = one([for zone in local.cloudflare_zones : zone if endswith(".${ingress.hostname}", ".${zone}")])
      }
    ]
  ])

  # Path-specific ingress rules repeat their hostname; each hostname needs one DNS route.
  cloudflare_tunnel_routes = {
    for route in distinct(local.cloudflare_tunnel_route_entries) : "${route.consumer}/${route.hostname}" => route
  }

  cloudflare_waf_zones = [
    for dns_zone in local.dns_zones : dns_zone.name
    if try(dns_zone.waf, false)
  ]

  cloudflare_zone_settings = merge([
    for zone in local.cloudflare_zones : {
      for setting, value in local.cloudflare.zone_settings : "${zone}/${setting}" => {
        setting = setting
        value   = value
        zone    = zone
      }
    }
  ]...)

  cloudflare_zones = toset(concat(
    values(local.domains),
    [for dns_zone in local.dns_zones : dns_zone.name],
  ))
}

resource "cloudflare_account_token" "access_applications" {
  for_each = local.cloudflare_consumers_access_applications

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare Access Applications: ${each.key}"

  # Consumers attach the reusable policies Homelab owns but cannot change them.
  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = local.cloudflare_permission_group_ids["Access: Apps Write"]
        },
        {
          id = local.cloudflare_permission_group_ids["Access: Policies Read"]
        },
      ]

      resources = jsonencode({
        "com.cloudflare.api.account.${data.cloudflare_account.default.id}" = "*"
      })
    },
  ]
}

resource "cloudflare_account_token" "acme" {
  for_each = local.cloudflare_consumers_acme

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare ACME DNS: ${each.value.credential_scope}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = local.cloudflare_permission_group_ids["DNS Write"]
        },
        {
          id = local.cloudflare_permission_group_ids["Zone Read"]
        },
      ]

      resources = jsonencode({
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[each.value.dns_write_zone].zone_id}" = "*"
      })
    },
  ]
}

resource "cloudflare_account_token" "external_dns" {
  for_each = local.cloudflare_consumers_external_dns

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare ExternalDNS: ${each.key}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = local.cloudflare_permission_group_ids["DNS Write"]
        },
        {
          id = local.cloudflare_permission_group_ids["Zone Read"]
        },
      ]

      resources = jsonencode({
        for zone in each.value.zones :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[zone].zone_id}" => "*"
      })
    },
  ]
}

resource "cloudflare_account_token" "waf" {
  for_each = local.cloudflare_consumers_waf

  account_id = data.cloudflare_account.default.id
  name       = "Cloudflare WAF: ${each.key}"

  policies = [
    {
      effect = "allow"

      permission_groups = [
        {
          id = local.cloudflare_permission_group_ids["Zone Read"]
        },
        {
          id = local.cloudflare_permission_group_ids["Zone WAF Write"]
        },
      ]

      resources = jsonencode({
        for zone in local.cloudflare_waf_zones :
        "com.cloudflare.api.account.zone.${data.cloudflare_zone.configured[zone].zone_id}" => "*"
      })
    },
  ]
}

resource "cloudflare_certificate_authorities_hostname_associations" "mtls" {
  for_each = local.cloudflare_tunnel_mtls_hostnames

  hostnames = distinct(each.value)
  zone_id   = data.cloudflare_zone.configured[each.key].zone_id
}

resource "cloudflare_dns_record" "managed" {
  for_each = local.dns_records

  comment  = each.value.comment
  content  = each.value.content
  name     = each.value.name
  priority = each.value.priority
  proxied  = each.value.proxied
  ttl      = each.value.ttl
  type     = each.value.type
  zone_id  = data.cloudflare_zone.configured[each.value.zone].zone_id
}

resource "cloudflare_zero_trust_access_application" "app_launcher" {
  account_id                = data.cloudflare_account.default.id
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.pocket_id.id]
  auto_redirect_to_identity = true
  type                      = "app_launcher"

  # Cloudflare stores an empty design that the provider otherwise keeps removing.
  landing_page_design = {
    title = "Welcome!"
  }

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.pocket_id.id
      precedence = 1
    },
  ]
}

resource "cloudflare_zero_trust_access_identity_provider" "pocket_id" {
  account_id = data.cloudflare_account.default.id
  name       = local.access.cloudflare_access.name
  type       = "oidc"

  config = {
    auth_url         = "${local.access.oidc_issuer_url}/authorize"
    certs_url        = "${local.access.oidc_issuer_url}/.well-known/jwks.json"
    client_id        = local.access.cloudflare_access.oidc_client_id
    client_secret    = local.cloudflare_access_client_secret
    email_claim_name = "email"
    pkce_enabled     = true
    scopes           = ["openid", "profile", "email"]
    token_url        = "${local.access.oidc_issuer_url}/api/oidc/token"
  }

  lifecycle {
    precondition {
      condition     = nonsensitive(try(length(local.cloudflare_access_client_secret), 0) > 0)
      error_message = "Kubelab has not yet published the Pocket ID client secret to the Cloudflare Access item."
    }
  }
}

resource "cloudflare_zero_trust_access_policy" "bypass" {
  account_id = data.cloudflare_account.default.id
  decision   = "bypass"
  name       = "Bypass"

  include = [
    {
      everyone = {}
    },
  ]
}

resource "cloudflare_zero_trust_access_policy" "fly" {
  account_id = data.cloudflare_account.default.id
  decision   = "non_identity"
  name       = "Gatus"

  include = [
    {
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.fly.id
      }
    },
  ]
}

resource "cloudflare_zero_trust_access_policy" "pocket_id" {
  account_id = data.cloudflare_account.default.id
  decision   = "allow"
  name       = local.access.cloudflare_access.name

  # Each Pocket ID client's user group decides who can sign in.
  include = [
    {
      login_method = {
        id = cloudflare_zero_trust_access_identity_provider.pocket_id.id
      }
    },
  ]
}

resource "cloudflare_zero_trust_access_service_token" "fly" {
  account_id = data.cloudflare_account.default.id
  duration   = "forever"
  name       = "fly"
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  config_src = "cloudflare"
  name       = each.key
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "cluster" {
  for_each = local.cloudflare_consumers_tunnel

  account_id = data.cloudflare_account.default.id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.cluster[each.key].id

  config = {
    ingress = each.value.ingress
  }
}

resource "cloudflare_zone_dnssec" "configured" {
  for_each = local.cloudflare_zones

  status  = "active"
  zone_id = data.cloudflare_zone.configured[each.key].zone_id
}

resource "cloudflare_zone_setting" "configured" {
  for_each = local.cloudflare_zone_settings

  setting_id = each.value.setting
  value      = each.value.value
  zone_id    = data.cloudflare_zone.configured[each.value.zone].zone_id
}
