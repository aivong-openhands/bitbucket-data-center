# Namespace for Bitbucket Data Center
resource "kubernetes_namespace" "bitbucket" {
  metadata {
    name = "bitbucket"
    labels = {
      app        = "bitbucket"
      managed-by = "terraform"
    }
  }

  depends_on = [google_container_node_pool.primary_nodes]
}

# Kubernetes Secret for Bitbucket database credentials
resource "kubernetes_secret" "bitbucket_db_credentials" {
  metadata {
    name      = "bitbucket-db-credentials"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
  }

  data = {
    username = var.database_username
    password = var.database_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.bitbucket]
}

# Ingress for HTTPS with Certificate Manager
resource "kubernetes_ingress_v1" "bitbucket" {
  metadata {
    name      = "bitbucket-ingress"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.bitbucket_ip.name
      # Use Certificate Manager certificate map
      "networking.gke.io/certmap" = google_certificate_manager_certificate_map.bitbucket.name
      # FrontendConfig for HTTP to HTTPS redirect
      "networking.gke.io/v1beta1.FrontendConfig" = "bitbucket-frontend-config"
      # Allow HTTP while certificate provisions
      "kubernetes.io/ingress.allow-http" = "true"
    }
  }

  spec {
    default_backend {
      service {
        name = "bitbucket"
        port {
          number = 80
        }
      }
    }

    rule {
      host = local.bitbucket_domain
      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "bitbucket"
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
    helm_release.bitbucket,
    kubectl_manifest.bitbucket_backend_config,
    kubectl_manifest.bitbucket_frontend_config,
    google_certificate_manager_certificate_map_entry.bitbucket
  ]
}

# Annotate service with BackendConfig
resource "kubernetes_annotations" "bitbucket_service" {
  api_version = "v1"
  kind        = "Service"
  metadata {
    name      = "bitbucket"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
  }
  annotations = {
    "cloud.google.com/backend-config" = "{\"default\": \"bitbucket-backend-config\"}"
  }

  depends_on = [helm_release.bitbucket, kubectl_manifest.bitbucket_backend_config]
}
