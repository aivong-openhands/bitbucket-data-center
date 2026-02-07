# OAuth Scope-Stripping Proxy for Bitbucket
# Removes 'openid' scope from OAuth requests since Bitbucket doesn't support OIDC

resource "kubernetes_config_map" "oauth_proxy_config" {
  metadata {
    name      = "oauth-proxy-config"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
  }

  data = {
    "oidc_proxy.py" = <<-PYTHON
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.request
import urllib.parse
import json
import base64
import hmac
import hashlib
import time

# Simple JWT creation (HS256)
SECRET_KEY = b'bitbucket-oidc-proxy-secret-key-change-in-production'

def base64url_encode(data):
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

def create_jwt(payload):
    header = {'alg': 'HS256', 'typ': 'JWT'}
    header_b64 = base64url_encode(json.dumps(header))
    payload_b64 = base64url_encode(json.dumps(payload))
    signature_input = f"{header_b64}.{payload_b64}".encode('utf-8')
    signature = hmac.new(SECRET_KEY, signature_input, hashlib.sha256).digest()
    signature_b64 = base64url_encode(signature)
    return f"{header_b64}.{payload_b64}.{signature_b64}"

def get_user_info(access_token):
    """Get user info from Bitbucket using the access token"""
    try:
        req = urllib.request.Request(
            'http://bitbucket/plugins/servlet/applinks/whoami',
            headers={'Authorization': f'Bearer {access_token}'}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            username = resp.read().decode('utf-8').strip()
        
        if username:
            # Try to get full user details
            try:
                req_user = urllib.request.Request(
                    f'http://bitbucket/rest/api/latest/users/{username}',
                    headers={'Authorization': f'Bearer {access_token}'}
                )
                with urllib.request.urlopen(req_user, timeout=10) as resp:
                    user_data = json.loads(resp.read().decode('utf-8'))
                    return {
                        'sub': user_data.get('name', username),
                        'preferred_username': user_data.get('name', username),
                        'name': user_data.get('displayName', username),
                        'email': user_data.get('emailAddress', f'{username}@bitbucket.local'),
                    }
            except:
                pass
            return {
                'sub': username,
                'preferred_username': username,
                'name': username,
                'email': f'{username}@bitbucket.local',
            }
    except Exception as e:
        print(f"Error getting user info: {e}")
    return None

class OIDCProxyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
            return
        
        if self.path.startswith('/oauth2/userinfo'):
            auth = self.headers.get('Authorization', '')
            if not auth or not auth.startswith('Bearer '):
                self.send_response(401)
                self.end_headers()
                return
            
            token = auth.replace('Bearer ', '')
            user_info = get_user_info(token)
            
            if user_info:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(user_info).encode())
            else:
                self.send_response(401)
                self.end_headers()
            return
        
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if self.path == '/oauth2/token':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            
            # Parse post data to get client_id and nonce
            params = urllib.parse.parse_qs(post_data)
            client_id = params.get('client_id', [''])[0]
            nonce = params.get('nonce', [''])[0]
            
            # Forward to Bitbucket token endpoint
            try:
                req = urllib.request.Request(
                    'http://bitbucket/rest/oauth2/latest/token',
                    data=post_data.encode('utf-8'),
                    headers={
                        'Content-Type': 'application/x-www-form-urlencoded',
                    }
                )
                
                with urllib.request.urlopen(req, timeout=30) as resp:
                    token_response = json.loads(resp.read().decode('utf-8'))
                
                # Get user info to create id_token
                access_token = token_response.get('access_token', '')
                user_info = get_user_info(access_token)
                
                if user_info:
                    # Create id_token with correct audience (client_id) and nonce
                    now = int(time.time())
                    id_token_payload = {
                        'iss': 'https://bitbucket-01.aivong.platform-team.all-hands.dev',
                        'sub': user_info['sub'],
                        'aud': client_id,  # Must match the client_id used in the request
                        'exp': now + 3600,
                        'iat': now,
                        'nonce': nonce,  # Required by OIDC
                        'preferred_username': user_info.get('preferred_username', ''),
                        'name': user_info.get('name', ''),
                        'email': user_info.get('email', ''),
                    }
                    token_response['id_token'] = create_jwt(id_token_payload)
                
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(token_response).encode())
                
            except urllib.error.HTTPError as e:
                error_body = e.read().decode('utf-8')
                self.send_response(e.code)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(error_body.encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
            return
        
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        print(f"{args[0]} {args[1]} {args[2]}")

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8081), OIDCProxyHandler)
    print('OIDC Proxy server running on port 8081')
    server.serve_forever()
    PYTHON

    "nginx.conf" = <<-EOF
      worker_processes 1;
      error_log /dev/stderr info;

      events {
        worker_connections 1024;
      }

      http {
        access_log /dev/stdout;
        
        # Upstream to actual Bitbucket
        upstream bitbucket {
          server bitbucket:80;
        }

        server {
          listen 8080;
          server_name _;

          # Health check endpoint
          location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
          }

          # User info endpoint - proxy to Python sidecar
          location /oauth2/userinfo {
            proxy_pass http://127.0.0.1:8081/oauth2/userinfo;
            proxy_set_header Authorization $http_authorization;
          }

          # Token endpoint - proxy to Python sidecar (adds id_token)
          location /oauth2/token {
            proxy_pass http://127.0.0.1:8081/oauth2/token;
            proxy_set_header Content-Type $content_type;
            proxy_set_header Content-Length $content_length;
          }

          # OAuth authorize endpoint via /oauth2/ path (used by main ingress)
          # Rewrites /oauth2/authorize to /rest/oauth2/latest/authorize
          location /oauth2/authorize {
            set $modified_args $args;
            
            # Remove 'openid' from scope parameter (handles various formats)
            if ($modified_args ~ "^(.*)scope=openid\+(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)\+openid(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }
            if ($modified_args ~ "^(.*)scope=openid(&.*)?$") {
              set $modified_args $1scope=PUBLIC_REPOS$2;
            }
            if ($modified_args ~ "^(.*)scope=openid%2B(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)%2Bopenid(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }
            if ($modified_args ~ "^(.*)scope=\+(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)\+(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }

            proxy_pass http://bitbucket/rest/oauth2/latest/authorize?$modified_args;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
          }

          # OAuth authorize endpoint - strip openid scope (original path)
          location /rest/oauth2/latest/authorize {
            set $modified_args $args;
            
            if ($modified_args ~ "^(.*)scope=openid\+(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)\+openid(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }
            if ($modified_args ~ "^(.*)scope=openid(&.*)?$") {
              set $modified_args $1scope=PUBLIC_REPOS$2;
            }
            if ($modified_args ~ "^(.*)scope=openid%2B(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)%2Bopenid(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }
            if ($modified_args ~ "^(.*)scope=\+(.*)$") {
              set $modified_args $1scope=$2;
            }
            if ($modified_args ~ "^(.*)scope=([^&]*)\+(&.*)?$") {
              set $modified_args $1scope=$2$3;
            }

            proxy_pass http://bitbucket/rest/oauth2/latest/authorize?$modified_args;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
          }

          # All other requests pass through unchanged
          location / {
            proxy_pass http://bitbucket;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
          }
        }
      }
    EOF
  }

  depends_on = [kubernetes_namespace.bitbucket]
}

resource "kubernetes_deployment" "oauth_proxy" {
  metadata {
    name      = "oauth-proxy"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    labels = {
      app = "oauth-proxy"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "oauth-proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "oauth-proxy"
        }
        annotations = {
          "config-hash" = sha256(jsonencode(kubernetes_config_map.oauth_proxy_config.data))
        }
      }

      spec {
        # Nginx proxy container
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

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        # Python OIDC proxy sidecar (adds id_token to token responses)
        container {
          name  = "oidc-proxy"
          image = "python:3.11-alpine"

          command = ["python3", "/app/oidc_proxy.py"]

          port {
            container_port = 8081
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/oidc_proxy.py"
            sub_path   = "oidc_proxy.py"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8081
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.oauth_proxy_config.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_config_map.oauth_proxy_config]
}

resource "kubernetes_service" "oauth_proxy" {
  metadata {
    name      = "oauth-proxy"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    annotations = {
      "cloud.google.com/neg" = "{\"ingress\": true}"
    }
  }

  spec {
    selector = {
      app = "oauth-proxy"
    }

    port {
      port        = 80
      target_port = 8080
    }

    type = "NodePort"
  }

  depends_on = [kubernetes_deployment.oauth_proxy]
}

# Ingress for OAuth proxy (external access for Keycloak)
resource "kubernetes_ingress_v1" "oauth_proxy" {
  metadata {
    name      = "oauth-proxy-ingress"
    namespace = kubernetes_namespace.bitbucket.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.oauth_proxy_ip.name
      "networking.gke.io/certmap"                   = google_certificate_manager_certificate_map.bitbucket.name
      # Allow HTTP while certificate provisions, will redirect to HTTPS once ready
      "kubernetes.io/ingress.allow-http"            = "true"
    }
  }

  spec {
    default_backend {
      service {
        name = kubernetes_service.oauth_proxy.metadata[0].name
        port {
          number = 80
        }
      }
    }
    
    rule {
      host = local.oauth_proxy_domain
      http {
        path {
          path      = "/*"
          path_type = "ImplementationSpecific"
          backend {
            service {
              name = kubernetes_service.oauth_proxy.metadata[0].name
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
    kubernetes_service.oauth_proxy,
    google_certificate_manager_certificate_map_entry.oauth_proxy
  ]
}

# Static IP for OAuth Proxy
resource "google_compute_global_address" "oauth_proxy_ip" {
  name = "${var.cluster_name}-oauth-proxy-ip"
}

# DNS Record for OAuth Proxy
resource "google_dns_record_set" "oauth_proxy" {
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = "oauth.${var.dns_name}"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.oauth_proxy_ip.address]
}

# Certificate for OAuth Proxy
resource "google_certificate_manager_certificate" "oauth_proxy" {
  name        = "${var.cluster_name}-oauth-proxy-cert"
  description = "SSL certificate for OAuth proxy"
  scope       = "DEFAULT"

  managed {
    domains = [local.oauth_proxy_domain]
    dns_authorizations = [
      google_certificate_manager_dns_authorization.oauth_proxy.id
    ]
  }
}

resource "google_certificate_manager_dns_authorization" "oauth_proxy" {
  name        = "${var.cluster_name}-oauth-proxy-dns-auth"
  description = "DNS authorization for OAuth proxy certificate"
  domain      = local.oauth_proxy_domain
}

resource "google_dns_record_set" "oauth_proxy_cert_validation" {
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = google_certificate_manager_dns_authorization.oauth_proxy.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.oauth_proxy.dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.oauth_proxy.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate_map_entry" "oauth_proxy" {
  name         = "${var.cluster_name}-oauth-proxy-cert-entry"
  description  = "Certificate map entry for OAuth proxy"
  map          = google_certificate_manager_certificate_map.bitbucket.name
  hostname     = local.oauth_proxy_domain
  certificates = [google_certificate_manager_certificate.oauth_proxy.id]

  depends_on = [google_dns_record_set.oauth_proxy_cert_validation]
}

locals {
  oauth_proxy_domain = "oauth.${local.bitbucket_domain}"
}

output "oauth_proxy_url" {
  value       = "https://${local.oauth_proxy_domain}"
  description = "OAuth Proxy URL - use this in Keycloak Authorization URL"
}
