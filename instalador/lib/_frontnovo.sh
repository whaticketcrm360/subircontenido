#!/bin/bash
#
# functions for setting up frontendNovo (Next.js)

#######################################
# Beta warning + CORS removal info
# Arguments:
#   None
#######################################
frontnovo_warn_beta() {
  print_banner
  printf "${YELLOW}  ⚠️   ATENÇÃO — frontendNovo está em BETA${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${WHITE}O frontendNovo (Next.js) é uma versão experimental em fase beta.${NC}\n\n"
  printf "  ${CYAN_LIGHT}O que será feito:${NC}\n"
  printf "  ${DIM}• Criação do .env.local com URL do backend, chave de criptografia e porta${NC}\n"
  printf "  ${DIM}• npm install + npm run build (pode levar vários minutos)${NC}\n"
  printf "  ${DIM}• Inicialização via PM2 + nginx + SSL (Let's Encrypt)${NC}\n"
  printf "  ${DIM}• Adição de FRONTEND_URL_2 e SECURE_URL=* no .env do backend${NC}\n\n"
  printf "  ${YELLOW}⚠️   REMOÇÃO DA RESTRIÇÃO CORS:${NC}\n"
  printf "  ${WHITE}A variável SECURE_URL=* será adicionada ao backend para permitir${NC}\n"
  printf "  ${WHITE}requisições do frontendNovo. Necessário para o funcionamento beta.${NC}\n"
  printf "  ${RED}   Não use SECURE_URL=* em produção sem revisão de segurança.${NC}\n\n"
  printf "  ${DIM}Se a instalação falhar, siga o tutorial em:${NC}\n"
  printf "  ${GREEN}https://hotmart.com/es/club/whatitan${NC}\n"
  printf "${LINE}\n\n"
  printf "  ${YELLOW}Pressione ENTER para continuar ou Ctrl+C para cancelar...${NC}\n"
  read -r
}

