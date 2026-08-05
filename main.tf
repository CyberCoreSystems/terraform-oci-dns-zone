# OCI DNS: a PRIMARY zone (public global or private view-scoped) with its record
# sets, plus optional traffic-management steering policies (failover / geo /
# load-balance) backed by HTTP health-check monitors.
#
# Secure by default:
# - PRIMARY zones only — OCI is the source of truth; no SECONDARY zone pulling
#   from an external (and harder-to-trust) master.
# - DNSSEC is enabled by default on public zones (origin authentication).
# - Private zones are scoped to a view (resolvable only inside the bound VCNs),
#   not exposed to the internet.
# - Steering policies must be attached to a domain to take effect; attachment
#   ordering (policy -> attachment) is handled by explicit dependencies so the
#   "attachment before answers exist" trap is avoided.

locals {
  is_public  = var.scope == "GLOBAL"
  is_private = var.scope == "PRIVATE"

  # DNSSEC applies to public/global zones; force DISABLED on private zones so the
  # provider does not reject the combination.
  dnssec_state = local.is_public && var.dnssec_enabled ? "ENABLED" : "DISABLED"
}

resource "oci_dns_zone" "this" {
  compartment_id = var.compartment_id
  name           = var.zone_name
  zone_type      = "PRIMARY"
  scope          = var.scope
  view_id        = local.is_private ? var.view_id : null
  dnssec_state   = local.dnssec_state

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  lifecycle {
    precondition {
      condition     = !local.is_private || var.view_id != null
      error_message = "A PRIVATE zone requires view_id (the OCID of the private view that scopes resolution to its bound VCNs)."
    }
  }
}

# Record sets keyed "<domain>/<rtype>". rdata is a list so a single RRSet can
# hold multiple records (e.g. several A records for round-robin).
resource "oci_dns_rrset" "this" {
  for_each = var.record_sets

  zone_name_or_id = oci_dns_zone.this.id
  domain          = each.value.domain
  rtype           = each.value.rtype
  scope           = var.scope
  view_id         = local.is_private ? var.view_id : null

  dynamic "items" {
    for_each = each.value.records
    content {
      domain = each.value.domain
      rtype  = each.value.rtype
      ttl    = items.value.ttl
      rdata  = items.value.rdata
    }
  }
}

# HTTP/HTTPS health-check monitors that feed liveness data to steering policies.
resource "oci_health_checks_http_monitor" "this" {
  for_each = var.health_check_monitors

  compartment_id      = var.compartment_id
  display_name        = coalesce(each.value.display_name, each.key)
  interval_in_seconds = each.value.interval_in_seconds
  protocol            = each.value.protocol
  targets             = each.value.targets

  is_enabled         = true
  method             = each.value.method
  path               = each.value.path
  port               = each.value.port
  timeout_in_seconds = each.value.timeout_in_seconds

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags
}

# Traffic-management steering policies (FAILOVER / LOAD_BALANCE / ROUTE_BY_GEO /
# ROUTE_BY_ASN / ROUTE_BY_IP / CUSTOM). Optionally health-gated by a monitor.
resource "oci_dns_steering_policy" "this" {
  for_each = var.steering_policies

  compartment_id          = var.compartment_id
  display_name            = coalesce(each.value.display_name, each.key)
  template                = each.value.template
  ttl                     = each.value.ttl
  health_check_monitor_id = each.value.health_check_monitor_key == null ? null : oci_health_checks_http_monitor.this[each.value.health_check_monitor_key].id

  freeform_tags = var.freeform_tags
  defined_tags  = var.defined_tags

  dynamic "answers" {
    for_each = each.value.answers
    content {
      name        = answers.value.name
      rtype       = answers.value.rtype
      rdata       = answers.value.rdata
      pool        = answers.value.pool
      is_disabled = answers.value.is_disabled
    }
  }

  dynamic "rules" {
    for_each = each.value.rules
    content {
      rule_type     = rules.value.rule_type
      description   = rules.value.description
      default_count = rules.value.default_count

      dynamic "default_answer_data" {
        for_each = rules.value.default_answer_data
        content {
          answer_condition = default_answer_data.value.answer_condition
          should_keep      = default_answer_data.value.should_keep
          value            = default_answer_data.value.value
        }
      }

      dynamic "cases" {
        for_each = rules.value.cases
        content {
          case_condition = cases.value.case_condition
          count          = cases.value.count

          dynamic "answer_data" {
            for_each = cases.value.answer_data
            content {
              answer_condition = answer_data.value.answer_condition
              should_keep      = answer_data.value.should_keep
              value            = answer_data.value.value
            }
          }
        }
      }
    }
  }
}

# Attach each steering policy to a domain in a public zone. Attachment depends
# on the policy resource (which carries its answers) so the policy is fully
# formed before the attachment references it — the documented ordering trap.
resource "oci_dns_steering_policy_attachment" "this" {
  for_each = var.steering_policies

  steering_policy_id = oci_dns_steering_policy.this[each.key].id
  zone_id            = oci_dns_zone.this.id
  domain_name        = each.value.domain_name
  display_name       = coalesce(each.value.display_name, each.key)

  lifecycle {
    precondition {
      condition     = local.is_public
      error_message = "Steering policy attachments require a public (GLOBAL scope) zone. Steering policy \"${each.key}\" cannot attach to a PRIVATE zone."
    }
  }
}
