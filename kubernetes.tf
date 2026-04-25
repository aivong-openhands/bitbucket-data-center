# Namespace for Atlassian Data Center product
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.product
    labels = {
      app        = var.product
      managed-by = "terraform"
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes Secret for database credentials
resource "kubernetes_secret" "app_db_credentials" {
  metadata {
    name      = "${var.product}-db-credentials"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    username = var.database_username
    password = var.database_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.app]
}

# Ingress for HTTP (GKE Ingress controller creates the URL map and backend)
# HTTPS is handled separately via google_compute_target_https_proxy
resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "${var.product}-ingress"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.app_ip.name
      # FrontendConfig for HTTP to HTTPS redirect
      "networking.gke.io/v1beta1.FrontendConfig" = "${var.product}-frontend-config"
      # Allow HTTP (will redirect to HTTPS via FrontendConfig)
      "kubernetes.io/ingress.allow-http" = "true"
    }
  }

  spec {
    default_backend {
      service {
        name = var.product
        port {
          number = 80
        }
      }
    }

    rule {
      host = local.app_domain
      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = var.product
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.app,
    kubectl_manifest.app_backend_config,
    kubectl_manifest.app_frontend_config,
    google_certificate_manager_certificate_map_entry.app
  ]
}

# Annotate service with BackendConfig
resource "kubernetes_annotations" "app_service" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = var.product
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  annotations = {
    "cloud.google.com/backend-config" = "{\"default\": \"${var.product}-backend-config\"}"
  }

  depends_on = [helm_release.app, kubectl_manifest.app_backend_config]
}
