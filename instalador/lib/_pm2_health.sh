#!/bin/bash
#
# _pm2_health.sh — Aplica melhorias de health/auto-restart no crm-backend (PM2).
#
# Codifica o runbook documentado em crm-backend-pm2-health.md (2026-05-04):
# substitui o `pm2 start dist/server.js` ad-hoc do installer pelo
# ecosystem.config.js com auto-restart configurado, instala pm2-logrotate
# com defaults razoaveis e configura pm2 startup (systemd).
#
# Idempotente: pode rodar varias vezes sem efeitos colaterais.
# Preserva cluster mode se ja estiver ativo (le `pm2 show <name>`).

# Defaults — alinhados com crm-backend-pm2-health.md
PM2_HEALTH_HEAP_MB="${PM2_HEALTH_HEAP_MB:-4096}"
PM2_HEALTH_MAX_MEM_RESTART="${PM2_HEALTH_MAX_MEM_RESTART:-3G}"
PM2_HEALTH_MAX_RESTARTS="${PM2_HEALTH_MAX_RESTARTS:-15}"
PM2_HEALTH_MIN_UPTIME="${PM2_HEALTH_MIN_UPTIME:-30s}"
PM2_HEALTH_RESTART_DELAY="${PM2_HEALTH_RESTART_DELAY:-4000}"
PM2_HEALTH_EXP_BACKOFF="${PM2_HEALTH_EXP_BACKOFF:-200}"
# pm2-logrotate
PM2_LOGROTATE_MAX_SIZE="${PM2_LOGROTATE_MAX_SIZE:-20M}"
PM2_LOGROTATE_RETAIN="${PM2_LOGROTATE_RETAIN:-14}"
PM2_LOGROTATE_COMPRESS="${PM2_LOGROTATE_COMPRESS:-true}"
PM2_LOGROTATE_INTERVAL="${PM2_LOGROTATE_INTERVAL:-0 0 * * *}"

#######################################
# Helper de visibilidade — true se PM2 instalado e ha pelo menos um
# crm-backend rodando. Usado pelo menu pra mostrar/ocultar [21].
# Returns: 0 se aplicavel, 1 caso contrario.
#######################################
pm2_health_available() {
  command -v pm2 >/dev/null 2>&1 || return 1
  sudo -u deploycrm pm2 list 2>/dev/null | grep -qE 'crm-backend' || return 1
  return 0
}

# Le exec_mode atual de uma instancia PM2. Echo: "cluster" ou "fork".
# Default: fork se processo nao existir.
_pm2_exec_mode() {
  local name="$1"
  local mode
  mode=$(sudo -u deploycrm pm2 show "$name" 2>/dev/null \
    | grep -oE 'cluster_mode|fork_mode' \
    | head -1)
  [ "$mode" = "cluster_mode" ] && echo "cluster" || echo "fork"
}

