locals {
  _dns_model_urls = distinct(concat(
    flatten([
      for service in values(local.services_input_targets) : [
        for url in service.routing.urls : url.url
        if url.url != null
      ]
    ]),
    flatten([
      for server in values(local.servers_input) : [
        for url in server.routing.urls : url.url
      ]
    ]),
  ))

  # Longest matching zone wins for nested domains.
  _dns_model_zones_matching = {
    for url in local._dns_model_urls : url => [
      for zone in keys(local.dns_input) : {
        length = length(zone)
        name   = zone
      }
      if(
        url == zone ||
        endswith(url, ".${zone}")
      )
    ]
  }

  dns_model_managed_zones_by_url = {
    for url, matches in local._dns_model_zones_matching : url => try(
      one([for match in matches : match.name if match.length == max(matches[*].length...)]),
      null,
    )
  }
}
