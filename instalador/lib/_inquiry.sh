#!/bin/bash

validate_email() {
  local email="$1"
  if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    return 0
  fi
  return 1
}

validate_dns() {
  local domain="$1"
  local vps_ip
  local dns_ip

  vps_ip=$(curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || curl -s -4 --max-time 5 icanhazip.com 2>/dev/null || echo "")
  dns_ip=$(dig +short A "$domain" 2>/dev/null | tail -n1)

  if [ -z "$dns_ip" ]; then
    printf "\n"
    printf "${RED}  ⚠️   Nenhum registro DNS (A) encontrado para: ${domain}${NC}\n"
    printf "${DIM}     O domínio não possui apontamento IPv4 configurado.${NC}\n"
    if [ -n "$vps_ip" ]; then
      printf "${DIM}     IP desta VPS: ${vps_ip}${NC}\n"
    fi
    printf "\n"
    printf "${YELLOW}  Deseja continuar mesmo assim? (s/N):${NC}\n"
    read -p "  > " dns_continue
    if [ "$dns_continue" != "s" ] && [ "$dns_continue" != "S" ]; then
      return 1
    fi
  elif [ -n "$vps_ip" ] && [ "$dns_ip" != "$vps_ip" ]; then
    printf "\n"
    printf "${YELLOW}  ⚠️   O DNS de ${domain} aponta para um IP diferente desta VPS.${NC}\n"
    printf "${LINE}\n"
    printf "  DNS aponta para : ${RED}${dns_ip}${NC}\n"
    printf "  IP desta VPS    : ${GREEN}${vps_ip}${NC}\n"
    printf "${LINE}\n"
    printf "\n"
    printf "${YELLOW}  Deseja continuar mesmo assim? (s/N):${NC}\n"
    read -p "  > " dns_continue
    if [ "$dns_continue" != "s" ] && [ "$dns_continue" != "S" ]; then
      return 1
    fi
  else
    printf "${GREEN}  ✅  DNS OK: ${domain} → ${dns_ip}${NC}\n"
  fi

  return 0
}

get_frontend_url() {
  print_banner
  printf "${WHITE}  💻 Digite o domínio da interface web (Frontend):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " frontend_url

  if ! validate_dns "$frontend_url"; then
    get_frontend_url
    return
  fi
}

get_backend_url() {
  print_banner
  printf "${WHITE}  💻 Digite o domínio da sua API (Backend):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " backend_url

  if ! validate_dns "$backend_url"; then
    get_backend_url
    return
  fi
}

get_urls() {
  get_deploy_email
  get_frontend_url
  get_backend_url
}

get_tenant_url() {
  print_banner
  printf "${WHITE}  💻 Digite o domínio da interface web da página de criação de empresas:${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " tenant_url
}

get_api_url() {
  print_banner
  printf "${WHITE}  💻 Digite o domínio da sua API gerada pelo superadmin:${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " api_url
}

get_tenant_token() {
  print_banner
  printf "${WHITE}  💻 Digite o token de acesso gerado pelo superadmin:${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " tenant_token
}

get_deploy_email() {
  print_banner
  printf "${WHITE}  💻 Digite o e-mail para o Certbot (SSL):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " deploy_email

  if ! validate_email "$deploy_email"; then
    printf "\n"
    printf "${RED}  ❌  E-mail inválido: ${deploy_email}${NC}\n"
    printf "${DIM}     Formato esperado: usuario@dominio.com${NC}\n"
    sleep 2
    get_deploy_email
    return
  fi
}

get_tenant_data() {
  get_tenant_url
  get_api_url
  get_tenant_token
  get_deploy_email
}

