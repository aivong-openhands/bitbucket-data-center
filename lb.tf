# HTTPS Load Balancer Frontend Configuration
#
# The GKE Ingress controller creates the HTTP frontend automatically, but does NOT
# create the HTTPS frontend when using Certificate Manager via the
# `networking.gke.io/certmap` annotation. We need to create these resources manually.

# Data source to get the URL map created by the GKE Ingress controller
data "google_compute_url_map" "bitbucket_ingress" {
  name    = "k8s2-um-${local.ingress_hash}-bitbucket-bitbucket-ingress-${local.ingress_suffix}"
  project = var.project_id

  depends_on = [kubernetes_ingress_v1.bitbucket]
}

# Local values for constructing GKE-managed resource names
locals {
  # GKE Ingress controller uses a hash of cluster name and UID in resource names
  # We derive these from the existing resources to ensure consistency
  ingress_hash   = substr(sha256(google_container_cluster.primary.id), 0, 8)
  ingress_suffix = substr(sha256("${kubernetes_namespace.bitbucket.metadata[0].name}/${kubernetes_ingress_v1.bitbucket.metadata[0].name}"), 0, 8)
}

# HTTPS Target Proxy with Certificate Manager certificate map
resource "google_compute_target_https_proxy" "bitbucket" {
  name             = "${var.cluster_name}-bitbucket-https-proxy"
  url_map          = data.google_compute_url_map.bitbucket_ingress.id
  certificate_map  = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.bitbucket.id}"

  depends_on = [
    kubernetes_ingress_v1.bitbucket,
    google_certificate_manager_certificate_map_entry.bitbucket
  ]
}

# HTTPS Forwarding Rule (port 443)
resource "google_compute_global_forwarding_rule" "bitbucket_https" {
  name                  = "${var.cluster_name}-bitbucket-https"
  ip_address            = google_compute_global_address.bitbucket_ip.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.bitbucket.id
  load_balancing_scheme = "EXTERNAL"
}
