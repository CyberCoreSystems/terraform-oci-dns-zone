variable "compartment_id" {
  description = "OCID of the compartment that owns the zone, monitors and steering policies."
  type        = string

  validation {
    condition     = can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_id))
    error_message = "compartment_id must be a compartment or tenancy OCID (ocid1.compartment.* / ocid1.tenancy.*)."
  }
}

variable "zone_name" {
  description = "Fully-qualified zone name (e.g. \"example.com\")."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", lower(var.zone_name)))
    error_message = "zone_name must be a valid FQDN (e.g. example.com)."
  }
}

variable "scope" {
  description = "Zone scope: GLOBAL (public, internet-resolvable) or PRIVATE (resolvable only inside the VCNs bound to view_id)."
  type        = string
  default     = "GLOBAL"

  validation {
    condition     = contains(["GLOBAL", "PRIVATE"], var.scope)
    error_message = "scope must be GLOBAL or PRIVATE."
  }
}

variable "view_id" {
  description = "OCID of the private DNS view that scopes a PRIVATE zone to its bound VCNs. Required when scope = PRIVATE; ignored for GLOBAL zones."
  type        = string
  default     = null

  validation {
    condition     = var.view_id == null || can(regex("^ocid1\\.dnsview\\.", var.view_id))
    error_message = "view_id must be a DNS view OCID (ocid1.dnsview.*)."
  }
}

variable "dnssec_enabled" {
  description = "Enable DNSSEC origin authentication on public (GLOBAL) zones. Ignored (forced off) for PRIVATE zones, which do not support DNSSEC."
  type        = bool
  default     = true
}

variable "record_sets" {
  description = "Record sets keyed by logical name. domain is the FQDN; rtype is the record type (A, AAAA, CNAME, MX, TXT, ...); records is a list of { ttl, rdata }."
  type = map(object({
    domain = string
    rtype  = string
    records = list(object({
      ttl   = number
      rdata = string
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.record_sets) : length(r.records) > 0])
    error_message = "Every record_sets entry must contain at least one record."
  }

  validation {
    condition     = alltrue([for r in values(var.record_sets) : alltrue([for rec in r.records : rec.ttl >= 30])])
    error_message = "Record TTLs must be at least 30 seconds (OCI rejects lower values)."
  }
}

variable "health_check_monitors" {
  description = "HTTP health-check monitors keyed by logical name, feeding liveness data to steering policies. protocol is HTTP or HTTPS; interval_in_seconds is 10, 30 or 60; timeout_in_seconds is 10, 20, 30 or 60."
  type = map(object({
    targets             = list(string)
    protocol            = optional(string, "HTTPS")
    interval_in_seconds = optional(number, 30)
    timeout_in_seconds  = optional(number, 30)
    method              = optional(string, "GET")
    path                = optional(string, "/")
    port                = optional(number)
    display_name        = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for m in values(var.health_check_monitors) : contains(["HTTP", "HTTPS"], m.protocol)])
    error_message = "Monitor protocol must be HTTP or HTTPS."
  }

  validation {
    condition     = alltrue([for m in values(var.health_check_monitors) : contains([10, 30, 60], m.interval_in_seconds)])
    error_message = "Monitor interval_in_seconds must be 10, 30 or 60."
  }

  validation {
    condition     = alltrue([for m in values(var.health_check_monitors) : contains([10, 20, 30, 60], m.timeout_in_seconds)])
    error_message = "Monitor timeout_in_seconds must be 10, 20, 30 or 60."
  }

  validation {
    condition     = alltrue([for m in values(var.health_check_monitors) : length(m.targets) > 0])
    error_message = "Every monitor must list at least one target (hostname or IP)."
  }
}

variable "steering_policies" {
  description = "Traffic-management steering policies keyed by logical name. template is FAILOVER / LOAD_BALANCE / ROUTE_BY_GEO / ROUTE_BY_ASN / ROUTE_BY_IP / CUSTOM. health_check_monitor_key references health_check_monitors. domain_name is the public-zone domain the policy attaches to. answers and rules follow the OCI steering-policy model."
  type = map(object({
    template                 = string
    domain_name              = string
    ttl                      = optional(number, 30)
    health_check_monitor_key = optional(string)
    display_name             = optional(string)
    answers = optional(list(object({
      name        = string
      rtype       = string
      rdata       = string
      pool        = optional(string)
      is_disabled = optional(bool, false)
    })), [])
    rules = optional(list(object({
      rule_type     = string
      description   = optional(string)
      default_count = optional(number)
      default_answer_data = optional(list(object({
        answer_condition = optional(string)
        should_keep      = optional(bool, false)
        value            = optional(number)
      })), [])
      cases = optional(list(object({
        case_condition = optional(string)
        count          = optional(number)
        answer_data = optional(list(object({
          answer_condition = optional(string)
          should_keep      = optional(bool, false)
          value            = optional(number)
        })), [])
      })), [])
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in values(var.steering_policies) :
      contains(["FAILOVER", "LOAD_BALANCE", "ROUTE_BY_GEO", "ROUTE_BY_ASN", "ROUTE_BY_IP", "CUSTOM"], p.template)
    ])
    error_message = "Every steering policy template must be FAILOVER, LOAD_BALANCE, ROUTE_BY_GEO, ROUTE_BY_ASN, ROUTE_BY_IP or CUSTOM."
  }

  validation {
    condition = alltrue([
      for p in values(var.steering_policies) :
      alltrue([for a in p.answers : contains(["A", "AAAA", "CNAME"], a.rtype)])
    ])
    error_message = "Steering policy answer rtype must be A, AAAA or CNAME."
  }

  validation {
    condition = alltrue([
      for p in values(var.steering_policies) :
      p.health_check_monitor_key == null || contains(keys(var.health_check_monitors), p.health_check_monitor_key)
    ])
    error_message = "Every steering_policies.health_check_monitor_key must reference a key declared in health_check_monitors."
  }
}

variable "freeform_tags" {
  description = "Freeform tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}

variable "defined_tags" {
  description = "Defined tags (\"Namespace.Key\" = value) applied to every resource."
  type        = map(string)
  default     = {}
}