#######################################
# Aviso de escopo: a opção 2 atualiza primária + todas as secundárias
# detectadas em /home/deploycrm/*/crm. Lista as instâncias antes
# de prosseguir e exige confirmação explícita.
# Returns:
#   0 = confirmado, 1 = cancelado
#######################################
warn_update_scope_all() {
  local _secundarias=()
  local _d _fname
  for _d in /home/deploycrm/*/crm; do
    [ -d "$_d" ] || continue
    _fname=$(basename "$(dirname "$_d")")
    [ "$_fname" = "crm" ] && continue
    _secundarias+=("$_fname")
  done

  print_banner
  printf "${YELLOW}${DLINE}${NC}\n\n"
  printf "  ${YELLOW}⚠️   ESCOPO — esta atualização afeta TODAS as instâncias${NC}\n\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"
  printf "  Esta opção itera ${WHITE}primária + todas as secundárias${NC} detectadas\n"
  printf "  em ${DIM}/home/deploycrm/*/crm${NC} e aplica a versão atual em cada uma:\n\n"
  printf "    ${GREEN}•${NC} primária  ${DIM}(/home/deploycrm/crm)${NC}\n"
  if [ ${#_secundarias[@]} -gt 0 ]; then
    for _fname in "${_secundarias[@]}"; do
      printf "    ${GREEN}•${NC} ${_fname}  ${DIM}(/home/deploycrm/${_fname}/crm)${NC}\n"
    done
  else
    printf "    ${DIM}(nenhuma instância secundária detectada)${NC}\n"
  fi
  printf "\n"
  printf "  ${WHITE}Cada instância tem PM2 parado e reiniciado individualmente,${NC}\n"
  printf "  ${WHITE}com rollback isolado em caso de falha.${NC}\n\n"
  printf "  ${DIM}A opção [2] já cobre primária + secundárias num único passe.${NC}\n\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"
  printf "  Para confirmar, digite ${WHITE}ATUALIZAR${NC}:\n"
  printf "  (ou pressione Enter para cancelar)\n\n"
  read -p "  > " _scope_confirm

  if [[ "${_scope_confirm}" != "ATUALIZAR" ]]; then
    printf "\n  ${YELLOW}Operação cancelada.${NC}\n\n"
    sleep 1
    return 1
  fi

  printf "\n  ${GREEN}✅ Escopo confirmado.${NC}\n\n"
  sleep 1
  return 0
}

software_update() {
  init_error_log "update"
  warn_update_scope_all || return 1
  warn_snapshot_required "atualização" || return 1
  rollback_ask_mode
  if [[ "${ROLLBACK_WITH_DUMP}" != "skip" ]]; then
    rollback_create_backup
  fi
  # Pré-flight global (Node 20, swap, disco) — usa instância primária para checks de ambiente
  preflight_checks ""
  system_check_fail2ban
  system_puppeteer_dependencies
  update_bd_update
  # Backend: stop, mover zip, limpar artefatos antigos, extrair APENAS backend
  update_stop_pm2
  update_mv_crm                   # cp update.zip /home/deploycrm/
  update_delete_backend            # limpa node_modules/dist/package*.json do backend
  update_tos                       # remove PDFs antigos
  update_unzip_backend_only        # extrai SÓ backend + PDFs (NÃO toca frontend)
  update_backend_node_dependencies
  update_backend_db_migrate
  # Frontend: loop por instância — detecta Vue/Next ANTES de extrair, faz rename Vue → legacy,
  # então _frontend_extract_zip puxa do /home/deploycrm/update.zip (que ainda existe).
  software_update_all_frontends
  # Agora sim: zip pode ser removido
  update_delete_zip
  # Backend PM2 estava parado; restart
  update_start_pm2
  install_firewall
  update_success
}

software_migration() {
  init_error_log "migration"
  migration_node_install
  migration_bd_update
  migration_stop_pm2
  migration_mv_crm
  migration_delete_backend
  migration_delete_frontend
  migration_unzip_crm
  migration_delete_zip
  migration_backend_node_dependencies
  migration_backend_db_migrate
  migration_backend_db_seed
  migration_backend_start_pm2
  migration_frontend_node_dependencies
  migration_frontend_node_build
  migration_frontend_start_pm2
  install_firewall
  migration_success
}

wweb_js() {
  wwebjs_node_install
  wwebjs_stop_pm2
  wwebjs_delete_backend
  wwebjs_update_api
  wwebjs_reboot
}

pending_fix() {
  pending_node_install
  pending_stop_pm2
  pending_mv_fix
  pending_delete_service
  pending_unzip_fix
  pending_delete_zip
  pending_restart_pm2
}

tenant() {
  get_tenant_data
  tenant_copy_zip
  tenant_unzip
  tenant_set_env
  tenant_install
  tenant_start_pm2
  tenant_nginx_setup
  tenant_delete_zip
  tenant_certbot_setup
  install_firewall
  tenant_success
}

redis() {
  docker_list_and_kill_redis
  create_redis_service
  check_redis_status
  redis_start_pm2
}

portainer_management() {
  step_header "🐳" "Gerenciar Portainer" \
    "Portainer é uma interface web para gerenciar containers Docker."
  printf "${DIM}  Acesse em: http://<IP-DO-SERVIDOR>:9000  |  porta segura: 9443${NC}\n"
  printf "${DIM}  Permite visualizar logs, inspecionar volumes, criar/destruir containers${NC}\n"
  printf "${DIM}  e monitorar uso de CPU/memória de cada serviço em tempo real.${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${YELLOW}[1]${NC}  Reiniciar o Portainer\n"
  printf "       ${DIM}↳ docker restart portainer — útil quando a interface web trava ou não responde.${NC}\n\n"
  printf "  ${RED}[2]${NC}  Remover o Portainer e seus volumes\n"
  printf "       ${DIM}↳ Para e remove o container + todos os dados salvos (configurações, usuários).${NC}\n"
  printf "       ${DIM}  Use apenas se quiser reinstalar do zero.${NC}\n\n"
  printf "  ${GREEN}[3]${NC}  Recriar o Portainer\n"
  printf "       ${DIM}↳ Remove o container existente e sobe um novo com a senha atual.${NC}\n"
  printf "       ${DIM}  Use quando o container estiver corrompido ou precisar de atualização.${NC}\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n"
  printf "\n"
  read -p "  Opção > " portainer_option

  case "${portainer_option}" in
    1)
      portainer_restart
      ask_continue
      ;;
    2)
      portainer_remove
      ask_continue
      ;;
    3)
      portainer_recreate
      ask_continue
      ;;
    0)
      inquiry_options
      ;;
    *)
      portainer_management
      ;;
  esac
}