#######################################
# Detect backend instances and ask which one to target
# Sets: frontnovo_instance_path, frontnovo_backend_env, frontnovo_pm2_name
# Arguments:
#   None
#######################################
frontnovo_select_instance() {
  local instances=()
  local instance_names=()
  local instance_paths=()

  # Primary instance
  if [ -f "/home/deploycrm/crm/backend/.env" ]; then
    instances+=("Instância primária  —  /home/deploycrm/crm")
    instance_names+=("primary")
    instance_paths+=("/home/deploycrm/crm")
  fi

  # Secondary instances
  for env_file in /home/deploycrm/*/crm/backend/.env; do
    [ -f "$env_file" ] || continue
    local sec_crm_path
    sec_crm_path=$(dirname "$(dirname "$env_file")")
    local sec_name
    sec_name=$(basename "$(dirname "$sec_crm_path")")
    instances+=("Instância: ${sec_name}  —  ${sec_crm_path}")
    instance_names+=("$sec_name")
    instance_paths+=("$sec_crm_path")
  done

  if [ ${#instances[@]} -eq 0 ]; then
    printf "${RED}  ❌  Nenhuma instância crm encontrada em /home/deploycrm/!${NC}\n\n"
    return 1
  fi

  if [ ${#instances[@]} -eq 1 ]; then
    frontnovo_instance_path="${instance_paths[0]}"
    frontnovo_backend_env="${instance_paths[0]}/backend/.env"
    if [ "${instance_names[0]}" = "primary" ]; then
      frontnovo_pm2_name="crm-frontnovo"
    else
      frontnovo_pm2_name="${instance_names[0]}-crm-frontnovo"
    fi
    printf "  ${GREEN}✅${NC}  Instância detectada: ${instances[0]}\n\n"
    sleep 1
    return 0
  fi

  print_banner
  printf "${WHITE}  💻 Selecione a instância crm para o frontendNovo:${NC}\n\n"
  printf "${LINE}\n"
  for i in "${!instances[@]}"; do
    printf "  ${GREEN}[$((i+1))]${NC}  ${instances[$i]}\n"
  done
  printf "${LINE}\n\n"
  read -p "  Número da instância > " _inst_num

  if ! [[ "$_inst_num" =~ ^[0-9]+$ ]] || [ "$_inst_num" -lt 1 ] || [ "$_inst_num" -gt "${#instances[@]}" ]; then
    printf "${RED}  ❌  Opção inválida!${NC}\n\n"
    sleep 2
    frontnovo_select_instance
    return
  fi

  local _idx=$((_inst_num - 1))
  frontnovo_instance_path="${instance_paths[$_idx]}"
  frontnovo_backend_env="${instance_paths[$_idx]}/backend/.env"
  if [ "${instance_names[$_idx]}" = "primary" ]; then
    frontnovo_pm2_name="crm-frontnovo"
  else
    frontnovo_pm2_name="${instance_names[$_idx]}-crm-frontnovo"
  fi

  printf "  ${GREEN}✅${NC}  Instância selecionada: ${instances[$_idx]}\n\n"
  sleep 1
}

#######################################
# Guard: abort install if PM2 process already exists
# Must run after frontnovo_select_instance (uses frontnovo_pm2_name)
# Arguments:
#   None
#######################################
frontnovo_check_not_installed() {
  if sudo su - deploycrm -c "pm2 list" 2>/dev/null | grep -q "${frontnovo_pm2_name}"; then
    print_banner
    printf "${YELLOW}  ⚠️   O processo '${frontnovo_pm2_name}' já existe no PM2.${NC}\n\n"
    printf "${LINE}\n"
    printf "  ${WHITE}O frontendNovo já está instalado nesta instância.${NC}\n"
    printf "  ${DIM}Para atualizar, use a opção  15 → 2  (Atualizar frontendNovo).${NC}\n"
    printf "${LINE}\n\n"
    printf "  ${YELLOW}Deseja forçar a instalação mesmo assim? Isso pode sobrescrever configurações existentes. (s/N):${NC}\n"
    read -p "  > " _install_confirm
    if [ "$_install_confirm" != "s" ] && [ "$_install_confirm" != "S" ]; then
      printf "\n  ${YELLOW}Operação cancelada. Use  15 → 2  para atualizar.${NC}\n\n"
      return 1
    fi
  fi
  return 0
}

#######################################
# Get frontendNovo URL (subdomain)
# Sets: frontnovo_url
# Arguments:
#   None
#######################################
frontnovo_get_url() {
  print_banner
  printf "${WHITE}  💻 Digite o domínio do frontendNovo (ex: app2.cliente.com.br):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " frontnovo_url

  if ! validate_dns "$frontnovo_url"; then
    frontnovo_get_url
    return
  fi
}

#######################################
# Get frontendNovo PORT
# Sets: frontnovo_port
# Arguments:
#   None
#######################################
frontnovo_get_port() {
  print_banner
  printf "${WHITE}  💻 Digite a porta para o frontendNovo:${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > [Enter para 3000]: " frontnovo_port

  if [ -z "$frontnovo_port" ]; then
    frontnovo_port="3000"
  fi

  if ! [[ "$frontnovo_port" =~ ^[0-9]+$ ]] || [ "$frontnovo_port" -lt 1024 ] || [ "$frontnovo_port" -gt 65535 ]; then
    printf "${RED}  ❌  Porta inválida. Use um número entre 1024 e 65535.${NC}\n\n"
    sleep 2
    frontnovo_get_port
    return
  fi

  printf "  ${GREEN}✅${NC}  Porta configurada: ${frontnovo_port}\n\n"
  sleep 1
}

#######################################
# Get deploy email for SSL (if not already set)
# Arguments:
#   None
#######################################
frontnovo_get_email() {
  if [ -n "${deploy_email:-}" ]; then
    return 0
  fi
  print_banner
  printf "${WHITE}  💻 Digite o e-mail para o certificado SSL (Let's Encrypt):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " deploy_email

  if ! validate_email "$deploy_email"; then
    printf "\n${RED}  ❌  E-mail inválido: ${deploy_email}${NC}\n"
    printf "${DIM}     Formato esperado: usuario@dominio.com${NC}\n"
    sleep 2
    frontnovo_get_email
    return
  fi
}

#######################################
# Create .env.local for frontendNovo
# Arguments:
#   None
#######################################
frontnovo_create_env() {
  step_header "⚙️ " "Criando .env.local do frontendNovo" \
    "Configura NEXT_PUBLIC_API_URL, chave de criptografia e porta."
  printf "  ${DIM}NEXT_PUBLIC_API_URL é lido do .env do backend (BACKEND_URL).${NC}\n\n"

  local _backend_api_url
  _backend_api_url=$(grep "^BACKEND_URL=" "${frontnovo_backend_env}" | cut -d'=' -f2 | tr -d '[:space:]')
  if [ -z "$_backend_api_url" ]; then
    printf "  ${YELLOW}⚠️   BACKEND_URL não encontrado em ${frontnovo_backend_env}.${NC}\n"
    printf "  ${YELLOW}     Edite manualmente o .env.local após a instalação.${NC}\n\n"
    _backend_api_url="https://api.seudominio.com.br"
  fi

  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

sudo su - deploycrm << EOF
  cat <<[-]EOF > "${_frontnovo_path}/.env.local"
NEXT_PUBLIC_API_URL=${_backend_api_url}
NEXT_PUBLIC_DEFAULT_ENCRYPTION_KEY=crm-passaporte-2024-encryption-key
NEXT_PUBLIC_INTERACTIVE_BAILEYS=false
# NEXT_PUBLIC_OAUTH_PROXY_URL=https://meta.zdg.com.br
PORT=${frontnovo_port}

# Ativa logs de debug no console do navegador (socket refresh da lista de tickets)
# NEXT_PUBLIC_DEBUG=true
[-]EOF
EOF

  printf "  ${GREEN}✅${NC}  .env.local criado em ${_frontnovo_path}/.env.local\n\n"
  sleep 1
}

#######################################
# Extract frontNovo from crm.zip if not exists
# Arguments:
#   None
#######################################
frontnovo_extract_files() {
  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

  # Verifica se já existe
  if [ -d "$_frontnovo_path" ] && [ -f "$_frontnovo_path/package.json" ]; then
    printf "  ${GREEN}✅${NC}  frontNovo já existe em $_frontnovo_path\n\n"
    sleep 1
    return 0
  fi

  step_header "📦" "Extraindo arquivos do frontNovo" \
    "Extrai frontNovo do crm.zip para ${frontnovo_instance_path}/"
  printf "  ${DIM}Copia os arquivos do Next.js para a instância selecionada.${NC}\n\n"

  local _crm_zip="${PROJECT_ROOT}/crm.zip"

  # Valida se crm.zip existe
  if [ ! -f "$_crm_zip" ]; then
    printf "  ${RED}❌  Arquivo crm.zip não encontrado em ${PROJECT_ROOT}/${NC}\n\n"
    return 1
  fi

  start_spinner "Extraindo frontNovo do crm.zip..."

  unzip -o "$_crm_zip" "crm/frontNovo/*" -d "$frontnovo_instance_path/.." > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao extrair frontNovo do crm.zip."
    return 1
  fi

  # Ajusta permissões
  chown -R deploycrm:deploycrm "${frontnovo_instance_path}/frontNovo" > /dev/null 2>&1

  # Valida se foi criado
  if [ ! -d "$_frontnovo_path" ]; then
    stop_spinner_error "Pasta frontNovo não foi criada após extração."
    return 1
  fi

  stop_spinner "frontNovo extraído com sucesso."
  sleep 1
}

#######################################
# Install npm dependencies for frontendNovo
# Arguments:
#   None
#######################################
frontnovo_node_dependencies() {
  step_header "📦" "Instalando dependências do frontendNovo" \
    "Executa npm install --force em ${frontnovo_instance_path}/frontNovo."
  printf "  ${DIM}Instala Next.js, React, Zustand e todas as dependências. Pode levar 3-5 min.${NC}\n\n"

  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

  start_spinner "Instalando pacotes npm do frontendNovo (pode demorar alguns minutos)..."
  sudo su - deploycrm <<EOF
  cd "${_frontnovo_path}"
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao instalar dependências do frontendNovo."
    log_error "npm install frontnovo" "Falha ao instalar dependências em ${_frontnovo_path}"
  else
    stop_spinner "Dependências do frontendNovo instaladas."
  fi
  sleep 1
}

#######################################
# Build frontendNovo for production
# Arguments:
#   None
#######################################
frontnovo_node_build() {
  step_header "🔨" "Compilando o frontendNovo" \
    "Executa npm run build — compila o Next.js para produção."
  printf "  ${DIM}Gera o bundle otimizado em .next — pode levar de 3 a 10 minutos.${NC}\n\n"

  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

  start_spinner "Compilando frontendNovo para produção (aguarde, pode demorar vários minutos)..."
  sudo su - deploycrm <<EOF
  cd "${_frontnovo_path}"
  npm run build
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao compilar o frontendNovo."
    log_error "frontnovo build" "Falha ao compilar em ${_frontnovo_path} (npm run build)"
  else
    stop_spinner "frontendNovo compilado. Bundle de produção gerado em .next"
  fi
  sleep 1
}

#######################################
# Start frontendNovo with PM2
# Arguments:
#   None
#######################################
frontnovo_start_pm2() {
  step_header "🚀" "Iniciando frontendNovo com PM2" \
    "Inicia o servidor Next.js com PM2 na porta ${frontnovo_port}."
  printf "  ${DIM}Processo: ${frontnovo_pm2_name} | O nginx encaminha HTTPS para esta porta.${NC}\n\n"

  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

  start_spinner "Iniciando ${frontnovo_pm2_name} na porta ${frontnovo_port}..."
  sudo su - deploycrm <<EOF
  cd "${_frontnovo_path}"
  pm2 start npm --name "${frontnovo_pm2_name}" -- run start
  pm2 save
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao iniciar frontendNovo no PM2."
    log_error "pm2 start frontnovo" "Falha ao iniciar ${frontnovo_pm2_name}"
  else
    stop_spinner "frontendNovo iniciado. Processo ${frontnovo_pm2_name} ativo no PM2."
  fi
  sleep 1
}

#######################################
# Stop and delete frontendNovo PM2 process
# Arguments:
#   None
#######################################
frontnovo_stop_pm2() {
  step_header "⏹️ " "Parando frontendNovo no PM2" \
    "Para e remove o processo ${frontnovo_pm2_name} para permitir o rebuild."
  printf "\n"

  start_spinner "Parando ${frontnovo_pm2_name}..."
  sudo su - deploycrm <<EOF
  pm2 stop "${frontnovo_pm2_name}" 2>/dev/null || true
  pm2 delete "${frontnovo_pm2_name}" 2>/dev/null || true
  pm2 save
EOF
  stop_spinner "${frontnovo_pm2_name} parado."
  sleep 1
}

#######################################
# Setup nginx vhost for frontendNovo
# Arguments:
#   None
#######################################
frontnovo_nginx_setup() {
  step_header "🌐" "Configurando nginx para o frontendNovo" \
    "Cria /etc/nginx/sites-available/crm-frontnovo e ativa o vhost."
  printf "  ${DIM}Proxy HTTPS → http://127.0.0.1:${frontnovo_port}${NC}\n\n"

  sleep 1

  local _frontnovo_hostname
  _frontnovo_hostname=$(echo "${frontnovo_url/https:\/\/}")
  _frontnovo_hostname=${_frontnovo_hostname%%/*}

sudo su - root << EOF

cat > /etc/nginx/sites-available/crm-frontnovo << 'END'
server {
  server_name ${_frontnovo_hostname};

  location / {
    proxy_pass http://127.0.0.1:${frontnovo_port};
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

ln -sf /etc/nginx/sites-available/crm-frontnovo /etc/nginx/sites-enabled/crm-frontnovo
nginx -t && systemctl reload nginx
EOF

  printf "  ${GREEN}✅${NC}  vhost crm-frontnovo criado e ativado no nginx.\n\n"
  sleep 1
}

#######################################
# Issue SSL certificate for frontendNovo
# Arguments:
#   None
#######################################
frontnovo_certbot_setup() {
  step_header "🔒" "Emitindo certificado SSL para o frontendNovo" \
    "Certbot valida o domínio via HTTP e emite o certificado Let's Encrypt."
  printf "  ${DIM}Configura redirecionamento automático HTTP → HTTPS no nginx.${NC}\n\n"

  local _frontnovo_hostname
  _frontnovo_hostname=$(echo "${frontnovo_url/https:\/\/}")
  _frontnovo_hostname=${_frontnovo_hostname%%/*}

  printf "  ${DIM}Domínio: ${_frontnovo_hostname}${NC}\n\n"

  start_spinner "Emitindo certificado SSL para ${_frontnovo_hostname}..."
  sudo su - root <<EOF
  certbot -m "${deploy_email}" \
          --nginx \
          --agree-tos \
          --redirect \
          --non-interactive \
          --domains "${_frontnovo_hostname}"
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao emitir certificado SSL. Verifique o DNS e tente novamente."
    log_error "certbot frontnovo" "Falha ao emitir SSL para ${_frontnovo_hostname}"
  else
    stop_spinner "Certificado SSL emitido. HTTPS ativo em ${_frontnovo_hostname}."
  fi
  sleep 1
}

#######################################
# Update backend .env with FRONTEND_URL_2 and SECURE_URL=*
# Then restart the backend PM2 process
# Arguments:
#   None
#######################################
frontnovo_backend_env_update() {
  step_header "⚙️ " "Configurando backend para o frontendNovo" \
    "Adiciona FRONTEND_URL_2 e SECURE_URL=* no .env do backend e reinicia."
  printf "  ${DIM}FRONTEND_URL_2 informa ao backend a URL do frontendNovo.${NC}\n"
  printf "  ${YELLOW}  SECURE_URL=* remove a restrição CORS — necessário para o beta.${NC}\n\n"

  # sanitiza CR/whitespace/trailing-;,/aspas — incidente CSP helmet (FRONTEND_URL_2=https://host;)
  local _frontnovo_hostname
  _frontnovo_hostname=$(printf '%s' "${frontnovo_url}" | tr -d '\r\n\t "'\''' | sed -E 's|^https?://||; s/[[:space:];,]+$//; s/^[[:space:]]+//')
  _frontnovo_hostname=${_frontnovo_hostname%%/*}
  if [ -z "${_frontnovo_hostname}" ] || [[ "${_frontnovo_hostname}" =~ [[:space:]] ]]; then
    stop_spinner_error "frontnovo_url inválido após sanitização: '${frontnovo_url}'"
    log_error "frontnovo_backend_env_update" "frontnovo_url inválido: '${frontnovo_url}'"
    return 1
  fi
  local _frontnovo_full_url="https://${_frontnovo_hostname}"

  sudo su - root << EOF
  # Remove entradas anteriores (idempotente)
  sed -i '/^FRONTEND_URL_2=/d' "${frontnovo_backend_env}"
  sed -i '/^SECURE_URL=/d' "${frontnovo_backend_env}"
  sed -i '/^# Remove restrição CORS/d' "${frontnovo_backend_env}"
  sed -i '/^# frontendNovo$/d' "${frontnovo_backend_env}"

  # Adiciona ao final do arquivo
  printf "\n# frontendNovo\nFRONTEND_URL_2=${_frontnovo_full_url}\n\n# Remove restrição CORS\nSECURE_URL=*\n" >> "${frontnovo_backend_env}"
EOF

  # Detect backend PM2 process name
  local _backend_pm2_name="crm-backend"
  if [ "${frontnovo_instance_path}" != "/home/deploycrm/crm" ]; then
    local _inst_name
    _inst_name=$(basename "${frontnovo_instance_path%/crm}")
    _backend_pm2_name="${_inst_name}-crm-backend"
  fi

  start_spinner "Reiniciando ${_backend_pm2_name} para aplicar novas variáveis..."
  sudo su - deploycrm <<EOF
  pm2 restart "${_backend_pm2_name}"
  pm2 save
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao reiniciar o backend. Reinicie manualmente: pm2 restart ${_backend_pm2_name}"
    log_error "pm2 restart backend" "Falha ao reiniciar ${_backend_pm2_name} após atualização do .env"
  else
    stop_spinner "Backend reiniciado com FRONTEND_URL_2 e SECURE_URL aplicados."
  fi
  sleep 1
}

#######################################
# Update source files (src, public, package.json, configs) from crm.zip
# Skips gracefully if crm.zip does not contain frontNovo entries.
# Preserves .env.local untouched.
# Arguments:
#   None
#######################################
frontnovo_update_source_files() {
  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"
  local _crm_zip="${PROJECT_ROOT}/crm.zip"

  # Check if zip contains frontNovo
  if [ ! -f "$_crm_zip" ]; then
    printf "  ${YELLOW}⚠️   crm.zip não encontrado — arquivos-fonte não serão atualizados.${NC}\n\n"
    sleep 1
    return 0
  fi

  local _has_frontnovo
  _has_frontnovo=$(unzip -l "$_crm_zip" 2>/dev/null | grep -c "crm/frontNovo/" || true)

  if [ "${_has_frontnovo:-0}" -eq 0 ]; then
    printf "  ${YELLOW}⚠️   crm.zip não contém frontNovo — arquivos-fonte não serão atualizados.${NC}\n\n"
    sleep 1
    return 0
  fi

  step_header "📂" "Atualizando arquivos-fonte do frontendNovo" \
    "Copia src/, public/, package.json e configs do crm.zip."
  printf "  ${DIM}O arquivo .env.local será preservado.${NC}\n\n"

  # Backup .env.local if it exists
  local _env_backup=""
  if [ -f "${_frontnovo_path}/.env.local" ]; then
    _env_backup=$(cat "${_frontnovo_path}/.env.local")
  fi

  start_spinner "Extraindo arquivos-fonte do frontNovo..."

  # Extract into a temp location then move, so we don't lose partial state on error
  local _tmp_extract="/tmp/frontnovo_update_$$"
  mkdir -p "$_tmp_extract"

  unzip -o "$_crm_zip" "crm/frontNovo/*" -d "$_tmp_extract" > /dev/null 2>&1
  local _unzip_rc=$?

  if [ "$_unzip_rc" -ne 0 ]; then
    stop_spinner_error "Falha ao extrair frontNovo do crm.zip."
    rm -rf "$_tmp_extract"
    return 1
  fi

  local _extracted_path="${_tmp_extract}/crm/frontNovo"

  if [ ! -d "$_extracted_path" ]; then
    stop_spinner_error "Pasta frontNovo não encontrada após extração."
    rm -rf "$_tmp_extract"
    return 1
  fi

  # Copy source files (preserve .env.local by not touching it)
  local _dirs_to_copy="src public"
  local _files_to_copy="package.json next.config.ts tsconfig.json tailwind.config.ts postcss.config.mjs vitest.config.ts next-env.d.ts .eslintrc.json .prettierrc .gitignore"

  for _dir in $_dirs_to_copy; do
    if [ -d "${_extracted_path}/${_dir}" ]; then
      sudo su - root <<EOF
      rm -rf "${_frontnovo_path}/${_dir}"
      cp -r "${_extracted_path}/${_dir}" "${_frontnovo_path}/${_dir}"
      chown -R deploycrm:deploycrm "${_frontnovo_path}/${_dir}"
EOF
    fi
  done

  for _file in $_files_to_copy; do
    if [ -f "${_extracted_path}/${_file}" ]; then
      sudo su - root <<EOF
      cp "${_extracted_path}/${_file}" "${_frontnovo_path}/${_file}"
      chown deploycrm:deploycrm "${_frontnovo_path}/${_file}"
EOF
    fi
  done

  # Restore .env.local
  if [ -n "$_env_backup" ]; then
    printf "%s" "$_env_backup" | sudo tee "${_frontnovo_path}/.env.local" > /dev/null
    sudo chown deploycrm:deploycrm "${_frontnovo_path}/.env.local"
  fi

  rm -rf "$_tmp_extract"

  stop_spinner "Arquivos-fonte atualizados (src/, public/, package.json e configs)."
  sleep 1
}

#######################################
# Delete .next and node_modules for clean update
# Arguments:
#   None
#######################################
frontnovo_delete_build() {
  step_header "🗑️ " "Removendo build anterior do frontendNovo" \
    "Apaga .next e node_modules para garantir um rebuild limpo."
  printf "  ${DIM}Ambas as pastas serão recriadas durante o reinstall + build.${NC}\n\n"

  local _frontnovo_path="${frontnovo_instance_path}/frontNovo"

  start_spinner "Removendo ${_frontnovo_path}/.next e node_modules..."
  sudo su - root <<EOF
  rm -rf "${_frontnovo_path}/.next"
  rm -rf "${_frontnovo_path}/node_modules"
EOF
  stop_spinner "Build anterior removido."
  sleep 1
}

#######################################
# Display install success message
# Arguments:
#   None
#######################################
frontnovo_install_success() {
  print_banner
  printf "${GREEN}  ✅  frontendNovo instalado com sucesso!${NC}\n\n"
  printf "${LINE}\n"

  local _frontnovo_hostname
  _frontnovo_hostname=$(echo "${frontnovo_url/https:\/\/}")
  _frontnovo_hostname=${_frontnovo_hostname%%/*}

  printf "${WHITE}  📊 Resumo da instalação:${NC}\n\n"
  printf "  • frontendNovo : ${GREEN}https://${_frontnovo_hostname}${NC}\n"
  printf "  • Porta        : ${frontnovo_port}\n"
  printf "  • PM2          : ${frontnovo_pm2_name}\n"
  printf "  • Instância    : ${frontnovo_instance_path}\n\n"
  printf "  ${YELLOW}⚠️   O frontendNovo está em BETA. Pode haver instabilidades.${NC}\n"
  printf "  ${DIM}Se encontrar problemas, siga o tutorial em:${NC}\n"
  printf "  ${GREEN}https://hotmart.com/es/club/whatitan${NC}\n"
  printf "  ${GREEN}Suporte: https://wa.me/50489520312/${NC}\n"
  printf "${LINE}\n\n"

  show_error_summary
  sleep 2
}

#######################################
# Display update success message
# Arguments:
#   None
#######################################
frontnovo_update_success() {
  print_banner
  printf "${GREEN}  ✅  frontendNovo atualizado com sucesso!${NC}\n\n"
  printf "${LINE}\n"

  printf "${WHITE}  📊 Resumo:${NC}\n\n"
  printf "  • PM2          : ${frontnovo_pm2_name}\n"
  printf "  • Instância    : ${frontnovo_instance_path}\n\n"
  printf "  ${YELLOW}⚠️   O frontendNovo está em BETA. Pode haver instabilidades.${NC}\n"
  printf "  ${DIM}Se encontrar problemas, siga o tutorial em:${NC}\n"
  printf "  ${GREEN}https://hotmart.com/es/club/whatitan${NC}\n"
  printf "  ${GREEN}Suporte: https://wa.me/50489520312/${NC}\n"
  printf "${LINE}\n\n"

  show_error_summary
  sleep 2
}

#######################################
# Full install flow for frontendNovo
# Arguments:
#   None
#######################################
install_frontnovo() {
  init_error_log "frontnovo_install"
  warn_snapshot_required "instalação do frontendNovo paralelo (legado)" || return 1
  frontnovo_warn_beta
  frontnovo_select_instance || return 1
  frontnovo_check_not_installed || return 1
  frontnovo_get_url
  frontnovo_get_port
  frontnovo_get_email
  frontnovo_extract_files || return 1
  frontnovo_create_env
  frontnovo_node_dependencies
  frontnovo_node_build
  frontnovo_start_pm2
  frontnovo_nginx_setup
  frontnovo_certbot_setup
  frontnovo_backend_env_update
  frontnovo_install_success
}

#######################################
# Full update flow for frontendNovo
# Arguments:
#   None
#######################################
update_frontnovo() {
  init_error_log "frontnovo_update"
  warn_snapshot_required "atualização do frontendNovo (beta)" || return 1
  frontnovo_warn_beta
  frontnovo_select_instance || return 1
  frontnovo_stop_pm2
  frontnovo_delete_build
  frontnovo_update_source_files
  frontnovo_node_dependencies
  frontnovo_node_build
  frontnovo_start_pm2
  frontnovo_update_success
}

#######################################
# Install or Update menu for frontendNovo (modo legado: subdomínio paralelo).
# Mantido apenas para usuários que ainda querem instalar Next em subdomínio
# separado mantendo o Vue. O caminho oficial agora é o update normal (opção [2]).
# Arguments:
#   None
#######################################
frontnovo_install_or_update() {
  print_banner
  printf "${WHITE}  💻 frontendNovo em subdomínio paralelo (modo legado)${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${GREEN}[1]${NC}  Instalar frontendNovo paralelo\n"
  printf "       ${DIM}↳ Mantém o frontend principal intocado, sobe Next em outro subdomínio${NC}\n\n"
  printf "  ${YELLOW}[2]${NC}  Atualizar frontendNovo paralelo\n"
  printf "       ${DIM}↳ Para PM2 do paralelo, apaga .next + node_modules, reinstala e rebuilda${NC}\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n\n"
  read -p "  Opção > " _fn_option

  case "${_fn_option}" in
    1) install_frontnovo ;;
    2) update_frontnovo ;;
    0) inquiry_options ;;
    *) frontnovo_install_or_update ;;
  esac
}

# =====================================================================
# SUB-MENU DINÂMICO PARA OPÇÃO [15] — baseado em detect_frontend_state
# =====================================================================

#######################################
# Seleciona instância (primária ou multi) para o sub-menu de gestão.
# Sets: frontnovo_target_instance (vazia = primária; ex: "crm2" = multi)
#######################################
frontnovo_select_target_instance() {
  local instances=()
  while IFS= read -r fname; do
    instances+=("$fname")
  done < <(list_crm_instances)

  if [ ${#instances[@]} -le 1 ]; then
    frontnovo_target_instance=""
    return 0
  fi

  print_banner
  printf "${WHITE}  💻 Selecione a instância para gerenciar:${NC}\n\n"
  printf "${LINE}\n"
  for i in "${!instances[@]}"; do
    local fname="${instances[$i]}"
    local label
    if [ -z "$fname" ]; then
      label="crm (primária)"
    else
      label="$fname"
    fi
    local state
    state=$(detect_frontend_state "$fname")
    printf "  ${GREEN}[$((i+1))]${NC}  ${label}  ${DIM}— ${state}${NC}\n"
  done
  printf "${LINE}\n\n"
  read -p "  Número > " _inst
  if ! [[ "$_inst" =~ ^[0-9]+$ ]] || [ "$_inst" -lt 1 ] || [ "$_inst" -gt "${#instances[@]}" ]; then
    frontnovo_target_instance=""
    return 1
  fi
  frontnovo_target_instance="${instances[$((_inst-1))]}"
}

#######################################
# Cleanup do .env do backend — remove FRONTEND_URL_2 e SECURE_URL=*.
# Cenário 4 (next_only_dirty_env).
# Arguments:
#   $1 - folder_name
#######################################
cleanup_legacy_env() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local env_file="$base/backend/.env"
  local pm2_be="${fname:+${fname}-}crm-backend"

  if [ ! -f "$env_file" ]; then
    printf "  ${RED}❌  .env do backend não encontrado: ${env_file}${NC}\n\n"
    return 1
  fi

  step_header "🧹" "Limpando FRONTEND_URL_2 / SECURE_URL legado" \
    "Backup em ${env_file}.bak.\$(date +%s) antes de remover."

  printf "${WHITE}  Linhas a remover:${NC}\n"
  grep -E '^(FRONTEND_URL_2|SECURE_URL|# Remove restrição CORS|# frontendNovo)=*' "$env_file" | sed 's/^/    /'
  printf "\n${YELLOW}  Confirma remoção? SECURE_URL=* pode estar lá por integração externa. (s/N):${NC}\n"
  read -p "  > " _conf
  [ "$_conf" = "s" ] || [ "$_conf" = "S" ] || { printf "${YELLOW}  Cancelado.${NC}\n\n"; return 0; }

  sudo cp "$env_file" "$env_file.bak.$(date +%s)"
  sudo sed -i '/^FRONTEND_URL_2=/d' "$env_file"
  sudo sed -i '/^SECURE_URL=/d' "$env_file"
  sudo sed -i '/^# Remove restrição CORS/d' "$env_file"
  sudo sed -i '/^# frontendNovo$/d' "$env_file"

  start_spinner "Reiniciando ${pm2_be}..."
  sudo su - deploycrm -c "pm2 restart ${pm2_be}; pm2 save"
  stop_spinner "${pm2_be} reiniciado."

  printf "  ${GREEN}✅${NC}  .env limpo. Backup em ${env_file}.bak.*\n\n"
}

#######################################
# Renomeia pasta frontNovo/ órfã (sem PM2) para legacy.
# Cenário 5 (*_with_orphan_novo).
# Arguments:
#   $1 - folder_name
#######################################
cleanup_orphan_novo() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  if [ ! -d "$base/frontNovo" ]; then
    printf "  ${YELLOW}  Pasta $base/frontNovo não existe.${NC}\n\n"
    return 0
  fi
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  printf "${WHITE}  Renomear $base/frontNovo → $base/frontNovo.legacy.${ts}/${NC}\n"
  printf "${YELLOW}  Confirma? (s/N):${NC}\n"
  read -p "  > " _conf
  [ "$_conf" = "s" ] || [ "$_conf" = "S" ] || { printf "${YELLOW}  Cancelado.${NC}\n\n"; return 0; }
  sudo mv "$base/frontNovo" "$base/frontNovo.legacy.${ts}"
  printf "  ${GREEN}✅${NC}  $base/frontNovo.legacy.${ts}/ criado.\n\n"
}

#######################################
# Limpa backups antigos (frontend.legacy.*, frontend.bak.*, frontend.failed.*)
# preservando o mais recente. Confirma cada um.
# Arguments:
#   $1 - folder_name
#######################################
cleanup_old_backups() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local backups=()
  while IFS= read -r b; do
    [ -d "$b" ] && backups+=("$b")
  done < <(ls -1dt "$base"/frontend.legacy.* "$base"/frontend.bak.* "$base"/frontend.failed.* 2>/dev/null)

  if [ ${#backups[@]} -le 1 ]; then
    printf "  ${DIM}Nenhum backup antigo a limpar (mantém-se sempre o mais recente).${NC}\n\n"
    return 0
  fi

  step_header "🗑️ " "Backups antigos do frontend em [${fname:-primária}]" \
    "Mantém o mais recente para rollback. Mover para /tmp/crm_trash_<epoch>/."

  printf "${WHITE}  Backups encontrados (mais novo no topo):${NC}\n"
  for i in "${!backups[@]}"; do
    local size
    size=$(du -sh "${backups[$i]}" 2>/dev/null | cut -f1)
    if [ "$i" = "0" ]; then
      printf "  ${GREEN}[${i}]${NC} ${backups[$i]} (${size})  ${DIM}← mais recente, será mantido${NC}\n"
    else
      printf "  ${YELLOW}[${i}]${NC} ${backups[$i]} (${size})\n"
    fi
  done
  printf "\n${YELLOW}  Confirma mover do índice 1+ para /tmp/crm_trash_$(date +%s)/? (s/N):${NC}\n"
  read -p "  > " _conf
  [ "$_conf" = "s" ] || [ "$_conf" = "S" ] || { printf "${YELLOW}  Cancelado.${NC}\n\n"; return 0; }

  local trash="/tmp/crm_trash_$(date +%s)"
  sudo mkdir -p "$trash"
  for i in "${!backups[@]}"; do
    [ "$i" = "0" ] && continue
    sudo mv "${backups[$i]}" "$trash/"
  done
  printf "  ${GREEN}✅${NC}  Backups movidos para ${trash}/. Use 'rm -rf' manualmente quando confirmar.\n\n"
}

#######################################
# Sub-menu dinâmico baseado em detect_frontend_state.
# Substitui o handler estático do menu [15].
#######################################
frontnovo_dynamic_menu() {
  frontnovo_select_target_instance || { ask_continue; return; }
  local fname="${frontnovo_target_instance:-}"
  local label
  if [ -z "$fname" ]; then
    label="crm (primária)"
  else
    label="$fname"
  fi

  # Antes do menu de estado normal, checar inconsistência (Cenário 6)
  local inc_state
  inc_state=$(detect_inconsistent_state "$fname")
  if [ "$inc_state" != "ok" ]; then
    print_banner
    printf "${RED}  ⚠️   Estado inconsistente detectado em [${label}]: ${inc_state}${NC}\n\n"
    printf "${LINE}\n"
    printf "  ${GREEN}[1]${NC}  Continuar a migração (re-extrair / re-build / consertar PM2)\n"
    printf "  ${YELLOW}[2]${NC}  Rollback para Vue legacy\n"
    printf "  ${DIM}[0]${NC}  Voltar\n"
    printf "${LINE}\n\n"
    read -p "  Opção > " _resume
    case "$_resume" in
      1) migrate_vue_to_next "$fname" ;;
      2)
        local last_ts
        last_ts=$(ls -1 "$(frontend_base_path "$fname")"/frontend.legacy.* 2>/dev/null | sort | tail -1 | sed 's|.*frontend.legacy.||')
        rollback_to_vue_legacy "$fname" "$last_ts"
        ;;
      *) inquiry_options ;;
    esac
    return
  fi

  local state
  state=$(detect_frontend_state "$fname")
  print_banner
  printf "${WHITE}  💻 Gerenciar frontendNovo — [${label}]${NC}\n"
  printf "  ${DIM}Estado: ${state}${NC}\n\n"
  printf "${LINE}\n"

  case "$state" in
    none)
      printf "  ${DIM}Nenhum frontend instalado. Use [1] Instalar crm no menu principal.${NC}\n"
      ;;
    vue_only)
      printf "  ${DIM}Frontend em Vue. Para migrar, rode [2] Atualizar crm no menu principal.${NC}\n"
      printf "  ${DIM}A migração Vue → Next é silenciosa e automática no Update.${NC}\n\n"
      printf "  ${GREEN}[1]${NC}  Limpar backups antigos\n"
      ;;
    vue_only_with_orphan_novo)
      printf "  ${GREEN}[1]${NC}  Limpar pasta frontNovo/ órfã (rename → .legacy.<ts>/)\n"
      printf "  ${GREEN}[2]${NC}  Limpar backups antigos\n"
      ;;
    vue_and_novo)
      if [ -n "$fname" ]; then
        printf "  ${RED}⚠️   Estado anômalo em instância secundária — instalar paralelo manualmente.${NC}\n"
      else
        printf "  ${YELLOW}[1]${NC}  Atualizar (Vue → Next + manter paralelo) — rode [2] do menu principal\n"
        printf "  ${GREEN}[2]${NC}  Desativar paralelo (redirect 301 do app2 → app)\n"
      fi
      ;;
    next_only)
      printf "  ${DIM}Frontend já é Next. [2] do menu principal faz rebuild.${NC}\n\n"
      printf "  ${GREEN}[1]${NC}  Limpar backups antigos\n"
      ;;
    next_only_dirty_env)
      printf "  ${YELLOW}[1]${NC}  Limpar FRONTEND_URL_2 / SECURE_URL=* legado do backend .env\n"
      printf "  ${GREEN}[2]${NC}  Limpar backups antigos\n"
      ;;
    next_only_with_orphan_novo)
      printf "  ${GREEN}[1]${NC}  Limpar pasta frontNovo/ órfã (rename → .legacy.<ts>/)\n"
      printf "  ${YELLOW}[2]${NC}  Limpar FRONTEND_URL_2 / SECURE_URL legado se presente\n"
      printf "  ${GREEN}[3]${NC}  Limpar backups antigos\n"
      ;;
    next_and_paralelo)
      if [ -n "$fname" ]; then
        printf "  ${RED}⚠️   Estado anômalo em instância secundária.${NC}\n"
      else
        printf "  ${GREEN}[1]${NC}  Desativar paralelo (redirect 301 do app2 → app)\n"
      fi
      ;;
    *)
      printf "  ${RED}Estado desconhecido (${state}). Verificar manualmente.${NC}\n"
      ;;
  esac

  printf "${LINE}\n"
  printf "  ${DIM}[L]${NC}  Modo legado: instalar/atualizar paralelo (subdomínio separado)\n"
  printf "  ${DIM}[0]${NC}  Voltar\n\n"
  read -p "  Opção > " _opt

  case "${state}:${_opt}" in
    vue_only:1|next_only:1) cleanup_old_backups "$fname" ;;
    vue_only_with_orphan_novo:1) cleanup_orphan_novo "$fname" ;;
    vue_only_with_orphan_novo:2) cleanup_old_backups "$fname" ;;
    next_only_dirty_env:1) cleanup_legacy_env "$fname" ;;
    next_only_dirty_env:2) cleanup_old_backups "$fname" ;;
    next_only_with_orphan_novo:1) cleanup_orphan_novo "$fname" ;;
    next_only_with_orphan_novo:2) cleanup_legacy_env "$fname" ;;
    next_only_with_orphan_novo:3) cleanup_old_backups "$fname" ;;
    next_and_paralelo:1) promote_frontnovo_to_primary "$fname" ;;
    vue_and_novo:2) promote_frontnovo_to_primary "$fname" ;;
    *:L|*:l) frontnovo_install_or_update ;;
    *:0) inquiry_options ;;
    *)   frontnovo_dynamic_menu ;;
  esac
}

#######################################
# Cenário 3 — promove frontendNovo paralelo a primário.
# Reescreve vhosts (Vue → Next na primária; paralelo → 301 redirect),
# limpa backend .env, renomeia frontNovo/ para legacy.
# Arguments:
#   $1 - folder_name (esperado vazio — só primária)
#######################################
promote_frontnovo_to_primary() {
  local fname="${1:-}"
  if [ -n "$fname" ]; then
    printf "  ${RED}❌  promote_frontnovo_to_primary só roda na instância primária.${NC}\n\n"
    return 1
  fi
  local base
  base=$(frontend_base_path "")
  local env_file="$base/backend/.env"
  local _frontend_url _frontnovo_url
  _frontend_url=$(grep -E '^FRONTEND_URL=' "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
  _frontnovo_url=$(grep -E '^FRONTEND_URL_2=' "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')

  if [ -z "$_frontend_url" ] || [ -z "$_frontnovo_url" ]; then
    printf "  ${RED}❌  FRONTEND_URL ou FRONTEND_URL_2 não encontrado em ${env_file}.${NC}\n\n"
    return 1
  fi

  local fnovo_port
  fnovo_port=$(grep -E '^PORT=' "$base/frontNovo/.env.local" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
  fnovo_port="${fnovo_port:-3000}"

  local fnovo_host fhost
  fnovo_host=$(echo "${_frontnovo_url/https:\/\/}" | cut -d'/' -f1)
  fhost=$(echo "${_frontend_url/https:\/\/}" | cut -d'/' -f1)
  local ts
  ts=$(date +%s)

  step_header "🔁" "Desativando paralelo: ${fnovo_host} → 301 → ${fhost}" \
    "vhost crm-frontend passa a apontar para porta ${fnovo_port} (Next)."
  printf "${YELLOW}  Confirma? (s/N):${NC}\n"
  read -p "  > " _conf
  [ "$_conf" = "s" ] || [ "$_conf" = "S" ] || { printf "${YELLOW}  Cancelado.${NC}\n\n"; return 0; }

  warn_snapshot_required "promoção do frontendNovo a primário" || return 1

  sudo cp /etc/nginx/sites-available/crm-frontend "/etc/nginx/sites-available/crm-frontend.bak.${ts}" 2>/dev/null || true
  sudo cp /etc/nginx/sites-available/crm-frontnovo "/etc/nginx/sites-available/crm-frontnovo.bak.${ts}" 2>/dev/null || true
  sudo cp "$env_file" "$env_file.bak.${ts}"

  # Reescreve crm-frontend para apontar pro Next
  sudo sed -i "s|proxy_pass http://127\.0\.0\.1:[0-9]\+|proxy_pass http://127.0.0.1:${fnovo_port}|" /etc/nginx/sites-available/crm-frontend

  # Reescreve crm-frontnovo para 301 (preservando bloco SSL — só altera o location /)
  sudo sed -i "/location \/ {/,/^  }$/c\  location / {\n    return 301 https://${fhost}\$request_uri;\n  }" /etc/nginx/sites-available/crm-frontnovo

  sudo nginx -t && sudo systemctl reload nginx
  if [ $? -ne 0 ]; then
    printf "  ${RED}❌  nginx -t falhou. Restaurando backups.${NC}\n"
    sudo cp "/etc/nginx/sites-available/crm-frontend.bak.${ts}" /etc/nginx/sites-available/crm-frontend
    sudo cp "/etc/nginx/sites-available/crm-frontnovo.bak.${ts}" /etc/nginx/sites-available/crm-frontnovo
    sudo systemctl reload nginx
    return 1
  fi

  # Limpa backend .env (FRONTEND_URL_2, SECURE_URL)
  sudo sed -i '/^FRONTEND_URL_2=/d; /^SECURE_URL=/d; /^# Remove restrição CORS/d; /^# frontendNovo$/d' "$env_file"

  # IMPORTANTE: o vhost crm-frontend foi reescrito acima para apontar pra
  # porta do Next (fnovo_port). Logo, NÃO podemos deletar crm-frontnovo nem
  # renomear o diretório frontNovo/ — o processo PM2 do Next continua sendo o
  # que serve o domínio primário agora.
  # Vue: pm2 delete (em vez de stop) pra que pm2 resurrect/save não traga ele
  # de volta. Next: restart pra recarregar config/.env mais recentes.
  sudo su - deploycrm -c "pm2 delete crm-frontend 2>/dev/null || true; pm2 restart crm-frontnovo; pm2 restart crm-backend; pm2 save"

  printf "  ${GREEN}✅${NC}  Paralelo desativado. ${fnovo_host} → 301 → ${fhost}.\n"
  printf "  ${DIM}Next continua em PM2 como crm-frontnovo, em ${base}/frontNovo.${NC}\n\n"
}
