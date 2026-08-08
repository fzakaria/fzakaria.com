# The built site on http://127.0.0.1:8080, behind the same nginx that would
# serve it for real -- so a redirect or a content type that only misbehaves
# under a web server misbehaves here too, rather than in production.
{pkgs}: let
  config = pkgs.writeText "nginx.conf" ''
    daemon off;
    error_log stderr info;
    pid /tmp/nginx.pid;
    events {}
    http {
      # Without this nginx labels everything text/plain, and browsers
      # refuse to apply a stylesheet served under the wrong type.
      include ${pkgs.nginx}/conf/mime.types;
      default_type application/octet-stream;
      access_log /dev/stdout;
      server {
        listen 8080;
        server_name localhost;
        root ${pkgs.blog-site};

        location / {
          try_files $uri $uri.html $uri/index.html =404;
        }
      }
    }
  '';
in
  pkgs.writeShellScriptBin "server" ''
    echo "🌍 Nginx serving at http://127.0.0.1:8080";
    ${pkgs.nginx}/bin/nginx -c ${config} -e /tmp/nginx_error.log
  ''
