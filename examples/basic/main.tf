terraform {
  required_version = ">= 1.6"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.0, < 9.0"
    }
  }
}

provider "oci" {
  region           = "us-ashburn-1"
  tenancy_ocid     = "ocid1.tenancy.oc1..aaaaaaaaexampleexampleexampleexampleexampleexampleexampleexa"
  user_ocid        = "ocid1.user.oc1..aaaaaaaaexampleexampleexampleexampleexampleexampleexampleexa"
  fingerprint      = "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff"
  private_key_path = "~/.oci/example_api_key.pem"
}

module "dns_zone" {
  source = "../../"

  compartment_id = "ocid1.compartment.oc1..aaaaaaaaexampleexampleexampleexampleexampleexampleexampleexa"
  zone_name      = "example.com"
  scope          = "GLOBAL"
  dnssec_enabled = true

  record_sets = {
    apex_a = {
      domain = "example.com"
      rtype  = "A"
      records = [
        { ttl = 300, rdata = "203.0.113.10" },
        { ttl = 300, rdata = "203.0.113.11" },
      ]
    }
    www_cname = {
      domain  = "www.example.com"
      rtype   = "CNAME"
      records = [{ ttl = 300, rdata = "example.com." }]
    }
  }

  health_check_monitors = {
    primary = {
      targets  = ["203.0.113.10"]
      protocol = "HTTPS"
      path     = "/healthz"
      port     = 443
    }
  }

  steering_policies = {
    failover = {
      template                 = "FAILOVER"
      domain_name              = "app.example.com"
      health_check_monitor_key = "primary"

      answers = [
        { name = "primary", rtype = "A", rdata = "203.0.113.10", pool = "us-east" },
        { name = "backup", rtype = "A", rdata = "203.0.113.20", pool = "us-west" },
      ]

      rules = [
        {
          rule_type = "HEALTH"
        },
        {
          rule_type     = "PRIORITY"
          default_count = 1
          default_answer_data = [
            { answer_condition = "answer.pool == 'us-east'", value = 1 },
            { answer_condition = "answer.pool == 'us-west'", value = 2 },
          ]
        },
        {
          rule_type     = "LIMIT"
          default_count = 1
        },
      ]
    }
  }

  freeform_tags = {
    environment = "example"
    managed_by  = "iac-bazaar"
  }
}

output "zone_id" {
  value = module.dns_zone.zone_id
}

output "zone_nameservers" {
  value = module.dns_zone.zone_nameservers
}
