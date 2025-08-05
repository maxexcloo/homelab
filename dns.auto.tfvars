# Non-sensitive DNS configuration
# This file contains DNS records for all managed zones and is safe to commit to version control

dns = {
  "bestmates.xyz" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "excloo.com" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    },
    {
      content = "fm1.excloo.com.dkim.fmhosted.com"
      name    = "fm1._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm2.excloo.com.dkim.fmhosted.com"
      name    = "fm2._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm3.excloo.com.dkim.fmhosted.com"
      name    = "fm3._domainkey"
      type    = "CNAME"
    },
    {
      content  = "in1-smtp.messagingengine.com"
      name     = "@"
      priority = 10
      type     = "MX"
    },
    {
      content  = "in2-smtp.messagingengine.com"
      name     = "@"
      priority = 20
      type     = "MX"
    },
    {
      content  = "feedback-smtp.us-east-1.amazonses.com"
      name     = "send"
      priority = 10
      type     = "MX"
    },
    {
      content = "\"v=spf1 include:spf.messagingengine.com ?all\""
      name    = "@"
      type    = "TXT"
    },
    {
      content = "\"8140efead95e8b57bc46473cbddae9\""
      name    = "_github-pages-challenge-maxexcloo"
      type    = "TXT"
    },
    {
      content = "\"p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDdgw27bzhJ1V0FrqOpjq/ZuxwIzr24Mp2fktwTkgy0Yr51ii/HKerJ0KtC5GYznPJLeq6QSwO67dQV7++3OuMjWVRtxQPAQarHcYIcwSH4QizUih3qvTjxgdqhzFt46eiW4orLJ5W0D2nv16C9fmbpfIeNXzfUPuf3grjaF0MqUQIDAQAB\""
      name    = "resend._domainkey"
      type    = "TXT"
    },
    {
      content = "\"v=spf1 include:amazonses.com ~all\""
      name    = "send"
      type    = "TXT"
    }
  ]
  "excloo.dev" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "excloo.net" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "excloo.org" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "maxexcloo.com" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "schaefer.au" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    },
    {
      content = "fm1.schaefer.au.dkim.fmhosted.com"
      name    = "fm1._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm2.schaefer.au.dkim.fmhosted.com"
      name    = "fm2._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm3.schaefer.au.dkim.fmhosted.com"
      name    = "fm3._domainkey"
      type    = "CNAME"
    },
    {
      content  = "in1-smtp.messagingengine.com"
      name     = "@"
      priority = 10
      type     = "MX"
    },
    {
      content  = "in2-smtp.messagingengine.com"
      name     = "@"
      priority = 20
      type     = "MX"
    },
    {
      content = "\"v=spf1 include:spf.messagingengine.com ?all\""
      name    = "@"
      type    = "TXT"
    }
  ]
}
