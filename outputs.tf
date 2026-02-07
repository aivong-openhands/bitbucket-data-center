output "bitbucket_url" {
  description = "The HTTPS URL to access Bitbucket"
  value       = "https://${local.bitbucket_domain}"
}
