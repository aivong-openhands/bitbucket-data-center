# BackendConfig for health checks
resource "kubectl_manifest" "app_backend_config" {
  yaml_body = <<-YAML
    apiVersion: cloud.google.com/v1
    kind: BackendConfig
    metadata:
      name: ${var.product}-backend-config
      namespace: ${kubernetes_namespace.app.metadata[0].name}
    spec:
      healthCheck:
        checkIntervalSec: 30
        timeoutSec: 10
        healthyThreshold: 1
        unhealthyThreshold: 3
        type: HTTP
        requestPath: /status
        port: ${local.service_port}
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [kubernetes_namespace.app]
}

# FrontendConfig for HTTP to HTTPS redirect
resource "kubectl_manifest" "app_frontend_config" {
  yaml_body = <<-YAML
    apiVersion: networking.gke.io/v1beta1
    kind: FrontendConfig
    metadata:
      name: ${var.product}-frontend-config
      namespace: ${kubernetes_namespace.app.metadata[0].name}
    spec:
      redirectToHttps:
        enabled: true
        responseCodeName: MOVED_PERMANENTLY_DEFAULT
  YAML

  force_conflicts   = true
  server_side_apply = true

  depends_on = [kubernetes_namespace.app]
}
