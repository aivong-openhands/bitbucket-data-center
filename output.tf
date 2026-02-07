output "database_private_ip" {
  description = "The private IP address of the Cloud SQL instance."
  value       = google_sql_database_instance.instance.private_ip_address
}
