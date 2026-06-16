#!/bin/bash
# 
# functions for setting up app backend

#######################################
# copy zip
# Arguments:
#   None
#######################################
tenant_copy_zip() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos copiar o tenant.zip...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}"/tenant.zip /home/deploycrm/
EOF

  sleep 2
}


#######################################
# unzip tenant
# Arguments:
#   None
#######################################
tenant_unzip() {
  print_banner
  printf "${WHITE} 💻 Fazendo unzip tenant.zip...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  unzip tenant.zip
EOF

  sleep 2
}

#######################################
# sets environment variable for tenant.
# Arguments:
#   None
#######################################
tenant_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  api_url=$(echo "${api_url/https:\/\/}")
  api_url=${api_url%%/*}
  api_url=https://$api_url

sudo su - deploycrm <<EOF
  cat <<'[-]EOF' > /home/deploycrm/crm/tenant/.env
API_BASE_URL=${api_url}
API_TOKEN='${tenant_token}'
[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
tenant_install() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do tenant...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/tenant
  npm install
EOF

  sleep 2
}

#######################################
# starts tenant using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
tenant_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/tenant
  pm2 start server.js --name crm-tenant
  pm2 save
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
tenant_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  tenant_hostname=$(echo "${tenant_url/https:\/\/}")

sudo su - root << EOF

cat > /etc/nginx/sites-available/crm-tenant << 'END'
server {
  server_name $tenant_hostname;

  location / {
    proxy_pass http://127.0.0.1:3101;
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

ln -s /etc/nginx/sites-available/crm-tenant /etc/nginx/sites-enabled
EOF

  sleep 2
}

#######################################
# delete zip
# Arguments:
#   None
#######################################
tenant_delete_zip() {
  print_banner
  printf "${WHITE} 💻 Vamos delete o zip do tenant...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm || exit
  rm -f tenant.zip
EOF

  sleep 2
}

#######################################
# installs nginx
# Arguments:
#   None
#######################################
tenant_certbot_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando certbot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  tenant_domain=$(echo "${tenant_url/https:\/\/}")

  sudo su - root <<EOF
  certbot -m $deploy_email \
          --nginx \
          --agree-tos \
          --redirect \
          --non-interactive \
          --domains $tenant_domain
EOF

  sleep 2
}

#######################################
# creates final message
# Arguments:
#   None
#######################################
tenant_success() {
  print_banner
  printf "${GREEN} 💻 Instalação concluída!${NC}"
  printf "\n\n"
  printf "URL Tenant: https://$tenant_domain"
  printf "\n"
  printf "Firewall foi ativado, liberando acesso as portas 22, 443, 80 e 9000"
  printf "\n"
  printf "${GREEN}FAQ: https://hotmart.com/es/club/whatitan${NC}"
  printf "\n"
  printf "${GREEN}Suporte: https://wa.me/50489520312/${NC}"
  printf "\n"
  printf "${CYAN_LIGHT}";
  printf "${NC}";

  sleep 2
}