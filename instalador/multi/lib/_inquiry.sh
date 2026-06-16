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

get_frontend_port() {
  print_banner
  printf "${WHITE}  💻 Digite a porta do Frontend (entre 3335 e 3345):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " frontend_port
}

get_backend_port() {
  print_banner
  printf "${WHITE}  💻 Digite a porta do Backend (entre 8090 e 8190):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " backend_port
}

get_redis_port() {
  print_banner
  printf "${WHITE}  💻 Digite a porta do Redis (entre 6380 e 6480):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " redis_port
}

get_pg_port() {
  print_banner
  printf "${WHITE}  💻 Digite a porta do PostgreSQL (entre 5440 e 5540):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " pg_port
}

get_db_name() {
  print_banner
  printf "${WHITE}  💻 Digite o nome do banco de dados (ex.: crm2):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " db_name
}

get_folder_name() {
  print_banner
  printf "${WHITE}  💻 Digite o nome da nova pasta (ex.: crm2):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " folder_name
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

get_urls() {
  get_deploy_email
  get_frontend_url
  get_backend_url
  get_backend_port
  get_frontend_port
  get_redis_port
  get_pg_port
  get_folder_name
}

inquiry_options() {
  print_banner
  printf "${WHITE}  Instalar instância secundária crm${NC}\n\n"

  printf "${CYAN_LIGHT}  INSTALAÇÃO${NC}\n"
  printf "${LINE}\n"
  printf "  ${GREEN}[1]${NC}  Instalar nova instância\n"
  printf "\n"

  printf "${GREEN}${DLINE}${NC}\n"
  printf "${YELLOW}  ⚠️   Antes de instalar: crie um snapshot da VPS.${NC}\n"
  printf "${GREEN}${DLINE}${NC}\n\n"

  read -p "  Opção > " option

  case "${option}" in
    1) get_urls ;;
    *) exit 0 ;;
  esac
}
