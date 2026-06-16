#!/bin/bash
#
# _postgres_tune.sh — tuning de PostgreSQL standalone (modo PM2/fork).
#
# Em modo PM2 o postgres roda em container Docker isolado (nome: postgresql),
# SEM docker-compose. Aqui aplicamos os mesmos parametros que o compose
# otimizado usa, via:
#   - ALTER SYSTEM SET ...   (persistente, escreve em postgresql.auto.conf)
#   - SELECT pg_reload_conf() (parametros que aceitam reload)
#   - docker restart          (parametros que exigem restart: max_connections,
#                              shared_buffers — sao "postmaster"-level)
#
# Foco em seguranca: snapshot obrigatorio + dry-run que mostra o diff antes
# de aplicar.

PG_CONTAINER_NAME="${PG_CONTAINER_NAME:-postgresql}"

# Preset recomendado crm — mesmos valores do compose otimizado.
# Cada entrada: "param=valor:context"  (context = reload | postmaster)
_pg_preset_crm() {
  cat <<'EOF'
max_connections=200:postmaster
shared_buffers=512MB:postmaster
effective_cache_size=4GB:reload
work_mem=16MB:reload
maintenance_work_mem=128MB:reload
checkpoint_completion_target=0.9:reload
wal_buffers=16MB:postmaster
default_statistics_target=100:reload
random_page_cost=1.1:reload
effective_io_concurrency=200:reload
statement_timeout=30000:reload
idle_in_transaction_session_timeout=300000:reload
autovacuum_vacuum_scale_factor=0.05:reload
autovacuum_analyze_scale_factor=0.025:reload
log_min_duration_statement=1000:reload
EOF
}

# psql -U postgres -t -c "<query>" no container — retorna stdout puro.
_pg_psql() {
  local query="$1"
  docker exec "$PG_CONTAINER_NAME" psql -U postgres -t -c "$query" 2>/dev/null | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Detecta se o container postgres standalone esta rodando.
_pg_container_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PG_CONTAINER_NAME}$"
}

