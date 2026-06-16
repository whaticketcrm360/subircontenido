#!/bin/bash
#
# Health check final + error logging ao longo da instalacao/atualizacao.

# --- error log ---
_ERROR_LOG_FILE=""
_ERROR_COUNT=0

#######################################
# Inicializa o arquivo de log de erros.
# Chamar uma vez no inicio da instalacao/atualizacao.
# Arguments:
#   $1 - prefixo (install ou update)
#######################################
init_error_log() {
  local prefix="${1:-crm}"
  _ERROR_LOG_FILE="/tmp/crm_${prefix}_errors_$(date +%Y%m%d_%H%M%S).log"
  _ERROR_COUNT=0
  : > "$_ERROR_LOG_FILE"
}

#######################################
# Registra um erro no log.
# Arguments:
#   $1 - nome da etapa
#   $2 - mensagem de erro
#######################################
log_error() {
  local step="${1:-unknown}"
  local msg="${2:-erro desconhecido}"
  _ERROR_COUNT=$(( _ERROR_COUNT + 1 ))
  # Guarda contra _ERROR_LOG_FILE não inicializado (chamadas fora de software_update/install).
  if [ -n "${_ERROR_LOG_FILE:-}" ]; then
    printf "[%s] [ERRO] %s — %s\n" "$(date '+%H:%M:%S')" "$step" "$msg" >> "$_ERROR_LOG_FILE" 2>/dev/null
  fi
}

#######################################
# Executa um comando e loga erro se falhar.
# Uso: run_logged "Nome da etapa" comando arg1 arg2...
# Arguments:
#   $1 - nome da etapa (para log)
#   $2... - comando a executar
# Returns:
#   exit code do comando
#######################################
run_logged() {
  local step_name="$1"
  shift
  local output
  output=$("$@" 2>&1)
  local rc=$?
  if [ $rc -ne 0 ]; then
    log_error "$step_name" "exit code $rc"
    # salva output completo para debug
    if [ -n "$_ERROR_LOG_FILE" ]; then
      printf "  --- output de '%s' ---\n%s\n  --- fim ---\n\n" "$step_name" "$output" >> "$_ERROR_LOG_FILE" 2>/dev/null
    fi
  fi
  return $rc
}

#######################################
# Verifica se o PostgreSQL esta acessivel via Docker.
# Arguments:
#   None
# Returns:
#   0 se OK, 1 se falhou
#######################################
_check_database() {
  # verifica se container existe e esta rodando
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^postgresql$"; then
    echo "Container postgresql nao esta rodando"
    return 1
  fi

  # tenta conexao real
  local db_pass
  db_pass=$(grep "^POSTGRES_PASSWORD=" /home/deploycrm/crm/backend/.env 2>/dev/null | cut -d'=' -f2)
  if [ -z "$db_pass" ]; then
    db_pass=$(grep "^DB_PASS=" /home/deploycrm/crm/backend/.env 2>/dev/null | cut -d'=' -f2)
  fi

  if docker exec postgresql pg_isready -U postgres -q 2>/dev/null; then
    return 0
  else
    echo "PostgreSQL nao responde a pg_isready"
    return 1
  fi
}

