
# Atlassian Data Center Helm Release
resource "helm_release" "app" {
  name       = var.product
  namespace  = kubernetes_namespace.app.metadata[0].name
  repository = "https://atlassian.github.io/data-center-helm-charts"
  chart      = var.product
  version    = var.helm_chart_version

  values = [
    yamlencode({
      image = {
        tag = var.product_version
      }
      replicaCount = var.replicas
      database = {
        url    = "jdbc:postgresql://${google_sql_database_instance.instance.private_ip_address}:5432/${var.database_name}"
        driver = "org.postgresql.Driver"
        credentials = {
          secretName = kubernetes_secret.app_db_credentials.metadata[0].name
        }
      }
      (var.product) = {
        resources = {
          jvm = {
            maxHeap = var.jvm_max_heap
            minHeap = var.jvm_min_heap
          }
          container = {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }
        }
        # Enable HTTPS - SSL terminated at load balancer
        additionalEnvironmentVariables = [
          {
            name  = "ATL_PROXY_NAME"
            value = local.app_domain
          },
          {
            name  = "ATL_PROXY_PORT"
            value = "443"
          },
          {
            name  = "ATL_TOMCAT_SCHEME"
            value = "https"
          },
          {
            name  = "ATL_TOMCAT_SECURE"
            value = "true"
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
                storage = var.storage_size
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
    kubernetes_namespace.app,
    google_container_node_pool.primary_nodes,
    kubernetes_secret.app_db_credentials,
    google_sql_database_instance.instance,
    google_sql_database.app,
    google_sql_user.db_user
  ]
}
