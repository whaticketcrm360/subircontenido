#!/bin/bash
#
# Backup e rollback de versões anteriores

ROLLBACK_DIR="/root/crm_backups"

#######################################
# Aviso obrigatório de snapshot antes de
# qualquer operação que envolva o banco.
# Exige confirmação explícita ou aborta.
# Arguments:
#   $1 - Contexto da operação (ex: "atualização", "rollback")
# Returns:
#   0 = confirmado, 1 = cancelado
#######################################
warn_snapshot_required() {
  local context="${1:-operação}"

  print_banner
  printf "${RED}${DLINE}${NC}\n"
  printf "\n"
  printf "  ${RED}⚠️   ATENÇÃO — SNAPSHOT OBRIGATÓRIO${NC}\n"
  printf "\n"
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  Esta ${context} envolve o banco de dados.\n\n"
  printf "  ${WHITE}Falhas durante operações no banco podem causar corrupção de dados${NC}\n"
  printf "  ${WHITE}que NÃO PODEM SER RECUPERADOS sem um snapshot da VPS.${NC}\n\n"
  printf "  ${YELLOW}Antes de continuar, certifique-se de ter criado um snapshot${NC}\n"
  printf "  ${YELLOW}completo da sua VPS no painel do provedor (ex: DigitalOcean,${NC}\n"
  printf "  ${YELLOW}Contabo, Hetzner, AWS, etc.).${NC}\n\n"
  printf "  ${DIM}O snapshot captura o estado completo do servidor, incluindo banco${NC}\n"
  printf "  ${DIM}de dados, arquivos e configurações. Em caso de falha elétrica,${NC}\n"
  printf "  ${DIM}travamento da VPS ou erro inesperado durante a operação, o snapshot${NC}\n"
  printf "  ${DIM}é a única forma de recuperação garantida.${NC}\n\n"
  printf "${RED}${DLINE}${NC}\n\n"
  printf "  Para confirmar que o snapshot foi criado, digite ${WHITE}CONFIRMO${NC}:\n"
  printf "  (ou pressione Enter para cancelar)\n\n"
  read -p "  > " _snapshot_confirm

  if [[ "${_snapshot_confirm}" != "CONFIRMO" ]]; then
    printf "\n  ${YELLOW}Operação cancelada. Crie o snapshot e tente novamente.${NC}\n\n"
    sleep 1
    return 1
  fi

  printf "\n  ${GREEN}✅ Confirmado. Prosseguindo...${NC}\n\n"
  sleep 1
  return 0
}

#######################################
# Pergunta ao usuário o modo de backup
# Define global: ROLLBACK_WITH_DUMP
#   "false" = somente código
#   "true"  = código + banco
#   "skip"  = sem backup
#######################################
rollback_ask_mode() {
  print_banner
  printf "${WHITE}  💾 Backup antes de atualizar${NC}\n\n"
  printf "${GREEN}${DLINE}${NC}\n"
  printf "  ${GREEN}[1]${NC}  Somente código\n"
  printf "       ${DIM}↳ Salva os arquivos da aplicação. Rápido (~1min).${NC}\n"
  printf "       ${DIM}  Banco não incluído.${NC}\n\n"
  printf "  ${YELLOW}[2]${NC}  Código + banco de dados\n"
  printf "       ${DIM}↳ Salva código e dump completo do PostgreSQL.${NC}\n"
  printf "       ${DIM}  Mais completo (~3-5min dependendo do banco).${NC}\n\n"
  printf "  ${DIM}[0]${NC}  Continuar sem backup\n"
  printf "       ${DIM}↳ Útil para quem já fez snapshot da VPS.${NC}\n"
  printf "${GREEN}${DLINE}${NC}\n\n"

  read -p "  Opção > " _rollback_choice

  case "${_rollback_choice}" in
    1)
      ROLLBACK_WITH_DUMP="false"
      ;;
    2)
      ROLLBACK_WITH_DUMP="true"
      ;;
    0)
      ROLLBACK_WITH_DUMP="skip"
      printf "\n  ${YELLOW}⚠️  Prosseguindo sem backup.${NC}\n\n"
      sleep 1
      ;;
    *)
      ROLLBACK_WITH_DUMP="false"
      ;;
  esac
}

