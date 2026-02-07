# Allocate an IP range for private services access (required for private Cloud SQL)
resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.cluster_name}-private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.vpc-network.id
}

resource "google_sql_database_instance" "instance" {
  name             = var.cluster_name
  database_version = var.database_version
  region           = var.region

  settings {
    tier = var.database_tier

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc-network.id
      enable_private_path_for_google_cloud_services = true
    }
  }

  # Note: You must explicitly set deletion_protection=false in a separate `terraform apply` 
  # to destroy the instance and its databases. Recommended to not set this field (or set it to true) 
  # until you are ready to destroy.
  deletion_protection = false
}

resource "google_sql_database" "bitbucket" {
  name     = var.database_name
  instance = google_sql_database_instance.instance.name
}

resource "google_sql_user" "db_user" {
  name     = var.database_name
  instance = google_sql_database_instance.instance.name
  password = var.database_password
}
