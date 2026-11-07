import {
  to = truenas_init_script.host["kimbap/crucial-x9-trim"]
  id = "1"
}

moved {
  from = talos_machine_configuration_apply.container["bento"]
  to   = talos_machine_configuration_apply.node["bento"]
}
