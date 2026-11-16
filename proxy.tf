locals {
  proxy_dsh_ca_path = "/etc/traefik-dsh.crt"

  host_files = merge(local.cloudflare_tunnel_files, {
    mercury = merge(local.cloudflare_tunnel_files.mercury, local.proxy_files)
  })

  proxy_files = {
    "/etc/containers/systemd/users/${local.proxy_machine.uid}/traefik.container" = {
      content = templatefile("${path.module}/templates/hosts/mercury/traefik.container.tftpl", {
        image  = local.versions.images.traefik
        dsh_ca = local.proxy_dsh_ca_path
      })
      mode = "0644"
    }
    "/etc/homelab/proxy/fnox.toml" = {
      # fnox uses op:// references, which cannot express ':' in item titles.
      content = <<-TOML
        [secrets]
        # Cloudflare ACME DNS: ${local.machine_fqdns.mercury}
        CF_DNS_API_TOKEN = { provider = "homelab", value = "${onepassword_item.cloudflare_acme["mercury"].uuid}/password" }
        # ${local.machine_login_titles.mercury}
        SYNCTHING_PASSWORD = { provider = "homelab", value = "${onepassword_item.machine_access["mercury"].uuid}/password" }
      TOML
      mode    = "0644"
    }
    "/etc/homelab/proxy/traefik/routes.yaml" = {
      content = yamlencode(local.proxy_routes)
      mode    = "0644"
    }
    "/etc/systemd/system/syncthing@${local.proxy_machine.username}.service.d/authentication.conf" = {
      content = templatefile("${path.module}/templates/hosts/mercury/syncthing-authentication.conf.tftpl", {
        username = local.proxy_machine.username
      })
      mode = "0644"
    }
  }

  proxy_machine = local.machines.mercury

  proxy_routes = {
    http = {
      routers = {
        for name, service in local.proxy_services : name => {
          entryPoints = ["websecure"]
          rule        = "Host(`${service.hostname}`)"
          service     = name
          tls         = { certResolver = "cloudflare" }
        }
      }
      services = {
        for name, service in local.proxy_services : name => {
          loadBalancer = merge(
            { servers = [{ url = service.upstream }] },
            name == "syncthing" ? { passHostHeader = false } : {},
            name == "dsh" ? { serversTransport = "dsh" } : {},
          )
        }
      }
      serversTransports = {
        dsh = { serverName = "localhost", rootCAs = [local.proxy_dsh_ca_path] }
      }
    }
  }

  proxy_services = {
    for name, service in local.proxy_machine.services : name => service
    if can(service.upstream)
  }
}
