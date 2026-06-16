#!/bin/bash
#
# PgBouncer — connection pooler para PostgreSQL
# Suporta primeira instância e instâncias secundárias crm

_PB_CONFIG_DIR="/etc/pgbouncer"
_PB_PORT_START=6432

#######################################
# Detecta todas as instâncias crm com .env
# Popula arrays globais:
#   _pb_instances[]   — nome da instância
#   _pb_paths[]       — diretório crm
#   _pb_envfiles[]    — caminho do .env
#   _pb_pm2names[]    — nome do processo PM2
#######################################
_pgbouncer_detect_instances() {
  _pb_instances=()
  _pb_paths=()
  _pb_envfiles=()
  _pb_pm2names=()

  # Primeira instância
  if [ -f "/home/deploycrm/crm/backend/.env" ]; then
    _pb_instances+=("primeira_instancia")
    _pb_paths+=("/home/deploycrm/crm")
    _pb_envfiles+=("/home/deploycrm/crm/backend/.env")
    _pb_pm2names+=("crm-backend")
  fi

  # Instâncias secundárias: /home/deploycrm/<nome>/crm/backend/.env
  while IFS= read -r envfile; do
    local folder_name
    folder_name=$(echo "$envfile" | sed 's|/home/deploycrm/||' | cut -d'/' -f1)
    if [ -n "$folder_name" ] && [ "$folder_name" != "crm" ]; then
      _pb_instances+=("$folder_name")
      _pb_paths+=("/home/deploycrm/$folder_name/crm")
      _pb_envfiles+=("$envfile")
      _pb_pm2names+=("${folder_name}-crm-backend")
    fi
  done < <(find /home/deploycrm -mindepth 4 -maxdepth 4 -path "*/crm/backend/.env" 2>/dev/null | sort)
}

#######################################
# Retorna a porta PgBouncer para uma instância.
# Reutiliza a porta existente se já houver config.
# Arguments:
#   $1 - config name (ex: crm-main, crm-crm2)
# Returns: porta (stdout)
#######################################
_pgbouncer_get_port() {
  local config_name="$1"
  local config_file="${_PB_CONFIG_DIR}/${config_name}.ini"

  # Reutiliza porta existente
  if [ -f "$config_file" ]; then
    local existing
    existing=$(grep -oP '(?<=listen_port = )\d+' "$config_file" 2>/dev/null || echo "")
    if [ -n "$existing" ]; then
      echo "$existing"
      return
    fi
  fi

  # Atribui próxima porta livre a partir de 6432
  local port=$_PB_PORT_START
  while [ $port -le 6500 ]; do
    if ! grep -rl "listen_port = $port" "${_PB_CONFIG_DIR}/" 2>/dev/null | grep -q .; then
      echo "$port"
      return
    fi
    port=$((port + 1))
  done

  echo $_PB_PORT_START
}

#######################################
# Menu de gerenciamento do PgBouncer
#######################################
pgbouncer_menu() {
  print_banner
  printf "${CYAN_LIGHT}  🔌  PgBouncer — Connection Pooler${NC}\n"
  printf "${LINE}\n"
  printf "${DIM}  Proxy de conexões entre o backend crm e o PostgreSQL.${NC}\n\n"
  printf "  ${GREEN}[1]${NC}  Instalar / Configurar PgBouncer\n"
  printf "       ${DIM}↳ Instala e configura o pooler para uma instância crm${NC}\n\n"
  printf "  ${YELLOW}[2]${NC}  Status dos serviços PgBouncer\n"
  printf "       ${DIM}↳ Exibe estado de todos os serviços pgbouncer-crm-* ativos${NC}\n\n"
  printf "  ${RED}[3]${NC}  Remover configuração de uma instância\n"
  printf "       ${DIM}↳ Para o serviço, reverte .env e remove arquivos de config${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n\n"
  read -p "  Opção > " _pb_menu_opt

  case "${_pb_menu_opt}" in
    1) pgbouncer_setup ;;
    2) pgbouncer_status ;;
    3) pgbouncer_remove ;;
    0) return 0 ;;
    *) pgbouncer_menu ;;
  esac
}

