#!/bin/bash
# Atualização do sistema para múltiplas instalações de crm

#######################################
# Percorre todas as instalações dentro de /home/deploycrm/
# e executa a atualização para cada pasta crm encontrada.
#######################################
update_all_instances() {
  for instance in /home/deploycrm/*/crm; do
    if [ -d "$instance" ]; then
      echo "\n🚀 Atualizando: $instance"
      update_instance "$instance"
    fi
  done
}

#######################################
# Executa a atualização em uma instância específica
# Arguments:
#   $1 - Caminho da instância (ex: /home/deploycrm/install1/crm)
#######################################
update_instance() {
  local INSTANCE_PATH="$1"

  print_banner
  printf "${WHITE} 💻 Atualizando instância em $INSTANCE_PATH...${GRAY_LIGHT}\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 stop all
EOF

  sleep 2

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}"/update.zip "$INSTANCE_PATH/.."
EOF

  sleep 2

  sudo su - root <<EOF
  cd "$INSTANCE_PATH/backend" || exit
  rm -rf node_modules dist package.json package-lock.json
EOF

  sleep 2

  sudo su - root <<EOF
  cd "$INSTANCE_PATH/frontend" || exit
  find src -mindepth 1 -not -name 'App.vue' -not -name 'index.template.html' -exec rm -rf {} +
  rm -rf public/POSTMAN_v2.json babel.config.js package.json package-lock.json
EOF

  sleep 2

  sudo su - root <<EOF
  cd "$INSTANCE_PATH/.." || exit
  unzip update.zip
  rm -f update.zip
EOF

  sleep 2

  sudo su - deploycrm <<EOF
  # Verifica se o arquivo index.html existe na pasta frontend da instância
  if [ ! -f "$INSTANCE_PATH/frontend/index.html" ]; then
    printf "${YELLOW} ⚠️  Arquivo index.html não encontrado no frontend da instância. Copiando...${GRAY_LIGHT}\n"
    cp "${PROJECT_ROOT}/index.html" "$INSTANCE_PATH/frontend/"
    printf "${GREEN} ✅ Arquivo index.html copiado com sucesso para $INSTANCE_PATH/frontend!${GRAY_LIGHT}\n"
  else
    printf "${GREEN} ✅ Arquivo index.html já existe no frontend da instância.${GRAY_LIGHT}\n"
  fi

  # Verifica se o script do wavoip já existe no index.html
  if ! grep -q '<script src="https://cdn.jsdelivr.net/npm/@wavoip/wavoip-webphone/dist/index.umd.min.js"></script>' "$INSTANCE_PATH/frontend/index.html"; then
    printf "${YELLOW} ⚠️  Script do wavoip não encontrado. Adicionando...${GRAY_LIGHT}\n"
    # Adiciona o script antes do fechamento do </head>
    sed -i '/<\/head>/i\    <script src="https://cdn.jsdelivr.net/npm/@wavoip/wavoip-webphone/dist/index.umd.min.js"></script>' "$INSTANCE_PATH/frontend/index.html"
    printf "${GREEN} ✅ Script do wavoip adicionado com sucesso!${GRAY_LIGHT}\n"
  else
    printf "${GREEN} ✅ Script do wavoip já existe no index.html.${GRAY_LIGHT}\n"
  fi
EOF

  sleep 2

  sudo su - deploycrm <<EOF
  cd "$INSTANCE_PATH/backend"
  npm install --force
  npx sequelize db:migrate
EOF

  sleep 2

  sudo su - deploycrm <<EOF
  cd "$INSTANCE_PATH/frontend"
  npm install --force
  npm run build
EOF

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 restart all
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Atualização concluída para $INSTANCE_PATH${NC}\n"
  printf "\n"
  printf "Firewall foi ativado, liberando acesso as portas 22, 443, 80 e 9000"
}