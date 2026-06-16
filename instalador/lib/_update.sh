#!/bin/bash
# 
# system management

#######################################
# installs node
# Arguments:
#   None
#######################################
update_node_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nodejs...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  apt-get install -y nodejs
EOF

  sleep 2
}

#######################################
# installs node
# Arguments:
#   None
#######################################
update_bd_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando permissões do banco...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 1

  sudo su - root <<'EOF'
  if docker ps -q -f name=postgresql >/dev/null; then
    # Determina o PGDATA real dentro do container (pode estar em /var/lib/postgresql/data
    # ou /var/lib/postgresql/data/pgdata, dependendo da config do compose).
    pg_dir=$(docker exec postgresql sh -c 'echo ${PGDATA:-/var/lib/postgresql/data}' 2>/dev/null)
    if [ -n "$pg_dir" ] && docker exec postgresql test -d "$pg_dir" 2>/dev/null; then
      docker exec -u root postgresql bash -c "chown -R postgres:postgres '$pg_dir'" >/dev/null 2>&1
    fi
  fi
EOF

  sleep 1
}

#######################################
# stop all services
# Arguments:
#   None
#######################################
update_stop_pm2() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos para os serviços no deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 stop all
  pm2 flush all
EOF

  sleep 2
}

#######################################
# move update folder
# Arguments:
#   None
#######################################
update_mv_crm() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos mover a update até o deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}"/update.zip /home/deploycrm/
EOF

  sleep 2
}

#######################################
# delete backend folder
# Arguments:
#   None
#######################################
update_delete_backend() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos deletar o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm/crm/backend || exit
  rm -rf node_modules
  rm -rf dist
  rm -f package.json
  rm -f package-lock.json
EOF

  sleep 2
}

#######################################
# DEPRECATED — substituída pelo loop migrate_vue_to_next / rebuild_next_in_place,
# que aplica princípio "rename never delete" (mv frontend → frontend.legacy.<ts>).
# Mantida como no-op para callers antigos.
# Arguments:
#   None
#######################################
update_delete_frontend() {
  printf "  ${DIM}[update_delete_frontend] no-op — substituído por migrate_vue_to_next.${NC}\n\n"
  return 0
}

#######################################
# Renomeia frontend/ para .bak.<ts>/ (substitui o rm -rf antigo).
# Princípio "rename never delete" — cleanup só por comando explícito.
# Arguments:
#   $1 - folder_name (opcional)
#######################################
update_rename_frontend_to_bak() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  if [ -d "$base/frontend" ]; then
    sudo mv "$base/frontend" "$base/frontend.bak.${ts}"
    printf "  ${GREEN}✅${NC}  $base/frontend → frontend.bak.${ts}/\n\n"
  fi
}

#######################################
# delete frontend folder
# Arguments:
#   None
#######################################
update_tos() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos atualizar os termos de uso...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm || exit
  rm -f aviso_de_privacidade.pdf
  rm -f termos_de_uso.pdf
EOF

  sleep 2
}

#######################################
# unzip update — extrai TUDO (backend + frontend).
# Mantida para compatibilidade com software_migration e outros flows que
# ainda assumem extração total.
# Arguments:
#   None
#######################################
update_unzip_crm() {
  print_banner
  printf "${WHITE} 💻 Fazendo unzip da update...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  unzip update.zip
EOF

  sleep 2
}

