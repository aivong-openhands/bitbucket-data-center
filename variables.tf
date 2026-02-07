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

variable "vpc_network" {
  description = "The name of the VPC network to deploy the instance into."
  type        = string
}

variable "cluster_name" {
  description = "The name of the bitbucket data center GKE cluster."
  type        = string
  default     = "bitbucket"
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

# Bitbucket Data Center Helm Chart variables
variable "bitbucket_version" {
  description = "The Bitbucket Data Center version to deploy"
  type        = string
  default     = "9.4"
}

variable "bitbucket_helm_chart_version" {
  description = "The version of the Atlassian Bitbucket Helm chart"
  type        = string
  default     = "1.22.0"
}

variable "bitbucket_replicas" {
  description = "Number of Bitbucket replicas"
  type        = number
  default     = 1
}

variable "storage_class" {
  description = "Kubernetes storage class for persistent volumes"
  type        = string
  default     = "standard-rwo"
}

variable "bitbucket_storage_size" {
  description = "Storage size for Bitbucket local home"
  type        = string
  default     = "50Gi"
}

variable "bitbucket_shared_storage_size" {
  description = "Storage size for Bitbucket shared home"
  type        = string
  default     = "50Gi"
}

variable "bitbucket_cpu_request" {
  description = "CPU request for Bitbucket container"
  type        = string
  default     = "1"
}

variable "bitbucket_cpu_limit" {
  description = "CPU limit for Bitbucket container"
  type        = string
  default     = "2"
}

variable "bitbucket_memory_request" {
  description = "Memory request for Bitbucket container"
  type        = string
  default     = "4Gi"
}

variable "bitbucket_memory_limit" {
  description = "Memory limit for Bitbucket container"
  type        = string
  default     = "6Gi"
}

variable "bitbucket_jvm_min_heap" {
  description = "JVM minimum heap size"
  type        = string
  default     = "2g"
}

variable "bitbucket_jvm_max_heap" {
  description = "JVM maximum heap size"
  type        = string
  default     = "4g"
}

variable "dns_name" {
  description = "DNS name for Bitbucket (e.g., bitbucket.example.com.). Used for Google-managed SSL certificate."
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "The name of the Cloud DNS managed zone to create the record in"
  type        = string
  default     = ""
}
