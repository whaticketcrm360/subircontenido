#!/bin/bash
#
# Pre-flight checks and system requirements for the Vue -> Next migration.
# Implements Fase 0 of docs/PLANO_FRONTNOVO_OFICIAL.md.

#######################################
# Ensure Node.js >= 18.17 (required by Next 14+).
# Idempotent: no-op if already on Node 18+.
# Arguments:
#   None
#######################################
system_install_node20() {
  local cur major
  cur=$(node -v 2>/dev/null | sed 's/^v//')
  major="${cur%%.*}"
  if [ -n "$cur" ] && [ "${major:-0}" -ge 18 ]; then
    printf "  ${GREEN}✅${NC}  Node.js v${cur} já atende requisito (>= 18.17).\n\n"
    return 0
  fi

  step_header "🟢" "Instalando Node.js 20 LTS" \
    "Next 14+ exige Node >= 18.17. Instalando via NodeSource."
  printf "  ${DIM}Versão atual: ${cur:-nenhuma}${NC}\n\n"

  start_spinner "Instalando Node.js 20 LTS..."
  sudo su - root <<EOF
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao instalar Node.js 20."
    log_error "node20 install" "Falha em system_install_node20"
    return 1
  fi
  stop_spinner "Node.js $(node -v 2>/dev/null) instalado."
  sleep 1
}

#######################################
# Create a 2 GiB swap file if RAM < 1 GiB and no swap is active.
# File is /swapfile.crm_install — never auto-removed (rename never delete).
# Arguments:
#   None
#######################################
system_create_temp_swap() {
  local mem_avail_kb swap_total_kb mem_avail_mb
  mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  swap_total_kb=$(awk '/SwapTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem_avail_mb=$(( mem_avail_kb / 1024 ))

  if [ "$mem_avail_mb" -ge 1024 ]; then
    return 0
  fi
  if [ "$swap_total_kb" -gt 0 ]; then
    printf "  ${DIM}RAM disponível baixa (${mem_avail_mb} MiB) mas já há swap ativo.${NC}\n\n"
    return 0
  fi

  step_header "💾" "Criando swap temporário (2 GiB)" \
    "RAM baixa detectada (${mem_avail_mb} MiB). Build do Next pode estourar memória."
  printf "  ${DIM}Arquivo: /swapfile.crm_install — não é removido automaticamente.${NC}\n\n"

  start_spinner "Criando swap..."
  sudo su - root <<'EOF'
  set -e
  if [ ! -f /swapfile.crm_install ]; then
    fallocate -l 2G /swapfile.crm_install || dd if=/dev/zero of=/swapfile.crm_install bs=1M count=2048
    chmod 600 /swapfile.crm_install
    mkswap /swapfile.crm_install
  fi
  swapon /swapfile.crm_install || true
  if ! grep -q '^/swapfile.crm_install' /etc/fstab; then
    printf '\n/swapfile.crm_install none swap sw 0 0  # crm-temp-swap\n' >> /etc/fstab
  fi
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao criar swap temporário."
    log_error "create_temp_swap" "Falha em system_create_temp_swap"
    return 1
  fi
  stop_spinner "Swap de 2 GiB ativo."
  sleep 1
}

#######################################
# Pre-flight checks before any destructive operation.
# Aborts with explicit message if any check fails.
# Arguments:
#   $1 - folder_name (vazio = primária; ex: "crm2" = multi)
#######################################
preflight_checks() {
  local fname="${1:-}"
  local base="/home/deploycrm${fname:+/$fname}/crm"
  local label="${fname:-crm (primária)}"

  step_header "🔍" "Pré-flight checks" \
    "Validando requisitos para [${label}] antes de operações destrutivas."

  # 1. Node.js
  local node_ver node_major
  node_ver=$(node -v 2>/dev/null | sed 's/^v//')
  node_major="${node_ver%%.*}"
  if [ -z "$node_ver" ] || [ "${node_major:-0}" -lt 18 ]; then
    printf "  ${YELLOW}⚠️   Node.js ${node_ver:-não instalado} < 18.17.${NC}\n"
    printf "  ${DIM}Tentando instalar Node 20...${NC}\n\n"
    system_install_node20 || {
      printf "  ${RED}❌  Não foi possível instalar Node 20 automaticamente.${NC}\n"
      printf "  ${DIM}Instale manualmente e rode novamente.${NC}\n\n"
      return 1
    }
  fi

  # 2. RAM + swap
  local mem_avail_kb swap_free_kb total_avail_mb
  mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  swap_free_kb=$(awk '/SwapFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  total_avail_mb=$(( (mem_avail_kb + swap_free_kb) / 1024 ))
  if [ "$total_avail_mb" -lt 2048 ]; then
    printf "  ${YELLOW}⚠️   Memória disponível (${total_avail_mb} MiB) abaixo de 2 GiB.${NC}\n"
    system_create_temp_swap || {
      printf "  ${RED}❌  Não foi possível criar swap. Build pode falhar.${NC}\n"
      printf "  ${YELLOW}Continuar mesmo assim? (s/N):${NC}\n"
      read -p "  > " _conf
      [ "$_conf" = "s" ] || [ "$_conf" = "S" ] || return 1
    }
  fi

  # 3. Disco em /home (>= 3 GiB livres)
  local home_free_kb home_free_mb
  home_free_kb=$(df -kP /home 2>/dev/null | awk 'NR==2 {print $4}')
  home_free_mb=$(( home_free_kb / 1024 ))
  if [ "$home_free_mb" -lt 3072 ]; then
    printf "  ${RED}❌  Disco em /home com apenas ${home_free_mb} MiB livres (< 3 GiB).${NC}\n\n"
    printf "  ${WHITE}Backups antigos consumindo espaço:${NC}\n"
    if ls -d "$base"/frontend.legacy.* "$base"/frontend.bak.* "$base"/frontend.failed.* 2>/dev/null | head -10; then
      du -sh "$base"/frontend.legacy.* "$base"/frontend.bak.* "$base"/frontend.failed.* 2>/dev/null | head -10
    fi
    printf "\n  ${DIM}Use a opção [15 → cleanup] para limpar backups antigos.${NC}\n\n"
    return 1
  fi

  # 4. openssl + curl + jq
  local missing=""
  for bin in openssl curl jq unzip; do
    command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
  done
  if [ -n "$missing" ]; then
    printf "  ${YELLOW}⚠️   Faltando:${missing}. Instalando...${NC}\n"
    sudo apt-get install -y $missing >/dev/null 2>&1 || {
      printf "  ${RED}❌  Falha ao instalar dependências.${NC}\n\n"
      return 1
    }
  fi

  printf "  ${GREEN}✅${NC}  Pré-flight OK para [${label}].\n\n"
  sleep 1
  return 0
}

#######################################
# Lista patterns do fail2ban que assumem paths Quasar (não modifica nada).
# Arguments:
#   None
#######################################
system_check_fail2ban() {
  if [ ! -d /etc/fail2ban/filter.d ]; then
    return 0
  fi
  local hits
  hits=$(grep -lE '/static/|/index\.html|/dist/pwa' /etc/fail2ban/filter.d/*.conf 2>/dev/null || true)
  if [ -n "$hits" ]; then
    printf "  ${YELLOW}⚠️   Patterns fail2ban com paths Quasar (revisar para Next /_next/static/):${NC}\n"
    printf "%s\n" "$hits" | sed 's/^/    /'
    printf "\n"
  fi
}
