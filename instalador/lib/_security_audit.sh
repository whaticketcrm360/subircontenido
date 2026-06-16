#!/bin/bash
#
# Auditoria de segurança contra brute force e hardening SSH/Ubuntu.
# Apenas LEITURA — não faz alterações no sistema.
# Exibe resultado de cada verificação e recomendações numeradas ao final.

# Contadores internos
_AUDIT_ISSUES=0
_AUDIT_WARNINGS=0
_AUDIT_OK=0
# Array de recomendações (índice → texto)
_AUDIT_RECS=()

#######################################
# Registra um item de recomendação e retorna seu número.
# Arguments:
#   $1 - texto da recomendação (bloco multi-linha ok)
#######################################
_audit_rec() {
  _AUDIT_RECS+=("$1")
  echo "${#_AUDIT_RECS[@]}"
}

#######################################
# Imprime linha de resultado.
# Arguments:
#   $1 - status: "ok" | "warn" | "fail"
#   $2 - label (max ~38 chars)
#   $3 - detalhe
#   $4 - número da recomendação (opcional, só para warn/fail)
#######################################
_audit_line() {
  local status="$1"
  local label="$2"
  local detail="$3"
  local rec_num="${4:-}"

  case "$status" in
    ok)
      printf "  ${GREEN}✅${NC}  %-38s ${DIM}%s${NC}\n" "$label" "$detail"
      _AUDIT_OK=$(( _AUDIT_OK + 1 ))
      ;;
    warn)
      local rec_tag=""
      [ -n "$rec_num" ] && rec_tag=" ${YELLOW}[rec #${rec_num}]${NC}"
      printf "  ${YELLOW}⚠️  ${NC}  %-38s ${YELLOW}%s${NC}%b\n" "$label" "$detail" "$rec_tag"
      _AUDIT_WARNINGS=$(( _AUDIT_WARNINGS + 1 ))
      ;;
    fail)
      local rec_tag=""
      [ -n "$rec_num" ] && rec_tag=" ${RED}[rec #${rec_num}]${NC}"
      printf "  ${RED}❌${NC}  %-38s ${RED}%s${NC}%b\n" "$label" "$detail" "$rec_tag"
      _AUDIT_ISSUES=$(( _AUDIT_ISSUES + 1 ))
      ;;
  esac
}

#######################################
# Lê valor de diretiva do sshd_config (ativo ou default).
# Arguments:
#   $1 - diretiva (ex: PermitRootLogin)
#   $2 - valor padrão se não encontrado
#######################################
_sshd_val() {
  local key="$1"
  local default="$2"
  # lê do sshd_config e também de /etc/ssh/sshd_config.d/*.conf
  local val
  val=$(grep -rEhi "^\s*${key}\s+" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
        | tail -1 | awk '{print $2}')
  echo "${val:-$default}"
}

# ─── Verificações ──────────────────────────────────────────────────────────────

