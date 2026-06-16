#!/bin/bash
#
# Next.js-aware frontend lifecycle (install / update / migration / rollback).
# Replaces Vue/Quasar-only build. Implements Fases A, B, C of
# docs/PLANO_FRONTNOVO_OFICIAL.md.
#
# All path/PM2/vhost helpers accept ${folder_name} as $1 — empty = primary
# instance (/home/deploycrm/crm), set = multi (/home/deploycrm/$folder_name/crm).

# =====================================================================
# Helpers de detecção / topologia
# =====================================================================

frontend_base_path() {
  local fname="${1:-}"
  printf '/home/deploycrm%s/crm' "${fname:+/$fname}"
}

frontend_pm2_name() {
  local fname="${1:-}"
  printf '%scrm-frontend' "${fname:+${fname}-}"
}

frontend_vhost_name() {
  local fname="${1:-}"
  printf '%scrm-frontend' "${fname:+${fname}-}"
}

#######################################
# Determine which framework lives in $base/frontend/.
# Echoes one of: next | vue | unknown | none
# Arguments:
#   $1 - folder_name (optional)
#######################################
frontend_detect_kind() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local pkg="$base/frontend/package.json"
  [ -f "$pkg" ] || { echo "none"; return; }
  if grep -q '"next"' "$pkg"; then
    echo "next"
  elif grep -q '"quasar"' "$pkg"; then
    echo "vue"
  elif [ -f "$base/frontend/next.config.js" ] || [ -f "$base/frontend/next.config.mjs" ] || [ -f "$base/frontend/next.config.ts" ]; then
    echo "next"
  elif [ -f "$base/frontend/quasar.conf.js" ] || [ -f "$base/frontend/quasar.config.js" ]; then
    echo "vue"
  else
    echo "unknown"
  fi
}

