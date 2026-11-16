locals {
  host_files = {
    for name in setunion(toset(keys(local.cloudflare_tunnel_files)), toset(keys(local.proxy_files))) : name => merge(
      try(local.cloudflare_tunnel_files[name], {}),
      try(local.proxy_files[name], {}),
    )
  }

  proxy_configurations = {
    for name, machine in local.proxy_machines : name => {
      static = {
        entryPoints = { websecure = { address = "127.0.0.1:8443" } }
        log         = { format = "json" }
        providers   = { file = { filename = "/etc/traefik/routes.yaml", watch = true } }
        certificatesResolvers = {
          cloudflare = {
            acme = {
              storage = "/data/acme.json"
              dnsChallenge = {
                provider  = "cloudflare"
                resolvers = ["1.1.1.1:53", "1.0.0.1:53"]
              }
            }
          }
        }
      }
      routes = {
        http = {
          routers = {
            for service_name, service in local.proxy_services[name] : service_name => {
              entryPoints = ["websecure"]
              rule        = "Host(`${service.hostname}`)"
              service     = service_name
              tls         = { certResolver = "cloudflare" }
            }
          }
          services = {
            for service_name, service in local.proxy_services[name] : service_name => {
              loadBalancer = merge(
                { servers = [{ url = service.upstream }] },
                service_name == "syncthing" ? { passHostHeader = false } : {},
                service_name == "dsh" ? { serversTransport = "dsh" } : {},
              )
            }
          }
          serversTransports = can(local.proxy_services[name].dsh) ? {
            dsh = { serverName = "localhost", rootCAs = [local.proxy_dsh_ca_path] }
          } : {}
        }
      }
    }
  }

  proxy_dsh_ca_path = "/etc/traefik-dsh.crt"

  proxy_files = {
    for name, machine in local.proxy_machines : name => merge({
      "/etc/homelab/proxy/traefik/traefik.json" = {
        content = jsonencode(local.proxy_configurations[name].static)
        mode    = "0644"
      }
      "/etc/homelab/proxy/traefik/routes.yaml" = {
        content = yamlencode(local.proxy_configurations[name].routes)
        mode    = "0644"
      }
      "/etc/homelab/proxy/fnox.toml" = {
        # fnox uses op:// references, which cannot express ':' in item titles.
        content = <<-TOML
          [secrets]
          # Cloudflare ACME DNS: ${local.machine_fqdns[name]}
          CF_DNS_API_TOKEN = { provider = "homelab", value = "${onepassword_item.cloudflare_acme[name].uuid}/password" }
          # ${local.machine_login_titles[name]}
          SYNCTHING_PASSWORD = { provider = "homelab", value = "${onepassword_item.machine_access[name].uuid}/password" }
        TOML
        mode    = "0644"
      }
      "/etc/homelab/proxy/create-secret.sh" = {
        content = file("${path.module}/data/hosts/common/create-secret.sh")
        mode    = "0755"
      }
      "/etc/containers/systemd/users/${machine.uid}/traefik.container" = {
        content = templatefile("${path.module}/data/hosts/common/traefik.container.tftpl", {
          image  = local.versions.images.traefik
          dsh    = can(local.proxy_services[name].dsh)
          dsh_ca = local.proxy_dsh_ca_path
        })
        mode = "0644"
      }
      "/etc/systemd/system/homelab-proxy.service" = {
        content = file("${path.module}/data/hosts/common/homelab-proxy.service")
        mode    = "0644"
      }
      }, can(local.proxy_services[name]["agent-browser"]) ? {
      "/etc/containers/systemd/users/${machine.uid}/browserless.container" = {
        content = templatefile("${path.module}/data/hosts/common/browserless.container.tftpl", {
          image = local.versions.images.browserless
          port  = regex(":([0-9]+)$", local.proxy_services[name]["agent-browser"].browser_upstream)[0]
        })
        mode = "0644"
      }
      "/etc/homelab/proxy/agent-browser.json" = {
        content = jsonencode({ cdp = "${replace(local.proxy_services[name]["agent-browser"].browser_upstream, "http://", "ws://")}/chromium" })
        mode    = "0644"
      }
      "/etc/systemd/user/agent-browser.service" = {
        content = templatefile("${path.module}/data/hosts/common/agent-browser.service.tftpl", {
          port = regex(":([0-9]+)$", local.proxy_services[name]["agent-browser"].upstream)[0]
          url  = local.machine_service_urls["${name}/agent-browser"]
        })
        mode = "0644"
      }
      } : {}, can(local.proxy_services[name].dsh) ? {
      "/etc/homelab/proxy/dsh-tls.sh" = {
        content = file("${path.module}/data/hosts/common/dsh-tls.sh")
        mode    = "0755"
      }
      "/etc/systemd/user/dsh.service" = {
        content = templatefile("${path.module}/data/hosts/common/dsh.service.tftpl", {
          hostname = local.proxy_services[name].dsh.hostname
          port     = regex(":([0-9]+)$", local.proxy_services[name].dsh.upstream)[0]
          url      = local.machine_service_urls["${name}/dsh"]
        })
        mode = "0644"
      }
      } : {}, can(local.proxy_services[name].syncthing) ? {
      "/etc/systemd/system/syncthing@${machine.username}.service.d/authentication.conf" = {
        content = templatefile("${path.module}/data/hosts/common/syncthing-authentication.conf.tftpl", {
          username = machine.username
        })
        mode = "0644"
      }
      "/etc/homelab/proxy/syncthing-auth.sh" = {
        content = file("${path.module}/data/hosts/common/syncthing-auth.sh")
        mode    = "0755"
      }
    } : {})
  }

  proxy_machines = {
    for name, machine in local.machines : name => machine
    if length(local.proxy_services[name]) > 0
  }

  proxy_services = {
    for name, machine in local.machines : name => {
      for service_name, service in machine.services : service_name => service
      if can(service.upstream)
    }
  }
}
