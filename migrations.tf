moved {
  from = unifi_client.host["94:54:c5:eb:3f:90"]
  to   = unifi_client.slzb_06m_previous_interface
}

removed {
  from = unifi_client.slzb_06m_previous_interface

  lifecycle {
    destroy = false
  }
}

import {
  to = unifi_client.host["94:54:c5:eb:3f:93"]
  id = "94:54:c5:eb:3f:93"
}
