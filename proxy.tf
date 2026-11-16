locals {
  host_files = {
    for name in setunion(toset(keys(local.cloudflare_tunnel_files)), toset(keys(local.proxy_files))) : name => merge(
      try(local.cloudflare_tunnel_files[name], {}),
      try(local.proxy_files[name], {}),
    )
  }

  proxy_files = {
    for name, machine in local.proxy_machines : name => merge({
      "/etc/homelab/proxy/Caddyfile" = {
        content = templatefile("${path.module}/templates/proxy/Caddyfile.tftpl", {
          challenge_hostname = local.cloudflare_consumers_acme[name].target_hostname
          services           = local.proxy_services[name]
        })
        mode = "0644"
      }
      "/etc/homelab/proxy/Containerfile" = {
        content = templatefile("${path.module}/templates/proxy/Containerfile.tftpl", {
          caddy      = local.versions.caddy
          cloudflare = local.versions.caddy_cloudflare
        })
        mode = "0644"
      }
      "/etc/homelab/proxy/fnox.toml" = {
        # fnox uses op:// references, which cannot express ':' in item titles.
        content = <<-TOML
          [secrets]
          # Cloudflare ACME DNS: ${local.machine_fqdns[name]}
          CLOUDFLARE_API_TOKEN = { provider = "homelab", value = "${onepassword_item.cloudflare_acme[name].uuid}/password" }
          # ${local.machine_login_titles[name]}
          SYNCTHING_PASSWORD = { provider = "homelab", value = "${onepassword_item.machine_access[name].uuid}/password" }
        TOML
        mode    = "0644"
      }
      "/etc/homelab/proxy/create-secret.sh" = {
        content = file("${path.module}/templates/proxy/create-secret.sh")
        mode    = "0755"
      }
      "/etc/containers/systemd/users/${machine.uid}/caddy.build" = {
        content = <<-UNIT
          [Build]
          File=/etc/homelab/proxy/Containerfile
          ImageTag=localhost/homelab-caddy:${local.versions.caddy}
          SetWorkingDirectory=/etc/homelab/proxy

          [Service]
          TimeoutStartSec=900
        UNIT
        mode    = "0644"
      }
      "/etc/containers/systemd/users/${machine.uid}/caddy.container" = {
        content = file("${path.module}/templates/proxy/caddy.container")
        mode    = "0644"
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
      }, can(local.proxy_services[name].dsh) ? {
      "/etc/systemd/user/dsh.service" = {
        content = <<-UNIT
          [Unit]
          Description=DeepSeek Harness

          [Service]
          Environment=PATH=%h/.local/share/mise/shims:/usr/local/bin:/usr/bin
          ExecStart=/usr/bin/mise run dsh:serve -- --host 127.0.0.1 --port ${regex(":([0-9]+)$", local.proxy_services[name].dsh.upstream)[0]} --public-url ${local.machine_service_urls["${name}/dsh"]}/ --trusted-host ${local.proxy_services[name].dsh.hostname}
          Restart=on-failure
          RuntimeDirectory=dsh
          RuntimeDirectoryMode=0700
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