#######################################
# Cria backup da instância principal
# (/home/deploycrm/crm)
#######################################
rollback_create_backup() {
  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  local backup_path="${ROLLBACK_DIR}/${timestamp}_main"

  print_banner
  printf "${WHITE}  💾 Criando backup da instância principal...${GRAY_LIGHT}"
  printf "\n\n"

  sudo su - root <<EOF
  mkdir -p "${backup_path}"

  tar --exclude='/home/deploycrm/crm/backend/node_modules' \
      --exclude='/home/deploycrm/crm/backend/dist' \
      --exclude='/home/deploycrm/crm/frontend/node_modules' \
      --exclude='/home/deploycrm/crm/frontend/dist' \
      --exclude='/home/deploycrm/crm/frontend/.quasar' \
      -czf "${backup_path}/code.tar.gz" \
      /home/deploycrm/crm 2>/dev/null

  echo "main" > "${backup_path}/type"
  echo "/home/deploycrm/crm" > "${backup_path}/instance_path"
  date '+%Y-%m-%d %H:%M:%S' > "${backup_path}/created_at"
  printf "${GREEN}  ✅ Backup de código criado.${NC}\n"
EOF

  if [[ "${ROLLBACK_WITH_DUMP}" == "true" ]]; then
    _rollback_dump_db "${backup_path}" "/home/deploycrm/crm/backend/.env"
  fi

  sleep 2
}

#######################################
# Cria backup de uma instância secundária
# Arguments:
#   $1 - Caminho da instância
#   $2 - Nome da instância
#######################################
rollback_create_instance_backup() {
  local INSTANCE_PATH="$1"
  local INSTANCE_NAME="$2"
  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  local backup_path="${ROLLBACK_DIR}/${timestamp}_${INSTANCE_NAME}"

  print_banner
  printf "${WHITE}  💾 Criando backup da instância ${INSTANCE_NAME}...${GRAY_LIGHT}"
  printf "\n\n"

  sudo su - root <<EOF
  mkdir -p "${backup_path}"

  tar --exclude="${INSTANCE_PATH}/backend/node_modules" \
      --exclude="${INSTANCE_PATH}/backend/dist" \
      --exclude="${INSTANCE_PATH}/frontend/node_modules" \
      --exclude="${INSTANCE_PATH}/frontend/dist" \
      --exclude="${INSTANCE_PATH}/frontend/.quasar" \
      -czf "${backup_path}/code.tar.gz" \
      "${INSTANCE_PATH}" 2>/dev/null

  echo "${INSTANCE_NAME}" > "${backup_path}/type"
  echo "${INSTANCE_PATH}" > "${backup_path}/instance_path"
  date '+%Y-%m-%d %H:%M:%S' > "${backup_path}/created_at"
  printf "${GREEN}  ✅ Backup de código criado: ${backup_path}${NC}\n"
EOF

  if [[ "${ROLLBACK_WITH_DUMP}" == "true" ]]; then
    _rollback_dump_db "${backup_path}" "${INSTANCE_PATH}/backend/.env"
  fi

  sleep 2
}

#######################################
# Executa pg_dump do banco da instância
# Arguments:
#   $1 - Diretório do backup
#   $2 - Caminho do .env com credenciais
#######################################
_rollback_dump_db() {
  local backup_path="$1"
  local env_file="$2"

  print_banner
  printf "${WHITE}  💾 Fazendo dump do banco de dados...${GRAY_LIGHT}"
  printf "\n\n"

  sudo su - root <<EOF
  if [ ! -f "${env_file}" ]; then
    printf "${RED}  ❌ .env não encontrado: ${env_file}${NC}\n"
    exit 0
  fi

  DB_NAME=\$(grep "^DB_NAME=" "${env_file}" | cut -d'=' -f2 | tr -d '[:space:]')
  DB_USER=\$(grep "^DB_USER=" "${env_file}" | cut -d'=' -f2 | tr -d '[:space:]')

  if [ -z "\${DB_NAME}" ] || [ -z "\${DB_USER}" ]; then
    printf "${RED}  ❌ DB_NAME ou DB_USER não encontrado no .env${NC}\n"
    exit 0
  fi

  if ! docker ps -q -f name=postgresql 2>/dev/null | grep -q .; then
    printf "${RED}  ❌ Container postgresql não está rodando. Dump ignorado.${NC}\n"
    exit 0
  fi

  docker exec postgresql pg_dump -U "\${DB_USER}" "\${DB_NAME}" | gzip > "${backup_path}/db.sql.gz"
  echo "\${DB_NAME}" > "${backup_path}/db_name"
  echo "\${DB_USER}" > "${backup_path}/db_user"
  printf "${GREEN}  ✅ Dump do banco criado.${NC}\n"
EOF

  sleep 2
}

