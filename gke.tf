resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  network  = data.google_compute_network.vpc-network.name

  # Remove the default node pool after creation, we'll use a separately managed pool
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false

  # Enable public endpoint access
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = false
  }

  # Authorize specific IPs to access the control plane
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = true

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      env = var.cluster_name
    }
  }
}