#######################################
# unzip update — APENAS backend e arquivos top-level (PDFs).
# Frontend é extraído depois pelo loop migrate_vue_to_next / rebuild_next_in_place,
# que aplica princípio "rename never delete" (preserva Vue legado).
# Pré-condição: update.zip está em /home/deploycrm/update.zip (após update_mv_crm).
# Arguments:
#   None
#######################################
update_unzip_backend_only() {
  print_banner
  printf "${WHITE} 💻 Extraindo backend do update.zip (frontend fica para o loop)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 1

  # Extrai TODO o crm/ em /tmp e SOBREPÕE o backend (rsync -a) em cima do
  # backend existente — em vez de nuke + replace. Isso preserva .env,
  # public/branding/, cache/, sessões Baileys/WWebJS, .sequelizerc e qualquer
  # outro estado que o usuário tenha gerado e que não venha no update.zip.
  # node_modules / dist / package*.json já foram limpos por update_delete_backend().
  #
  # Guard --exclude: defesa em profundidade. Mesmo que um build futuro do
  # update.zip vaze por engano caminhos de runtime/customs, o rsync descarta
  # antes de tocar o destino. Hoje esses paths não estão no zip; o exclude
  # garante que continuem assim.
  sudo su - deploycrm <<'EOF'
  set -e
  TMP=$(mktemp -d -t crm_unzip_be.XXXXXX)
  cd /home/deploycrm
  unzip -qo update.zip -d "$TMP" </dev/null
  if [ -d "$TMP/crm/backend" ]; then
    mkdir -p /home/deploycrm/crm/backend
    # rsync -a: preserva permissões, timestamps, links (equivalente a cp -af).
    # --force: sobrescreve no conflito (mesmo comportamento que cp -af).
    # Trailing / na origem copia o conteúdo sem aninhar a pasta.
    rsync -a --force \
      --exclude='public/branding/***' \
      --exclude='public/uploads/***' \
      --exclude='public/fonts/***' \
      --exclude='cache/***' \
      --exclude='.wwebjs_auth/***' \
      --exclude='.env' \
      "$TMP/crm/backend/" /home/deploycrm/crm/backend/
  fi
  # PDFs top-level (termos_de_uso, aviso_de_privacidade) — opcionais
  for pdf in "$TMP"/*.pdf; do
    [ -f "$pdf" ] && mv "$pdf" /home/deploycrm/ 2>/dev/null || true
  done
  rm -rf "$TMP"
EOF

  if [ ! -d /home/deploycrm/crm/backend ]; then
    printf "${RED} ❌ Falha: backend não foi extraído.${NC}\n\n"
    return 1
  fi

  sleep 1
}

#######################################
# check and copy index.html to frontend
# Arguments:
#   None
#######################################
update_check_frontend_index() {
  print_banner
  printf "${WHITE} 💻 Verificando arquivo index.html no frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  # Verifica se o arquivo index.html existe na pasta frontend
  if [ ! -f "/home/deploycrm/crm/frontend/index.html" ]; then
    printf "${YELLOW} ⚠️  Arquivo index.html não encontrado no frontend. Copiando...${GRAY_LIGHT}\n"
    cp "${PROJECT_ROOT}/index.html" /home/deploycrm/crm/frontend/
    printf "${GREEN} ✅ Arquivo index.html copiado com sucesso!${GRAY_LIGHT}\n"
  else
    printf "${GREEN} ✅ Arquivo index.html já existe no frontend.${GRAY_LIGHT}\n"
  fi

  # Verifica se o script do wavoip já existe no index.html
  if ! grep -q '<script src="https://cdn.jsdelivr.net/npm/@wavoip/wavoip-webphone/dist/index.umd.min.js"></script>' /home/deploycrm/crm/frontend/index.html; then
    printf "${YELLOW} ⚠️  Script do wavoip não encontrado. Adicionando...${GRAY_LIGHT}\n"
    # Adiciona o script antes do fechamento do </head>
    sed -i '/<\/head>/i\    <script src="https://cdn.jsdelivr.net/npm/@wavoip/wavoip-webphone/dist/index.umd.min.js"></script>' /home/deploycrm/crm/frontend/index.html
    printf "${GREEN} ✅ Script do wavoip adicionado com sucesso!${GRAY_LIGHT}\n"
  else
    printf "${GREEN} ✅ Script do wavoip já existe no index.html.${GRAY_LIGHT}\n"
  fi
EOF

  sleep 2
}

#######################################
# delete zip
# Arguments:
#   None
#######################################
update_delete_zip() {
  print_banner
  printf "${WHITE} 💻 Vamos delete o zip do update...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm || exit
  rm -f update.zip
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
update_backend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    log_error "npm install backend" "Falha ao instalar dependencias do backend"
  fi

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
update_backend_db_migrate() {
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npx sequelize db:migrate
EOF
  if [ $? -ne 0 ]; then
    log_error "db:migrate" "Falha ao executar migrations do banco de dados"
  fi

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
update_backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npx sequelize db:seed:all
EOF
  if [ $? -ne 0 ]; then
    log_error "db:seed" "Falha ao executar seeds do banco de dados"
  fi

  sleep 2
}

#######################################
# installed node packages
# Arguments:
#   None
#######################################
update_frontend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/frontend
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    log_error "npm install frontend" "Falha ao instalar dependencias do frontend"
  fi

  sleep 2
}

#######################################
# compiles frontend code
# Arguments:
#   None
#######################################
update_frontend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/frontend
  npm run build
EOF
  if [ $? -ne 0 ]; then
    log_error "frontend build" "Falha ao compilar o frontend (npm run build)"
  fi

  sleep 2
}

#######################################
# stop all services
# Arguments:
#   None
#######################################
update_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos reiniciar os serviços no deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 restart all
EOF
  if [ $? -ne 0 ]; then
    log_error "pm2 restart" "Falha ao reiniciar processos PM2"
  fi

  sleep 2
}

#######################################
# creates final message
# Arguments:
#   None
#######################################
update_success() {
  # health check antes de exibir resultado
  health_check_all

  print_banner
  printf "${GREEN} 💻 Atualização concluída!${NC}"
  printf "\n\n"

  printf "${WHITE} 📊 URLs do sistema:${GRAY_LIGHT}"
  printf "\n"

  # Itera todas as instâncias crm do servidor (primária + multi) e mostra suas URLs.
  local fname label env_file _be _fe
  while IFS= read -r fname; do
    if [ -z "$fname" ]; then
      label="crm (primária)"
      env_file="/home/deploycrm/crm/backend/.env"
    else
      label="$fname"
      env_file="/home/deploycrm/${fname}/crm/backend/.env"
    fi
    [ -f "$env_file" ] || continue
    _be=$(grep '^BACKEND_URL='  "$env_file" | cut -d'=' -f2 | tr -d '[:space:]')
    _fe=$(grep '^FRONTEND_URL=' "$env_file" | cut -d'=' -f2 | tr -d '[:space:]')
    printf "  ${CYAN_LIGHT}%s${NC}\n" "$label"
    printf "    • Backend : %s\n" "${_be:-(nao definido)}"
    printf "    • Frontend: %s\n" "${_fe:-(nao definido)}"
  done < <(list_crm_instances)
  printf "\n"

  # exibe resumo de erros (se houver)
  show_error_summary

  printf "Firewall ativo — portas: 22, 80, 443, 9000"
  printf "\n\n"
  printf "${GREEN}FAQ: https://hotmart.com/es/club/whatitan${NC}"
  printf "\n"
  printf "${GREEN}Suporte: https://wa.me/50489520312/${NC}"
  printf "\n"
  printf "${CYAN_LIGHT}";
  printf "${NC}";

  sleep 2
}