#######################################
# Menu principal de rollback
#######################################
rollback_menu() {
  print_banner
  printf "${WHITE}  🔄 Restaurar versão anterior${NC}\n\n"

  if [ ! -d "${ROLLBACK_DIR}" ] || [ -z "$(ls -A "${ROLLBACK_DIR}" 2>/dev/null)" ]; then
    printf "  ${YELLOW}  Nenhum backup encontrado em ${ROLLBACK_DIR}${NC}\n\n"
    printf "  ${DIM}Os backups são criados automaticamente ao usar as opções${NC}\n"
    printf "  ${DIM}[2] Atualizar crm e [4] Atualizar instâncias secundárias.${NC}\n\n"
    return 0
  fi

  printf "${GREEN}${LINE}${NC}\n"

  local idx=1
  local dirs=()

  for dir in $(ls -t "${ROLLBACK_DIR}" 2>/dev/null); do
    local backup_path="${ROLLBACK_DIR}/${dir}"
    [ -d "$backup_path" ] || continue
    local created
    created=$(cat "${backup_path}/created_at" 2>/dev/null || echo "data desconhecida")
    local type
    type=$(cat "${backup_path}/type" 2>/dev/null || echo "?")
    local has_dump=""
    [ -f "${backup_path}/db.sql.gz" ] && has_dump="${GREEN} + banco${NC}"
    local code_size
    code_size=$(du -sh "${backup_path}/code.tar.gz" 2>/dev/null | cut -f1 || echo "?")
    printf "  ${GREEN}[${idx}]${NC}  ${created}  —  instância: ${YELLOW}${type}${NC}  —  ${code_size}${has_dump}\n"
    dirs+=("$backup_path")
    idx=$((idx + 1))
  done

  printf "${GREEN}${LINE}${NC}\n\n"
  printf "  Digite o número do backup para restaurar (ou Enter para cancelar):\n"
  read -p "  > " restore_choice

  if [ -z "$restore_choice" ]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n"
    return 0
  fi

  if ! [[ "$restore_choice" =~ ^[0-9]+$ ]] || \
     [ "$restore_choice" -lt 1 ] || \
     [ "$restore_choice" -gt "${#dirs[@]}" ]; then
    printf "\n  ${RED}❌ Opção inválida.${NC}\n"
    return 1
  fi

  _rollback_confirm_restore "${dirs[$((restore_choice - 1))]}"
}

#######################################
# Confirma e executa o restore
# Arguments:
#   $1 - Diretório do backup selecionado
#######################################
_rollback_confirm_restore() {
  local backup_path="$1"
  local type
  type=$(cat "${backup_path}/type" 2>/dev/null || echo "?")
  local created
  created=$(cat "${backup_path}/created_at" 2>/dev/null || echo "?")
  local has_dump=false
  [ -f "${backup_path}/db.sql.gz" ] && has_dump=true

  print_banner
  printf "${WHITE}  🔄 Restaurar versão anterior${NC}\n\n"
  printf "${GREEN}${DLINE}${NC}\n"
  printf "  Backup     : ${YELLOW}${created}${NC}\n"
  printf "  Instância  : ${YELLOW}${type}${NC}\n"
  if [ "$has_dump" = true ]; then
    printf "  Banco      : ${GREEN}dump disponível${NC}\n"
  else
    printf "  Banco      : ${DIM}não incluído${NC}\n"
  fi
  printf "${GREEN}${DLINE}${NC}\n\n"

  local restore_mode

  if [ "$has_dump" = true ]; then
    printf "  ${GREEN}[1]${NC}  Restaurar código + banco de dados\n"
    printf "       ${DIM}↳ ⚠️  Banco será revertido. Dados após o backup serão perdidos.${NC}\n\n"
    printf "  ${YELLOW}[2]${NC}  Restaurar somente código\n"
    printf "       ${DIM}↳ Banco permanece como está (recomendado se não houve mudança de schema).${NC}\n\n"
    printf "  ${RED}[0]${NC}  Cancelar\n\n"
    read -p "  Opção > " restore_mode
  else
    printf "  ${DIM}Este backup não inclui dump do banco.${NC}\n"
    printf "  ${YELLOW}O banco permanecerá na versão atual.${NC}\n\n"
    printf "  ${GREEN}[1]${NC}  Restaurar código\n"
    printf "  ${RED}[0]${NC}  Cancelar\n\n"
    read -p "  Opção > " restore_mode
    [ "$restore_mode" = "1" ] && restore_mode="2"
  fi

  case "$restore_mode" in
    0|"")
      printf "\n  ${YELLOW}Operação cancelada.${NC}\n"
      return 0
      ;;
    1)
      warn_snapshot_required "restauração com reversão do banco" || return 1
      _rollback_do_restore "${backup_path}" true
      ;;
    2)
      _rollback_do_restore "${backup_path}" false
      ;;
    *)
      printf "\n  ${RED}❌ Opção inválida.${NC}\n"
      return 1
      ;;
  esac
}

