locals {
  # Merge schema defaults into each source service before expanding targets.
  services_input = {
    for service_key, service in {
      for file_path in fileset(path.module, "data/services/*.yml") :
      trimsuffix(basename(file_path), ".yml") => yamldecode(file("${path.module}/${file_path}"))
    } : service_key => provider::deepmerge::mergo(local.defaults_service, service)
  }

  # Each entry in `targets` becomes its own stack, so target-specific secrets
  # and rendered files have stable addresses like service-target. Per-target
  # platform sections (container, fly, truenas) are flattened to the top level
  # with target_defaults and service-level base merged in (target wins);
  # per-target feature overrides layer on top of the service-level features.
  services_input_targets = merge([
    for service_key, service in local.services_input : {
      for target_key, target_config in service.targets : "${service_key}-${target_key}" => merge(
        {
          for key, value in service : key => value
          if !contains(["container", "targets"], key)
        },
        {
          target = target_key

          container = provider::deepmerge::mergo(
            local.defaults_target.container,
            try(service.container, {}),
            try(target_config.container, {}),
          )

          features = merge(
            service.features,
            try(target_config.features, {}),
          )

          fly = provider::deepmerge::mergo(
            local.defaults_target.fly,
            try(target_config.fly, {}),
          )

          truenas = provider::deepmerge::mergo(
            local.defaults_target.truenas,
            try(target_config.truenas, {}),
          )
        },
      )
    }
  ]...)
}