#######################################
# Enumera todas as instâncias crm do servidor.
# Primária aparece como string vazia. Secundárias = nome da pasta.
#######################################
list_crm_instances() {
  echo ""
  for d in /home/deploycrm/*/crm; do
    [ -d "$d" ] || continue
    local fname
    fname=$(basename "$(dirname "$d")")
    [ "$fname" = "crm" ] && continue
    echo "$fname"
  done
}

#######################################
# Detect topology of a given instance.
# Echoes: none | vue_only | vue_and_novo | next_only | next_and_paralelo
#         | *_with_orphan_novo | next_only_dirty_env | unknown
# Arguments:
#   $1 - folder_name
#######################################
detect_frontend_state() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local kind
  kind=$(frontend_detect_kind "$fname")
  local pm2_novo="${fname:+${fname}-}crm-frontnovo"
  local has_paralelo=0
  local has_orphan_dir=0
  local has_dirty_env=0
  if sudo su - deploycrm -c "pm2 list" 2>/dev/null | grep -q "$pm2_novo"; then
    has_paralelo=1
  fi
  [ -d "$base/frontNovo" ] && has_orphan_dir=1
  if [ -f "$base/backend/.env" ] && grep -qE '^(FRONTEND_URL_2|SECURE_URL)=' "$base/backend/.env"; then
    has_dirty_env=1
  fi

  local state
  case "$kind:$has_paralelo" in
    none:0)    state="none" ;;
    vue:0)     state="vue_only" ;;
    vue:1)     state="vue_and_novo" ;;
    next:0)    state="next_only" ;;
    next:1)    state="next_and_paralelo" ;;
    *)         state="unknown" ;;
  esac

  if [ "$has_paralelo" = "0" ] && [ "$has_orphan_dir" = "1" ]; then
    state="${state}_with_orphan_novo"
  fi
  if [ "$state" = "next_only" ] && [ "$has_dirty_env" = "1" ]; then
    state="next_only_dirty_env"
  fi
  echo "$state"
}

#######################################
# Detecta estados de inconsistência (script morreu mid-migration).
# Echoes: ok | stuck_after_rename | stuck_no_build | stuck_pm2_stale
#######################################
detect_inconsistent_state() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local pm2_name
  pm2_name=$(frontend_pm2_name "$fname")

  if [ ! -d "$base/frontend" ] && ls -d "$base"/frontend.legacy.* >/dev/null 2>&1; then
    echo "stuck_after_rename"; return
  fi
  if [ -d "$base/frontend" ] && [ ! -d "$base/frontend/.next" ] \
     && [ -f "$base/frontend/package.json" ] \
     && grep -q '"next"' "$base/frontend/package.json" 2>/dev/null; then
    echo "stuck_no_build"; return
  fi
  if [ -f "$base/frontend/package.json" ] && grep -q '"next"' "$base/frontend/package.json" 2>/dev/null; then
    if sudo su - deploycrm -c "pm2 prettylist" 2>/dev/null \
        | grep -A2 "\"name\":\"$pm2_name\"" | grep -q "server.js"; then
      echo "stuck_pm2_stale"; return
    fi
  fi
  echo "ok"
}

#######################################
# Read the upstream port currently used in the nginx vhost.
# Falls back to 4444 (primary) or 3335 (multi) if vhost is missing.
# Arguments:
#   $1 - folder_name
#######################################
vue_detect_port() {
  local fname="${1:-}"
  local vhost_name
  vhost_name=$(frontend_vhost_name "$fname")
  local vhost_file="/etc/nginx/sites-available/${vhost_name}"
  local port=""
  if [ -f "$vhost_file" ]; then
    port=$(grep -oP 'proxy_pass\s+http://127\.0\.0\.1:\K[0-9]+' "$vhost_file" | head -n1)
  fi
  if [ -z "$port" ]; then
    if [ -z "$fname" ]; then
      port=4444
    else
      port=3335
    fi
  fi
  echo "$port"
}

#######################################
# Health-check of a Next.js instance via curl + regex Next 14+ App Router.
# Polls up to 30 seconds.
# Arguments:
#   $1 - folder_name
#######################################
frontend_health_check() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local fport
  fport=$(vue_detect_port "$fname")
  local target="http://127.0.0.1:${fport}"
  local i=0 status="" body=""
  while [ "$i" -lt 30 ]; do
    status=$(curl -s -o /tmp/crm_hc_body.$$ -w "%{http_code}" --max-time 5 "$target" 2>/dev/null || echo "000")
    body=$(head -c 2000 /tmp/crm_hc_body.$$ 2>/dev/null)
    rm -f /tmp/crm_hc_body.$$ 2>/dev/null
    # Aceita 2xx (HTML servido) OU 3xx (Next App Router redirect para /login quando sem auth).
    # Rejeita só se for 4xx/5xx/000 ou se o body de uma resposta 200 ainda for Vue.
    case "$status" in
      2*)
        # Sanity: 200 + Quasar = Vue zumbi (rejeita)
        if echo "$body" | grep -qE 'quasar|/assets/vendor__quasar|/assets/quasar\.'; then
          printf "  ${RED}❌${NC}  Resposta em ${target} ainda parece ser Vue/Quasar.\n"
          return 1
        fi
        return 0
        ;;
      3*)
        # Redirect (Next App Router → /login). Suficiente para confirmar que o Next está vivo.
        return 0
        ;;
    esac
    sleep 1
    i=$((i+1))
  done
  printf "  ${YELLOW}⚠️${NC}  Health-check timeout após 30s. Último status HTTP: ${status:-vazio}.\n"
  if [ -n "$body" ]; then
    printf "  ${DIM}Primeiros 200 chars do body:${NC}\n"
    printf "%s\n" "${body:0:200}" | sed 's/^/    /'
  fi
  return 1
}

# =====================================================================
# Helpers de geração de .env / nginx
# =====================================================================

#######################################
# Generate .env.local for a Next.js instance with a per-instance encryption key.
# Arguments:
#   $1 - folder_name
#   $2 - port (default: 4444 for primary, 3335 for multi via vue_detect_port)
#######################################
frontend_set_env_next() {
  local fname="${1:-}"
  local fport="${2:-}"
  local base
  base=$(frontend_base_path "$fname")
  if [ -z "$fport" ]; then
    fport=$(vue_detect_port "$fname")
  fi
  local _backend_url="${backend_url:-}"
  if [ -z "$_backend_url" ] && [ -f "$base/backend/.env" ]; then
    _backend_url=$(grep -E '^BACKEND_URL=' "$base/backend/.env" | cut -d'=' -f2 | tr -d '[:space:]')
  fi
  local enc_key
  enc_key=$(openssl rand -base64 32 2>/dev/null | tr -d '\n=' | head -c 32)
  if [ -z "$enc_key" ]; then
    enc_key="crm-fallback-$(date +%s)"
  fi

  sudo su - deploycrm <<EOF
cat > "$base/frontend/.env.local" <<ENV
NEXT_PUBLIC_API_URL=${_backend_url}
NEXT_PUBLIC_DEFAULT_ENCRYPTION_KEY=${enc_key}
NEXT_PUBLIC_INTERACTIVE_BAILEYS=false
PORT=${fport}
ENV
EOF
  printf "  ${GREEN}✅${NC}  .env.local gerado em $base/frontend/.env.local (porta ${fport}).\n\n"
}

#######################################
# Diff de customizações no Vue legacy antes da migração.
# Não migra nada — só reporta para o usuário.
# Arguments:
#   $1 - folder_name
#######################################
frontend_diff_legacy() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local env_file="$base/frontend/.env"
  if [ ! -f "$env_file" ]; then
    return 0
  fi

  local extra_vars
  extra_vars=$(grep -vE '^(URL_API|FACEBOOK_APP_ID|#|$)' "$env_file" | grep -E '=' || true)
  if [ -n "$extra_vars" ]; then
    printf "${YELLOW}  ⚠️   Variáveis customizadas detectadas em ${env_file}:${NC}\n"
    printf "%s\n" "$extra_vars" | sed 's/^/    /'
    printf "\n  ${DIM}Replicar manualmente em frontend/.env.local como NEXT_PUBLIC_*${NC}\n\n"
  fi

  if [ -f "$base/frontend/quasar.conf.js" ] || [ -f "$base/frontend/quasar.config.js" ]; then
    if ! diff -q "$base/frontend/quasar.conf.js" /dev/null >/dev/null 2>&1; then
      printf "  ${DIM}quasar.conf.js presente — verifique customizações de tema.${NC}\n"
    fi
  fi
}

# =====================================================================
# Funções "frontend_*" tradicionais — agora geram Next.js.
# Mantêm os mesmos nomes que o entry-point `crm` chama.
# =====================================================================

frontend_set_env() {
  step_header "⚙️ " "Configurando .env.local do frontendNovo (Next.js)" \
    "Cria /home/deploycrm/crm/frontend/.env.local com NEXT_PUBLIC_API_URL e encryption key."
  printf "  ${DIM}Encryption key gerada por VPS via openssl rand.${NC}\n\n"
  frontend_set_env_next "" "4444"
  sleep 1
}

frontend_node_dependencies() {
  step_header "📦" "Instalando dependências do frontendNovo" \
    "Executa npm install --force em /home/deploycrm/crm/frontend."
  printf "  ${DIM}Instala Next.js 14, React, Zustand. Pode levar 3-5 minutos.${NC}\n\n"

  start_spinner "Instalando pacotes npm do frontend..."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/frontend
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao instalar dependências do frontend."
    log_error "npm install frontend" "Falha ao instalar dependencias do frontend"
  else
    stop_spinner "Dependências do frontend instaladas."
  fi
  sleep 1
}

frontend_node_build() {
  step_header "🔨" "Compilando o frontendNovo (Next.js)" \
    "Executa npm run build — gera bundle de produção em .next/."
  printf "  ${DIM}Pode levar de 3 a 10 minutos. Memory-intensive.${NC}\n\n"

  start_spinner "Compilando frontend para produção..."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/frontend
  NODE_OPTIONS="--max-old-space-size=2048" npm run build
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao compilar o frontend."
    log_error "frontend build" "Falha ao compilar o frontend (npm run build)"
  else
    stop_spinner "Frontend compilado. Bundle de produção em .next/."
  fi
  sleep 1
}

frontend_start_pm2() {
  step_header "🚀" "Iniciando frontend (Next.js standalone) com PM2" \
    "Inicia .next/standalone/server.js com PM2 na porta 4444."
  printf "  ${DIM}Processo: crm-frontend | nginx encaminha HTTPS para esta porta.${NC}\n"
  printf "  ${DIM}Standalone evita 'next start' (incompatível com output:standalone no Next 15).${NC}\n\n"

  start_spinner "Iniciando crm-frontend na porta 4444..."
  sudo su - deploycrm <<EOF
  export PORT=4444
  pm2 delete crm-frontend 2>/dev/null || true
  pm2 start /home/deploycrm/crm/frontend/.next/standalone/server.js \
    --name crm-frontend \
    --cwd /home/deploycrm/crm/frontend/.next/standalone \
    --update-env
  pm2 save
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao iniciar frontend no PM2."
    log_error "pm2 start frontend" "Falha ao iniciar crm-frontend no PM2"
  else
    stop_spinner "Frontend iniciado. Processo crm-frontend ativo no PM2."
  fi
  sleep 1
}

frontend_nginx_setup() {
  step_header "🌐" "Configurando nginx para o frontend (Next.js)" \
    "Cria /etc/nginx/sites-available/crm-frontend e ativa o vhost."
  printf "  ${DIM}Proxy HTTPS → http://127.0.0.1:4444${NC}\n\n"

  sleep 1

  local frontend_hostname
  frontend_hostname=$(echo "${frontend_url/https:\/\/}")

sudo su - root << EOF

cat > /etc/nginx/sites-available/crm-frontend << 'END'
server {
  server_name $frontend_hostname;

    location / {
    proxy_pass http://127.0.0.1:4444;
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

ln -sf /etc/nginx/sites-available/crm-frontend /etc/nginx/sites-enabled/crm-frontend
EOF

  printf "  ${GREEN}✅${NC}  vhost crm-frontend criado e ativado no nginx.\n\n"
  sleep 1
}

# =====================================================================
# Migração / rebuild / rollback (loop por instância)
# =====================================================================

#######################################
# Migra Vue → Next preservando o legado em frontend.legacy.<ts>/.
# Arguments:
#   $1 - folder_name
# Returns: 0 on success, 1 on failure (rollback applied).
#######################################
migrate_vue_to_next() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local pm2_name
  pm2_name=$(frontend_pm2_name "$fname")
  local label="${fname:-crm (primária)}"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local fport
  fport=$(vue_detect_port "$fname")

  step_header "🔄" "Migrando Vue → Next em [${label}]" \
    "Porta detectada: ${fport}. Backup em frontend.legacy.${ts}/."

  # Cenário 7: avisar customizações antes de qualquer mv
  frontend_diff_legacy "$fname"

  start_spinner "Parando ${pm2_name}..."
  sudo su - deploycrm -c "pm2 stop ${pm2_name} 2>/dev/null || true"
  stop_spinner "${pm2_name} parado."

  sudo mv "$base/frontend" "$base/frontend.legacy.${ts}" || {
    log_error "migrate rename" "Falha ao renomear frontend para legacy em ${label}"
    return 1
  }

  # Extrai novo frontend/ do update.zip já presente em /home/deploycrm/
  if ! _frontend_extract_zip "$fname"; then
    log_error "migrate extract" "Falha ao extrair frontend Next em ${label}"
    rollback_to_vue_legacy "$fname" "$ts"
    return 1
  fi

  sudo chown -R deploycrm:deploycrm "$base/frontend"

  # Vue não tinha .env.local — gerar do zero com encryption key única
  frontend_set_env_next "$fname" "$fport"

  start_spinner "Instalando dependências (Next) em [${label}]..."
  sudo su - deploycrm <<EOF
  cd "$base/frontend"
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha em npm install."
    rollback_to_vue_legacy "$fname" "$ts"
    return 1
  fi
  stop_spinner "Dependências instaladas."

  start_spinner "Build Next.js em [${label}] (pode demorar)..."
  sudo su - deploycrm <<EOF
  cd "$base/frontend"
  NODE_OPTIONS="--max-old-space-size=2048" npm run build
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha em npm run build."
    rollback_to_vue_legacy "$fname" "$ts"
    return 1
  fi
  stop_spinner "Build concluído."

  sudo su - deploycrm <<EOF
  export PORT=${fport}
  pm2 delete ${pm2_name} 2>/dev/null || true
  pm2 start "$base/frontend/.next/standalone/server.js" \
    --name ${pm2_name} \
    --cwd "$base/frontend/.next/standalone" \
    --update-env
  pm2 save
EOF

  if frontend_health_check "$fname"; then
    printf "  ${GREEN}✅${NC}  Migração [${label}] concluída. Vue preservado em $base/frontend.legacy.${ts}/.\n\n"
    return 0
  else
    printf "  ${RED}❌${NC}  Health-check falhou em [${label}] — aplicando rollback.\n\n"
    rollback_to_vue_legacy "$fname" "$ts"
    return 1
  fi
}

#######################################
# Rollback determinístico para Vue legacy.
# Arguments:
#   $1 - folder_name
#   $2 - timestamp (do legacy)
#######################################
rollback_to_vue_legacy() {
  local fname="${1:-}"
  local ts="$2"
  local base
  base=$(frontend_base_path "$fname")
  local pm2_name
  pm2_name=$(frontend_pm2_name "$fname")

  if [ -z "$ts" ]; then
    ts=$(ls -1 "$base"/frontend.legacy.* 2>/dev/null | sort | tail -1 | sed 's|.*frontend.legacy.||')
  fi
  [ -z "$ts" ] && return 1

  printf "  ${YELLOW}↩️   Rollback em ${pm2_name} para frontend.legacy.${ts}/${NC}\n\n"
  sudo su - deploycrm -c "pm2 delete ${pm2_name} 2>/dev/null || true"
  if [ -d "$base/frontend" ]; then
    sudo mv "$base/frontend" "$base/frontend.failed.${ts}"
  fi
  sudo mv "$base/frontend.legacy.${ts}" "$base/frontend"
  sudo su - deploycrm <<EOF
  pm2 start "$base/frontend/server.js" --name ${pm2_name}
  pm2 save
EOF
}

#######################################
# Rebuild Next → Next preservando .env.local.
# Arguments:
#   $1 - folder_name
#######################################
rebuild_next_in_place() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")
  local pm2_name
  pm2_name=$(frontend_pm2_name "$fname")
  local label="${fname:-crm (primária)}"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)

  step_header "🔁" "Rebuild Next em [${label}]" \
    "Preserva .env.local. Backup em frontend.bak.${ts}/."

  if [ -f "$base/frontend/.env.local" ]; then
    sudo cp "$base/frontend/.env.local" "/tmp/.env.local.${fname:-primary}.${ts}"
  fi

  start_spinner "Parando ${pm2_name}..."
  sudo su - deploycrm -c "pm2 stop ${pm2_name} 2>/dev/null || true"
  stop_spinner "${pm2_name} parado."

  sudo mv "$base/frontend" "$base/frontend.bak.${ts}" || return 1

  if ! _frontend_extract_zip "$fname"; then
    log_error "rebuild extract" "Falha ao extrair frontend Next em ${label}"
    sudo mv "$base/frontend.bak.${ts}" "$base/frontend"
    sudo su - deploycrm -c "pm2 start npm --name ${pm2_name} --cwd $base/frontend -- run start"
    return 1
  fi
  sudo chown -R deploycrm:deploycrm "$base/frontend"

  if [ -f "/tmp/.env.local.${fname:-primary}.${ts}" ]; then
    sudo cp "/tmp/.env.local.${fname:-primary}.${ts}" "$base/frontend/.env.local"
    sudo chown deploycrm:deploycrm "$base/frontend/.env.local"
  fi

  start_spinner "npm install + build em [${label}]..."
  sudo su - deploycrm <<EOF
  cd "$base/frontend"
  npm install --force
  NODE_OPTIONS="--max-old-space-size=2048" npm run build
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha no build."
    log_error "rebuild build" "Falha em rebuild_next_in_place [${label}]"
    return 1
  fi
  stop_spinner "Build concluído."

  local fport
  fport=$(vue_detect_port "$fname")
  sudo su - deploycrm <<EOF
  export PORT=${fport}
  pm2 delete ${pm2_name} 2>/dev/null || true
  pm2 start "$base/frontend/.next/standalone/server.js" \
    --name ${pm2_name} \
    --cwd "$base/frontend/.next/standalone" \
    --update-env
  pm2 save
EOF
  printf "  ${GREEN}✅${NC}  Rebuild [${label}] concluído.\n\n"
}

#######################################
# Helper interno: extrai frontend/ do update.zip ou crm.zip.
# Espera que o zip esteja em /home/deploycrm/update.zip ou no PROJECT_ROOT.
# Arguments:
#   $1 - folder_name
#######################################
_frontend_extract_zip() {
  local fname="${1:-}"
  local base
  base=$(frontend_base_path "$fname")

  local zip_src=""
  if [ -f /home/deploycrm/update.zip ]; then
    zip_src=/home/deploycrm/update.zip
  elif [ -f "${PROJECT_ROOT}/update.zip" ]; then
    zip_src="${PROJECT_ROOT}/update.zip"
  elif [ -f "${PROJECT_ROOT}/crm.zip" ]; then
    zip_src="${PROJECT_ROOT}/crm.zip"
  else
    printf "  ${RED}❌  Nenhum zip encontrado para extrair frontend.${NC}\n"
    return 1
  fi

  local tmp
  tmp="/tmp/crm_frontend_extract_$$"
  mkdir -p "$tmp"
  if ! unzip -o "$zip_src" "crm/frontend/*" -d "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi
  if [ ! -d "$tmp/crm/frontend" ]; then
    rm -rf "$tmp"
    return 1
  fi
  sudo mv "$tmp/crm/frontend" "$base/frontend"
  rm -rf "$tmp"
  return 0
}

#######################################
# Apply update flow per instance — switch by detected kind.
# Arguments:
#   $1 - folder_name
#######################################
software_update_frontend_for_instance() {
  local fname="${1:-}"
  preflight_checks "$fname" || return 1
  local kind
  kind=$(frontend_detect_kind "$fname")
  case "$kind" in
    vue)   migrate_vue_to_next "$fname" ;;
    next)  rebuild_next_in_place "$fname" ;;
    none)  return 0 ;;
    *)     log_error "unknown frontend kind" "Instância [${fname:-primária}] em estado desconhecido"; return 1 ;;
  esac
}

#######################################
# Loop principal — itera todas as instâncias do servidor.
#######################################
software_update_all_frontends() {
  local failures=()
  while IFS= read -r fname; do
    local label="${fname:-crm (primária)}"
    if ! software_update_frontend_for_instance "$fname"; then
      failures+=("$label")
    fi
  done < <(list_crm_instances)

  if [ ${#failures[@]} -gt 0 ]; then
    printf "\n${RED}  ❌  Instâncias com falha (rollback aplicado):${NC}\n"
    printf '    - %s\n' "${failures[@]}"
    printf "\n"
  else
    printf "\n${GREEN}  ✅  Todas as instâncias atualizadas com sucesso.${NC}\n\n"
  fi
}