# Popula arrays globais com instancias crm que tem PM2 backend ativo:
#   PM2H_INSTANCES — nome curto da instancia ("primeira_instancia", etc.)
#   PM2H_NAMES     — nome do processo PM2 (crm-backend, etc.)
#   PM2H_PATHS     — path absoluto da instancia
_pm2_health_discover_instances() {
  PM2H_INSTANCES=()
  PM2H_NAMES=()
  PM2H_PATHS=()

  local instance_dir instance_name pm2_name instance_path
  while IFS= read -r instance_dir; do
    instance_name=$(echo "$instance_dir" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
      pm2_name="crm-backend"
      instance_path="/home/deploycrm/crm"
    else
      pm2_name="${instance_name}-crm-backend"
      instance_path="/home/deploycrm/$instance_name/crm"
    fi

    if sudo -u deploycrm pm2 list 2>/dev/null | grep -q "$pm2_name"; then
      PM2H_INSTANCES+=("$instance_name")
      PM2H_NAMES+=("$pm2_name")
      PM2H_PATHS+=("$instance_path")
    fi
  done < <(find /home/deploycrm -type d -name "crm" 2>/dev/null)
}

# Gera ecosystem.config.js para uma instancia. Backup do anterior, se houver.
# Args: $1 = pm2 name, $2 = path da instancia, $3 = "cluster"|"fork"
_pm2_health_write_ecosystem() {
  local name="$1"
  local path="$2"
  local mode="$3"

  local exec_mode_js instances_js
  if [ "$mode" = "cluster" ]; then
    exec_mode_js="cluster"
    instances_js="'max'"
  else
    exec_mode_js="fork"
    instances_js="1"
  fi

  local ecosystem="${path}/backend/ecosystem.config.js"

  if [ -f "$ecosystem" ]; then
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    sudo -u deploycrm cp "$ecosystem" "${ecosystem}.bak.${ts}" || return 1
  fi

  sudo -u deploycrm tee "$ecosystem" >/dev/null <<EOF
// ecosystem.config.js — gerado por pm2_apply_health_fixes ($(date '+%Y-%m-%d %H:%M:%S'))
// Para reverter: pm2 delete ${name} && pm2 start dist/server.js --name ${name}
module.exports = {
  apps: [{
    name: '${name}',
    script: './dist/server.js',
    cwd: '${path}/backend',
    node_args: '--max-old-space-size=${PM2_HEALTH_HEAP_MB}',
    instances: ${instances_js},
    exec_mode: '${exec_mode_js}',

    // auto-restart
    autorestart: true,
    max_restarts: ${PM2_HEALTH_MAX_RESTARTS},
    min_uptime: '${PM2_HEALTH_MIN_UPTIME}',
    restart_delay: ${PM2_HEALTH_RESTART_DELAY},
    exp_backoff_restart_delay: ${PM2_HEALTH_EXP_BACKOFF},
    max_memory_restart: '${PM2_HEALTH_MAX_MEM_RESTART}',

    // logs
    error_file: '/home/deploycrm/.pm2/logs/${name}-error.log',
    out_file:   '/home/deploycrm/.pm2/logs/${name}-out.log',
    merge_logs: true,
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',

    env: { NODE_ENV: 'production' },
  }]
};
EOF
}

# Configura pm2-logrotate (idempotente — install pula se ja instalado).
_pm2_health_setup_logrotate() {
  step_header "📜" "pm2-logrotate" \
    "Rotacao: ${PM2_LOGROTATE_MAX_SIZE}, ${PM2_LOGROTATE_RETAIN} dias, compressao=${PM2_LOGROTATE_COMPRESS}"

  if sudo -u deploycrm pm2 list 2>/dev/null | grep -q "pm2-logrotate"; then
    printf "  ${GREEN}✅  pm2-logrotate ja instalado.${NC}\n"
  else
    printf "  ${DIM}Instalando pm2-logrotate...${NC}\n"
    if sudo -u deploycrm pm2 install pm2-logrotate >/dev/null 2>&1; then
      printf "  ${GREEN}✅  pm2-logrotate instalado.${NC}\n"
    else
      printf "  ${RED}❌  Falha ao instalar pm2-logrotate.${NC}\n"
      return 1
    fi
  fi

  sudo -u deploycrm pm2 set pm2-logrotate:max_size       "${PM2_LOGROTATE_MAX_SIZE}" >/dev/null 2>&1
  sudo -u deploycrm pm2 set pm2-logrotate:retain         "${PM2_LOGROTATE_RETAIN}"   >/dev/null 2>&1
  sudo -u deploycrm pm2 set pm2-logrotate:compress       "${PM2_LOGROTATE_COMPRESS}" >/dev/null 2>&1
  sudo -u deploycrm pm2 set pm2-logrotate:rotateInterval "${PM2_LOGROTATE_INTERVAL}" >/dev/null 2>&1
  printf "  ${GREEN}✅  Configuracao aplicada.${NC}\n"
}

# Configura pm2 startup (systemd unit pm2-deploycrm). Idempotente.
_pm2_health_setup_startup() {
  step_header "🚀" "pm2 startup (systemd)" \
    "Faz processos PM2 voltarem automaticamente apos reboot do servidor."

  if systemctl list-unit-files 2>/dev/null | grep -q "^pm2-deploycrm.service"; then
    printf "  ${GREEN}✅  pm2-deploycrm.service ja configurado.${NC}\n"
    return 0
  fi

  # pm2 startup imprime um comando "sudo env PATH=... pm2 startup ..." que
  # precisamos extrair e executar como root pra criar a systemd unit.
  local cmd
  cmd=$(sudo -u deploycrm pm2 startup systemd -u deploycrm --hp /home/deploycrm 2>/dev/null \
    | grep -E '^sudo env PATH=' | head -1)

  if [ -z "$cmd" ]; then
    printf "  ${YELLOW}⚠️   pm2 startup nao retornou comando — talvez ja esteja configurado.${NC}\n"
    return 0
  fi

  if eval "$cmd" >/dev/null 2>&1; then
    printf "  ${GREEN}✅  systemd unit criada (pm2-deploycrm.service).${NC}\n"
  else
    printf "  ${RED}❌  Falha ao criar systemd unit.${NC}\n"
    printf "  ${DIM}Comando que falhou: ${cmd}${NC}\n"
    return 1
  fi
}

#######################################
# Aplica melhorias de health/auto-restart no(s) crm-backend (PM2).
# - ecosystem.config.js por instancia (preserva cluster se ativo)
# - pm2-logrotate com defaults
# - pm2 startup (systemd)
# Arguments:
#   None
#######################################
pm2_apply_health_fixes() {
  step_header "💚" "Health PM2 — crm-backend" \
    "Aplica ecosystem.config.js + pm2-logrotate + pm2 startup. Idempotente."

  if ! pm2_health_available; then
    printf "  ${RED}❌  PM2 nao instalado ou nenhum crm-backend rodando.${NC}\n"
    printf "  ${DIM}Esta opcao serve para instalacoes PM2 (nao-Docker) ja existentes.${NC}\n\n"
    return 1
  fi

  _pm2_health_discover_instances

  if [ "${#PM2H_INSTANCES[@]}" -eq 0 ]; then
    printf "  ${RED}❌  Nenhuma instancia crm com backend PM2 ativo encontrada.${NC}\n\n"
    return 1
  fi

  printf "  ${CYAN}Instancias detectadas${NC} (${#PM2H_INSTANCES[@]}):\n"
  printf "  ${DIM}%-3s %-25s %-30s %s${NC}\n" "#" "instancia" "PM2 name" "exec_mode"
  local i
  for i in "${!PM2H_INSTANCES[@]}"; do
    local mode
    mode=$(_pm2_exec_mode "${PM2H_NAMES[$i]}")
    printf "  ${WHITE}[%d]${NC} %-25s %-30s %s\n" "$((i+1))" "${PM2H_INSTANCES[$i]}" "${PM2H_NAMES[$i]}" "$mode"
  done
  printf "  ${WHITE}[a]${NC} todas as instancias\n\n"

  read -p "  Selecione (numero ou 'a' para todas) > " choice
  local selected_idx=()
  if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
    for i in "${!PM2H_INSTANCES[@]}"; do
      selected_idx+=("$i")
    done
  elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#PM2H_INSTANCES[@]}" ]; then
    selected_idx+=("$((choice-1))")
  else
    printf "  ${RED}❌  Opcao invalida.${NC}\n\n"
    return 1
  fi

  printf "\n  ${CYAN}Sera aplicado em:${NC}\n"
  for i in "${selected_idx[@]}"; do
    local mode
    mode=$(_pm2_exec_mode "${PM2H_NAMES[$i]}")
    printf "  ${DIM}•${NC} ${PM2H_NAMES[$i]} ${DIM}(${mode}, heap ${PM2_HEALTH_HEAP_MB}MB, max-mem-restart ${PM2_HEALTH_MAX_MEM_RESTART})${NC}\n"
  done
  printf "\n"

  if ! require_snapshot_confirmation \
    "Aplicar health fixes PM2 em ${#selected_idx[@]} instancia(s)" \
    "Vou gerar ecosystem.config.js + pm2 reload + instalar pm2-logrotate + pm2 startup. Backup do config atual fica como ecosystem.config.js.bak.<timestamp>."; then
    return 1
  fi

  local applied=0 failed=0
  for i in "${selected_idx[@]}"; do
    local name="${PM2H_NAMES[$i]}"
    local path="${PM2H_PATHS[$i]}"
    local mode
    mode=$(_pm2_exec_mode "$name")

    step_header "🔧" "Aplicando em ${name}"

    printf "  ${DIM}Gerando ${path}/backend/ecosystem.config.js (mode=${mode})...${NC}\n"
    if _pm2_health_write_ecosystem "$name" "$path" "$mode"; then
      printf "  ${GREEN}✅  ecosystem.config.js gerado.${NC}\n"
    else
      printf "  ${RED}❌  Falha ao gerar ecosystem.config.js.${NC}\n"
      failed=$((failed+1))
      continue
    fi

    # delete + start eh mais robusto que reload pra apply de novo ecosystem
    # (reload nao recarrega exec_mode/instances/node_args).
    printf "  ${DIM}pm2 delete + start ecosystem.config.js...${NC}\n"
    sudo -u deploycrm pm2 delete "$name" >/dev/null 2>&1 || true
    if sudo -u deploycrm bash -c "cd '$path/backend' && pm2 start ecosystem.config.js" >/dev/null 2>&1; then
      printf "  ${GREEN}✅  ${name} (re)iniciado com novo ecosystem.${NC}\n"
      applied=$((applied+1))
    else
      printf "  ${RED}❌  Falha no pm2 start ecosystem.config.js.${NC}\n"
      printf "  ${DIM}    Verifique: sudo -u deploycrm pm2 logs ${name} --err --lines 50${NC}\n"
      failed=$((failed+1))
    fi
  done

  sudo -u deploycrm pm2 save >/dev/null 2>&1

  _pm2_health_setup_logrotate
  _pm2_health_setup_startup

  sudo -u deploycrm pm2 save >/dev/null 2>&1

  step_header "✅" "Resumo"
  printf "  ${GREEN}Aplicado:${NC} %d instancia(s)\n" "$applied"
  if [ "$failed" -gt 0 ]; then
    printf "  ${RED}Falhou:${NC}   %d instancia(s)\n" "$failed"
  fi
  printf "\n  ${DIM}Verificar:${NC}\n"
  printf "  ${DIM}  pm2 list${NC}\n"
  printf "  ${DIM}  pm2 describe <nome>${NC}\n"
  printf "  ${DIM}  systemctl status pm2-deploycrm${NC}\n"
  printf "  ${DIM}  pm2 logs <nome> --err --lines 100${NC}\n\n"

  return 0
}