monitoring_setup() {
  step_header "📊" "Configurar Monitoramento" \
    "Stack de observabilidade para acompanhar a saúde do servidor em tempo real."
  printf "${DIM}  Prometheus coleta métricas (CPU, memória, disco, rede, requisições).${NC}\n"
  printf "${DIM}  Node Exporter expõe métricas do SO para o Prometheus (porta 9100).${NC}\n"
  printf "${DIM}  Grafana exibe dashboards visuais e alertas com base nos dados coletados.${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${GREEN}[1]${NC}  Instalar Prometheus + Node Exporter\n"
  printf "       ${DIM}↳ Coleta métricas do servidor. Interface em: http://<IP>:9090${NC}\n\n"
  printf "  ${GREEN}[2]${NC}  Instalar Grafana\n"
  printf "       ${DIM}↳ Dashboard visual. Interface em: http://<IP>:3022  (login: admin/admin)${NC}\n"
  printf "       ${DIM}  Já conectado ao Prometheus automaticamente.${NC}\n\n"
  printf "  ${GREEN}[3]${NC}  Instalar tudo (Prometheus + Node Exporter + Grafana)\n"
  printf "       ${DIM}↳ Configuração completa da stack de monitoramento.${NC}\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n"
  printf "\n"
  read -p "  Opção > " monitoring_option

  case "${monitoring_option}" in
    1)
      setup_prometheus
      ask_continue
      ;;
    2)
      setup_grafana
      ask_continue
      ;;
    3)
      setup_prometheus
      setup_grafana
      ask_continue
      ;;
    0)
      inquiry_options
      ;;
    *)
      monitoring_setup
      ;;
  esac
}

advanced_settings() {
  print_banner
  printf "${WHITE}  💻 Configurações Avançadas${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${DIM}[1]${NC}  Configurar backup personalizado\n"
  printf "  ${DIM}[2]${NC}  Configurar Rate Limiting\n"
  printf "  ${DIM}[3]${NC}  Configurar Fail2ban\n"
  printf "  ${DIM}[4]${NC}  Configurar Health Check\n"
  printf "  ${DIM}[5]${NC}  Configurar Firewall\n"
  printf "  ${DIM}[6]${NC}  Configurar tudo\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n"
  printf "\n"
  read -p "  Opção > " advanced_option

  case "${advanced_option}" in
    1)
      setup_backup
      ask_continue
      ;;
    2)
      setup_rate_limiting
      ask_continue
      ;;
    3)
      setup_fail2ban
      ask_continue
      ;;
    4)
      setup_health_check
      ask_continue
      ;;
    5)
      setup_firewall
      ask_continue
      ;;
    6)
      setup_backup
      setup_rate_limiting
      setup_fail2ban
      setup_health_check
      setup_firewall
      ask_continue
      ;;
    0)
      inquiry_options
      ;;
    *)
      advanced_settings
      ;;
  esac
}

