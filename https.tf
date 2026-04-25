# HTTPS Load Balancer Resources
# GKE Ingress controller doesn't reliably create HTTPS resources when using
# Certificate Manager certificate maps, so we create them explicitly.

# Wait for GKE Ingress controller to create the URL map
resource "time_sleep" "wait_for_ingress" {
  depends_on = [kubernetes_ingress_v1.app]

  create_duration = "120s"

  triggers = {
    ingress_name = kubernetes_ingress_v1.app.metadata[0].name
  }
}

# Get the URL map name from GKE Ingress controller annotations
# Waits and retries until the annotation is available
data "external" "ingress_url_map" {
  program = ["bash", "-c", <<-EOT
    # Use gcloud to get credentials for the correct cluster
    gcloud container clusters get-credentials "${var.cluster_name}" --region "${var.region}" --project "${var.project_id}" 2>/dev/null

    for i in {1..30}; do
      URL_MAP=$(kubectl get ingress ${var.product}-ingress -n ${var.product} -o jsonpath='{.metadata.annotations.ingress\.kubernetes\.io/url-map}' 2>/dev/null)
      if [ -n "$URL_MAP" ]; then
        echo "{\"url_map\": \"$URL_MAP\"}"
        exit 0
      fi
      sleep 10
    done
    echo '{"error": "URL map annotation not found after 5 minutes"}' >&2
    exit 1
  EOT
  ]

  depends_on = [time_sleep.wait_for_ingress]
}

# HTTPS Target Proxy using Certificate Manager certificate map
# References the URL map created by GKE Ingress controller
resource "google_compute_target_https_proxy" "app" {
  name            = "${var.cluster_name}-https-proxy"
  url_map         = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/urlMaps/${data.external.ingress_url_map.result.url_map}"
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.app.id}"

  depends_on = [
    time_sleep.wait_for_ingress,
    google_certificate_manager_certificate_map_entry.app
  ]

  lifecycle {
    # URL map name may change if Ingress is recreated
    create_before_destroy = true
  }
}

# HTTPS Forwarding Rule (port 443)
resource "google_compute_global_forwarding_rule" "app_https" {
  name                  = "${var.cluster_name}-https"
  target                = google_compute_target_https_proxy.app.id
  ip_address            = google_compute_global_address.app_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL"

  depends_on = [google_compute_target_https_proxy.app]
}