#######################################
# Exibe status de todos os serviços PgBouncer crm
#######################################
pgbouncer_status() {
  print_banner
  printf "${CYAN_LIGHT}  📊  Status PgBouncer${NC}\n"
  printf "${LINE}\n\n"

  local found=0
  while IFS= read -r svc; do
    found=1
    local svc_name
    svc_name=$(basename "$svc" .service)
    local status
    status=$(systemctl is-active "$svc_name" 2>/dev/null || echo "desconhecido")

    # Tenta ler a porta do config correspondente
    local config_name="${svc_name#pgbouncer-}"
    local config_file="${_PB_CONFIG_DIR}/${config_name}.ini"
    local port
    port=$(grep -oP '(?<=listen_port = )\d+' "$config_file" 2>/dev/null || echo "?")
    local pg_target
    pg_target=$(grep -oP '(?<=port=)\d+' "$config_file" 2>/dev/null | head -1 || echo "?")

    if [ "$status" = "active" ]; then
      printf "  ${GREEN}●${NC}  ${WHITE}${svc_name}${NC}  ${GREEN}[active]${NC}\n"
    else
      printf "  ${RED}●${NC}  ${WHITE}${svc_name}${NC}  ${RED}[${status}]${NC}\n"
    fi
    printf "     ${DIM}Porta PgBouncer : ${port}  →  PostgreSQL : ${pg_target}${NC}\n"
    printf "     ${DIM}Config          : ${config_file}${NC}\n"
    printf "     ${DIM}Logs            : sudo journalctl -u ${svc_name} -n 50${NC}\n\n"
  done < <(find /etc/systemd/system -name "pgbouncer-crm-*.service" 2>/dev/null | sort)

  if [ $found -eq 0 ]; then
    printf "  ${YELLOW}Nenhum serviço PgBouncer crm encontrado.${NC}\n\n"
    printf "  ${DIM}Use a opção [1] para instalar e configurar.${NC}\n\n"
  fi

  printf "${LINE}\n"
}