#######################################
# Imprime trecho do log para diagnostico quando um servico falha.
# Tambem salva no _ERROR_LOG_FILE para consulta posterior.
# Arguments:
#   $1 - nome do servico (postgresql|backend|frontend|nginx)
#######################################
_print_service_logs() {
  local service="$1"
  local lines=15
  local out=""
  local source=""

  case "$service" in
    postgresql)
      if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^postgresql$"; then
        source="docker logs postgresql"
        out=$(docker logs --tail "$lines" postgresql 2>&1)
      else
        source="docker ps -a"
        out=$(docker ps -a --filter "name=postgresql" --format '{{.Names}}\t{{.Status}}' 2>&1)
      fi
      ;;
    backend)
      local err_log="/home/deploycrm/.pm2/logs/crm-backend-error.log"
      local out_log="/home/deploycrm/.pm2/logs/crm-backend-out.log"
      if [ -f "$err_log" ]; then
        source="$err_log"
        out=$(sudo tail -n "$lines" "$err_log" 2>/dev/null)
      fi
      if [ -z "$out" ] && [ -f "$out_log" ]; then
        source="$out_log"
        out=$(sudo tail -n "$lines" "$out_log" 2>/dev/null)
      fi
      if [ -z "$out" ]; then
        source="pm2 logs crm-backend"
        out=$(sudo su - deploycrm -c "pm2 logs crm-backend --nostream --lines $lines --err 2>/dev/null" 2>/dev/null)
      fi
      ;;
    frontend)
      local err_log="/home/deploycrm/.pm2/logs/crm-frontend-error.log"
      local out_log="/home/deploycrm/.pm2/logs/crm-frontend-out.log"
      if [ -f "$err_log" ]; then
        source="$err_log"
        out=$(sudo tail -n "$lines" "$err_log" 2>/dev/null)
      fi
      if [ -z "$out" ] && [ -f "$out_log" ]; then
        source="$out_log"
        out=$(sudo tail -n "$lines" "$out_log" 2>/dev/null)
      fi
      if [ -z "$out" ]; then
        source="pm2 logs crm-frontend"
        out=$(sudo su - deploycrm -c "pm2 logs crm-frontend --nostream --lines $lines --err 2>/dev/null" 2>/dev/null)
      fi
      ;;
    nginx)
      local nginx_test
      nginx_test=$(nginx -t 2>&1)
      local nginx_log=""
      if [ -f /var/log/nginx/error.log ]; then
        nginx_log=$(sudo tail -n "$lines" /var/log/nginx/error.log 2>/dev/null)
      fi
      source="nginx -t + /var/log/nginx/error.log"
      out=$(printf '%s\n--- /var/log/nginx/error.log ---\n%s' "$nginx_test" "$nginx_log")
      ;;
  esac

  if [ -z "$out" ]; then
    out="(sem log disponivel)"
  fi

  printf "  ${DIM}    └─ Log (${source}, ultimas ${lines} linhas):${NC}\n"
  printf '%s\n' "$out" | sed 's/^/         /' | head -n "$lines"
  printf "\n"

  if [ -n "${_ERROR_LOG_FILE:-}" ]; then
    {
      printf "  --- log de '%s' (%s) ---\n" "$service" "$source"
      printf '%s\n' "$out"
      printf "  --- fim ---\n\n"
    } >> "$_ERROR_LOG_FILE" 2>/dev/null
  fi
}

#######################################
# Verifica se o backend esta acessivel (PM2 + HTTP).
# Arguments:
#   None
# Returns:
#   0 se OK, 1 se falhou
#######################################
_check_backend() {
  # parsing JSON correto via python (jq pode não estar presente).
  # Retorna o status do processo "crm-backend" especificamente — não pega processos com nomes parecidos.
  local status
  status=$(sudo su - deploycrm -c "pm2 jlist" 2>/dev/null \
    | python3 -c 'import sys, json
try:
  procs = json.loads(sys.stdin.read() or "[]")
  for p in procs:
    if p.get("name") == "crm-backend":
      print((p.get("pm2_env") or {}).get("status", "missing"))
      sys.exit(0)
  print("missing")
except Exception:
  print("parse-error")' 2>/dev/null)

  case "$status" in
    online)  ;;
    missing) echo "Processo crm-backend nao encontrado no PM2"; return 1 ;;
    errored|stopped|launching) echo "Processo crm-backend esta com status ${status} no PM2"; return 1 ;;
    parse-error) echo "Falha ao ler pm2 jlist"; return 1 ;;
    *) echo "Status PM2 desconhecido: ${status}"; return 1 ;;
  esac

  # detecta porta do backend a partir do .env (default 3000)
  local bport
  bport=$(grep '^PORT=' /home/deploycrm/crm/backend/.env 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
  bport="${bport:-3000}"

  # Aceita qualquer resposta HTTP (2xx/3xx/4xx) — significa que o servidor
  # bindou a porta e está respondendo. PM2 "online" não garante que o
  # app.listen() já rodou (boot pesado: Sequelize sync, Redis, etc.), então
  # aumentamos a janela de retry para ~50s.
  local attempt code
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${bport}" 2>/dev/null || echo "000")
    case "$code" in
      2*|3*|4*) return 0 ;;
    esac
    sleep 5
  done

  echo "Backend nao responde em http://localhost:${bport} (ultimo HTTP: ${code})"
  return 1
}

