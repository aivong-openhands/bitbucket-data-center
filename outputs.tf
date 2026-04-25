output "bitbucket_url" {
  description = "The HTTPS URL to access Bitbucket"
  value       = "https://${local.bitbucket_domain}"
}

output "database_private_ip" {
  description = "The private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.private_ip_address
}