#######################################
# Instala e configura PgBouncer para uma instância
#######################################
pgbouncer_setup() {
  # ─── AVISO OBRIGATÓRIO ──────────────────────────────────────────────────────
  print_banner
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  ${RED}⚠️   ATENÇÃO — OPERAÇÃO CRÍTICA DE INFRAESTRUTURA${NC}\n\n"
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  ${WHITE}Este processo instala e configura o PgBouncer como proxy de${NC}\n"
  printf "  ${WHITE}conexões entre o backend crm e o PostgreSQL.${NC}\n\n"
  printf "  ${YELLOW}RECOMENDAÇÕES OBRIGATÓRIAS ANTES DE CONTINUAR:${NC}\n\n"
  printf "  ${RED}•${NC}  ${WHITE}Este processo DEVE ser acompanhado por um especialista em${NC}\n"
  printf "     ${WHITE}infraestrutura ou DBA.${NC}\n"
  printf "     ${DIM}Erros de configuração podem derrubar o banco e impedir o sistema${NC}\n"
  printf "     ${DIM}de funcionar. Não execute isso sem supervisão técnica adequada.${NC}\n\n"
  printf "  ${RED}•${NC}  ${WHITE}Crie um snapshot completo da VPS AGORA, antes de continuar.${NC}\n"
  printf "     ${DIM}Acesse o painel do seu provedor (DigitalOcean, Hetzner, Contabo,${NC}\n"
  printf "     ${DIM}AWS, etc.) e tire o snapshot. Em caso de falha, é a única forma${NC}\n"
  printf "     ${DIM}de recuperação garantida.${NC}\n\n"
  printf "  ${RED}•${NC}  ${WHITE}O backend crm será reiniciado durante o processo.${NC}\n"
  printf "     ${DIM}Isso causará uma breve interrupção no atendimento.${NC}\n\n"
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  ${YELLOW}Para confirmar que você leu este aviso E criou o snapshot,${NC}\n"
  printf "  ${YELLOW}digite ${WHITE}CONFIRMO${YELLOW} em maiúsculas (ou Enter para cancelar):${NC}\n\n"
  read -p "  > " _pb_confirm

  if [[ "${_pb_confirm}" != "CONFIRMO" ]]; then
    printf "\n  ${YELLOW}Operação cancelada. Crie o snapshot e tente novamente.${NC}\n\n"
    sleep 1
    return 0
  fi

  printf "\n  ${GREEN}✅ Confirmado. Prosseguindo...${NC}\n\n"
  sleep 1

  # ─── DETECTAR INSTÂNCIAS ────────────────────────────────────────────────────
  _pgbouncer_detect_instances

  if [ ${#_pb_instances[@]} -eq 0 ]; then
    printf "${RED}  ❌  Nenhuma instância crm encontrada em /home/deploycrm/!${NC}\n\n"
    printf "${DIM}     Verifique se o crm está instalado corretamente.${NC}\n\n"
    return 1
  fi

  # ─── SELECIONAR INSTÂNCIA ───────────────────────────────────────────────────
  print_banner
  printf "${CYAN_LIGHT}  🔌  Configurar PgBouncer — Selecione a instância${NC}\n"
  printf "${LINE}\n\n"

  for i in "${!_pb_instances[@]}"; do
    local current_db_port
    current_db_port=$(grep "^DB_PORT=" "${_pb_envfiles[$i]}" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "?")
    local current_pg_host
    current_pg_host=$(grep "^POSTGRES_HOST=" "${_pb_envfiles[$i]}" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "localhost")

    printf "  ${GREEN}[$((i+1))]${NC}  ${WHITE}${_pb_instances[$i]}${NC}\n"
    printf "       ${DIM}Path : ${_pb_paths[$i]}${NC}\n"
    printf "       ${DIM}DB   : ${current_pg_host}:${current_db_port}${NC}\n\n"
  done

  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Cancelar\n\n"
  read -p "  Opção > " _pb_choice

  if [ "$_pb_choice" = "0" ] || [ -z "$_pb_choice" ]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
    return 0
  fi

  if ! [[ "$_pb_choice" =~ ^[0-9]+$ ]] || \
     [ "$_pb_choice" -lt 1 ] || \
     [ "$_pb_choice" -gt "${#_pb_instances[@]}" ]; then
    printf "${RED}  ❌  Opção inválida.${NC}\n\n"
    return 1
  fi

  local sel_idx=$((_pb_choice - 1))
  local sel_instance="${_pb_instances[$sel_idx]}"
  local sel_path="${_pb_paths[$sel_idx]}"
  local sel_envfile="${_pb_envfiles[$sel_idx]}"
  local sel_pm2name="${_pb_pm2names[$sel_idx]}"

  # ─── LER CREDENCIAIS DO .ENV ────────────────────────────────────────────────
  local pg_host pg_port pg_user pg_pass_env pg_db
  pg_host=$(grep "^POSTGRES_HOST=" "$sel_envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "localhost")
  pg_port=$(grep "^DB_PORT=" "$sel_envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "5433")
  pg_user=$(grep "^POSTGRES_USER=" "$sel_envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "postgres")
  pg_pass_env=$(grep "^POSTGRES_PASSWORD=" "$sel_envfile" 2>/dev/null | cut -d'=' -f2-)
  pg_db=$(grep "^POSTGRES_DB=" "$sel_envfile" 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]' || echo "postgres")

  if [ -z "$pg_pass_env" ]; then
    printf "${RED}  ❌  Não foi possível ler POSTGRES_PASSWORD do .env!${NC}\n\n"
    printf "${DIM}     Arquivo: ${sel_envfile}${NC}\n\n"
    return 1
  fi

  # ─── DEFINIR NOMES E PORTAS ─────────────────────────────────────────────────
  local pb_config_name
  if [ "$sel_instance" = "primeira_instancia" ]; then
    pb_config_name="crm-main"
  else
    pb_config_name="crm-${sel_instance}"
  fi

  local pb_config_file="${_PB_CONFIG_DIR}/${pb_config_name}.ini"
  local pb_userlist_file="${_PB_CONFIG_DIR}/${pb_config_name}-userlist.txt"
  local pb_service_name="pgbouncer-${pb_config_name}"
  local pb_port
  pb_port=$(_pgbouncer_get_port "$pb_config_name")

  # Verifica se já está configurado
  if [ -f "$pb_config_file" ]; then
    printf "\n${YELLOW}  ⚠️   PgBouncer já está configurado para esta instância.${NC}\n\n"
    printf "  Config : ${DIM}${pb_config_file}${NC}\n"
    printf "  Porta  : ${DIM}${pb_port}${NC}\n\n"
    printf "  ${YELLOW}Deseja reconfigurar (sobrescreve a config atual)? (s/N):${NC}\n"
    read -p "  > " _pb_reconfig
    if [ "$_pb_reconfig" != "s" ] && [ "$_pb_reconfig" != "S" ]; then
      printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
      return 0
    fi
    # Garante que a porta seja reutilizada na reconfiguração
  fi

  # ─── EXIBIR PLANO E CONFIRMAR ───────────────────────────────────────────────
  print_banner
  printf "${CYAN_LIGHT}  🔌  Plano de configuração — PgBouncer${NC}\n"
  printf "${LINE}\n\n"
  printf "  ${WHITE}Instância         :${NC} ${sel_instance}\n"
  printf "  ${WHITE}Processo PM2      :${NC} ${sel_pm2name}\n"
  printf "  ${WHITE}PostgreSQL atual  :${NC} ${pg_host}:${pg_port}  (banco: ${pg_db})\n"
  printf "  ${WHITE}PgBouncer         :${NC} 127.0.0.1:${pb_port}  (pool mode: transaction)\n"
  printf "  ${WHITE}Config file       :${NC} ${pb_config_file}\n"
  printf "  ${WHITE}Serviço systemd   :${NC} ${pb_service_name}\n\n"
  printf "${LINE}\n"
  printf "  ${YELLOW}Alterações que serão realizadas:${NC}\n\n"
  printf "  ${DIM}1.${NC}  Instalar pgbouncer via apt (se ausente)\n"
  printf "  ${DIM}2.${NC}  Desabilitar serviço pgbouncer padrão\n"
  printf "  ${DIM}3.${NC}  Criar ${pb_config_file}\n"
  printf "  ${DIM}4.${NC}  Criar ${pb_userlist_file}\n"
  printf "  ${DIM}5.${NC}  Criar /etc/systemd/system/${pb_service_name}.service\n"
  printf "  ${DIM}6.${NC}  Atualizar ${sel_envfile}:\n"
  printf "        ${DIM}DB_PORT: ${pg_port}  →  ${pb_port}${NC}\n"
  printf "  ${DIM}7.${NC}  Reiniciar PM2: ${sel_pm2name}\n\n"
  printf "${LINE}\n"
  printf "  ${YELLOW}Confirma execução? (s/N):${NC}\n"
  read -p "  > " _pb_exec_confirm

  if [ "$_pb_exec_confirm" != "s" ] && [ "$_pb_exec_confirm" != "S" ]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
    return 0
  fi

  # ─── BACKUP DO .ENV ─────────────────────────────────────────────────────────
  local env_backup="${sel_envfile}.pgbouncer_bkp_$(date +%Y%m%d_%H%M%S)"
  start_spinner "Criando backup do .env..."
  if ! cp "$sel_envfile" "$env_backup"; then
    stop_spinner_error "Falha ao criar backup do .env."
    log_error "pgbouncer backup" "Falha ao copiar ${sel_envfile} para ${env_backup}"
    return 1
  fi
  stop_spinner "Backup criado: $(basename "$env_backup")"
  sleep 1

  # ─── INSTALAR PGBOUNCER ─────────────────────────────────────────────────────
  step_header "📦" "Instalando PgBouncer" \
    "Instalação via apt. O serviço padrão será desabilitado — usamos serviços por instância."

  start_spinner "Executando apt-get install pgbouncer..."
  if ! sudo apt-get update -qq 2>/dev/null && sudo apt-get install -y pgbouncer 2>/dev/null; then
    # Tenta sem o update separado (algumas distros têm apt-get update problemático)
    sudo apt-get install -y pgbouncer > /dev/null 2>&1
  fi
  if ! command -v pgbouncer > /dev/null 2>&1; then
    stop_spinner_error "Falha ao instalar pgbouncer. Verifique a conectividade e tente: sudo apt-get install pgbouncer"
    log_error "pgbouncer install" "pgbouncer não encontrado após apt-get install"
    return 1
  fi

  # Desabilita serviço padrão para evitar conflito de porta
  sudo systemctl stop pgbouncer 2>/dev/null || true
  sudo systemctl disable pgbouncer 2>/dev/null || true
  stop_spinner "PgBouncer instalado. Serviço padrão desabilitado."
  sleep 1

  # ─── CRIAR CONFIGURAÇÃO ─────────────────────────────────────────────────────
  step_header "⚙️ " "Criando configuração do PgBouncer" \
    "Pool mode: transaction | Max client conn: 500 | Default pool: 20"

  # Hash MD5 da senha para o userlist.txt: md5( senha + usuário )
  local pg_pass_md5
  pg_pass_md5="md5$(printf '%s' "${pg_pass_env}${pg_user}" | md5sum | cut -d' ' -f1)"

  sudo mkdir -p "${_PB_CONFIG_DIR}"

  start_spinner "Criando ${pb_config_file}..."
  sudo tee "${pb_config_file}" > /dev/null << EOF
[databases]
${pg_db} = host=${pg_host} port=${pg_port} dbname=${pg_db}

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = ${pb_port}
auth_file = ${pb_userlist_file}
auth_type = md5
pool_mode = transaction
max_client_conn = 500
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
server_idle_timeout = 600
client_idle_timeout = 0
server_lifetime = 3600
log_connections = 0
log_disconnections = 0
log_pooler_errors = 1
stats_period = 60
pidfile = /var/run/postgresql/${pb_config_name}.pid
logfile = /var/log/postgresql/${pb_config_name}.log
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao criar ${pb_config_file}."
    log_error "pgbouncer config" "Falha ao criar ${pb_config_file}"
    return 1
  fi
  stop_spinner "Arquivo de configuração criado."

  # Cria userlist.txt com hash MD5
  start_spinner "Criando userlist.txt com hash MD5..."
  sudo tee "${pb_userlist_file}" > /dev/null << EOF
"${pg_user}" "${pg_pass_md5}"
EOF
  sudo chmod 640 "${pb_userlist_file}"
  sudo chown root:postgres "${pb_userlist_file}" 2>/dev/null || \
    sudo chown root:pgbouncer "${pb_userlist_file}" 2>/dev/null || true
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao criar userlist.txt."
    log_error "pgbouncer userlist" "Falha ao criar ${pb_userlist_file}"
    return 1
  fi
  stop_spinner "Userlist criado com autenticação MD5."

  # Garante diretórios de log/pid acessíveis
  sudo mkdir -p /var/run/postgresql /var/log/postgresql
  sleep 1

  # ─── CRIAR SERVIÇO SYSTEMD ──────────────────────────────────────────────────
  step_header "🔧" "Criando serviço systemd: ${pb_service_name}" \
    "O PgBouncer iniciará automaticamente com o servidor."

  start_spinner "Criando /etc/systemd/system/${pb_service_name}.service..."
  sudo tee "/etc/systemd/system/${pb_service_name}.service" > /dev/null << EOF
[Unit]
Description=PgBouncer Connection Pooler - crm (${sel_instance})
Documentation=https://www.pgbouncer.org/
After=network.target docker.service

[Service]
Type=forking
User=postgres
ExecStart=/usr/sbin/pgbouncer -d ${pb_config_file}
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/postgresql/${pb_config_name}.pid
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=${pb_service_name}

[Install]
WantedBy=multi-user.target
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao criar serviço systemd."
    log_error "pgbouncer service" "Falha ao criar /etc/systemd/system/${pb_service_name}.service"
    return 1
  fi

  sudo systemctl daemon-reload
  sudo systemctl enable "${pb_service_name}" 2>/dev/null
  sudo systemctl start "${pb_service_name}" 2>/dev/null
  sleep 3

  local pb_start_ok=0
  if sudo systemctl is-active --quiet "${pb_service_name}" 2>/dev/null; then
    stop_spinner "Serviço ${pb_service_name} iniciado e habilitado no boot."
    pb_start_ok=1
  else
    stop_spinner_error "Serviço não iniciou. Verifique: sudo systemctl status ${pb_service_name}"
    log_error "pgbouncer start" "Serviço ${pb_service_name} falhou ao iniciar"
    printf "\n  ${DIM}Logs:${NC}\n"
    sudo journalctl -u "${pb_service_name}" -n 20 --no-pager 2>/dev/null | sed 's/^/     /'
    printf "\n"
  fi
  sleep 1

  # ─── ATUALIZAR .ENV ─────────────────────────────────────────────────────────
  step_header "📝" "Atualizando .env do backend" \
    "DB_PORT: ${pg_port} → ${pb_port}"

  start_spinner "Atualizando DB_PORT em ${sel_envfile}..."
  sudo sed -i "s|^DB_PORT=.*|DB_PORT=${pb_port}|" "$sel_envfile"
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao atualizar .env."
    log_error "pgbouncer env" "Falha ao atualizar DB_PORT em ${sel_envfile}"
    return 1
  fi
  stop_spinner ".env atualizado (DB_PORT=${pb_port})."
  sleep 1

  # ─── REINICIAR BACKEND ──────────────────────────────────────────────────────
  step_header "🔄" "Reiniciando backend" \
    "Recarregando configuração do PM2: ${sel_pm2name}"

  start_spinner "Reiniciando ${sel_pm2name}..."
  sudo -u deploycrm pm2 restart "${sel_pm2name}" 2>/dev/null
  sleep 4

  local pm2_ok=0
  if sudo -u deploycrm pm2 list 2>/dev/null | grep -E "${sel_pm2name}.*online" > /dev/null 2>&1; then
    stop_spinner "Backend ${sel_pm2name} reiniciado e online."
    pm2_ok=1
  else
    stop_spinner_error "Backend pode não estar online. Verifique: pm2 logs ${sel_pm2name}"
    log_error "pgbouncer pm2" "PM2 restart de ${sel_pm2name} — status não confirmado"
  fi
  sleep 1

  # ─── RESUMO FINAL ───────────────────────────────────────────────────────────
  print_banner
  printf "${GREEN}${DLINE}${NC}\n\n"
  if [ $pb_start_ok -eq 1 ] && [ $pm2_ok -eq 1 ]; then
    printf "  ${GREEN}✅  PgBouncer configurado com sucesso!${NC}\n\n"
  else
    printf "  ${YELLOW}⚠️   PgBouncer configurado com avisos. Revise os itens abaixo.${NC}\n\n"
  fi
  printf "${GREEN}${DLINE}${NC}\n\n"

  printf "${CYAN_LIGHT}  📋 RESUMO DAS ALTERAÇÕES${NC}\n"
  printf "${LINE}\n\n"
  printf "  ${WHITE}Instância         :${NC} ${sel_instance}\n"
  printf "  ${WHITE}Serviço PgBouncer :${NC} ${pb_service_name}\n"
  printf "  ${WHITE}Porta PgBouncer   :${NC} ${pb_port}\n"
  printf "  ${WHITE}Aponta para       :${NC} ${pg_host}:${pg_port}  (PostgreSQL original)\n"
  printf "  ${WHITE}Pool mode         :${NC} transaction\n"
  printf "  ${WHITE}Max client conn   :${NC} 500\n"
  printf "  ${WHITE}Default pool size :${NC} 20\n\n"

  printf "${LINE}\n"
  printf "  ${WHITE}Arquivos criados / modificados:${NC}\n\n"

  if [ $pb_start_ok -eq 1 ]; then
    printf "  ${GREEN}[OK]${NC}  ${pb_config_file}\n"
    printf "  ${GREEN}[OK]${NC}  ${pb_userlist_file}\n"
    printf "  ${GREEN}[OK]${NC}  /etc/systemd/system/${pb_service_name}.service\n"
  else
    printf "  ${RED}[ERRO]${NC} ${pb_config_file}  ${DIM}(serviço não iniciou — verifique o arquivo)${NC}\n"
    printf "  ${YELLOW}[OK]${NC}   ${pb_userlist_file}\n"
    printf "  ${YELLOW}[OK]${NC}   /etc/systemd/system/${pb_service_name}.service\n"
  fi

  if [ $pm2_ok -eq 1 ]; then
    printf "  ${GREEN}[OK]${NC}  ${sel_envfile}\n"
  else
    printf "  ${YELLOW}[AVISO]${NC} ${sel_envfile}  ${DIM}(alterado, mas PM2 pode não estar online)${NC}\n"
  fi

  printf "  ${DIM}[BKP]${NC}  ${env_backup}\n\n"

  printf "${LINE}\n"
  printf "  ${WHITE}Status dos serviços:${NC}\n\n"

  local pb_final_status
  pb_final_status=$(sudo systemctl is-active "${pb_service_name}" 2>/dev/null || echo "desconhecido")
  if [ "$pb_final_status" = "active" ]; then
    printf "  ${GREEN}●${NC}  ${pb_service_name}  ${GREEN}[active]${NC}\n"
  else
    printf "  ${RED}●${NC}  ${pb_service_name}  ${RED}[${pb_final_status}]${NC}\n"
  fi
  printf "  ${DIM}    sudo journalctl -u ${pb_service_name} -n 50${NC}\n\n"

  if [ $pm2_ok -eq 1 ]; then
    printf "  ${GREEN}●${NC}  ${sel_pm2name}  ${GREEN}[online]${NC}\n\n"
  else
    printf "  ${RED}●${NC}  ${sel_pm2name}  ${RED}[verificar]${NC}\n"
    printf "  ${DIM}    pm2 logs ${sel_pm2name}${NC}\n\n"
  fi

  printf "${RED}${DLINE}${NC}\n"
  printf "\n  ${RED}⚠️   COMO REVERTER — guarde estas instruções${NC}\n\n"
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  ${WHITE}Passo 1 — Restaurar o .env original:${NC}\n"
  printf "  ${DIM}  sudo cp ${env_backup} \\${NC}\n"
  printf "  ${DIM}          ${sel_envfile}${NC}\n\n"
  printf "  ${WHITE}Passo 2 — Reiniciar o backend:${NC}\n"
  printf "  ${DIM}  sudo -u deploycrm pm2 restart ${sel_pm2name}${NC}\n\n"
  printf "  ${WHITE}Passo 3 — Parar e desabilitar o PgBouncer:${NC}\n"
  printf "  ${DIM}  sudo systemctl stop ${pb_service_name}${NC}\n"
  printf "  ${DIM}  sudo systemctl disable ${pb_service_name}${NC}\n\n"
  printf "  ${WHITE}Passo 4 — Remover arquivos de configuração (opcional):${NC}\n"
  printf "  ${DIM}  sudo rm -f ${pb_config_file}${NC}\n"
  printf "  ${DIM}  sudo rm -f ${pb_userlist_file}${NC}\n"
  printf "  ${DIM}  sudo rm -f /etc/systemd/system/${pb_service_name}.service${NC}\n"
  printf "  ${DIM}  sudo systemctl daemon-reload${NC}\n\n"
  printf "${RED}${DLINE}${NC}\n\n"
  sleep 2
}

#######################################
# Remove configuração PgBouncer de uma instância
#######################################
pgbouncer_remove() {
  _pgbouncer_detect_instances

  # Lista serviços PgBouncer existentes
  local pb_services=()
  while IFS= read -r svc; do
    pb_services+=("$(basename "$svc" .service)")
  done < <(find /etc/systemd/system -name "pgbouncer-crm-*.service" 2>/dev/null | sort)

  if [ ${#pb_services[@]} -eq 0 ]; then
    print_banner
    printf "${YELLOW}  Nenhum serviço PgBouncer crm encontrado para remover.${NC}\n\n"
    return 0
  fi

  print_banner
  printf "${CYAN_LIGHT}  🗑️   Remover PgBouncer — Selecione o serviço${NC}\n"
  printf "${LINE}\n\n"

  for i in "${!pb_services[@]}"; do
    local svc="${pb_services[$i]}"
    local status
    status=$(sudo systemctl is-active "$svc" 2>/dev/null || echo "inativo")
    printf "  ${RED}[$((i+1))]${NC}  ${svc}  ${DIM}[${status}]${NC}\n"
  done

  printf "\n${LINE}\n"
  printf "  ${DIM}[0]${NC}  Cancelar\n\n"
  read -p "  Opção > " _pb_rm_choice

  if [ "$_pb_rm_choice" = "0" ] || [ -z "$_pb_rm_choice" ]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
    return 0
  fi

  if ! [[ "$_pb_rm_choice" =~ ^[0-9]+$ ]] || \
     [ "$_pb_rm_choice" -lt 1 ] || \
     [ "$_pb_rm_choice" -gt "${#pb_services[@]}" ]; then
    printf "${RED}  ❌  Opção inválida.${NC}\n\n"
    return 1
  fi

  local sel_svc="${pb_services[$((_pb_rm_choice - 1))]}"
  local config_name="${sel_svc#pgbouncer-}"
  local config_file="${_PB_CONFIG_DIR}/${config_name}.ini"
  local userlist_file="${_PB_CONFIG_DIR}/${config_name}-userlist.txt"

  # Descobre qual instância e porta estava usando
  local pb_port
  pb_port=$(grep -oP '(?<=listen_port = )\d+' "$config_file" 2>/dev/null || echo "?")
  local pg_port
  pg_port=$(grep -oP '(?<=port=)\d+' "$config_file" 2>/dev/null | head -1 || echo "5433")

  # Tenta identificar o .env para reverter o DB_PORT
  local sel_envfile=""
  local sel_pm2name=""
  for i in "${!_pb_instances[@]}"; do
    local inst="${_pb_instances[$i]}"
    local expected_config
    if [ "$inst" = "primeira_instancia" ]; then
      expected_config="crm-main"
    else
      expected_config="crm-${inst}"
    fi
    if [ "$expected_config" = "$config_name" ]; then
      sel_envfile="${_pb_envfiles[$i]}"
      sel_pm2name="${_pb_pm2names[$i]}"
      break
    fi
  done

  printf "\n${YELLOW}  ⚠️   Confirma remoção de ${sel_svc}? (s/N):${NC}\n"
  read -p "  > " _pb_rm_confirm
  if [ "$_pb_rm_confirm" != "s" ] && [ "$_pb_rm_confirm" != "S" ]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
    return 0
  fi

  local removed_ok=1

  start_spinner "Parando e desabilitando ${sel_svc}..."
  sudo systemctl stop "${sel_svc}" 2>/dev/null || true
  sudo systemctl disable "${sel_svc}" 2>/dev/null || true
  stop_spinner "Serviço parado e desabilitado."

  start_spinner "Removendo arquivos de configuração..."
  [ -f "$config_file" ] && sudo rm -f "$config_file"
  [ -f "$userlist_file" ] && sudo rm -f "$userlist_file"
  [ -f "/etc/systemd/system/${sel_svc}.service" ] && sudo rm -f "/etc/systemd/system/${sel_svc}.service"
  sudo systemctl daemon-reload
  stop_spinner "Arquivos removidos."

  # Reverte o .env se encontrado
  if [ -n "$sel_envfile" ] && [ -f "$sel_envfile" ] && [ "$pb_port" != "?" ]; then
    start_spinner "Revertendo DB_PORT no .env (${pb_port} → ${pg_port})..."
    sudo sed -i "s|^DB_PORT=.*|DB_PORT=${pg_port}|" "$sel_envfile"
    if [ -n "$sel_pm2name" ]; then
      sudo -u deploycrm pm2 restart "${sel_pm2name}" 2>/dev/null
    fi
    stop_spinner ".env revertido e backend reiniciado."
  fi

  print_banner
  printf "${GREEN}  ✅  ${sel_svc} removido com sucesso.${NC}\n\n"
  if [ -n "$sel_envfile" ] && [ "$pb_port" != "?" ]; then
    printf "  ${DIM}DB_PORT revertido para ${pg_port} em ${sel_envfile}${NC}\n\n"
  fi
  sleep 2
}