#######################################
# Verifica se o frontend esta acessivel (PM2 + HTTP).
# Arguments:
#   None
# Returns:
#   0 se OK, 1 se falhou
#######################################
_check_frontend() {
  # parsing JSON correto + detecção de porta do .env.local (não hardcode 4444).
  local status
  status=$(sudo su - deploycrm -c "pm2 jlist" 2>/dev/null \
    | python3 -c 'import sys, json
try:
  procs = json.loads(sys.stdin.read() or "[]")
  for p in procs:
    if p.get("name") == "crm-frontend":
      print((p.get("pm2_env") or {}).get("status", "missing"))
      sys.exit(0)
  print("missing")
except Exception:
  print("parse-error")' 2>/dev/null)

  case "$status" in
    online)  ;;
    missing) echo "Processo crm-frontend nao encontrado no PM2"; return 1 ;;
    errored|stopped|launching) echo "Processo crm-frontend esta com status ${status} no PM2"; return 1 ;;
    parse-error) echo "Falha ao ler pm2 jlist"; return 1 ;;
    *) echo "Status PM2 desconhecido: ${status}"; return 1 ;;
  esac

  # detecta porta do frontend: tenta .env.local (Next), depois vhost nginx (fallback)
  local fport
  fport=$(grep '^PORT=' /home/deploycrm/crm/frontend/.env.local 2>/dev/null | cut -d'=' -f2 | tr -d '[:space:]')
  if [ -z "$fport" ]; then
    fport=$(grep -oP 'proxy_pass\s+http://127\.0\.0\.1:\K[0-9]+' /etc/nginx/sites-available/crm-frontend 2>/dev/null | head -n1)
  fi
  fport="${fport:-4444}"

  local attempt
  for attempt in 1 2 3; do
    # Aceita 2xx OU 3xx (Next App Router redireciona para /login quando sem auth)
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${fport}" 2>/dev/null || echo "000")
    case "$code" in
      2*|3*) return 0 ;;
    esac
    sleep 5
  done

  echo "Frontend nao responde em http://localhost:${fport}"
  return 1
}

#######################################
# Verifica se o nginx esta rodando e respondendo.
# Arguments:
#   None
# Returns:
#   0 se OK, 1 se falhou
#######################################
_check_nginx() {
  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    echo "nginx nao esta ativo (systemctl)"
    return 1
  fi

  # testa se config do nginx e valida
  if ! nginx -t 2>/dev/null; then
    echo "Configuracao do nginx tem erros (nginx -t falhou)"
    return 1
  fi

  return 0
}

