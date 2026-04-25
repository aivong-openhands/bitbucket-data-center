output "app_url" {
  description = "The HTTPS URL to access the Atlassian Data Center product"
  value       = "https://${local.app_domain}"
}

output "database_private_ip" {
  description = "The private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.private_ip_address
}
