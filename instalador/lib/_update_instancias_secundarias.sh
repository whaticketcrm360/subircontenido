#!/bin/bash
# 
# system management para atualização de instâncias secundárias

#######################################
# Percorre todas as instalações dentro de /home/deploycrm/
# e executa a atualização para cada pasta crm encontrada.
#######################################
update_all_instances() {
  # Lista instâncias secundárias detectadas
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
  printf "  ${YELLOW}⚠️   ESCOPO — esta opção afeta APENAS as instâncias secundárias${NC}\n\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"
  printf "  A primária ${WHITE}(/home/deploycrm/crm)${NC} ${RED}NÃO${NC} é atualizada por esta opção.\n\n"
  if [ ${#_secundarias[@]} -gt 0 ]; then
    printf "  Instâncias secundárias detectadas:\n\n"
    for _fname in "${_secundarias[@]}"; do
      printf "    ${GREEN}•${NC} ${_fname}  ${DIM}(/home/deploycrm/${_fname}/crm)${NC}\n"
    done
    printf "\n"
  else
    printf "  ${RED}Nenhuma instância secundária detectada — nada a fazer.${NC}\n\n"
    sleep 2
    return 1
  fi
  printf "  ${DIM}Use esta opção apenas se você atualizou o backend da primária${NC}\n"
  printf "  ${DIM}manualmente e precisa reaplicar a versão nas secundárias.${NC}\n"
  printf "  ${DIM}Para atualizar TUDO de uma vez, use a opção [2] do menu.${NC}\n\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"

  warn_snapshot_required "atualização de instâncias secundárias" || return 1
  rollback_ask_mode

  # Garantir que update.zip está em /home/deploycrm/ — fonte única para
  # todas as instâncias durante este loop.
  if [ ! -f /home/deploycrm/update.zip ] && [ -f "${PROJECT_ROOT}/update.zip" ]; then
    sudo cp "${PROJECT_ROOT}/update.zip" /home/deploycrm/update.zip
  fi

  for instance in /home/deploycrm/*/crm; do
    if [ -d "$instance" ]; then
      instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
      if [ -n "$instance_name" ]; then
        if [[ "${ROLLBACK_WITH_DUMP}" != "skip" ]]; then
          rollback_create_instance_backup "$instance" "$instance_name"
        fi
        echo "\n🚀 Atualizando instância: $instance_name"
        update_instance "$instance" "$instance_name"
      fi
    fi
  done

  # Cleanup global do zip
  sudo rm -f /home/deploycrm/update.zip
}

#######################################
# Executa a atualização em uma instância específica.
# Pós-migração para Next: o frontend é tratado pelos helpers Next-aware
# (migrate_vue_to_next OU rebuild_next_in_place, conforme o estado).
# Arguments:
#   $1 - Caminho da instância (ex: /home/deploycrm/crm2/crm)
#   $2 - Nome da instância (ex: crm2)
#######################################
update_instance() {
  local INSTANCE_PATH="$1"
  local INSTANCE_NAME="$2"

  print_banner
  printf "${WHITE} 💻 Atualizando instância $INSTANCE_NAME em $INSTANCE_PATH...${GRAY_LIGHT}\n\n"

  preflight_checks "$INSTANCE_NAME" || {
    printf "${RED} ❌ Pré-flight falhou para $INSTANCE_NAME — abortando esta instância.${NC}\n"
    return 1
  }

  sleep 1

  # Parar serviços PM2 da instância (não tudo — outras instâncias continuam)
  sudo su - deploycrm <<EOF
  pm2 stop ${INSTANCE_NAME}-crm-backend  2>/dev/null || true
  pm2 stop ${INSTANCE_NAME}-crm-frontend 2>/dev/null || true
  pm2 flush all
EOF

  sleep 1

  # Copiar update.zip para o root da instância (parent de crm)
  sudo cp "${PROJECT_ROOT}/update.zip" "$INSTANCE_PATH/.."

  # Limpar e extrair APENAS backend (princípio: rename never delete vale para o frontend)
  sudo su - root <<EOF
  cd "$INSTANCE_PATH/backend" || exit
  rm -rf node_modules dist package.json package-lock.json
EOF

  sudo su - deploycrm <<EOF
  cd "$INSTANCE_PATH/.."
  unzip -o update.zip "crm/backend/*" 2>/dev/null || true
  unzip -o update.zip "*.pdf"             2>/dev/null || true
EOF

  sudo su - deploycrm <<EOF
  cd "$INSTANCE_PATH/backend"
  npm install --force
  npx sequelize db:migrate
EOF

  # Frontend Next-aware: detecta Vue/Next e aplica migrate ou rebuild.
  # _frontend_extract_zip vai procurar update.zip em /home/deploycrm/update.zip
  # OU em $INSTANCE_PATH/../update.zip (para multi). Preparar esse fallback.
  if [ ! -f /home/deploycrm/update.zip ]; then
    sudo cp "$INSTANCE_PATH/../update.zip" /home/deploycrm/update.zip
  fi
  software_update_frontend_for_instance "$INSTANCE_NAME"

  # Limpar zip da instância (o /home/deploycrm/update.zip é apagado no fim de update_all_instances)
  sudo rm -f "$INSTANCE_PATH/../update.zip"

  # Reiniciar PM2 da instância
  sudo su - deploycrm <<EOF
  pm2 restart ${INSTANCE_NAME}-crm-backend  2>/dev/null || true
  pm2 restart ${INSTANCE_NAME}-crm-frontend 2>/dev/null || true
  pm2 save
EOF

  printf "${GREEN} ✅ Instância $INSTANCE_NAME atualizada com sucesso!${NC}\n"
}

#######################################
# Cria mensagem final
# Arguments:
#   None
#######################################
update_instances_success() {
  print_banner
  printf "${GREEN} 💻 Atualização de todas as instâncias concluída!${NC}"
  printf "\n\n"
  printf "${WHITE} 📊 Instâncias atualizadas:${GRAY_LIGHT}\n\n"

  # Percorrer todas as instâncias para mostrar informações
  for instance in /home/deploycrm/*/crm; do
    if [ -d "$instance" ]; then
      instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
      if [ -n "$instance_name" ]; then
        # Ler URLs do arquivo .env do backend
        if [ -f "$instance/backend/.env" ]; then
          backend_url=$(grep "BACKEND_URL=" "$instance/backend/.env" | cut -d'=' -f2)
          frontend_url=$(grep "FRONTEND_URL=" "$instance/backend/.env" | cut -d'=' -f2)
          
          printf "  • Instância: ${YELLOW}$instance_name${NC}\n"
          printf "    - Pasta: ${GRAY_LIGHT}$instance${NC}\n"
          printf "    - Backend: ${GREEN}$backend_url${NC}\n"
          printf "    - Frontend: ${GREEN}$frontend_url${NC}\n\n"
        fi
      fi
    fi
  done

  printf "${YELLOW} ⚠️  Caso o sistema apresente alguma instabilidade, verifique os retornos dos processos rolando a barra lateral para cima, em busca de possíveis incosistências ou restaure o seu backup...${NC}"
  printf "\n"
  printf "${GREEN}FAQ: https://hotmart.com/es/club/whatitan${NC}"
  printf "\n"
  printf "${GREEN}Suporte: https://wa.me/50489520312/${NC}"
  printf "\n"
  printf "${CYAN_LIGHT}";
  printf "${NC}";

  sleep 2
} 