#######################################
# Tuning de Postgres standalone (modo PM2/fork). Aplica preset crm ou
# permite revisao parametro-a-parametro.
# Arguments:
#   None
#######################################
pg_tune_standalone() {
  step_header "🐘" "Tunar PostgreSQL standalone (PM2/fork)" \
    "Aplica parametros otimizados (memoria, conexoes, autovacuum) num container postgres standalone."

  # Pre-checks
  if ! command -v docker >/dev/null 2>&1; then
    printf "  ${RED}❌  Docker nao encontrado.${NC}\n\n"
    return 1
  fi
  if ! _pg_container_running; then
    printf "  ${RED}❌  Container '${PG_CONTAINER_NAME}' nao esta rodando.${NC}\n"
    printf "  ${DIM}    docker ps mostra:${NC}\n"
    docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null
    printf "\n"
    return 1
  fi
  if ! _pg_psql "SELECT 1" | grep -q "1"; then
    printf "  ${RED}❌  Postgres nao responde a SELECT 1.${NC}\n\n"
    return 1
  fi

  # Capacidade
  local mem_avail_mb mem_total_mb
  mem_avail_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  mem_total_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  printf "  ${CYAN}Container PG${NC}    : ${PG_CONTAINER_NAME}\n"
  printf "  ${CYAN}RAM total${NC}       : ${mem_total_mb} MiB\n"
  printf "  ${CYAN}RAM disponivel${NC}  : ${mem_avail_mb} MiB\n"

  # Preset — comparar atual vs alvo
  printf "\n  ${CYAN}Comparativo (atual -> preset crm):${NC}\n"
  printf "  ${DIM}%-40s %-15s %-15s %s${NC}\n" "parametro" "atual" "alvo" "tipo"
  local need_restart=false
  local changes=()
  while IFS= read -r entry; do
    local param value context current
    param="${entry%%=*}"
    value="${entry#*=}"; value="${value%%:*}"
    context="${entry##*:}"
    current=$(_pg_psql "SHOW $param;" || echo "?")
    if [ "$current" != "$value" ]; then
      changes+=("$entry|$current")
      [ "$context" = "postmaster" ] && need_restart=true
      printf "  ${YELLOW}%-40s %-15s -> %-15s %s${NC}\n" "$param" "$current" "$value" "$context"
    else
      printf "  ${GREEN}%-40s %-15s == %-15s %s${NC}\n" "$param" "$current" "$value" "ok"
    fi
  done < <(_pg_preset_crm)

  if [ "${#changes[@]}" -eq 0 ]; then
    printf "\n  ${GREEN}✅  Postgres ja esta com todos os parametros do preset crm.${NC}\n\n"
    return 0
  fi

  printf "\n  ${CYAN}Mudancas pendentes${NC} : ${#changes[@]}\n"
  if $need_restart; then
    printf "  ${YELLOW}⚠️   Restart do container necessario${NC} (max_connections / shared_buffers / wal_buffers).\n"
    printf "  ${DIM}    Downtime previsto: ~10-30s. Conexoes ativas serao derrubadas.${NC}\n"
  else
    printf "  ${GREEN}Sem restart necessario${NC} — todos parametros aceitam reload.\n"
  fi

  # Sanity check de RAM vs shared_buffers
  if [ "$mem_total_mb" -lt 1500 ]; then
    printf "\n  ${YELLOW}⚠️   RAM total ${mem_total_mb} MiB < 1.5 GiB — preset com shared_buffers=512MB${NC}\n"
    printf "  ${YELLOW}    pode ficar apertado. Considere aplicar manualmente shared_buffers menor.${NC}\n"
  fi

  printf "\n"
  if ! require_snapshot_confirmation \
    "Tuning PostgreSQL standalone (${PG_CONTAINER_NAME})" \
    "Se shared_buffers/max_connections forem incompativeis com a RAM, postgres pode nao subir."; then
    return 1
  fi

  # Aplica via ALTER SYSTEM
  step_header "🔧" "Aplicando ALTER SYSTEM"
  for entry_with_current in "${changes[@]}"; do
    local entry="${entry_with_current%%|*}"
    local param value
    param="${entry%%=*}"
    value="${entry#*=}"; value="${value%%:*}"
    local q="ALTER SYSTEM SET $param = '$value';"
    if _pg_psql "$q" >/dev/null 2>&1; then
      printf "  ${GREEN}✅${NC}  %s = %s\n" "$param" "$value"
    else
      printf "  ${RED}❌${NC}  Falhou: %s = %s\n" "$param" "$value"
    fi
  done

  # Reload
  step_header "🔁" "Reload de configuracao"
  if _pg_psql "SELECT pg_reload_conf();" | grep -q "t"; then
    printf "  ${GREEN}✅  pg_reload_conf() executado.${NC}\n"
  else
    printf "  ${YELLOW}⚠️   pg_reload_conf() nao retornou t — verifique logs.${NC}\n"
  fi

  # Restart se necessario
  if $need_restart; then
    step_header "🔄" "Restart do container PostgreSQL (necessario pra max_connections/shared_buffers)"
    if docker restart "$PG_CONTAINER_NAME" >/dev/null 2>&1; then
      printf "  ${GREEN}✅  docker restart ${PG_CONTAINER_NAME}${NC}\n"
      printf "  ${DIM}Aguardando postgres aceitar conexoes...${NC}\n"
      local i
      for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        sleep 2
        if _pg_psql "SELECT 1" 2>/dev/null | grep -q "1"; then
          printf "  ${GREEN}✅  Postgres respondendo (tentativa ${i}).${NC}\n"
          break
        fi
        if [ "$i" = "12" ]; then
          printf "  ${RED}❌  Postgres nao respondeu apos 24s. Verifique:${NC}\n"
          printf "  ${DIM}    docker logs ${PG_CONTAINER_NAME} --tail 50${NC}\n"
          printf "  ${DIM}    Se nao subir, restaure o snapshot da VPS.${NC}\n"
          return 1
        fi
      done
    else
      printf "  ${RED}❌  docker restart falhou.${NC}\n"
      return 1
    fi
  fi

  # Validacao final — mostra estado pos-aplicacao
  step_header "✅" "Validacao pos-tuning"
  printf "  ${CYAN}Parametros agora:${NC}\n"
  while IFS= read -r entry; do
    local param value current
    param="${entry%%=*}"
    value="${entry#*=}"; value="${value%%:*}"
    current=$(_pg_psql "SHOW $param;" || echo "?")
    if [ "$current" = "$value" ]; then
      printf "  ${GREEN}✅${NC}  %-40s = %s\n" "$param" "$current"
    else
      printf "  ${YELLOW}⚠️${NC}   %-40s = %s ${DIM}(esperado: %s)${NC}\n" "$param" "$current" "$value"
    fi
  done < <(_pg_preset_crm)

  printf "\n  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "  ${GREEN}✅  Tuning aplicado.${NC}\n"
  printf "  ${DIM}Rollback: docker exec ${PG_CONTAINER_NAME} psql -U postgres -c \"ALTER SYSTEM RESET ALL; SELECT pg_reload_conf();\"${NC}\n"
  printf "  ${DIM}E em seguida: docker restart ${PG_CONTAINER_NAME}${NC}\n"
  printf "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
  return 0
}
