output "zone_id" {
  description = "OCID of the DNS zone."
  value       = oci_dns_zone.this.id
}

output "zone_name" {
  description = "Name of the DNS zone."
  value       = oci_dns_zone.this.name
}

output "zone_nameservers" {
  description = "OCI nameservers authoritative for the zone (delegate the parent domain to these for public zones)."
  value       = oci_dns_zone.this.nameservers
}

output "zone_serial" {
  description = "Current SOA serial number of the zone."
  value       = oci_dns_zone.this.serial
}

output "record_set_ids" {
  description = "Map of record set key => RRSet resource id."
  value       = { for k, r in oci_dns_rrset.this : k => r.id }
}

output "health_check_monitor_ids" {
  description = "Map of monitor key => HTTP health-check monitor OCID."
  value       = { for k, m in oci_health_checks_http_monitor.this : k => m.id }
}

output "steering_policy_ids" {
  description = "Map of steering policy key => OCID."
  value       = { for k, p in oci_dns_steering_policy.this : k => p.id }
}

output "steering_policy_attachment_ids" {
  description = "Map of steering policy key => attachment OCID."
  value       = { for k, a in oci_dns_steering_policy_attachment.this : k => a.id }
}