#######################################
# Pergunta se quer continuar ou sair
# Arguments:
#   None
#######################################
ask_continue() {
  printf "\n"
  printf "${LINE}\n"
  printf "  ${DIM}Pressione ENTER para voltar ao menu ou digite 'sair' para encerrar:${NC}\n\n"
  read -p "  > " choice
  if [ "$choice" = "sair" ]; then
    exit 0
  else
    inquiry_options
  fi
}

#######################################
# Menu principal interativo
# Arguments:
#   None
#######################################
inquiry_options() {
  print_banner
  printf "${YELLOW}  ⚠️   Antes de atualizar ou migrar: crie um snapshot da VPS.${NC}\n\n"

  printf "${CYAN_LIGHT}  INSTALAÇÃO${NC}  ${DIM}────────────────────────────────────────────────${NC}\n"
  printf "  ${GREEN}[1]${NC}   Instalar crm               ${DIM}— Sistema, Node 20, Docker, PostgreSQL, Redis, nginx, SSL, PM2${NC}\n"

  printf "${CYAN_LIGHT}  ATUALIZAÇÃO${NC}  ${DIM}───────────────────────────────────────────────${NC}\n"
  printf "  ${YELLOW}[2]${NC}   Atualizar crm (TUDO)       ${DIM}— Atualiza primária + TODAS as secundárias num único passe${NC}\n"
  printf "  ${YELLOW}[3]${NC}   Instalar instâncias secund. ${DIM}— Nova instalação crm isolada no mesmo servidor${NC}\n"
  printf "  ${DIM}[4]   Atualizar APENAS secund.    — Legado, não funciona mais; opção [2] já atualiza tudo${NC}\n"

  printf "${CYAN_LIGHT}  CONFIGURAÇÕES${NC}  ${DIM}─────────────────────────────────────────────${NC}\n"
  printf "  ${DIM}[0]${NC}   Interface empresa (opc.)    ${DIM}— Portal externo de cadastro; crm já tem gestão de tenants nativa${NC}\n"
  printf "  ${DIM}[5]   Instalar Webchat            — Legado, não funciona mais; widget agora é nativo no crm${NC}\n"
  printf "  ${DIM}[6]${NC}   Alterar Subdomínio          ${DIM}— Atualiza domínios, reconfigura nginx e renova SSL${NC}\n"
  printf "  ${DIM}[7]${NC}   Gerenciar Portainer         ${DIM}— Interface web Docker (reiniciar, remover, recriar)${NC}\n"
  printf "  ${DIM}[8]${NC}   Recriar Redis               ${DIM}— Recria container Docker do Redis (cache e filas)${NC}\n"
  printf "  ${DIM}[9]${NC}   Configurar Firewall         ${DIM}— UFW: portas 22 (SSH), 80, 443 (HTTPS), 9000 (Portainer)${NC}\n"
  printf "  ${DIM}[10]${NC}  Configurar Monitoramento    ${DIM}— Prometheus + Node Exporter + Grafana em Docker${NC}\n"
  printf "  ${DIM}[11]${NC}  Permissões deploycrm        ${DIM}— chown -R deploycrm:deploycrm /home/deploycrm${NC}\n"
  printf "  ${DIM}[12]${NC}  Heap do Backend             ${DIM}— Ajusta --max-old-space-size do Node.js no PM2${NC}\n"
  printf "  ${DIM}[13]${NC}  PM2-Logrotate               ${DIM}— Rotação de logs PM2: tamanho máximo, retenção e compressão${NC}\n"

  printf "${CYAN_LIGHT}  FRONTEND / DOCKER${NC}  ${DIM}───────────────────────────────────────${NC}\n"
  printf "  ${YELLOW}[15]${NC}  Gerenciar frontendNovo      ${DIM}— Migração / cleanup / paralelo (sub-menu dinâmico)${NC}\n"
  printf "  ${YELLOW}[16]${NC}  Instalação Docker (Beta)    ${DIM}— Sobe backend+frontend+frontNovo via Docker+nginx${NC}\n"

  printf "${CYAN_LIGHT}  ROLLBACK${NC}  ${DIM}───────────────────────────────────────────────────${NC}\n"
  printf "  ${DIM}[14]${NC}  Restaurar versão anterior   ${DIM}— Lista backups, restaura código e/ou banco de dados${NC}\n"

  printf "${CYAN_LIGHT}  SEGURANÇA${NC}  ${DIM}──────────────────────────────────────────────────${NC}\n"
  printf "  ${GREEN}[17]${NC}  Auditoria de Segurança      ${DIM}— Verifica SSH, Fail2ban, firewall e brute force (só leitura)${NC}\n"

  printf "${CYAN_LIGHT}  BANCO DE DADOS${NC}  ${DIM}─────────────────────────────────────────────${NC}\n"
  printf "  ${CYAN_LIGHT}[18]${NC}  PgBouncer                   ${DIM}— Connection pooler: instalar, status ou remover por instância${NC}\n"

  # [19], [20] e [21] — itens condicionais (so aparecem se o tipo de install bater)
  if docker_install_detected; then
    printf "  ${CYAN_LIGHT}[19]${NC}  Otimizar Docker compose     ${DIM}— Aplica novo docker-compose.yml (volumes preservados, ~30s downtime)${NC}\n"
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^postgresql$'; then
    printf "  ${CYAN_LIGHT}[20]${NC}  Tunar PostgreSQL (PM2)      ${DIM}— ALTER SYSTEM + reload/restart no container postgres standalone${NC}\n"
  fi
  if pm2_health_available; then
    printf "  ${CYAN_LIGHT}[21]${NC}  Health PM2 backend          ${DIM}— ecosystem.config.js + auto-restart + logrotate + pm2 startup (idempotente)${NC}\n"
  fi

  printf "\n"
  read -p "  Opção > " option

  case "${option}" in
    1)
      if [[ "${crm_DEV:-}" != "1" ]]; then
        system_check_os
        system_check_port_80
      fi
      get_urls
      ;;

    2)
      software_update
      ask_continue
      ;;

    3)
      cd "${PROJECT_ROOT}/multi"
      chmod +x crm
      bash crm
      ask_continue
      ;;

    4)
      print_banner
      printf "${YELLOW}${DLINE}${NC}\n\n"
      printf "  ${YELLOW}ℹ️   Opção legada — não funciona mais${NC}\n\n"
      printf "${YELLOW}${DLINE}${NC}\n\n"
      printf "  A opção [4] (Atualizar APENAS secundárias) foi descontinuada.\n\n"
      printf "  ${WHITE}Use a opção [2]${NC} — ${GREEN}Atualizar crm (TUDO)${NC} — que já faz\n"
      printf "  a primária + todas as secundárias num único passe.\n\n"
      printf "  ${DIM}Esta opção do menu foi mantida apenas por compatibilidade${NC}\n"
      printf "  ${DIM}visual e não executa mais nenhuma ação.${NC}\n\n"
      printf "${YELLOW}${DLINE}${NC}\n\n"
      ask_continue
      ;;

    5)
      print_banner
      printf "${YELLOW}${DLINE}${NC}\n\n"
      printf "  ${YELLOW}ℹ️   Webchat agora é nativo no crm${NC}\n\n"
      printf "${YELLOW}${DLINE}${NC}\n\n"
      printf "  O widget de Webchat passou a ser entregue nativamente pelo\n"
      printf "  próprio crm — não precisa mais ser instalado por este script.\n\n"
      printf "  ${WHITE}Como usar:${NC}\n"
      printf "    ${GREEN}•${NC} Acesse o painel do crm\n"
      printf "    ${GREEN}•${NC} Vá em ${WHITE}Sessões → Webchat${NC} para gerar o snippet\n"
      printf "    ${GREEN}•${NC} Cole o JS no site externo\n\n"
      printf "  ${DIM}Esta opção do menu foi mantida apenas por compatibilidade${NC}\n"
      printf "  ${DIM}com instalações antigas e não executa mais nenhuma ação.${NC}\n\n"
      printf "${YELLOW}${DLINE}${NC}\n\n"
      ask_continue
      ;;

    6)
      change_subdomain
      ask_continue
      ;;

    7)
      portainer_management
      ask_continue
      ;;

    8)
      recreate_redis
      ask_continue
      ;;

    9)
      setup_firewall
      ask_continue
      ;;

    10)
      monitoring_setup
      ask_continue
      ;;

    11)
      set_folder_owner
      ask_continue
      ;;

    12)
      update_backend_heap
      ask_continue
      ;;

    13)
      setup_pm2_logrotate
      ask_continue
      ;;

    14)
      rollback_menu
      ask_continue
      ;;

    15)
      frontnovo_dynamic_menu
      ask_continue
      ;;

    16)
      docker_install_or_update
      ask_continue
      ;;

    17)
      run_security_audit
      ask_continue
      ;;

    18)
      pgbouncer_menu
      ask_continue
      ;;

    19)
      docker_apply_optim
      ask_continue
      ;;

    20)
      pg_tune_standalone
      ask_continue
      ;;

    21)
      pm2_apply_health_fixes
      ask_continue
      ;;

    0)
      tenant
      ask_continue
      ;;

    *)
      ask_continue
      ;;
  esac
}

