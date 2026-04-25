
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
