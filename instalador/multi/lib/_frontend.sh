#!/bin/bash
#
# Multi-instance frontend lifecycle — Next.js.
# Substitui o build Vue/Quasar por Next.js. Usa ${folder_name} e ${frontend_port}
# fornecidos por inquiry_options do multi/crm.

#######################################
# Install npm dependencies for Next.js frontend (multi instance).
# Arguments:
#   None — uses ${folder_name}
#######################################
frontend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do frontendNovo em ${folder_name}...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/frontend
  npm install --force
EOF

  sleep 2
}

#######################################
# Build Next.js frontend.
# Arguments:
#   None — uses ${folder_name}
#######################################
frontend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando frontendNovo (Next.js) em ${folder_name}...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/frontend
  NODE_OPTIONS="--max-old-space-size=2048" npm run build
EOF

  sleep 2
}

#######################################
# DEPRECATED — Vue tinha server.js, Next não precisa. No-op para compat.
#######################################
frontend_remove_server_js() {
  return 0
}

#######################################
# Generate .env.local for Next.js with per-instance encryption key.
# Arguments:
#   None — uses ${folder_name}, ${frontend_port}, ${backend_url}
#######################################
frontend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando .env.local do frontendNovo (Next.js) em ${folder_name}...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

  local enc_key
  enc_key=$(openssl rand -base64 32 2>/dev/null | tr -d '\n=' | head -c 32)
  [ -z "$enc_key" ] && enc_key="crm-fallback-$(date +%s)"

sudo su - deploycrm << EOF
  cat <<[-]EOF > /home/deploycrm/${folder_name}/crm.io/frontend/.env.local
NEXT_PUBLIC_API_URL=${backend_url}
NEXT_PUBLIC_DEFAULT_ENCRYPTION_KEY=${enc_key}
NEXT_PUBLIC_INTERACTIVE_BAILEYS=false
PORT=${frontend_port}
[-]EOF
EOF

  sleep 2
}

#######################################
# DEPRECATED — Next.js usa npm run start, sem server.js.
#######################################
frontend_set_server_js() {
  return 0
}

#######################################
# Start Next.js frontend with PM2.
# Arguments:
#   None — uses ${folder_name}
#######################################
frontend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando ${folder_name}-crm-frontend (Next.js)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  export PORT=${frontend_port}
  pm2 delete ${folder_name}-crm-frontend 2>/dev/null || true
  pm2 start "/home/deploycrm/${folder_name}/crm.io/frontend/.next/standalone/server.js" \
    --name "${folder_name}-crm-frontend" \
    --cwd "/home/deploycrm/${folder_name}/crm.io/frontend/.next/standalone" \
    --update-env
  pm2 save
EOF

  sleep 2
}

#######################################
# Setup nginx vhost for Next.js frontend.
# Arguments:
#   None — uses ${folder_name}, ${frontend_port}, ${frontend_url}
#######################################
frontend_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx para ${folder_name}-crm-frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  frontend_hostname=$(echo "${frontend_url/https:\/\/}")

sudo su - root << EOF

cat > /etc/nginx/sites-available/${folder_name}-crm-frontend << 'END'
server {
  server_name $frontend_hostname;

    location / {
    proxy_pass http://127.0.0.1:${frontend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;
  }
}


END

ln -sf /etc/nginx/sites-available/${folder_name}-crm-frontend /etc/nginx/sites-enabled/${folder_name}-crm-frontend
EOF

  sleep 2
}