#######################################
# Define o dono de todas as pastas para deploycrm
# Arguments:
#   None
#######################################
set_folder_owner() {
  print_banner
  printf "${WHITE}  💻 Definindo dono das pastas para deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  chown -R deploycrm:deploycrm /home/deploycrm
  printf "${GREEN}  ✅  Dono das pastas atualizado para deploycrm:deploycrm${NC}\n"
EOF

  sleep 2
}

#######################################
# Instala e configura pm2-logrotate
# Arguments:
#   None
#######################################
setup_pm2_logrotate() {
  print_banner
  printf "${WHITE}  💻 Configurando pm2-logrotate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # Verificar se já está instalado
  if sudo -u deploycrm pm2 list | grep -q "pm2-logrotate"; then
    printf "${YELLOW}  ⚠️   pm2-logrotate já está instalado.${NC}\n\n"
  else
    printf "${WHITE}  💻 Instalando pm2-logrotate...${GRAY_LIGHT}\n\n"
    sudo su - deploycrm <<EOF
    pm2 install pm2-logrotate
EOF
    sleep 2
  fi

  # Obter configurações atuais
  current_max_size=$(sudo -u deploycrm pm2 get pm2-logrotate:max_size 2>/dev/null | grep -oP 'value:\s*\K[^\s]+' || echo "")
  current_retain=$(sudo -u deploycrm pm2 get pm2-logrotate:retain 2>/dev/null | grep -oP 'value:\s*\K[^\s]+' || echo "")
  current_compress=$(sudo -u deploycrm pm2 get pm2-logrotate:compress 2>/dev/null | grep -oP 'value:\s*\K[^\s]+' || echo "")

  if [ -n "$current_max_size" ] || [ -n "$current_retain" ] || [ -n "$current_compress" ]; then
    printf "${WHITE}  📊 Configurações atuais:${GRAY_LIGHT}\n"
    [ -n "$current_max_size" ] && printf "     Tamanho máximo : ${current_max_size}\n"
    [ -n "$current_retain"   ] && printf "     Retenção       : ${current_retain} dias\n"
    [ -n "$current_compress" ] && printf "     Compressão     : ${current_compress}\n"
    printf "\n"
  fi

  # Tamanho máximo
  printf "${WHITE}  Tamanho máximo por arquivo de log (ex: 300M, 1G):${NC}\n"
  if [ -n "$current_max_size" ]; then
    read -p "  > [Enter para manter ${current_max_size}]: " max_size
  else
    read -p "  > [Enter para padrão 300M]: " max_size
  fi
  if [ -z "$max_size" ]; then
    max_size="${current_max_size:-300M}"
  fi
  if ! [[ "$max_size" =~ ^[0-9]+[MGKmgk]$ ]]; then
    printf "${RED}  ❌  Formato inválido. Use: 300M, 500M, 1G, etc.${NC}\n\n"
    return 1
  fi

  # Retenção
  printf "\n${WHITE}  Dias de retenção dos logs:${NC}\n"
  if [ -n "$current_retain" ]; then
    read -p "  > [Enter para manter ${current_retain}]: " retain
  else
    read -p "  > [Enter para padrão 7]: " retain
  fi
  if [ -z "$retain" ]; then
    retain="${current_retain:-7}"
  fi
  if ! [[ "$retain" =~ ^[0-9]+$ ]]; then
    printf "${RED}  ❌  Valor inválido. Deve ser número inteiro.${NC}\n\n"
    return 1
  fi

  # Compressão
  printf "\n${WHITE}  Habilitar compressão dos logs? (s/N):${NC}\n"
  read -p "  > " compress_choice
  if [ -z "$compress_choice" ]; then
    compress="${current_compress:-false}"
  elif [ "$compress_choice" = "s" ] || [ "$compress_choice" = "S" ]; then
    compress="true"
  else
    compress="false"
  fi

  # Resumo
  printf "\n${WHITE}  📊 Resumo da configuração:${NC}\n"
  printf "${LINE}\n"
  printf "  Tamanho máximo : ${max_size}\n"
  printf "  Retenção       : ${retain} dias\n"
  printf "  Compressão     : $([ "$compress" = "true" ] && echo "Habilitada" || echo "Desabilitada")\n"
  printf "${LINE}\n\n"

  printf "${YELLOW}  ⚠️   Confirma aplicar essas configurações? (s/N):${NC}\n"
  read -p "  > " confirm
  if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
    printf "${YELLOW}  Operação cancelada.${NC}\n\n"
    return 0
  fi

  sudo su - deploycrm <<EOF
  pm2 set pm2-logrotate:max_size ${max_size}
  pm2 set pm2-logrotate:retain ${retain}
  pm2 set pm2-logrotate:compress ${compress}
  pm2 save
EOF

  sleep 2
  print_banner
  printf "${GREEN}  ✅  pm2-logrotate configurado com sucesso!${NC}\n\n"
  printf "${WHITE}  📊 Configurações aplicadas:${NC}\n"
  printf "${LINE}\n"
  printf "  Tamanho máximo : ${max_size}\n"
  printf "  Retenção       : ${retain} dias\n"
  printf "  Compressão     : $([ "$compress" = "true" ] && echo "Habilitada" || echo "Desabilitada")\n"
  printf "${LINE}\n\n"
  sleep 2
}