#######################################
# Executa a restauração
# Arguments:
#   $1 - Diretório do backup
#   $2 - true = restaurar banco também
#######################################
_rollback_do_restore() {
  local backup_path="$1"
  local restore_db="$2"
  local instance_path
  instance_path=$(cat "${backup_path}/instance_path" 2>/dev/null || echo "/home/deploycrm/crm")

  print_banner
  printf "${WHITE}  🔄 Parando serviços PM2...${GRAY_LIGHT}\n\n"

  sudo su - deploycrm <<EOF
  pm2 stop all
  pm2 flush all
EOF

  sleep 2

  print_banner
  printf "${WHITE}  🔄 Restaurando código...${GRAY_LIGHT}\n\n"

  sudo su - root <<EOF
  tar -xzf "${backup_path}/code.tar.gz" -C / 2>/dev/null
  printf "${GREEN}  ✅ Código restaurado.${NC}\n"
EOF

  sleep 2

  if [[ "${restore_db}" == "true" ]] && [ -f "${backup_path}/db.sql.gz" ]; then
    print_banner
    printf "${WHITE}  🔄 Restaurando banco de dados...${GRAY_LIGHT}\n\n"

    sudo su - root <<EOF
    DB_NAME=\$(cat "${backup_path}/db_name" 2>/dev/null)
    DB_USER=\$(cat "${backup_path}/db_user" 2>/dev/null)

    if [ -z "\${DB_NAME}" ] || [ -z "\${DB_USER}" ]; then
      printf "${RED}  ❌ Credenciais do backup não encontradas. Banco não restaurado.${NC}\n"
      exit 0
    fi

    if ! docker ps -q -f name=postgresql 2>/dev/null | grep -q .; then
      printf "${RED}  ❌ Container postgresql não está rodando. Banco não restaurado.${NC}\n"
      exit 0
    fi

    # Termina conexões ativas no banco
    docker exec postgresql psql -U "\${DB_USER}" -d postgres -c \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='\${DB_NAME}' AND pid <> pg_backend_pid();" \
      > /dev/null 2>&1

    # Drop e recria o banco
    docker exec postgresql psql -U "\${DB_USER}" -d postgres -c "DROP DATABASE IF EXISTS \"\${DB_NAME}\";" > /dev/null 2>&1
    docker exec postgresql psql -U "\${DB_USER}" -d postgres -c "CREATE DATABASE \"\${DB_NAME}\";" > /dev/null 2>&1

    # Restaura o dump
    gunzip -c "${backup_path}/db.sql.gz" | docker exec -i postgresql psql -U "\${DB_USER}" "\${DB_NAME}" > /dev/null 2>&1
    printf "${GREEN}  ✅ Banco de dados restaurado.${NC}\n"
EOF

    sleep 2
  fi

  print_banner
  printf "${WHITE}  🔄 Reinstalando dependências do backend...${GRAY_LIGHT}\n\n"

  sudo su - deploycrm <<EOF
  cd "${instance_path}/backend"
  npm install --force
EOF

  sleep 2

  print_banner
  printf "${WHITE}  🔄 Reinstalando dependências e compilando frontend...${GRAY_LIGHT}\n\n"

  sudo su - deploycrm <<EOF
  cd "${instance_path}/frontend"
  npm install --force
  npm run build
EOF

  sleep 2

  print_banner
  printf "${WHITE}  🔄 Reiniciando PM2...${GRAY_LIGHT}\n\n"

  sudo su - deploycrm <<EOF
  pm2 restart all
EOF

  sleep 2

  print_banner
  printf "${GREEN}  ✅ Rollback concluído!${NC}\n\n"
  printf "${GREEN}${DLINE}${NC}\n"

  if [[ "${restore_db}" == "true" ]]; then
    printf "  Código e banco restaurados para: ${YELLOW}$(cat "${backup_path}/created_at" 2>/dev/null)${NC}\n"
  else
    printf "  Código restaurado para: ${YELLOW}$(cat "${backup_path}/created_at" 2>/dev/null)${NC}\n"
    printf "\n  ${YELLOW}⚠️  Banco permanece na versão atual.${NC}\n"
    printf "  ${DIM}   Se houve db:migrate na atualização, pode haver incompatibilidade.${NC}\n"
    printf "  ${DIM}   Neste caso, execute um novo backup com dump para rollback completo.${NC}\n"
  fi

  printf "${GREEN}${DLINE}${NC}\n\n"

  sleep 2
}
