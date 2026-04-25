variable "project_id" {
  description = "The GCP project ID to deploy to."
  type        = string
  default     = "platform-team-sandbox-62793"
}

variable "region" {
  description = "The GCP region to deploy to."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone to deploy to."
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
  default     = "atlassian"
}

variable "default_labels" {
  description = "Default labels to apply to all resources"
  type        = map(string)
  default = {
    "environment" = "platform-team-sandbox"
    "team"        = "platform"
    "managed-by"  = "terraform"
  }
}

# GKE Node Pool variables
variable "node_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "node_count" {
  description = "Number of nodes in the node pool"
  type        = number
  default     = 1
}

variable "node_disk_size_gb" {
  description = "Disk size in GB for each node"
  type        = number
  default     = 100
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the GKE control plane"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All IPv4"
    }
  ]
}

# Atlassian Data Center Helm Chart variables
variable "product" {
  description = "The Atlassian Data Center product to deploy (jira, confluence, bitbucket, crowd, bamboo)"
  type        = string
  default     = "jira"

  validation {
    condition     = contains(["jira", "confluence", "bitbucket", "crowd", "bamboo"], var.product)
    error_message = "product must be one of: jira, confluence, bitbucket, crowd, bamboo"
  }
}

variable "product_version" {
  description = "The product image tag to deploy"
  type        = string
  default     = ""
}

variable "helm_chart_version" {
  description = "The version of the Atlassian Data Center Helm chart"
  type        = string
  default     = "1.22.0"
}

variable "replicas" {
  description = "Number of product replicas"
  type        = number
  default     = 1
}

variable "storage_class" {
  description = "Kubernetes storage class for persistent volumes"
  type        = string
  default     = "standard-rwo"
}

variable "storage_size" {
  description = "Storage size for product local home"
  type        = string
  default     = "50Gi"
}

variable "shared_storage_size" {
  description = "Storage size for product shared home"
  type        = string
  default     = "50Gi"
}

variable "cpu_request" {
  description = "CPU request for product container"
  type        = string
  default     = "2"
}

variable "cpu_limit" {
  description = "CPU limit for product container"
  type        = string
  default     = "4"
}

variable "memory_request" {
  description = "Memory request for product container"
  type        = string
  default     = "4Gi"
}

variable "memory_limit" {
  description = "Memory limit for product container"
  type        = string
  default     = "6Gi"
}

variable "jvm_min_heap" {
  description = "JVM minimum heap size"
  type        = string
  default     = "384m"
}

variable "jvm_max_heap" {
  description = "JVM maximum heap size"
  type        = string
  default     = "2g"
}

variable "service_port" {
  description = "Override the HTTP port the application listens on (used for health checks). Defaults to the product's standard port."
  type        = number
  default     = null
}

variable "dns_name" {
  description = "DNS name for the product (e.g., jira.example.com.). Used for SSL certificate."
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone to create the record in"
  type        = string
  default     = ""
}

variable "database_version" {
  description = "The database version to use."
  type        = string
  default     = "POSTGRES_16"
}

variable "database_tier" {
  description = "The tier for the database."
  type        = string
  default     = "db-perf-optimized-N-2"
}

variable "database_name" {
  description = "The name of the database."
  type        = string
  default     = "atlassian"
}

variable "database_username" {
  description = "The username of the database."
  type        = string
  default     = "atlassian"
}

variable "database_password" {
  description = "The password of the database."
  type        = string
  default     = "atlassian"
}

variable "acme_email" {
  description = "The email address to use for the ACME account."
  type        = string
}

variable "acme_server" {
  description = "The ACME server URL."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}
