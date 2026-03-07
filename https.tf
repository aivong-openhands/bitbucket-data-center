# HTTPS Load Balancer Resources
# GKE Ingress controller doesn't reliably create HTTPS resources when using
# Certificate Manager certificate maps, so we create them explicitly.

# Wait for GKE Ingress controller to create the URL map
resource "time_sleep" "wait_for_ingress" {
  depends_on = [kubernetes_ingress_v1.bitbucket]

  create_duration = "120s"

  triggers = {
    ingress_name = kubernetes_ingress_v1.bitbucket.metadata[0].name
  }
}

# Get the URL map name from GKE Ingress controller annotations
data "external" "ingress_url_map" {
  program = ["bash", "-c", <<-EOT
    URL_MAP=$(kubectl get ingress bitbucket-ingress -n bitbucket -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/url-map}' 2>/dev/null)
    if [ -z "$URL_MAP" ]; then
      echo '{"url_map": ""}'
    else
      echo "{\"url_map\": \"$URL_MAP\"}"
    fi
  EOT
  ]

  depends_on = [time_sleep.wait_for_ingress]
}

# HTTPS Target Proxy using Certificate Manager certificate map
# References the URL map created by GKE Ingress controller
resource "google_compute_target_https_proxy" "bitbucket" {
  name            = "${var.cluster_name}-bitbucket-https-proxy"
  url_map         = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/urlMaps/${data.external.ingress_url_map.result.url_map}"
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.bitbucket.id}"

  depends_on = [
    time_sleep.wait_for_ingress,
    google_certificate_manager_certificate_map_entry.bitbucket
  ]

  lifecycle {
    # URL map name may change if Ingress is recreated
    create_before_destroy = true
  }
}

# HTTPS Forwarding Rule (port 443)
resource "google_compute_global_forwarding_rule" "bitbucket_https" {
  name                  = "${var.cluster_name}-bitbucket-https"
  target                = google_compute_target_https_proxy.bitbucket.id
  ip_address            = google_compute_global_address.bitbucket_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [google_compute_target_https_proxy.bitbucket]
}
