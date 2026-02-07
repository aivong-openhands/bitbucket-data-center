# User Info Proxy for Bitbucket OAuth2
# Converts Bitbucket's whoami + user API to JSON userinfo

resource "kubernetes_config_map" "userinfo_proxy_config" {
  metadata {
    name      = "userinfo-proxy-config"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
  }

  data = {
    "nginx.conf" = <<-EOT
      events {
        worker_connections 1024;
      }
      http {
        server {
          listen 8080;
          
          location = / {
            return 200 'OK';
            add_header Content-Type text/plain;
          }
          
          location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
          }
          
          location /oauth2/userinfo {
            # Extract Bearer token and proxy to Python sidecar
            proxy_pass http://127.0.0.1:8081/userinfo;
            proxy_set_header Authorization $http_authorization;
            proxy_set_header Host $host;
          }
        }
      }
    EOT

    "userinfo.py" = <<-PYTHON
#!/usr/bin/env python3
import http.server
import json
import urllib.request
import urllib.error

class UserInfoHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress logs
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
            return
        
        if self.path == '/userinfo':
            auth_header = self.headers.get('Authorization', '')
            
            if not auth_header.startswith('Bearer '):
                self.send_response(401)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'missing_token'}).encode())
                return
            
            try:
                # Get username from whoami
                req = urllib.request.Request(
                    'http://bitbucket.bitbucket.svc.cluster.local/plugins/servlet/applinks/whoami',
                    headers={'Authorization': auth_header}
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    username = resp.read().decode('utf-8').strip()
                
                if not username:
                    self.send_response(401)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({'error': 'not_authenticated'}).encode())
                    return
                
                # Get user details
                req = urllib.request.Request(
                    f'http://bitbucket.bitbucket.svc.cluster.local/rest/api/latest/users/{username}',
                    headers={'Authorization': auth_header}
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    user_data = json.loads(resp.read().decode('utf-8'))
                
                # Convert to standard userinfo format
                userinfo = {
                    'sub': str(user_data.get('id', username)),
                    'preferred_username': user_data.get('name', username),
                    'name': user_data.get('displayName', username),
                    'email': user_data.get('emailAddress', ''),
                }
                
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(userinfo).encode())
                
            except urllib.error.HTTPError as e:
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = http.server.HTTPServer(('0.0.0.0', 8081), UserInfoHandler)
    print('UserInfo proxy listening on :8081')
    server.serve_forever()
    PYTHON
  }

  depends_on = [kubernetes_namespace.bitbucket]
}

resource "kubernetes_deployment" "userinfo_proxy" {
  metadata {
    name      = "userinfo-proxy"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    labels = {
      app = "userinfo-proxy"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "userinfo-proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "userinfo-proxy"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }

        container {
          name  = "userinfo"
          image = "python:3.11-alpine"

          command = ["python3", "/app/userinfo.py"]

          port {
            container_port = 8081
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/userinfo.py"
            sub_path   = "userinfo.py"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.userinfo_proxy_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.userinfo_proxy_config]
}

resource "kubernetes_service" "userinfo_proxy" {
  metadata {
    name      = "userinfo-proxy"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    annotations = {
      "cloud.google.com/backend-config" = "{\"default\": \"userinfo-proxy-backend-config\"}"
      "cloud.google.com/neg"            = "{\"ingress\": true}"
    }
  }

  spec {
    selector = {
      app = "userinfo-proxy"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "NodePort"
  }

  depends_on = [kubernetes_deployment.userinfo_proxy, kubernetes_manifest.userinfo_backend_config]
}

resource "kubernetes_manifest" "userinfo_backend_config" {
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "userinfo-proxy-backend-config"
      namespace = kubernetes_namespace.bitbucket.metadata[0].name
    }
    spec = {
      healthCheck = {
        checkIntervalSec   = 15
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 2
        type               = "HTTP"
        requestPath        = "/health"
        port               = 8080
      }
    }
  }

  depends_on = [kubernetes_namespace.bitbucket]
}

# Note: userinfo path is added to main bitbucket ingress in main.tf
