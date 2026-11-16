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
          BROWSERLESS_TOKEN = { provider = "automation", value = "Browserless/${name}" }
        TOML
        mode    = "0644"
      }
      "/etc/homelab/proxy/create-secret.sh" = {
        content = file("${path.module}/templates/proxy/create-secret.sh")
        mode    = "0755"
      }
      "/etc/containers/systemd/users/${machine.uid}/traefik.container" = {
        content = templatefile("${path.module}/templates/proxy/traefik.container.tftpl", {
          image  = local.versions.images.traefik
          dsh    = can(local.proxy_services[name].dsh)
          dsh_ca = local.proxy_dsh_ca_path
        })
        mode = "0644"
      }
      "/etc/systemd/system/homelab-proxy.service" = {
        content = <<-UNIT
          [Unit]
          After=tailscaled.service
          Requires=tailscaled.service

          [Service]
          Type=oneshot
          ExecStart=/usr/bin/tailscale serve --bg --tcp=443 tcp://127.0.0.1:8443
          ExecStop=/usr/bin/tailscale serve --tcp=443 off
          RemainAfterExit=yes

          [Install]
          WantedBy=multi-user.target
        UNIT
        mode    = "0644"
      }
      }, can(local.proxy_services[name].browserless) ? {
      "/etc/containers/systemd/users/${machine.uid}/browserless.container" = {
        content = templatefile("${path.module}/templates/proxy/browserless.container.tftpl", {
          image = local.versions.images.browserless
          port  = regex(":([0-9]+)$", local.proxy_services[name].browserless.upstream)[0]
          url   = local.machine_service_urls["${name}/browserless"]
        })
        mode = "0644"
      }
      "/etc/homelab/proxy/browserless.json" = {
        content = jsonencode({ upstream = local.proxy_services[name].browserless.upstream })
        mode    = "0644"
      }
      "/etc/homelab/proxy/prepare_browserless.py" = {
        content = file("${path.module}/templates/proxy/prepare_browserless.py")
        mode    = "0644"
      }
      } : {}, can(local.proxy_services[name].dsh) ? {
      "/etc/homelab/proxy/dsh-tls.sh" = {
        content = file("${path.module}/templates/proxy/dsh-tls.sh")
        mode    = "0755"
      }
      "/etc/systemd/user/dsh.service" = {
        content = <<-UNIT
          [Unit]
          Description=DeepSeek Harness

          [Service]
          Environment=PATH=%h/.local/share/mise/shims:/usr/local/bin:/usr/bin
          ExecStartPre=/etc/homelab/proxy/dsh-tls.sh
          ExecStart=/usr/bin/mise run dsh:serve -- --host 127.0.0.1 --port ${regex(":([0-9]+)$", local.proxy_services[name].dsh.upstream)[0]} --public-url ${local.machine_service_urls["${name}/dsh"]}/ --trusted-host ${local.proxy_services[name].dsh.hostname} --tls-cert %S/dsh/server.crt --tls-key %S/dsh/server.key
          Restart=on-failure
          RuntimeDirectory=dsh
          RuntimeDirectoryMode=0700
          StateDirectory=dsh
          StateDirectoryMode=0700
          UMask=0077
          WorkingDirectory=%h

          [Install]
          WantedBy=default.target
        UNIT
        mode    = "0644"
      }
      } : {}, can(local.proxy_services[name].syncthing) ? {
      "/etc/systemd/system/syncthing@${machine.username}.service.d/authentication.conf" = {
        content = <<-UNIT
          [Service]
          Environment=PATH=/var/home/${machine.username}/.local/share/mise/shims:/usr/local/bin:/usr/bin
          ExecStartPre=/var/home/${machine.username}/.local/share/mise/shims/fnox exec --config /etc/homelab/proxy/fnox.toml --only SYNCTHING_PASSWORD -- /etc/homelab/proxy/syncthing-auth.sh ${machine.username}
        UNIT
        mode    = "0644"
      }
      "/etc/homelab/proxy/syncthing-auth.sh" = {
        content = file("${path.module}/templates/proxy/syncthing-auth.sh")
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