_audit_ssh() {
  printf "\n  ${CYAN_LIGHT}── SSH ──────────────────────────────────────────────────${NC}\n\n"

  # 1. PermitRootLogin
  local val
  val=$(_sshd_val "PermitRootLogin" "yes")
  if [[ "$val" == "no" || "$val" == "prohibit-password" || "$val" == "forced-commands-only" ]]; then
    _audit_line ok "PermitRootLogin" "$val"
  else
    local n
    n=$(_audit_rec "Desabilitar login root via SSH.
  Edite /etc/ssh/sshd_config e defina:
    PermitRootLogin no
  Depois: systemctl restart sshd
  Motivo: root é o alvo primário de ataques brute force.")
    _audit_line fail "PermitRootLogin" "$val — root acessível via SSH" "$n"
  fi

  # 2. PasswordAuthentication
  val=$(_sshd_val "PasswordAuthentication" "yes")
  if [[ "$val" == "no" ]]; then
    _audit_line ok "PasswordAuthentication" "desabilitado — apenas chave SSH"
  else
    local n
    n=$(_audit_rec "Usar apenas chave SSH (desabilitar senha via SSH).
  ATENÇÃO: só faça isso depois de configurar e testar sua chave SSH,
  caso contrário perderá o acesso ao servidor.
  Edite /etc/ssh/sshd_config:
    PasswordAuthentication no
  Depois: systemctl restart sshd
  Motivo: elimina completamente ataques de dicionário/brute force.")
    _audit_line warn "PasswordAuthentication" "habilitado — senhas aceitas via SSH" "$n"
  fi

  # 3. PermitEmptyPasswords
  val=$(_sshd_val "PermitEmptyPasswords" "no")
  if [[ "$val" == "no" ]]; then
    _audit_line ok "PermitEmptyPasswords" "no"
  else
    local n
    n=$(_audit_rec "Proibir senhas vazias.
  Edite /etc/ssh/sshd_config:
    PermitEmptyPasswords no
  Depois: systemctl restart sshd")
    _audit_line fail "PermitEmptyPasswords" "yes — senhas vazias aceitas!" "$n"
  fi

  # 4. MaxAuthTries
  val=$(_sshd_val "MaxAuthTries" "6")
  if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -le 4 ]; then
    _audit_line ok "MaxAuthTries" "$val tentativas"
  else
    local n
    n=$(_audit_rec "Reduzir MaxAuthTries para limitar tentativas por conexão.
  Edite /etc/ssh/sshd_config:
    MaxAuthTries 3
  Depois: systemctl restart sshd
  Motivo: limita quantas senhas erradas por sessão SSH.")
    _audit_line warn "MaxAuthTries" "${val} tentativas (recomendado ≤ 4)" "$n"
  fi

  # 5. X11Forwarding
  val=$(_sshd_val "X11Forwarding" "yes")
  if [[ "$val" == "no" ]]; then
    _audit_line ok "X11Forwarding" "desabilitado"
  else
    local n
    n=$(_audit_rec "Desabilitar X11Forwarding (não é necessário em servidores).
  Edite /etc/ssh/sshd_config:
    X11Forwarding no
  Depois: systemctl restart sshd")
    _audit_line warn "X11Forwarding" "habilitado (desnecessário em servidor)" "$n"
  fi

  # 6. Porta SSH
  local ssh_port
  ssh_port=$(_sshd_val "Port" "22")
  if [[ "$ssh_port" != "22" ]]; then
    _audit_line ok "Porta SSH" "porta não-padrão: $ssh_port"
  else
    local n
    n=$(_audit_rec "Mudar a porta SSH da padrão 22 para uma porta alta (ex: 2222, 43022).
  ATENÇÃO: abra a nova porta no UFW ANTES de trocar, e teste sem fechar
  a sessão atual. Só feche a porta 22 após confirmar o acesso.
  Edite /etc/ssh/sshd_config:
    Port 2222
  Depois: ufw allow 2222/tcp && systemctl restart sshd
  Motivo: elimina 99% do ruído de scans automáticos.")
    _audit_line warn "Porta SSH" "porta padrão 22 — alvo frequente de scans" "$n"
  fi

  # 7. ClientAliveInterval / Idle timeout
  local alive
  alive=$(_sshd_val "ClientAliveInterval" "0")
  if [[ "$alive" =~ ^[0-9]+$ ]] && [ "$alive" -gt 0 ] && [ "$alive" -le 300 ]; then
    _audit_line ok "ClientAliveInterval" "${alive}s — sessões ociosas encerradas"
  else
    local n
    n=$(_audit_rec "Configurar timeout de sessões SSH ociosas.
  Edite /etc/ssh/sshd_config:
    ClientAliveInterval 300
    ClientAliveCountMax 2
  Depois: systemctl restart sshd
  Motivo: encerra sessões abandonadas, reduz superfície de ataque.")
    _audit_line warn "ClientAliveInterval" "não configurado — sessões ociosas abertas" "$n"
  fi
}

_audit_fail2ban() {
  printf "\n  ${CYAN_LIGHT}── Fail2ban ─────────────────────────────────────────────${NC}\n\n"

  # 1. Instalado?
  if ! command -v fail2ban-client &>/dev/null; then
    local n
    n=$(_audit_rec "Instalar e configurar o Fail2ban.
  Comandos:
    apt-get install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
  Configure o jail SSH em /etc/fail2ban/jail.local:
    [sshd]
    enabled  = true
    port     = ssh
    maxretry = 5
    bantime  = 3600
    findtime = 600
  Depois: systemctl restart fail2ban
  Motivo: bloqueia automaticamente IPs com muitas tentativas falhas.")
    _audit_line fail "Fail2ban instalado" "NÃO instalado" "$n"
    return
  fi
  _audit_line ok "Fail2ban instalado" "$(fail2ban-client --version 2>/dev/null | head -1)"

  # 2. Ativo?
  if systemctl is-active --quiet fail2ban 2>/dev/null; then
    _audit_line ok "Fail2ban ativo" "serviço em execução"
  else
    local n
    n=$(_audit_rec "Iniciar e habilitar o Fail2ban:
  systemctl enable fail2ban
  systemctl start fail2ban")
    _audit_line fail "Fail2ban ativo" "serviço INATIVO" "$n"
    return
  fi

  # 3. Jail SSH ativo?
  local jail_status
  jail_status=$(fail2ban-client status sshd 2>/dev/null || fail2ban-client status ssh 2>/dev/null)
  if [ -n "$jail_status" ]; then
    local currently_banned
    currently_banned=$(echo "$jail_status" | grep -i "Currently banned" | awk -F: '{print $2}' | xargs)
    local total_banned
    total_banned=$(echo "$jail_status" | grep -i "Total banned" | awk -F: '{print $2}' | xargs)
    _audit_line ok "Fail2ban jail SSH" "ativo | banidos agora: ${currently_banned:-0} | total: ${total_banned:-0}"
  else
    local n
    n=$(_audit_rec "Habilitar o jail SSH no Fail2ban.
  Crie /etc/fail2ban/jail.local se não existir:
    [sshd]
    enabled  = true
    port     = ssh
    maxretry = 5
    bantime  = 3600
    findtime = 600
  Depois: systemctl restart fail2ban")
    _audit_line fail "Fail2ban jail SSH" "jail 'sshd' não encontrado" "$n"
  fi

  # 4. Tentativas recentes (últimas 24h no log do fail2ban)
  local recent_bans
  recent_bans=$(grep -c "Ban " /var/log/fail2ban.log 2>/dev/null || echo "0")
  if [ "$recent_bans" -gt 50 ]; then
    local n
    n=$(_audit_rec "Alto volume de IPs banidos pelo Fail2ban (${recent_bans} bans no log).
  Considere reduzir o bantime para detectar ataques contínuos ou
  aumentar o bantime para penalizar IPs reincidentes:
    bantime  = 86400   # 24h
    maxretry = 3
  Verifique os IPs mais frequentes:
    grep 'Ban ' /var/log/fail2ban.log | awk '{print \$NF}' | sort | uniq -c | sort -rn | head -20")
    _audit_line warn "Fail2ban — bans totais" "${recent_bans} bans registrados no log" "$n"
  elif [ "$recent_bans" -gt 0 ]; then
    _audit_line ok "Fail2ban — bans totais" "${recent_bans} bans registrados (normal)"
  else
    _audit_line ok "Fail2ban — bans totais" "nenhum ban registrado"
  fi
}

_audit_ufw() {
  printf "\n  ${CYAN_LIGHT}── Firewall (UFW) ───────────────────────────────────────${NC}\n\n"

  # 1. UFW ativo?
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    _audit_line ok "UFW ativo" "firewall em execução"
  else
    local n
    n=$(_audit_rec "Ativar o UFW (firewall).
  Comandos mínimos para ativar com segurança:
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp    # SSH
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw allow 9000/tcp  # Portainer (se necessário)
    ufw --force enable
  ATENÇÃO: confirme que a porta SSH está liberada antes de ativar.")
    _audit_line fail "UFW ativo" "INATIVO — servidor sem firewall" "$n"
    return
  fi

  # 2. Porta 5432/5433 exposta?
  local pg_exposed
  pg_exposed=$(ufw status 2>/dev/null | grep -E "5432|5433" | grep -iv "DENY\|REJECT" || true)
  if [ -z "$pg_exposed" ]; then
    _audit_line ok "PostgreSQL no UFW" "porta 5432/5433 não exposta"
  else
    local n
    n=$(_audit_rec "Fechar a porta do PostgreSQL no UFW.
  O PostgreSQL não deve ser acessível externamente.
  Comandos:
    ufw delete allow 5432/tcp
    ufw delete allow 5433/tcp
    ufw reload
  Acesse o banco localmente via: docker exec -it postgresql psql -U postgres")
    _audit_line fail "PostgreSQL no UFW" "porta 5432/5433 ABERTA no firewall!" "$n"
  fi

  # 3. Docker e bind 0.0.0.0 no PostgreSQL
  local pg_bind
  pg_bind=$(ss -tlnp 2>/dev/null | awk '{print $4}' | grep -E "^0\.0\.0\.0:(5432|5433)$" || true)
  if [ -z "$pg_bind" ]; then
    _audit_line ok "PostgreSQL bind" "não escuta em 0.0.0.0"
  else
    local n
    n=$(_audit_rec "O PostgreSQL está vinculado a 0.0.0.0 — acessível em todas as interfaces.
  Mesmo com UFW, o Docker injeta regras no iptables que contornam o UFW.
  Solução: use bind 127.0.0.1 no docker run / docker-compose:
    -p 127.0.0.1:5433:5432
  Recrie o container após a mudança (dados no volume são preservados).")
    _audit_line fail "PostgreSQL bind" "escuta em 0.0.0.0 — exposto externamente" "$n"
  fi

  # 4. Portas TCP abertas desnecessárias (ex: 5432, 5433, 3306, 27017, 6379)
  local dangerous_ports=()
  for port in 3306 27017 6379 5432 5433 9200 9300 11211 2375 2376; do
    if ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE "^0\.0\.0\.0:${port}$"; then
      dangerous_ports+=("$port")
    fi
  done
  if [ ${#dangerous_ports[@]} -eq 0 ]; then
    _audit_line ok "Portas de banco expostas" "nenhuma em 0.0.0.0"
  else
    local n
    n=$(_audit_rec "Portas sensíveis expostas em 0.0.0.0: ${dangerous_ports[*]}
  Estas portas devem escutar apenas em 127.0.0.1.
  Para containers Docker, use: -p 127.0.0.1:PORTA:PORTA_INTERNA
  Para serviços nativos, edite a configuração do serviço para bind-address=127.0.0.1.")
    _audit_line fail "Portas de banco expostas" "${dangerous_ports[*]} em 0.0.0.0" "$n"
  fi
}

_audit_bruteforce_history() {
  printf "\n  ${CYAN_LIGHT}── Histórico de ataques ─────────────────────────────────${NC}\n\n"

  # 1. Tentativas SSH falhas recentes (auth.log / secure)
  local auth_log="/var/log/auth.log"
  [ ! -f "$auth_log" ] && auth_log="/var/log/secure"

  if [ -f "$auth_log" ]; then
    local failed_count
    failed_count=$(grep -c "Failed password\|Invalid user\|Connection closed by authenticating user" "$auth_log" 2>/dev/null || echo "0")
    local unique_ips
    unique_ips=$(grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" "$auth_log" 2>/dev/null \
                 | sort -u | wc -l)

    if [ "$failed_count" -gt 1000 ]; then
      local n
      n=$(_audit_rec "Alto volume de tentativas SSH falhas: ${failed_count} entradas em ${auth_log}.
  Origem de ${unique_ips} IPs distintos.
  Ações recomendadas (por prioridade):
  1. Instalar Fail2ban (veja recomendação acima)
  2. Mudar porta SSH da 22 (veja recomendação acima)
  3. Desabilitar PasswordAuthentication (veja recomendação acima)
  Para ver os 10 IPs mais ativos:
    grep 'Failed password' ${auth_log} | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -10")
      _audit_line fail "Tentativas SSH falhas" "${failed_count} entradas, ${unique_ips} IPs únicos" "$n"
    elif [ "$failed_count" -gt 100 ]; then
      local n
      n=$(_audit_rec "Volume moderado de tentativas SSH falhas: ${failed_count} entradas.
  Verifique os IPs de origem:
    grep 'Failed password' ${auth_log} | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -10
  Se Fail2ban estiver ativo, verifique se os bans estão ocorrendo:
    fail2ban-client status sshd")
      _audit_line warn "Tentativas SSH falhas" "${failed_count} entradas, ${unique_ips} IPs únicos" "$n"
    else
      _audit_line ok "Tentativas SSH falhas" "${failed_count} entradas (baixo volume)"
    fi
  else
    _audit_line warn "Tentativas SSH falhas" "log de auth não encontrado"
  fi

  # 2. Últimos logins bem-sucedidos
  local last_ok
  last_ok=$(last -n 5 -F 2>/dev/null | grep -v "^reboot\|^wtmp" | head -5 || echo "")
  if [ -n "$last_ok" ]; then
    printf "\n  ${DIM}  Últimos 5 logins bem-sucedidos:${NC}\n"
    echo "$last_ok" | while IFS= read -r line; do
      printf "  ${DIM}    %s${NC}\n" "$line"
    done
    printf "\n"
  fi

  # 3. Usuários com login nos últimos 7 dias de IPs suspeitos
  local foreign_logins
  foreign_logins=$(last -F 2>/dev/null | grep -v "^reboot\|^wtmp\|^$" \
                   | awk '{print $3}' | grep -vE "^:0$|^pts/|^$|^still" \
                   | grep -vE "^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)" \
                   | sort -u | head -5 || true)
  if [ -n "$foreign_logins" ]; then
    printf "  ${YELLOW}⚠️  ${NC}  %-38s ${YELLOW}%s${NC}\n" "Logins de IPs externos" "$(echo "$foreign_logins" | tr '\n' ' ')"
    _AUDIT_WARNINGS=$(( _AUDIT_WARNINGS + 1 ))
  fi
}

_audit_users() {
  printf "\n  ${CYAN_LIGHT}── Contas de usuário ────────────────────────────────────${NC}\n\n"

  # 1. Usuários com UID 0 (root equivalente) além do root
  local extra_root
  extra_root=$(awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd 2>/dev/null)
  if [ -z "$extra_root" ]; then
    _audit_line ok "UID 0 extra" "nenhum usuário com UID 0 além de root"
  else
    local n
    n=$(_audit_rec "Usuário(s) com UID 0 (privilégios root) além de root: ${extra_root}
  Verifique se esses usuários são legítimos:
    passwd -l USUARIO   # bloquear conta
    usermod -u NOVO_UID USUARIO   # mudar UID
  Investigue antes de qualquer alteração.")
    _audit_line fail "UID 0 extra" "usuários com root: ${extra_root}" "$n"
  fi

  # 2. Usuários com senha vazia
  local empty_pass
  empty_pass=$(awk -F: '($2 == "" || $2 == "!!" ) {print $1}' /etc/shadow 2>/dev/null | head -10 || true)
  # filtra contas de sistema sem login
  local empty_login
  empty_login=""
  if [ -n "$empty_pass" ]; then
    while IFS= read -r user; do
      local shell
      shell=$(grep "^${user}:" /etc/passwd | cut -d: -f7)
      if [[ "$shell" != "/usr/sbin/nologin" && "$shell" != "/bin/false" && "$shell" != "/sbin/nologin" ]]; then
        empty_login="${empty_login} ${user}"
      fi
    done <<< "$empty_pass"
    empty_login=$(echo "$empty_login" | xargs)
  fi

  if [ -z "$empty_login" ]; then
    _audit_line ok "Senhas vazias" "nenhum usuário com shell e senha vazia"
  else
    local n
    n=$(_audit_rec "Usuários com shell ativo e senha vazia/bloqueada: ${empty_login}
  Defina uma senha forte ou bloqueie as contas não utilizadas:
    passwd USUARIO          # definir nova senha
    passwd -l USUARIO       # bloquear conta
    usermod -s /sbin/nologin USUARIO  # remover shell")
    _audit_line fail "Senhas vazias" "usuários sem senha: ${empty_login}" "$n"
  fi

  # 3. Usuários com sudo (group sudo / wheel)
  local sudo_users
  sudo_users=$(grep -E "^(sudo|wheel):" /etc/group 2>/dev/null | cut -d: -f4 | tr ',' ' ')
  if [ -n "$sudo_users" ]; then
    _audit_line ok "Usuários sudo" "${sudo_users}"
  fi
}

_audit_updates() {
  printf "\n  ${CYAN_LIGHT}── Atualizações automáticas ─────────────────────────────${NC}\n\n"

  # 1. unattended-upgrades instalado e ativo?
  if dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
    _audit_line ok "unattended-upgrades" "instalado"
    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
      _audit_line ok "unattended-upgrades ativo" "habilitado no systemd"
    else
      local n
      n=$(_audit_rec "Habilitar o unattended-upgrades no systemd:
  systemctl enable unattended-upgrades
  systemctl start unattended-upgrades")
      _audit_line warn "unattended-upgrades ativo" "instalado mas não habilitado" "$n"
    fi
  else
    local n
    n=$(_audit_rec "Instalar e habilitar atualizações automáticas de segurança:
  apt-get install -y unattended-upgrades
  dpkg-reconfigure --priority=low unattended-upgrades
  Ou manualmente:
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
  Motivo: aplica patches de segurança sem intervenção manual.")
    _audit_line warn "unattended-upgrades" "não instalado" "$n"
  fi

  # 2. Pacotes com atualizações pendentes
  local pending
  pending=$(apt-get -s upgrade 2>/dev/null | grep -c "^Inst" || echo "0")
  if [ "$pending" -eq 0 ]; then
    _audit_line ok "Pacotes pendentes" "nenhuma atualização pendente"
  elif [ "$pending" -le 10 ]; then
    local n
    n=$(_audit_rec "Aplicar ${pending} atualizações de pacotes pendentes:
  apt-get update && apt-get upgrade -y
  ATENÇÃO: faça isso com snapshot e em horário de baixo tráfego.")
    _audit_line warn "Pacotes pendentes" "${pending} atualizações aguardando" "$n"
  else
    local n
    n=$(_audit_rec "Aplicar ${pending} atualizações de pacotes pendentes (alto volume):
  apt-get update && apt-get upgrade -y
  ATENÇÃO: verifique changelogs antes, especialmente para nginx, openssl e kernel.
  Faça isso com snapshot e em horário de baixo tráfego.
  Para ver quais pacotes: apt list --upgradable 2>/dev/null")
    _audit_line fail "Pacotes pendentes" "${pending} atualizações — servidor desatualizado!" "$n"
  fi
}

_audit_docker_ports() {
  printf "\n  ${CYAN_LIGHT}── Containers Docker (portas expostas) ──────────────────${NC}\n\n"

  if ! command -v docker &>/dev/null; then
    _audit_line ok "Docker" "não instalado — seção ignorada"
    return
  fi

  if ! docker info &>/dev/null 2>&1; then
    _audit_line warn "Docker" "instalado mas não acessível com este usuário"
    return
  fi

  # Itera todos os containers em execução
  local exposed_external=()
  while IFS= read -r line; do
    # linha formato: 0.0.0.0:5433->5432/tcp
    if echo "$line" | grep -qE "^0\.0\.0\.0:[0-9]+->[0-9]+"; then
      local container port
      container=$(echo "$line" | awk '{print $1}')
      port=$(echo "$line" | awk '{print $2}' | grep -oE "0\.0\.0\.0:[0-9]+" || true)
      exposed_external+=("${container}:${port}")
    fi
  done < <(docker ps --format "{{.Names}} {{.Ports}}" 2>/dev/null | tr ',' '\n' | awk '{print $1, $NF}')

  if [ ${#exposed_external[@]} -eq 0 ]; then
    _audit_line ok "Docker portas externas" "todos os containers em 127.0.0.1 ou rede interna"
  else
    for item in "${exposed_external[@]}"; do
      local cname cport
      cname=$(echo "$item" | cut -d: -f1)
      cport=$(echo "$item" | cut -d: -f2-)
      local n
      n=$(_audit_rec "Container '${cname}' expõe ${cport} em 0.0.0.0.
  Edite o docker-compose.yml ou o comando docker run para usar bind 127.0.0.1:
    -p 127.0.0.1:PORTA_HOST:PORTA_CONTAINER
  Após editar, recrie o container:
    docker compose up -d --force-recreate ${cname}
  Motivo: Docker contorna o UFW via iptables — somente bind 127.0.0.1 é seguro.")
      _audit_line fail "Docker: ${cname}" "expõe ${cport} em 0.0.0.0" "$n"
    done
  fi
}

# ─── Cabeçalho e aviso ─────────────────────────────────────────────────────────

_audit_warn_header() {
  print_banner
  printf "${RED}${DLINE}${NC}\n"
  printf "\n"
  printf "  ${RED}⚠️   AUDITORIA DE SEGURANÇA — APENAS LEITURA${NC}\n"
  printf "\n"
  printf "${RED}${DLINE}${NC}\n\n"

  printf "  ${WHITE}Esta rotina analisa a configuração do servidor e exibe${NC}\n"
  printf "  ${WHITE}pontos de melhoria contra ataques brute force.${NC}\n\n"

  printf "  ${YELLOW}⚠️   IMPORTANTE — leia antes de continuar:${NC}\n\n"
  printf "  ${WHITE}1.${NC}  Esta rotina é ${GREEN}somente leitura${NC} — não altera nada no servidor.\n"
  printf "  ${WHITE}2.${NC}  As recomendações ao final devem ser aplicadas ${RED}apenas com:${NC}\n"
  printf "       ${RED}•${NC}  Auxílio de um técnico ou profissional de infraestrutura\n"
  printf "       ${RED}•${NC}  Snapshot da VPS criado previamente no painel do provedor\n"
  printf "  ${WHITE}3.${NC}  Alterações incorretas em SSH ou firewall podem ${RED}bloquear\n"
  printf "       ${RED}o acesso ao servidor permanentemente${NC}.\n"
  printf "  ${WHITE}4.${NC}  Faça as alterações uma por vez e teste entre cada uma.\n\n"

  printf "${YELLOW}${LINE}${NC}\n"
  printf "  Pressione ${WHITE}ENTER${NC} para iniciar a análise ou ${WHITE}Ctrl+C${NC} para cancelar...\n"
  read -r
}

# ─── Relatório final ───────────────────────────────────────────────────────────

_audit_final_report() {
  printf "\n"
  printf "${DLINE}\n"

  if [ "$_AUDIT_ISSUES" -eq 0 ] && [ "$_AUDIT_WARNINGS" -eq 0 ]; then
    printf "  ${GREEN}✅  Parabéns! Nenhum problema crítico encontrado.${NC}\n\n"
    printf "${DLINE}\n"
    return
  fi

  # Placar
  printf "  ${WHITE}Resumo da análise:${NC}\n\n"
  printf "  ${GREEN}✅  OK         :${NC} ${_AUDIT_OK}\n"
  printf "  ${YELLOW}⚠️   Atenção    :${NC} ${_AUDIT_WARNINGS}\n"
  printf "  ${RED}❌  Crítico    :${NC} ${_AUDIT_ISSUES}\n\n"
  printf "${DLINE}\n"

  if [ ${#_AUDIT_RECS[@]} -gt 0 ]; then
    printf "\n  ${WHITE}Recomendações detalhadas:${NC}\n"
    printf "  ${RED}⚠️   Aplique apenas com snapshot + auxílio de técnico.${NC}\n\n"

    local i
    for i in "${!_AUDIT_RECS[@]}"; do
      local num=$(( i + 1 ))
      printf "  ${CYAN_LIGHT}── Recomendação #${num} ─────────────────────────────────────${NC}\n\n"
      # indenta cada linha da recomendação
      echo "${_AUDIT_RECS[$i]}" | while IFS= read -r rline; do
        printf "  ${DIM}%s${NC}\n" "$rline"
      done
      printf "\n"
    done

    printf "${DLINE}\n"
    printf "\n  ${RED}⚠️   LEMBRETE FINAL:${NC}\n"
    printf "  ${WHITE}Não aplique estas correções sem:${NC}\n"
    printf "  ${RED}  1.${NC}  Snapshot completo da VPS criado no painel do provedor\n"
    printf "  ${RED}  2.${NC}  Auxílio de um técnico ou profissional de infraestrutura\n"
    printf "  ${RED}  3.${NC}  Testar em ambiente staging antes (se possível)\n"
    printf "  ${RED}  4.${NC}  Janela de manutenção com baixo tráfego\n\n"
    printf "  ${DIM}Suporte: https://wa.me/50489520312/${NC}\n"
    printf "${DLINE}\n\n"
  fi
}

# ─── Entry point ──────────────────────────────────────────────────────────────

#######################################
# Executa a auditoria de segurança completa (somente leitura).
# Arguments:
#   None
#######################################
run_security_audit() {
  # reset contadores
  _AUDIT_ISSUES=0
  _AUDIT_WARNINGS=0
  _AUDIT_OK=0
  _AUDIT_RECS=()

  _audit_warn_header

  print_banner
  printf "${CYAN_LIGHT}  🔒  Auditoria de Segurança — Brute Force & Hardening${NC}\n"
  printf "${LINE}\n"
  printf "${DIM}  Verificando configurações do sistema... aguarde.${NC}\n"

  _audit_ssh
  _audit_fail2ban
  _audit_ufw
  _audit_bruteforce_history
  _audit_users
  _audit_updates
  _audit_docker_ports

  _audit_final_report
}