#######################################
# Atualiza o heap e configurações avançadas do backend
# Arguments:
#   None
#######################################
update_backend_heap() {
  print_banner
  printf "${WHITE}  💻 Configurando parâmetros avançados do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  instances=()
  pm2_names=()
  instance_paths=()

  while IFS= read -r instance; do
    instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
      pm2_name="crm-backend"
      instance_path="/home/deploycrm/crm"
    else
      pm2_name="${instance_name}-crm-backend"
      instance_path="/home/deploycrm/$instance_name/crm"
    fi

    if sudo -u deploycrm pm2 list | grep -q "$pm2_name"; then
      instances+=("$instance_name")
      pm2_names+=("$pm2_name")
      instance_paths+=("$instance_path")
    fi
  done < <(find /home/deploycrm -type d -name "crm" 2>/dev/null)

  if [ ${#instances[@]} -eq 0 ]; then
    printf "${RED}  ❌  Nenhuma instância crm com backend em execução encontrada!${NC}\n\n"
    return 1
  fi

  printf "${WHITE}  📊 Instâncias encontradas:${NC}\n"
  printf "${LINE}\n"
  for i in "${!instances[@]}"; do
    printf "  ${DIM}[$((i+1))]${NC}  ${instances[$i]}  ${DIM}(PM2: ${pm2_names[$i]})${NC}\n"
  done
  printf "${LINE}\n\n"

  read -p "  Número da instância > " instance_number
  if [ "$instance_number" -lt 1 ] || [ "$instance_number" -gt ${#instances[@]} ]; then
    printf "${RED}  ❌  Opção inválida!${NC}\n\n"
    return 1
  fi

  selected_index=$((instance_number-1))
  selected_instance=${instances[$selected_index]}
  selected_pm2_name=${pm2_names[$selected_index]}
  selected_instance_path=${instance_paths[$selected_index]}

  pm2_info=$(sudo -u deploycrm pm2 show "$selected_pm2_name" 2>/dev/null)
  current_heap=$(echo "$pm2_info" | grep "node_args" | grep -oP 'max-old-space-size=\K[0-9]+' || echo "não configurado")
  current_expose_gc=$(echo "$pm2_info" | grep "node_args" | grep -q "expose-gc" && echo "sim" || echo "não")
  current_max_memory=$(echo "$pm2_info" | grep "max_memory_restart" | awk '{print $2}' || echo "não configurado")

  printf "\n${WHITE}  📊 Configurações atuais:${NC}\n"
  printf "${LINE}\n"
  printf "  Instância      : ${selected_instance}\n"
  printf "  Processo PM2   : ${selected_pm2_name}\n"
  printf "  Heap           : ${current_heap} MB\n"
  printf "  Expose GC      : ${current_expose_gc}\n"
  printf "  Max Mem Restart: ${current_max_memory}\n"
  printf "${LINE}\n\n"

  read -p "  Novo heap em MB (ex: 2048) [Enter para manter]: " new_heap
  if [ -z "$new_heap" ]; then
    new_heap="$current_heap"
    [ "$new_heap" = "não configurado" ] && new_heap="2048"
  elif ! [[ "$new_heap" =~ ^[0-9]+$ ]]; then
    printf "${RED}  ❌  Valor inválido!${NC}\n\n"
    return 1
  fi

  printf "\n"
  read -p "  Habilitar --expose-gc? (s/N): " enable_expose_gc
  if [ "$enable_expose_gc" = "s" ] || [ "$enable_expose_gc" = "S" ]; then
    expose_gc_flag="--expose-gc"
  else
    expose_gc_flag=""
  fi

  printf "\n"
  read -p "  Max-memory-restart em GB (ex: 15) [Enter para não configurar]: " max_memory_restart
  if [ -n "$max_memory_restart" ] && ! [[ "$max_memory_restart" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    printf "${RED}  ❌  Valor inválido!${NC}\n\n"
    return 1
  fi

  node_args="--max-old-space-size=$new_heap"
  [ -n "$expose_gc_flag" ] && node_args="$node_args $expose_gc_flag"

  printf "\n${WHITE}  📊 Resumo:${NC}\n"
  printf "${LINE}\n"
  printf "  Heap           : ${new_heap} MB\n"
  printf "  Expose GC      : $([ -n "$expose_gc_flag" ] && echo "Habilitado" || echo "Desabilitado")\n"
  [ -n "$max_memory_restart" ] && printf "  Max Mem Restart: ${max_memory_restart} G\n"
  printf "${LINE}\n\n"

  printf "${YELLOW}  ⚠️   O processo PM2 será reiniciado. Confirma? (s/N):${NC}\n"
  read -p "  > " confirm
  if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
    printf "${YELLOW}  Operação cancelada.${NC}\n\n"
    return 0
  fi

  sudo su - deploycrm <<EOF
  cd "$selected_instance_path/backend"
  pm2 stop "$selected_pm2_name"
  pm2 delete "$selected_pm2_name"
EOF

  if [ -n "$max_memory_restart" ]; then
    sudo -u deploycrm bash -c "cd '$selected_instance_path/backend' && pm2 start dist/server.js --name '$selected_pm2_name' --node-args='$node_args' --max-memory-restart ${max_memory_restart}G"
  else
    sudo -u deploycrm bash -c "cd '$selected_instance_path/backend' && pm2 start dist/server.js --name '$selected_pm2_name' --node-args='$node_args'"
  fi

  sudo -u deploycrm pm2 save

  sleep 2
  print_banner
  printf "${GREEN}  ✅  Backend atualizado com sucesso!${NC}\n\n"
  printf "${WHITE}  📊 Configurações aplicadas:${NC}\n"
  printf "${LINE}\n"
  printf "  Instância      : ${selected_instance}\n"
  printf "  Processo PM2   : ${selected_pm2_name}\n"
  printf "  Heap           : ${new_heap} MB\n"
  printf "  Expose GC      : $([ -n "$expose_gc_flag" ] && echo "Habilitado" || echo "Desabilitado")\n"
  [ -n "$max_memory_restart" ] && printf "  Max Mem Restart: ${max_memory_restart} G\n"
  printf "${LINE}\n\n"
  sleep 2
}