#######################################
# Preflight: sanitiza URLs malformadas (trailing ;, espaços, aspas) em
# arquivos .env de instâncias instaladas. Existe pq lixo no .env (ex.:
# FRONTEND_URL_2=https://host;) derruba o helmet CSP no boot do backend
# e o healthcheck só vê "não responde". Faz backup .bak.<ts>, reescreve
# in-place e dá pm2 restart. Idempotente: sai silencioso se .env tá limpo.
# Arguments:
#   None
# Returns:
#   0 sempre (best-effort; falhas individuais não abortam o healthcheck)
#######################################
_preflight_sanitize_env_urls() {
  local env_files=()
  [ -f /home/deploycrm/crm/backend/.env ] && env_files+=("/home/deploycrm/crm/backend/.env")
  for env_file in /home/deploycrm/*/crm/backend/.env; do
    [ -f "$env_file" ] || continue
    env_files+=("$env_file")
  done

  [ ${#env_files[@]} -eq 0 ] && return 0

  local any_fixed=false
  local fixed_list=""

  for env_file in "${env_files[@]}"; do
    local tmp_file
    tmp_file=$(mktemp 2>/dev/null) || tmp_file="/tmp/.crm_env_sanitize.$$"

    python3 - "$env_file" "$tmp_file" <<'PY' 2>/dev/null || { rm -f "$tmp_file"; continue; }
import re, sys
src, dst = sys.argv[1], sys.argv[2]
TARGET = re.compile(r"^(BACKEND_URL|FRONTEND_URL(?:_[2-9])?|SECURE_URL)\s*=(.*)$")
with open(src, "r", encoding="utf-8", errors="replace") as f:
    lines = f.readlines()
out = []
for line in lines:
    stripped = line.rstrip("\r\n")
    m = TARGET.match(stripped)
    if not m:
        out.append(line)
        continue
    key, val = m.group(1), m.group(2)
    val = val.replace("\r", "").strip()
    val = re.sub(r"[;,\s]+$", "", val)
    if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
        val = val[1:-1]
    out.append(f"{key}={val}\n")
with open(dst, "w", encoding="utf-8") as f:
    f.writelines(out)
PY

    if [ -s "$tmp_file" ] && ! cmp -s "$env_file" "$tmp_file"; then
      local instance_label pm2_name
      if [ "$env_file" = "/home/deploycrm/crm/backend/.env" ]; then
        instance_label="primary"
        pm2_name="crm-backend"
      else
        instance_label=$(basename "$(dirname "$(dirname "$(dirname "$env_file")")")")
        pm2_name="${instance_label}-crm-backend"
      fi

      cp "$env_file" "${env_file}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
      cat "$tmp_file" > "$env_file"

      sudo su - deploycrm -c "pm2 restart ${pm2_name} --update-env" >/dev/null 2>&1

      fixed_list="${fixed_list}    • ${env_file}  →  pm2 restart ${pm2_name}\n"
      any_fixed=true
    fi

    rm -f "$tmp_file"
  done

  if $any_fixed; then
    printf "\n  ${YELLOW}🔧  Preflight: .env sanitizado (URLs com ; / espaços / aspas removidos)${NC}\n"
    printf "${fixed_list}"
    printf "  ${DIM}Aguardando backend reiniciar (8s)...${NC}\n\n"
    sleep 8
  fi

  return 0
}

#######################################
# Executa health check completo e exibe resultado.
# Arguments:
#   None
#######################################
health_check_all() {
  step_header "🏥" "Verificacao final de saude" \
    "Validando se todos os servicos estao acessiveis e respondendo corretamente."

  # Auto-corrige .env corrompido (ex.: FRONTEND_URL=https://host;) que
  # derruba o helmet CSP. Sem isto, _check_backend só reportaria "não
  # responde" sem diagnosticar a causa real.
  _preflight_sanitize_env_urls

  local all_ok=true
  local result

  # --- PostgreSQL ---
  printf "  ${DIM}Verificando PostgreSQL...${NC}"
  result=$(_check_database 2>&1)
  if [ $? -eq 0 ]; then
    printf "\r  ${GREEN}✅  PostgreSQL${NC}       — rodando e respondendo\033[K\n"
  else
    printf "\r  ${RED}❌  PostgreSQL${NC}       — ${result}\033[K\n"
    log_error "health_check" "PostgreSQL: $result"
    _print_service_logs postgresql
    all_ok=false
  fi

  # --- Backend ---
  printf "  ${DIM}Verificando Backend (pode levar alguns segundos)...${NC}"
  result=$(_check_backend 2>&1)
  if [ $? -eq 0 ]; then
    printf "\r  ${GREEN}✅  Backend${NC}          — PM2 online, HTTP respondendo\033[K\n"
  else
    printf "\r  ${RED}❌  Backend${NC}          — ${result}\033[K\n"
    log_error "health_check" "Backend: $result"
    _print_service_logs backend
    all_ok=false
  fi

  # --- Frontend ---
  printf "  ${DIM}Verificando Frontend (pode levar alguns segundos)...${NC}"
  result=$(_check_frontend 2>&1)
  if [ $? -eq 0 ]; then
    printf "\r  ${GREEN}✅  Frontend${NC}         — PM2 online, HTTP respondendo\033[K\n"
  else
    printf "\r  ${RED}❌  Frontend${NC}          — ${result}\033[K\n"
    log_error "health_check" "Frontend: $result"
    _print_service_logs frontend
    all_ok=false
  fi

  # --- nginx ---
  printf "  ${DIM}Verificando nginx...${NC}"
  result=$(_check_nginx 2>&1)
  if [ $? -eq 0 ]; then
    printf "\r  ${GREEN}✅  nginx${NC}            — ativo, configuracao valida\033[K\n"
  else
    printf "\r  ${RED}❌  nginx${NC}            — ${result}\033[K\n"
    log_error "health_check" "nginx: $result"
    _print_service_logs nginx
    all_ok=false
  fi

  printf "\n"

  if $all_ok; then
    printf "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${GREEN}✅  Todos os servicos estao saudaveis!${NC}\n"
    printf "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  else
    printf "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${RED}⚠️   Alguns servicos apresentaram problemas.${NC}\n"
    printf "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${DIM}Verifique os logs do PM2: sudo su - deploycrm -c \"pm2 logs\"${NC}\n"
  fi
  printf "\n"
}

#######################################
# Exibe resumo de todos os erros logados durante a operacao.
# Arguments:
#   None
#######################################
show_error_summary() {
  if [ -z "$_ERROR_LOG_FILE" ] || [ ! -f "$_ERROR_LOG_FILE" ]; then
    return 0
  fi

  if [ "$_ERROR_COUNT" -eq 0 ]; then
    printf "  ${GREEN}📋  Nenhum erro registrado durante o processo.${NC}\n\n"
    rm -f "$_ERROR_LOG_FILE" 2>/dev/null
    return 0
  fi

  printf "${YELLOW}${DLINE}${NC}\n"
  printf "  ${YELLOW}⚠️   ${_ERROR_COUNT} erro(s) registrado(s) durante o processo:${NC}\n"
  printf "${YELLOW}${LINE}${NC}\n\n"

  # mostra cada erro
  while IFS= read -r line; do
    printf "  ${RED}•${NC}  ${line}\n"
  done < <(grep "^\[" "$_ERROR_LOG_FILE" 2>/dev/null)

  printf "\n"
  printf "  ${DIM}Log completo salvo em: ${_ERROR_LOG_FILE}${NC}\n"
  printf "  ${DIM}Para detalhes: cat ${_ERROR_LOG_FILE}${NC}\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"
}
