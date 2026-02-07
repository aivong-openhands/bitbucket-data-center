terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.17.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    acme = {
      source  = "vancluever/acme"
      version = "2.43.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.5"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = merge(var.default_labels, {
    "name" = var.cluster_name
  })
}

data "google_client_config" "default" {}

provider "acme" {
  server_url = var.acme_server
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

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

# Bitbucket Data Center Helm Release
resource "helm_release" "bitbucket" {
  name       = "bitbucket"
  namespace  = kubernetes_namespace.bitbucket.metadata[0].name
  repository = "https://atlassian.github.io/data-center-helm-charts"
  chart      = "bitbucket"
  version    = var.bitbucket_helm_chart_version

  values = [
    yamlencode({
      image = {
        tag = var.bitbucket_version
      }
      replicaCount = var.bitbucket_replicas
      database = {
        url    = "jdbc:postgresql://${google_sql_database_instance.instance.private_ip_address}:5432/${var.database_name}"
        driver = "org.postgresql.Driver"
        credentials = {
          secretName = kubernetes_secret.bitbucket_db_credentials.metadata[0].name
        }
      }
      bitbucket = {
        resources = {
          jvm = {
            maxHeap = var.bitbucket_jvm_max_heap
            minHeap = var.bitbucket_jvm_min_heap
          }
          container = {
            requests = {
              cpu    = var.bitbucket_cpu_request
              memory = var.bitbucket_memory_request
            }
            limits = {
              cpu    = var.bitbucket_cpu_limit
              memory = var.bitbucket_memory_limit
            }
          }
        }
        service = {
          type = "LoadBalancer"
        }
        # Enable HTTPS - SSL terminated at load balancer
        additionalEnvironmentVariables = [
          {
            name  = "SERVER_SECURE"
            value = "true"
          },
          {
            name  = "SERVER_SCHEME"
            value = "https"
          },
          {
            name  = "SERVER_PROXY_PORT"
            value = "443"
          }
        ]
      }
      ingress = {
        create = false
      }
      volumes = {
        localHome = {
          persistentVolumeClaim = {
            create           = true
            storageClassName = var.storage_class
            resources = {
              requests = {
                storage = var.bitbucket_storage_size
              }
            }
          }
        }
        sharedHome = {
          # Use emptyDir for single-replica deployment (no RWX storage needed)
          customVolume = {
            emptyDir = {}
          }
          persistentVolumeClaim = {
            create = false
          }
        }
      }
    })
  ]

  timeout = 900

  depends_on = [
    kubernetes_namespace.bitbucket,
    google_container_node_pool.primary_nodes,
    kubernetes_secret.bitbucket_db_credentials,
    google_sql_database_instance.instance,
    google_sql_database.bitbucket,
    google_sql_user.db_user
  ]
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

# Local to get domain without trailing dot
locals {
  # Remove trailing dot from dns_name if present (e.g., "example.com." -> "example.com")
  bitbucket_domain = trimsuffix(var.dns_name, ".")
}

# Static IP for Ingress
resource "google_compute_global_address" "bitbucket_ip" {
  name = "${var.cluster_name}-bitbucket-ip"
}

# DNS Record for Bitbucket
resource "google_dns_record_set" "bitbucket" {
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = var.dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.bitbucket_ip.address]
}

# BackendConfig for health checks
resource "kubernetes_manifest" "bitbucket_backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "bitbucket-backend-config"
      namespace = kubernetes_namespace.bitbucket.metadata[0].name
    }
    spec = {
      healthCheck = {
        checkIntervalSec   = 30
        timeoutSec         = 10
        healthyThreshold   = 1
        unhealthyThreshold = 3
        type               = "HTTP"
        requestPath        = "/status"
        port               = 7990
      }
    }
  }

  # Force Terraform to take over field ownership from kubectl
  field_manager {
    name            = "Terraform"
    force_conflicts = true
  }

  depends_on = [kubernetes_namespace.bitbucket]
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

  depends_on = [helm_release.bitbucket, kubernetes_manifest.bitbucket_backend_config]
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
        # OAuth proxy path - must come before the catch-all
        path {
          path      = "/oauth2/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = "oauth-proxy"
              port {
                number = 80
              }
            }
          }
        }
        # Default Bitbucket path
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
    kubernetes_manifest.bitbucket_backend_config,
    kubernetes_manifest.bitbucket_frontend_config,
    google_certificate_manager_certificate_map_entry.bitbucket,
    kubernetes_service.oauth_proxy
  ]
}

# FrontendConfig for HTTP to HTTPS redirect
resource "kubernetes_manifest" "bitbucket_frontend_config" {
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = "bitbucket-frontend-config"
      namespace = kubernetes_namespace.bitbucket.metadata[0].name
    }
    spec = {
      redirectToHttps = {
        enabled          = true
        responseCodeName = "MOVED_PERMANENTLY_DEFAULT"
      }
    }
  }

  field_manager {
    name            = "Terraform"
    force_conflicts = true
  }

  depends_on = [kubernetes_namespace.bitbucket]
}
