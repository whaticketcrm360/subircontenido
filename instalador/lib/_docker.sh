#!/bin/bash
#
# Rotina BETA: instalação via Docker Compose
# Sobe backend + frontend (Next.js) em containers Docker.
# Pós-migração: frontend == Next.js standalone (não há mais serviço "frontnovo"
# separado — o frontendNovo é o frontend oficial, em /frontend dentro do zip).
# nginx existente é usado como proxy SSL (certbot), sem conflito de porta.
# Traefik NÃO é iniciado nesta rotina (nginx já faz proxy + SSL).
#
# Portas host expostas pelos containers:
#   backend  → 7563
#   frontend → 7564 (mapeia container 4444 — Next.js standalone)

# DOCKER_DIR é resolvido em docker_ensure_extracted:
#   - /home/deploycrm/crm  se o install PM2 já existe (deploycrm presente)
#   - /root/crm            se é instalação Docker standalone (sem deploycrm)
DOCKER_DIR=""

#######################################
# Beta warning para instalação Docker
# Arguments:
#   None
#######################################
docker_warn_beta() {
  print_banner
  printf "${YELLOW}  ⚠️   ATENÇÃO — Instalação Docker está em BETA${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${WHITE}Esta rotina sobe backend + frontend (Next.js) em containers Docker.${NC}\n\n"
  printf "  ${CYAN_LIGHT}Arquitetura:${NC}\n"
  printf "  ${DIM}• nginx (já instalado) faz SSL + proxy → containers Docker${NC}\n"
  printf "  ${DIM}• Traefik NÃO é usado — nginx ocupa as portas 80/443${NC}\n"
  printf "  ${DIM}• Portas host: selecionadas interativamente (padrão 7563/7564/7544)${NC}\n"
  printf "  ${DIM}• Frontend oficial = Next.js (Vue/Quasar foi migrado).${NC}\n\n"
  printf "  ${YELLOW}⚠️   NEXT_PUBLIC_* são baked-in no build:${NC}\n"
  printf "  ${WHITE}Se trocar a URL do backend, é necessário rebuild do container frontend.${NC}\n\n"
  printf "  ${DIM}Se a instalação falhar, siga o tutorial em:${NC}\n"
  printf "  ${GREEN}https://hotmart.com/es/club/whatitan${NC}\n"
  printf "${LINE}\n\n"
  printf "  ${YELLOW}Pressione ENTER para continuar ou Ctrl+C para cancelar...${NC}\n"
  read -r
}

#######################################
# Verifica se Docker e Docker Compose estão instalados
# Arguments:
#   None
#######################################
docker_check_requirements() {
  step_header "🐳" "Verificando ambiente Docker" \
    "Detecta Docker, docker compose v2, nginx e certbot. Oferece instalar o que faltar."
  printf "\n"

  local missing=()
  command -v docker     &>/dev/null || missing+=("docker")
  if command -v docker &>/dev/null; then
    docker compose version &>/dev/null || missing+=("docker-compose-plugin")
  fi
  command -v nginx      &>/dev/null || missing+=("nginx")
  command -v certbot    &>/dev/null || missing+=("certbot")
  command -v unzip      &>/dev/null || missing+=("unzip")
  command -v openssl    &>/dev/null || missing+=("openssl")

  if [ ${#missing[@]} -eq 0 ]; then
    local _docker_version
    _docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    printf "  ${GREEN}✅${NC}  Ambiente OK — Docker ${_docker_version}, compose v2, nginx e certbot encontrados.\n\n"
    sleep 1
    return 0
  fi

  printf "${YELLOW}  ⚠️   Componentes faltando para a instalação Docker:${NC}\n"
  for m in "${missing[@]}"; do
    printf "    ${RED}•${NC}  %s\n" "$m"
  done
  printf "\n"
  printf "  ${WHITE}Deseja instalar agora os componentes que faltam? (S/n):${NC} "
  read -r _install_confirm
  if [ "$_install_confirm" = "n" ] || [ "$_install_confirm" = "N" ]; then
    printf "\n  ${RED}Instalação cancelada — pré-requisitos não atendidos.${NC}\n"
    printf "  ${DIM}Para instalar manualmente:${NC}\n"
    printf "  ${DIM}  curl -fsSL https://get.docker.com | sh${NC}\n"
    printf "  ${DIM}  apt-get install -y docker-compose-plugin nginx certbot python3-certbot-nginx unzip openssl${NC}\n\n"
    return 1
  fi
  printf "\n"

  # apt-get update uma vez antes de qualquer instalação via apt
  start_spinner "Atualizando índice apt..."
  sudo apt-get update -y >/dev/null 2>&1
  stop_spinner "Índice apt atualizado."

  # Instala cada componente faltando, reusando rotinas de _system.sh quando possível
  for m in "${missing[@]}"; do
    case "$m" in
      docker)
        # system_docker_install já cuida de get.docker.com + plugin compose
        system_docker_install || { log_error "docker install" "Falha ao instalar Docker"; return 1; }
        ;;
      docker-compose-plugin)
        start_spinner "Instalando docker-compose-plugin..."
        sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1
        stop_spinner "docker-compose-plugin instalado."
        ;;
      nginx)
        system_nginx_install  || { log_error "nginx install"  "Falha ao instalar nginx";  return 1; }
        ;;
      certbot)
        system_certbot_install || { log_error "certbot install" "Falha ao instalar certbot"; return 1; }
        ;;
      unzip|openssl)
        start_spinner "Instalando ${m}..."
        sudo apt-get install -y "${m}" >/dev/null 2>&1
        stop_spinner "${m} instalado."
        ;;
    esac
  done

  # Re-valida após instalação
  printf "\n"
  local still_missing=()
  for bin in docker nginx certbot unzip openssl; do
    command -v "$bin" >/dev/null 2>&1 || still_missing+=("$bin")
  done
  if command -v docker >/dev/null 2>&1 && ! docker compose version &>/dev/null; then
    still_missing+=("docker-compose-plugin")
  fi
  if [ ${#still_missing[@]} -gt 0 ]; then
    printf "  ${RED}❌  Ainda faltam após tentativa de instalação: ${still_missing[*]}${NC}\n"
    printf "  ${DIM}Verifique conexão de internet e logs do apt em /var/log/apt/.${NC}\n\n"
    return 1
  fi

  local _docker_version
  _docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
  printf "  ${GREEN}✅${NC}  Ambiente preparado — Docker ${_docker_version}, compose v2, nginx e certbot OK.\n\n"
  sleep 1
  return 0
}

#######################################
# Retorna a próxima porta TCP livre a partir de $1
# Arguments:
#   $1 — porta inicial
#######################################
_docker_next_free_port() {
  local _p=$1
  while ss -tlnp 2>/dev/null | awk '{print $4}' | grep -q ":${_p}$"; do
    _p=$((_p + 1))
  done
  echo "$_p"
}

#######################################
# Seleciona portas para os containers Docker.
# Para cada porta padrão, se estiver em uso mostra o processo,
# sugere a próxima livre e permite ao usuário confirmar ou digitar outra.
# Sets: docker_backend_port, docker_frontend_port, docker_db_port
# Arguments:
#   None
#######################################
docker_select_ports() {
  step_header "🔍" "Selecionando portas para os containers Docker" \
    "Detecta conflitos com PM2 ou outros serviços e resolve interativamente."
  printf "  ${DIM}PM2 usa 3000/4444 — portas Docker são diferentes por design.${NC}\n\n"

  # helper: pergunta porta para um serviço
  # $1=nome  $2=porta padrão  → escreve apenas a porta escolhida em stdout.
  # Tudo informativo vai para stderr (>&2) para não contaminar a captura $(...).
  _ask_port() {
    local _name="$1"
    local _default="$2"
    local _pid _proc _suggested _input

    _pid=$(ss -tlnp 2>/dev/null | awk -v p=":${_default}$" '$4 ~ p {match($0,/pid=([0-9]+)/,a); print a[1]}' | head -1)

    if [ -z "$_pid" ]; then
      printf "  ${GREEN}%-7s${NC}  %-22s ${GREEN}livre${NC} — usando %s\n" "$_default" "$_name" "$_default" >&2
      printf '%s' "$_default"
      return
    fi

    _proc=$(ps -p "$_pid" -o comm= 2>/dev/null || echo "pid $_pid")
    _suggested=$(_docker_next_free_port $((_default + 1)))
    printf "  ${RED}%-7s${NC}  %-22s ${RED}EM USO${NC} por: %s\n" "$_default" "$_name" "$_proc" >&2
    printf "         ${DIM}Próxima livre: ${_suggested}${NC}\n" >&2
    printf "         Digite a porta desejada [Enter = %s]: " "$_suggested" >&2
    read -r _input </dev/tty
    if [ -z "$_input" ]; then
      _input="$_suggested"
    fi
    # valida que é número e está livre
    if ! [[ "$_input" =~ ^[0-9]+$ ]] || [ "$_input" -lt 1024 ] || [ "$_input" -gt 65535 ]; then
      printf "  ${RED}Porta inválida. Usando %s.${NC}\n" "$_suggested" >&2
      _input="$_suggested"
    fi
    printf '%s' "$_input"
  }

  printf "  ${WHITE}%-7s  %-22s  Status${NC}\n" "Porta" "Serviço"
  printf "  ${LINE}\n"

  docker_backend_port=$(_ask_port  "backend Docker"   7563)
  docker_frontend_port=$(_ask_port "frontend Docker"  7564)
  docker_db_port=$(_ask_port       "PostgreSQL Docker" 7544)

  printf "\n"
  printf "  ${GREEN}✅${NC}  Portas definidas:\n"
  printf "  ${DIM}backend=%s  frontend=%s  postgres=%s${NC}\n\n" \
    "$docker_backend_port" "$docker_frontend_port" "$docker_db_port"
  sleep 1
}

#######################################
# Coleta domínios e email para o deploy Docker
# Sets: docker_backend_domain, docker_frontend_domain,
#       docker_backend_url, docker_frontend_url
# Arguments:
#   None
#######################################
docker_get_domains() {
  print_banner
  printf "${WHITE}  💻 Domínio do Frontend Docker (ex: dockerapp.cliente.com.br):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " docker_frontend_domain
  if ! validate_dns "$docker_frontend_domain"; then
    docker_get_domains
    return
  fi
  docker_frontend_url="https://${docker_frontend_domain}"

  print_banner
  printf "${WHITE}  💻 Domínio do Backend Docker (ex: dockerapi.cliente.com.br):${GRAY_LIGHT}"
  printf "\n\n"
  read -p "  > " docker_backend_domain
  if ! validate_dns "$docker_backend_domain"; then
    docker_get_domains
    return
  fi
  docker_backend_url="https://${docker_backend_domain}"
}

#######################################
# Garante que os arquivos da aplicação estão disponíveis para o Docker build.
# Define DOCKER_DIR dinamicamente:
#   - /home/deploycrm/crm  se PM2 já instalado (reaproveita arquivos existentes)
#   - /root/crm            standalone Docker — extrai como root, sem deploycrm
# Arguments:
#   None
#######################################
docker_ensure_extracted() {
  step_header "📦" "Verificando arquivos da aplicação" \
    "Localiza ou extrai backend/ e frontend/ (Next.js) para o Docker build."
  printf "\n"

  # Cenário 1: install PM2 anterior — arquivos já prontos
  if [ -d "/home/deploycrm/crm/backend" ]; then
    DOCKER_DIR="/home/deploycrm/crm"
    printf "  ${GREEN}✅${NC}  Usando arquivos existentes em ${DOCKER_DIR}\n\n"
    sleep 1
    return 0
  fi

  # Cenário 2: Docker standalone — extrai como root em /root/crm
  DOCKER_DIR="/root/crm"
  printf "  ${YELLOW}⚠️   Arquivos não encontrados — extraindo crm.zip como root...${NC}\n\n"

  # Copia zip se ainda não está em /root/
  if [ ! -f "/root/crm.zip" ]; then
    start_spinner "Copiando crm.zip para /root/..."
    sudo su - root <<EOF
    cp "${PROJECT_ROOT}/crm.zip" /root/crm.zip
EOF
    stop_spinner "crm.zip copiado para /root/."
  fi

  start_spinner "Extraindo crm.zip em /root/..."
  sudo su - root <<'EOF'
  cd /root
  # -o = overwrite sem perguntar; -q = quiet
  unzip -qo crm.zip </dev/null
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao extrair crm.zip."
    log_error "unzip crm docker" "Falha ao extrair crm.zip em /root"
    return 1
  fi
  stop_spinner "Arquivos extraídos em ${DOCKER_DIR}."
  sleep 1
}

#######################################
# Prepara diretório e arquivo .env do Docker
# Arguments:
#   None
#######################################
docker_prepare_env() {
  step_header "⚙️ " "Preparando ambiente Docker" \
    "Gera ${DOCKER_DIR}/.env.docker para o docker-compose."
  printf "\n"

  local _pg_pass
  _pg_pass=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
  local _jwt_secret
  _jwt_secret=$(openssl rand -base64 32)
  local _jwt_refresh_secret
  _jwt_refresh_secret=$(openssl rand -base64 32)
  # Encryption key única por instalação (NEXT_PUBLIC_* — vai para o bundle JS no build).
  local _enc_key
  _enc_key=$(openssl rand -base64 32 | tr -d '\n=' | head -c 32)

sudo su - root <<EOF
  cat <<[-]EOF > "${DOCKER_DIR}/.env.docker"
# Backend
BACKEND_URL=${docker_backend_url}
BACKEND_DOMAIN=${docker_backend_domain}
FRONTEND_URL=${docker_frontend_url}
FRONTEND_DOMAIN=${docker_frontend_domain}

# Subdomínios extras / CORS (vazios por padrão — preencher só se houver paralelo legado)
FRONTEND_URL_2=
SECURE_URL=

# Portas host (configuradas na seleção de portas)
BACKEND_PORT=${docker_backend_port}
FRONTEND_PORT=${docker_frontend_port}
DB_PORT=${docker_db_port}

# Banco de dados
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${_pg_pass}
POSTGRES_DB=postgres

# JWT
JWT_SECRET=${_jwt_secret}
JWT_REFRESH_SECRET=${_jwt_refresh_secret}

# Frontend Next.js — chave default usada pelo bundle JS (NEXT_PUBLIC_*).
# Não é segredo (vai para o bundle público), mas geramos única por VPS.
FRONTEND_ENCRYPTION_KEY=${_enc_key}

# Let's Encrypt
ACME_EMAIL=${deploy_email}

# Misc
NODE_ENV=production
[-]EOF
EOF

  printf "  ${GREEN}✅${NC}  ${DOCKER_DIR}/.env.docker criado.\n\n"
  sleep 1
}

#######################################
# Copia docker-compose.yml para o diretório Docker
# Arguments:
#   None
#######################################
docker_copy_compose() {
  step_header "📋" "Copiando docker-compose.yml" \
    "Copia ${PROJECT_ROOT}/docker-compose.yml para ${DOCKER_DIR}/."
  printf "\n"

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}/docker-compose.yml" "${DOCKER_DIR}/docker-compose.yml"
EOF

  printf "  ${GREEN}✅${NC}  docker-compose.yml copiado para ${DOCKER_DIR}/\n\n"
  sleep 1
}

#######################################
# Sobe os containers Docker (sem Traefik — nginx faz proxy)
# Arguments:
#   None
#######################################
docker_compose_up() {
  step_header "🐳" "Subindo containers Docker" \
    "Executa docker compose up com build — pode levar vários minutos."
  printf "  ${DIM}Serviços: postgres, backend, frontend (Next.js)${NC}\n"
  printf "  ${DIM}Traefik NÃO é iniciado — nginx é o proxy.${NC}\n\n"

  start_spinner "Executando docker compose up --build (pode demorar 10-20 min no primeiro build)..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  docker compose --env-file .env.docker up -d --build postgres backend frontend
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao subir containers Docker. Verifique: docker compose logs"
    log_error "docker compose up" "Falha ao subir containers em ${DOCKER_DIR}"
  else
    stop_spinner "Containers Docker iniciados com sucesso."
  fi
  sleep 2
}

#######################################
# Configura nginx para proxiar os containers Docker
# Arguments:
#   None
#######################################
docker_nginx_setup() {
  step_header "🌐" "Configurando nginx para os containers Docker" \
    "Cria vhosts: backend→${docker_backend_port}, frontend→${docker_frontend_port}."
  printf "\n"

  sleep 1

sudo su - root << EOF

# ── Backend Docker ──────────────────────────────────────────
cat > /etc/nginx/sites-available/crm-docker-backend << 'END'
server {
  server_name ${docker_backend_domain};

  location /.well-known/acme-challenge/ {
    proxy_pass http://127.0.0.1:81;
  }

  location / {
    proxy_pass http://127.0.0.1:${docker_backend_port};
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
ln -sf /etc/nginx/sites-available/crm-docker-backend /etc/nginx/sites-enabled/crm-docker-backend

# ── Frontend Docker ─────────────────────────────────────────
cat > /etc/nginx/sites-available/crm-docker-frontend << 'END'
server {
  server_name ${docker_frontend_domain};

  location /.well-known/acme-challenge/ {
    proxy_pass http://127.0.0.1:81;
  }

  location / {
    proxy_pass http://127.0.0.1:${docker_frontend_port};
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
ln -sf /etc/nginx/sites-available/crm-docker-frontend /etc/nginx/sites-enabled/crm-docker-frontend

EOF

  # Remove vhost legado de frontnovo paralelo se ainda existir (instalações antigas)
  sudo rm -f /etc/nginx/sites-enabled/crm-docker-frontnovo /etc/nginx/sites-available/crm-docker-frontnovo 2>/dev/null

  sudo nginx -t && sudo systemctl reload nginx

  printf "  ${GREEN}✅${NC}  vhosts Docker criados e nginx recarregado.\n\n"
  sleep 1
}

#######################################
# Emite SSL para os domínios Docker via certbot
# Arguments:
#   None
#######################################
docker_certbot_setup() {
  step_header "🔒" "Emitindo certificados SSL para os domínios Docker" \
    "Certbot via nginx para backend e frontend Docker."
  printf "\n"

  local _domains="${docker_backend_domain},${docker_frontend_domain}"
  printf "  ${DIM}Domínios: ${_domains}${NC}\n\n"

  start_spinner "Emitindo certificados SSL..."
  sudo su - root <<EOF
  certbot -m "${deploy_email}" \
          --nginx \
          --agree-tos \
          --redirect \
          --non-interactive \
          --domains "${_domains}"
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao emitir SSL. Verifique DNS e tente novamente."
    log_error "certbot docker" "Falha ao emitir SSL para ${_domains}"
  else
    stop_spinner "Certificados SSL emitidos para os domínios Docker."
  fi
  sleep 1
}

#######################################
# Exibe mensagem de sucesso da instalação Docker
# Arguments:
#   None
#######################################
docker_install_success() {
  print_banner
  printf "${GREEN}  ✅  Instalação Docker concluída!${NC}\n\n"
  printf "${LINE}\n"
  printf "${WHITE}  📊 Serviços em execução:${NC}\n\n"
  printf "  • Backend   : ${GREEN}${docker_backend_url}${NC}  ${DIM}(host:${docker_backend_port})${NC}\n"
  printf "  • Frontend  : ${GREEN}${docker_frontend_url}${NC}  ${DIM}(host:${docker_frontend_port})${NC}  ${DIM}(Next.js)${NC}\n"
  printf "\n"
  printf "  ${DIM}Gerenciar containers:${NC}\n"
  printf "  ${DIM}  cd ${DOCKER_DIR} && docker compose --env-file .env.docker ps${NC}\n"
  printf "  ${DIM}  docker compose --env-file .env.docker logs -f backend${NC}\n"
  printf "  ${DIM}  docker compose --env-file .env.docker down   # parar tudo${NC}\n\n"
  printf "  ${YELLOW}⚠️   NEXT_PUBLIC_* são fixos no build:${NC}\n"
  printf "  ${DIM}Para trocar a URL do backend, edite .env.docker e rebuilde:${NC}\n"
  printf "  ${DIM}  cd ${DOCKER_DIR} && docker compose --env-file .env.docker up -d --build frontend${NC}\n\n"
  printf "  ${GREEN}FAQ: https://hotmart.com/es/club/whatitan${NC}\n"
  printf "  ${GREEN}Suporte: https://wa.me/50489520312/${NC}\n"
  printf "${LINE}\n\n"

  show_error_summary
  sleep 2
}

#######################################
# Fluxo completo de instalação Docker (beta)
# Arguments:
#   None
#######################################
#######################################
# Guard rail: aborta se já existe instalação PM2 nativa rodando.
# Misturar Docker em cima de PM2 nativo gera conflito de portas, vhosts duplicados
# e backend duplicado — sempre quebra. Recomendamos VPS dedicada para Docker.
#######################################
docker_check_no_pm2_install() {
  local conflicts=()
  if sudo su - deploycrm -c "pm2 list" 2>/dev/null | grep -qE 'crm-frontend|crm-backend'; then
    conflicts+=("PM2 com processo crm-frontend ou crm-backend ativo")
  fi
  if [ -d "/home/deploycrm/crm/frontend" ] && [ -f "/home/deploycrm/crm/frontend/.env.local" ]; then
    conflicts+=("/home/deploycrm/crm/frontend já existe (instalação PM2)")
  fi
  if [ -f "/etc/nginx/sites-enabled/crm-frontend" ] || [ -f "/etc/nginx/sites-enabled/crm-backend" ]; then
    conflicts+=("vhost nginx crm-frontend ou crm-backend já ativo")
  fi
  if [ ${#conflicts[@]} -eq 0 ]; then
    return 0
  fi

  print_banner
  printf "${RED}  ❌  Conflito detectado — instalação PM2 nativa já existe nesta VPS:${NC}\n\n"
  printf "${LINE}\n"
  for c in "${conflicts[@]}"; do
    printf "  ${RED}•${NC}  %s\n" "$c"
  done
  printf "${LINE}\n\n"
  printf "  ${WHITE}Misturar Docker em cima de PM2 vai causar:${NC}\n"
  printf "  ${DIM}• Conflito de portas (4444, 7563 vs 7563/7564 Docker)${NC}\n"
  printf "  ${DIM}• Backend duplicado escrevendo no mesmo banco${NC}\n"
  printf "  ${DIM}• vhosts nginx sobrepostos${NC}\n\n"
  printf "  ${YELLOW}Use uma VPS dedicada para a instalação Docker.${NC}\n\n"
  printf "  ${YELLOW}Forçar instalação assim mesmo? (NÃO recomendado) (s/N):${NC}\n"
  read -p "  > " _force
  if [ "$_force" = "s" ] || [ "$_force" = "S" ]; then
    printf "  ${YELLOW}⚠️   Prosseguindo a seu próprio risco.${NC}\n\n"
    return 0
  fi
  return 1
}

#######################################
# Guard rail: aborta se já existe outro proxy reverso (Traefik, Caddy, HAProxy)
# ocupando 80/443. Este instalador assume nginx + certbot.
#######################################
docker_check_no_proxy_conflict() {
  local conflicts=()

  # 1. Container Traefik / Caddy / HAProxy rodando
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qiE 'traefik|caddy|haproxy'; then
    local _names
    _names=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE 'traefik|caddy|haproxy' | head -3 | tr '\n' ' ')
    conflicts+=("Container de proxy rodando: ${_names}")
  fi

  # 2. Porta 80 ou 443 já ocupada por processo que NÃO é nginx
  local _p
  for _p in 80 443; do
    local _pid _proc
    _pid=$(ss -tlnp 2>/dev/null | awk -v p=":${_p}$" '$4 ~ p {print}' | grep -oP 'pid=\K[0-9]+' | head -1)
    [ -z "$_pid" ] && continue
    _proc=$(ps -p "$_pid" -o comm= 2>/dev/null)
    if [ -n "$_proc" ] && [ "$_proc" != "nginx" ]; then
      conflicts+=("Porta ${_p} em uso por: ${_proc} (pid ${_pid})")
    fi
  done

  if [ ${#conflicts[@]} -eq 0 ]; then
    return 0
  fi

  print_banner
  printf "${RED}  ❌  Conflito detectado — proxy reverso já existe nesta VPS:${NC}\n\n"
  printf "${LINE}\n"
  for c in "${conflicts[@]}"; do
    printf "  ${RED}•${NC}  %s\n" "$c"
  done
  printf "${LINE}\n\n"
  printf "  ${WHITE}Este instalador assume nginx + certbot como proxy SSL.${NC}\n"
  printf "  ${WHITE}Outro proxy (Traefik/Caddy/HAProxy) já presente vai causar:${NC}\n"
  printf "  ${DIM}• apt install nginx falha em systemctl start (porta 80/443 ocupada)${NC}\n"
  printf "  ${DIM}• Containers Docker com labels traefik.* podem ser roteados pelo Traefik existente${NC}\n"
  printf "  ${DIM}• Networks bridge isoladas — Traefik não vê os novos containers${NC}\n"
  printf "  ${DIM}• Conflito de gestão de SSL Let's Encrypt${NC}\n\n"
  printf "  ${YELLOW}Recomendado: VPS dedicada para a instalação Docker do crm.${NC}\n"
  printf "  ${YELLOW}Ou pare/remova o proxy concorrente antes:${NC}\n"
  printf "  ${DIM}  docker ps -q --filter name=traefik | xargs -r docker stop${NC}\n"
  printf "  ${DIM}  docker ps -aq --filter name=traefik | xargs -r docker rm${NC}\n\n"
  printf "  ${YELLOW}Forçar instalação assim mesmo? (NÃO recomendado) (s/N):${NC} "
  read -r _force
  if [ "$_force" = "s" ] || [ "$_force" = "S" ]; then
    printf "  ${YELLOW}⚠️   Prosseguindo a seu próprio risco.${NC}\n\n"
    return 0
  fi
  return 1
}

#######################################
# Instala/recria container Portainer (interface Docker web).
# Idempotente: pula se já está rodando. Senha gerada e salva em
# ${DOCKER_DIR}/portainer_password.txt.
# Arguments:
#   None
#######################################
docker_install_portainer() {
  step_header "🐳" "Instalando Portainer (interface Docker web)" \
    "Acesse em http://<IP-VPS>:9000 — gerencia containers, volumes, logs e imagens."
  printf "\n"

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
    printf "  ${YELLOW}⏭${NC}   Container portainer já está rodando — pulando.\n\n"
    sleep 1
    return 0
  fi

  # Gera senha (pode ser sobrescrita por env PORTAINER_PASSWORD do .env.docker)
  local _ptn_pass
  _ptn_pass=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16)

  start_spinner "Subindo container portainer (porta 9000/9443)..."
  sudo su - root <<EOF
  docker rm -f portainer 2>/dev/null || true
  docker run -d --name portainer \
    -p 9000:9000 -p 9443:9443 \
    --restart=unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    --label com.crm.role=portainer \
    portainer/portainer-ce
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Falha ao criar container Portainer."
    log_error "portainer install" "Falha ao subir container portainer"
    return 1
  fi
  stop_spinner "Portainer criado."

  # Salva senha (uso via env PORTAINER_PASSWORD requer hash bcrypt — preferimos
  # registro inicial via UI no primeiro acesso, dentro de 5 minutos).
  sudo tee "${DOCKER_DIR}/portainer_credentials.txt" >/dev/null <<EOF
# Portainer — primeiro acesso
# Acesse em até 5 minutos após o boot do container, senão precisa restart:
#   docker restart portainer
URL : http://${PUBLIC_IP:-<IP-da-VPS>}:9000  (HTTPS: 9443)
USER: admin (você define no primeiro acesso)
PASS: você define no primeiro acesso

# Senha sugerida (use ou ignore):
PORTAINER_PASS_SUGGESTION=${_ptn_pass}
EOF

  printf "  ${GREEN}✅${NC}  Portainer rodando.\n"
  printf "  ${DIM}Acesse http://<IP-da-VPS>:9000 nos próximos 5 min para registrar admin.${NC}\n"
  printf "  ${DIM}Credenciais sugeridas: ${DOCKER_DIR}/portainer_credentials.txt${NC}\n\n"
  sleep 1
}

#######################################
# Pré-flight checks específicos para Docker:
# - OS apt-based (Debian/Ubuntu — necessário para apt-get install nginx/certbot)
# - RAM + swap >= 2 GiB (build Next no container exige ~2-3 GiB)
# - Disco em / e em DockerRootDir (>= 5 GiB livre — imagens + volumes)
# - Setup de swap automático se RAM baixa
# Reusa system_create_temp_swap de _preflight.sh.
# Arguments:
#   None
#######################################
docker_preflight_checks() {
  step_header "🔍" "Pré-flight checks (Docker)" \
    "Validando OS, RAM, swap e disco antes da instalação Docker."
  printf "\n"

  # 1. OS apt-based — _docker.sh::docker_check_requirements faz apt-get install
  if ! command -v apt-get >/dev/null 2>&1; then
    printf "  ${RED}❌  OS sem apt-get detectado. O instalador assume Debian/Ubuntu.${NC}\n"
    printf "  ${DIM}    Em RHEL/Fedora/Arch a instalação automática de nginx/certbot vai falhar.${NC}\n\n"
    printf "  ${YELLOW}Continuar mesmo assim? (NÃO recomendado) (s/N):${NC} "
    read -r _f
    [ "$_f" = "s" ] || [ "$_f" = "S" ] || return 1
    printf "  ${YELLOW}⚠️   Prosseguindo a seu próprio risco.${NC}\n\n"
  fi

  # 2. RAM + swap >= 2 GiB
  local mem_kb swap_kb total_mb
  mem_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  swap_kb=$(awk '/SwapFree/    {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  total_mb=$(( (mem_kb + swap_kb) / 1024 ))
  if [ "$total_mb" -lt 2048 ]; then
    printf "  ${YELLOW}⚠️   Memória disponível (${total_mb} MiB) abaixo de 2 GiB.${NC}\n"
    printf "  ${DIM}    Build Next dentro do container precisa de ~2-3 GiB.${NC}\n"
    if command -v system_create_temp_swap >/dev/null 2>&1; then
      system_create_temp_swap || true
    fi
    # Re-checar após criar swap
    swap_kb=$(awk '/SwapFree/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    total_mb=$(( (mem_kb + swap_kb) / 1024 ))
    if [ "$total_mb" -lt 2048 ]; then
      printf "  ${YELLOW}Memória ainda abaixo de 2 GiB. Continuar mesmo assim? (s/N):${NC} "
      read -r _f
      [ "$_f" = "s" ] || [ "$_f" = "S" ] || return 1
    fi
  fi

  # 3. Disco em / e em DockerRootDir (>= 5 GiB)
  local docker_root
  docker_root=$(docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
  local checked=""
  for path in / "$docker_root"; do
    [ -d "$path" ] || continue
    case " $checked " in *" $path "*) continue;; esac
    checked="$checked $path"
    local free_mb
    free_mb=$(df -mP "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$free_mb" ] && [ "$free_mb" -lt 5120 ]; then
      printf "  ${RED}❌  Disco em ${path}: ${free_mb} MiB livres (< 5 GiB recomendado).${NC}\n"
      printf "  ${DIM}    Imagens Docker (postgres, alpine, ubuntu) + builds + volumes precisam espaço.${NC}\n"
      printf "  ${DIM}    Use [16]→[3] para limpar pastas legacy/failed antigas.${NC}\n\n"
      printf "  ${YELLOW}Continuar mesmo assim? (s/N):${NC} "
      read -r _f
      [ "$_f" = "s" ] || [ "$_f" = "S" ] || return 1
    fi
  done

  printf "  ${GREEN}✅${NC}  Pré-flight Docker OK (${total_mb} MiB RAM+swap, disco OK).\n\n"
  sleep 1
  return 0
}

install_docker_crm() {
  init_error_log "docker_install"
  warn_snapshot_required "instalação Docker (beta)" || return 1
  docker_warn_beta
  docker_check_no_pm2_install || return 1
  docker_check_no_proxy_conflict || return 1
  docker_preflight_checks || return 1
  docker_check_requirements || return 1
  docker_select_ports || return 1
  docker_ensure_extracted || return 1
  # Ordem: 1) email  2) frontend URL  3) backend URL
  get_deploy_email
  docker_get_domains
  docker_prepare_env
  docker_copy_compose
  docker_compose_up
  docker_install_portainer
  docker_nginx_setup
  docker_certbot_setup
  docker_install_success
}

#######################################
# Detecta onde o Docker foi instalado e define DOCKER_DIR
# Procura .env.docker em /home/deploycrm/crm e /root/crm
# Arguments:
#   None
#######################################
docker_detect_dir() {
  if [ -f "/home/deploycrm/crm/.env.docker" ]; then
    DOCKER_DIR="/home/deploycrm/crm"
  elif [ -f "/root/crm/.env.docker" ]; then
    DOCKER_DIR="/root/crm"
  else
    printf "  ${RED}❌  Instalação Docker não encontrada.${NC}\n"
    printf "  ${DIM}Nenhum .env.docker em /home/deploycrm/crm ou /root/crm${NC}\n\n"
    return 1
  fi
  printf "  ${GREEN}✅${NC}  Instalação Docker encontrada em: ${DOCKER_DIR}\n\n"
  sleep 1
}

#######################################
# Para os containers Docker antes do update
# Arguments:
#   None
#######################################
docker_stop_containers() {
  step_header "⏹️ " "Parando containers Docker" \
    "Executa docker compose stop para permitir a atualização dos arquivos."
  printf "\n"

  start_spinner "Parando containers em ${DOCKER_DIR}..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  docker compose --env-file .env.docker stop
EOF
  stop_spinner "Containers parados."
  sleep 1
}

#######################################
# Remove source antigo e extrai update.zip
# Mantém .env.docker, docker-compose.yml e volumes intactos
# Arguments:
#   None
#######################################
docker_update_extract() {
  step_header "📦" "Atualizando arquivos fonte" \
    "Remove source antigo e extrai update.zip em ${DOCKER_DIR}."
  printf "  ${DIM}.env.docker e volumes Docker são preservados.${NC}\n\n"

  start_spinner "Renomeando backend/ e frontend/ antigos para .legacy.<ts>/..."
  local _ts
  _ts=$(date +%Y%m%d-%H%M%S)
  # Variável global usada por docker_update_rollback em caso de falha
  DOCKER_UPDATE_LEGACY_TS="$_ts"
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  [ -d backend ]    && mv backend  "backend.legacy.${_ts}"  || true
  [ -d frontend ]   && mv frontend "frontend.legacy.${_ts}" || true
  # Remove pasta paralela legada se existir (instalações antigas)
  [ -d frontNovo ]  && mv frontNovo "frontNovo.legacy.${_ts}" || true
EOF
  stop_spinner "Source antigo preservado em .legacy.${_ts}/."

  # Extrai o zip em /tmp e move backend/ + frontend/ para o DOCKER_DIR.
  # IMPORTANTE: extrai sem pattern para garantir que dotfiles (.sequelizerc,
  # .wwebjs_auth, .wwebjs_cache) e arquivos top-level (docker-entrypoint.sh,
  # Dockerfile) também sejam pegos. Patterns "crm/backend/*" no unzip
  # podem ignorar dotfiles dependendo da versão.
  start_spinner "Extraindo update.zip..."
  local _tmp="/tmp/crm_docker_update_$$"
  sudo su - root <<EOF
  mkdir -p "${_tmp}"
  unzip -qo "${PROJECT_ROOT}/update.zip" -d "${_tmp}" </dev/null
  if [ -d "${_tmp}/crm/backend" ]; then
    mv "${_tmp}/crm/backend" "${DOCKER_DIR}/backend"
  fi
  if [ -d "${_tmp}/crm/frontend" ]; then
    mv "${_tmp}/crm/frontend" "${DOCKER_DIR}/frontend"
  fi
  rm -rf "${_tmp}"
EOF
  if [ ! -d "${DOCKER_DIR}/backend" ] || [ ! -d "${DOCKER_DIR}/frontend" ]; then
    stop_spinner_error "Falha ao extrair update.zip — backend/ ou frontend/ ausentes."
    log_error "unzip update docker" "Falha ao extrair update.zip em ${DOCKER_DIR}"
    return 1
  fi
  stop_spinner "Arquivos atualizados em ${DOCKER_DIR}."
  sleep 1
}

#######################################
# Rebuilda e reinicia os containers com o novo código
# Arguments:
#   None
#######################################
docker_compose_rebuild() {
  step_header "🔨" "Rebuilding e reiniciando containers" \
    "docker compose up --build com o novo código — pode levar vários minutos."
  printf "  ${DIM}As imagens serão reconstruídas; volumes de dados são preservados.${NC}\n\n"

  start_spinner "Executando docker compose up --build (aguarde)..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  docker compose --env-file .env.docker up -d --build postgres backend frontend
EOF
  local _rc=$?
  if [ $_rc -ne 0 ]; then
    stop_spinner_error "Falha ao rebuildar containers. Verifique: docker compose logs"
    log_error "docker compose rebuild" "Falha ao rebuildar em ${DOCKER_DIR}"
    sleep 2
    return 1
  fi
  stop_spinner "Containers rebuilados e reiniciados."
  sleep 2
  return 0
}

#######################################
# Rollback do update Docker — restaura source antigo (.legacy.<ts>/) e
# rebuilda containers. Move source novo (incompleto) para .failed.<ts>/.
# Volumes (postgres_data, sessions, uploads) preservados.
# Arguments:
#   $1 - timestamp do backup legacy (DOCKER_UPDATE_LEGACY_TS)
#######################################
docker_update_rollback() {
  local _ts="${1:-${DOCKER_UPDATE_LEGACY_TS:-}}"

  print_banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════${NC}\n"
  printf "${YELLOW}  ↩️   ROLLBACK AUTOMÁTICO — restaurando source anterior${NC}\n"
  printf "${YELLOW}══════════════════════════════════════════════════════════════${NC}\n\n"

  if [ -z "$_ts" ]; then
    printf "${RED}  ❌  Rollback impossível — timestamp legacy não definido.${NC}\n"
    printf "${DIM}      Restaure manualmente do snapshot da VPS.${NC}\n\n"
    return 1
  fi

  if [ ! -d "${DOCKER_DIR}/backend.legacy.${_ts}" ] && [ ! -d "${DOCKER_DIR}/frontend.legacy.${_ts}" ]; then
    printf "${RED}  ❌  Backups .legacy.${_ts}/ não encontrados em ${DOCKER_DIR}.${NC}\n"
    printf "${DIM}      Restaure manualmente do snapshot da VPS.${NC}\n\n"
    return 1
  fi

  # 1. Para containers (podem estar parados, em loop crash, ou parcialmente up)
  start_spinner "Parando containers..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  docker compose --env-file .env.docker stop 2>/dev/null || true
EOF
  stop_spinner "Containers parados."

  # 2. Move source novo (incompleto) para .failed.<ts>/ e restaura legacy
  start_spinner "Movendo source novo para .failed.${_ts}/ e restaurando legacy..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  [ -d backend ]  && mv backend  "backend.failed.${_ts}"  2>/dev/null || true
  [ -d frontend ] && mv frontend "frontend.failed.${_ts}" 2>/dev/null || true
  [ -d "backend.legacy.${_ts}"  ] && mv "backend.legacy.${_ts}"  backend
  [ -d "frontend.legacy.${_ts}" ] && mv "frontend.legacy.${_ts}" frontend
EOF
  stop_spinner "Source antigo restaurado em backend/ e frontend/."

  # 3. Restaurar docker-compose.yml antigo se houver backup
  local _compose_bak
  _compose_bak=$(ls -1 "${DOCKER_DIR}"/docker-compose.yml.bak.* 2>/dev/null | sort | tail -1)
  if [ -n "$_compose_bak" ]; then
    sudo cp "$_compose_bak" "${DOCKER_DIR}/docker-compose.yml"
    printf "  ${DIM}docker-compose.yml restaurado de: $(basename "$_compose_bak")${NC}\n\n"
  fi

  # 4. Rebuild com source antigo
  start_spinner "Rebuilding containers com source anterior..."
  sudo su - root <<EOF
  cd "${DOCKER_DIR}"
  docker compose --env-file .env.docker up -d --build postgres backend frontend
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Rebuild com source antigo FALHOU — VPS em estado degradado."
    log_error "rollback rebuild" "Failed to rebuild with old source"
    printf "  ${RED}❌  Rollback automático não conseguiu reerguer os containers.${NC}\n"
    printf "  ${YELLOW}    Restaure do snapshot da VPS ou diagnostique manualmente:${NC}\n"
    printf "  ${DIM}      cd ${DOCKER_DIR}${NC}\n"
    printf "  ${DIM}      ls -la backend* frontend*${NC}\n"
    printf "  ${DIM}      docker compose --env-file .env.docker logs${NC}\n\n"
    return 1
  fi
  stop_spinner "Containers reerguidos com source anterior."

  printf "\n  ${GREEN}✅  Rollback concluído. VPS voltou ao estado pré-update.${NC}\n"
  printf "  ${DIM}    Source novo (incompleto) preservado em:${NC}\n"
  printf "  ${DIM}      ${DOCKER_DIR}/backend.failed.${_ts}/${NC}\n"
  printf "  ${DIM}      ${DOCKER_DIR}/frontend.failed.${_ts}/${NC}\n"
  printf "  ${DIM}    Investigue o conteúdo do update.zip antes de tentar de novo.${NC}\n\n"
  return 0
}

#######################################
# Mensagem de sucesso do update Docker
# Arguments:
#   None
#######################################
docker_update_success() {
  print_banner
  printf "${GREEN}  ✅  Update Docker concluído!${NC}\n\n"
  printf "${LINE}\n"
  printf "${WHITE}  📊 Containers atualizados:${NC}\n\n"

  sudo su - root <<'EOF'
  cd "${DOCKER_DIR}" 2>/dev/null || true
  docker compose --env-file .env.docker ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
EOF

  printf "\n"
  printf "  ${DIM}Logs: cd ${DOCKER_DIR} && docker compose --env-file .env.docker logs -f${NC}\n\n"
  printf "  ${YELLOW}⚠️   Frontend (Next.js): NEXT_PUBLIC_* são baked-in no build.${NC}\n"
  printf "  ${DIM}Se a URL do backend mudou, edite .env.docker e rebuilde:${NC}\n"
  printf "  ${DIM}  cd ${DOCKER_DIR} && docker compose --env-file .env.docker up -d --build frontend${NC}\n\n"
  printf "  ${GREEN}FAQ: https://hotmart.com/es/club/whatitan${NC}\n"
  printf "  ${GREEN}Suporte: https://wa.me/50489520312/${NC}\n"
  printf "${LINE}\n\n"

  show_error_summary
  sleep 2
}

#######################################
# Fluxo completo de update Docker
# Arguments:
#   None
#######################################
update_docker_crm() {
  init_error_log "docker_update"
  warn_snapshot_required "atualização Docker (beta)" || return 1
  docker_warn_beta
  docker_preflight_checks || return 1
  docker_check_requirements || return 1
  docker_detect_dir || return 1
  # No update as portas já estão no .env.docker — apenas lê para exibir no success
  docker_backend_port=$(grep "^BACKEND_PORT=" "${DOCKER_DIR}/.env.docker" 2>/dev/null | cut -d= -f2 || echo "7563")
  docker_frontend_port=$(grep "^FRONTEND_PORT=" "${DOCKER_DIR}/.env.docker" 2>/dev/null | cut -d= -f2 || echo "7564")
  docker_stop_containers
  docker_update_extract || { docker_update_rollback; return 1; }
  docker_copy_compose
  if ! docker_compose_rebuild; then
    docker_update_rollback
    return 1
  fi
  docker_update_success
}

#######################################
# Limpa pastas legacy/failed deixadas pelo update Docker.
# Princípio: pastas listadas com tamanho, usuário confirma cada uma, e elas
# vão para /tmp/crm_trash_<epoch>/ (não deletadas direto). Cleanup definitivo
# fica a cargo do usuário com `rm -rf /tmp/crm_trash_*` quando confiante.
# Sempre preserva o backup MAIS RECENTE de cada categoria (último rollback).
#######################################
docker_cleanup_legacy() {
  step_header "🗑️ " "Limpar pastas legacy/failed do Docker" \
    "Move backend/frontend.legacy.* e .failed.* para /tmp/crm_trash_<epoch>/."
  printf "  ${DIM}Princípio: nada é apagado direto. Cleanup definitivo é manual.${NC}\n"
  printf "  ${DIM}O backup mais recente de cada categoria fica preservado para rollback.${NC}\n\n"

  if ! docker_detect_dir; then
    return 1
  fi

  cd "$DOCKER_DIR" 2>/dev/null || {
    printf "${RED}  ❌  Não foi possível entrar em ${DOCKER_DIR}.${NC}\n\n"
    return 1
  }

  # Coleta todas as pastas candidatas
  local -a all_dirs=()
  while IFS= read -r d; do
    [ -d "$d" ] && all_dirs+=("$d")
  done < <(ls -1d backend.legacy.* frontend.legacy.* frontNovo.legacy.* \
                  backend.failed.* frontend.failed.* 2>/dev/null)

  if [ ${#all_dirs[@]} -eq 0 ]; then
    printf "  ${GREEN}✅${NC}  Nenhuma pasta legacy/failed encontrada em ${DOCKER_DIR}/.\n\n"
    sleep 1
    return 0
  fi

  # Determina o backup MAIS RECENTE de cada categoria (não pode apagar)
  local most_recent_backend_legacy most_recent_frontend_legacy
  most_recent_backend_legacy=$(ls -1dt backend.legacy.* 2>/dev/null | head -1)
  most_recent_frontend_legacy=$(ls -1dt frontend.legacy.* 2>/dev/null | head -1)

  # Mostra lista com tamanhos
  printf "${WHITE}  Pastas encontradas em ${DOCKER_DIR}/:${NC}\n\n"
  local total_kb=0
  local -a removable=()
  for d in "${all_dirs[@]}"; do
    local size_kb size_h
    size_kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    size_h=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
    total_kb=$((total_kb + size_kb))
    if [ "$d" = "$most_recent_backend_legacy" ] || [ "$d" = "$most_recent_frontend_legacy" ]; then
      printf "  ${GREEN}🔒${NC}  %-50s  %s  ${DIM}← preservado (último rollback disponível)${NC}\n" "$d" "$size_h"
    else
      printf "  ${YELLOW}🗑${NC}   %-50s  %s\n" "$d" "$size_h"
      removable+=("$d")
    fi
  done
  printf "\n"
  printf "  ${WHITE}Total ocupado:${NC} $((total_kb / 1024)) MiB\n"
  printf "  ${WHITE}A liberar:${NC} ${#removable[@]} pasta(s)\n\n"

  if [ ${#removable[@]} -eq 0 ]; then
    printf "  ${DIM}Apenas o backup mais recente está presente — nada a limpar.${NC}\n\n"
    sleep 1
    return 0
  fi

  printf "${YELLOW}  Mover essas ${#removable[@]} pasta(s) para /tmp/crm_trash_$(date +%s)/? (s/N):${NC} "
  read -r _conf
  if [ "$_conf" != "s" ] && [ "$_conf" != "S" ]; then
    printf "${DIM}  Cancelado.${NC}\n\n"
    return 0
  fi

  local trash="/tmp/crm_trash_$(date +%s)"
  sudo mkdir -p "$trash"
  local moved=0
  for d in "${removable[@]}"; do
    if sudo mv "${DOCKER_DIR}/${d}" "$trash/" 2>/dev/null; then
      moved=$((moved + 1))
    fi
  done

  printf "\n  ${GREEN}✅${NC}  ${moved} pasta(s) movida(s) para ${trash}/.\n"
  printf "  ${DIM}    Para apagar definitivamente quando confiante:${NC}\n"
  printf "  ${DIM}      sudo rm -rf ${trash}${NC}\n\n"
  sleep 1
}

#######################################
# Submenu: Instalar / Atualizar / Limpar Docker
# Arguments:
#   None
#######################################
docker_install_or_update() {
  print_banner
  printf "${WHITE}  💻 Docker (Beta) — crm em containers${NC}\n\n"
  printf "${LINE}\n"
  printf "  ${GREEN}[1]${NC}  Instalar Docker\n"
  printf "       ${DIM}↳ Extrai zip, configura .env.docker, nginx, SSL e sobe containers${NC}\n\n"
  printf "  ${YELLOW}[2]${NC}  Atualizar Docker\n"
  printf "       ${DIM}↳ Para containers, extrai update.zip, rebuilda imagens e reinicia${NC}\n\n"
  printf "  ${CYAN_LIGHT}[3]${NC}  Limpar pastas legacy/failed\n"
  printf "       ${DIM}↳ Move backend/frontend.legacy.* e .failed.* para /tmp/ (libera disco)${NC}\n"
  printf "${LINE}\n"
  printf "  ${DIM}[0]${NC}  Voltar\n\n"
  read -p "  Opção > " _dk_option

  case "${_dk_option}" in
    1)
      install_docker_crm
      ;;
    2)
      update_docker_crm
      ;;
    3)
      docker_cleanup_legacy
      ;;
    0)
      inquiry_options
      ;;
    *)
      docker_install_or_update
      ;;
  esac
}

#######################################
# Detecta se a VPS tem instalacao Docker (full compose) do crm.
# Usado pelo menu pra mostrar/ocultar a opcao de "Aplicar otimizacoes Docker".
# Returns:
#   0 se detectado, 1 caso contrario.
#######################################
docker_install_detected() {
  for candidate in /root/crm /home/deploycrm/crm; do
    if [ -f "$candidate/.env.docker" ]; then
      return 0
    fi
  done
  return 1
}

# Resolve o DOCKER_DIR (root ou deploycrm) e ecoa pra stdout. Vazio se nao acha.
_docker_resolve_dir() {
  for candidate in /root/crm /home/deploycrm/crm; do
    if [ -f "$candidate/.env.docker" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Localiza o docker-compose.yml NOVO (de instalador atualizado).
# Ordem: /root/crm_passaporte_shell_hotfix > /root/crm_passaporte_shell > PROJECT_ROOT
_docker_resolve_new_compose() {
  local arg="${1:-}"
  if [ -n "$arg" ] && [ -f "$arg" ]; then
    echo "$arg"; return 0
  fi
  for candidate in \
      /root/crm_passaporte_shell_hotfix/docker-compose.yml \
      /root/crm_passaporte_shell/docker-compose.yml \
      "${PROJECT_ROOT:-}/docker-compose.yml"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"; return 0
    fi
  done
  return 1
}

#######################################
# Aplica novo docker-compose.yml em VPS Docker (full compose) preservando
# volumes named (postgres_data, sessions, uploads, public).
# Refator de extra/apply-docker-optim.sh — agora integra com snapshot guard,
# log_error e step_header compartilhados.
# Arguments:
#   $1 - (opcional) caminho do novo docker-compose.yml
#######################################
docker_apply_optim() {
  step_header "🐳" "Aplicar otimizacoes Docker (compose)" \
    "Substitui docker-compose.yml e recria containers preservando volumes named."

  local DOCKER_DIR NEW_COMPOSE CUR_COMPOSE
  if ! DOCKER_DIR=$(_docker_resolve_dir); then
    printf "  ${RED}❌  Instalacao Docker nao encontrada.${NC}\n"
    printf "  ${DIM}    Esperado: /root/crm/.env.docker ou /home/deploycrm/crm/.env.docker${NC}\n\n"
    return 1
  fi
  if ! NEW_COMPOSE=$(_docker_resolve_new_compose "${1:-}"); then
    printf "  ${RED}❌  Novo docker-compose.yml nao encontrado.${NC}\n"
    printf "  ${DIM}    Procurei em /root/crm_passaporte_shell{,_hotfix}/docker-compose.yml${NC}\n\n"
    return 1
  fi
  CUR_COMPOSE="$DOCKER_DIR/docker-compose.yml"
  if [ ! -f "$CUR_COMPOSE" ]; then
    printf "  ${RED}❌  Compose atual nao existe em ${CUR_COMPOSE}.${NC}\n\n"
    return 1
  fi

  printf "  ${CYAN}DOCKER_DIR${NC}    = %s\n" "$DOCKER_DIR"
  printf "  ${CYAN}Compose atual${NC} = %s\n" "$CUR_COMPOSE"
  printf "  ${CYAN}Compose novo${NC}  = %s\n\n" "$NEW_COMPOSE"

  cd "$DOCKER_DIR" || return 1

  printf "  ${CYAN}Containers em execucao:${NC}\n"
  if ! docker compose --env-file .env.docker ps 2>/dev/null; then
    printf "  ${RED}❌  docker compose ps falhou — Docker nao esta rodando ou .env.docker invalido.${NC}\n\n"
    return 1
  fi
  printf "\n"

  # Pre-checks de capacidade
  local PG_CONN
  PG_CONN=$(docker exec crm-postgres psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ' || echo "?")
  printf "  ${CYAN}Conexoes PostgreSQL ativas:${NC} ${PG_CONN}\n"
  if [[ "$PG_CONN" =~ ^[0-9]+$ ]] && [ "$PG_CONN" -gt 80 ]; then
    printf "  ${YELLOW}⚠️   ${PG_CONN} > 80 — novo max_connections=100 pode ficar apertado.${NC}\n"
  fi

  local MEM_AVAIL_MB
  MEM_AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
  printf "  ${CYAN}RAM disponivel:${NC} ${MEM_AVAIL_MB} MiB\n"
  if [ "$MEM_AVAIL_MB" -lt 1500 ]; then
    printf "  ${YELLOW}⚠️   RAM disponivel < 1.5 GB — shared_buffers=512MB pode pressionar.${NC}\n"
  fi

  # Diff
  printf "\n  ${CYAN}Diff entre compose atual e novo (head -120):${NC}\n"
  diff "$CUR_COMPOSE" "$NEW_COMPOSE" 2>/dev/null | head -120 || true
  printf "\n"

  # Snapshot guard obrigatorio
  if ! require_snapshot_confirmation \
    "Aplicar novo docker-compose.yml + recreate containers (~30s downtime)" \
    "Containers serao recriados; volumes named ficam preservados, mas erros de config podem impedir o stack de subir."; then
    return 1
  fi

  # Backup
  step_header "💾" "Backup do compose e env atuais"
  local TS BAK_COMPOSE BAK_ENV
  TS=$(date +%Y%m%d-%H%M%S)
  BAK_COMPOSE="$CUR_COMPOSE.bak.$TS"
  BAK_ENV="$DOCKER_DIR/.env.docker.bak.$TS"
  cp "$CUR_COMPOSE"            "$BAK_COMPOSE"
  cp "$DOCKER_DIR/.env.docker" "$BAK_ENV"
  printf "  ${GREEN}✅${NC}  docker-compose.yml -> %s\n" "$BAK_COMPOSE"
  printf "  ${GREEN}✅${NC}  .env.docker        -> %s\n\n" "$BAK_ENV"

  # Aplica + recreate
  step_header "🔁" "Aplicando novo compose + recreate"
  cp "$NEW_COMPOSE" "$CUR_COMPOSE"
  printf "  ${GREEN}✅${NC}  Copiado: %s -> %s\n\n" "$NEW_COMPOSE" "$CUR_COMPOSE"
  if ! docker compose --env-file .env.docker up -d --force-recreate; then
    printf "\n  ${RED}❌  docker compose up falhou. Restaurando backup...${NC}\n"
    cp "$BAK_COMPOSE" "$CUR_COMPOSE"
    docker compose --env-file .env.docker up -d --force-recreate
    log_error "docker_apply_optim" "compose up falhou apos novo docker-compose.yml — backup restaurado de ${BAK_COMPOSE}"
    return 1
  fi

  # Validacao
  step_header "✅" "Validacao"
  printf "  ${DIM}Aguardando healthchecks (15s)...${NC}\n"
  sleep 15
  printf "\n  ${CYAN}Containers:${NC}\n"
  docker compose --env-file .env.docker ps
  printf "\n  ${CYAN}Healthchecks:${NC}\n"
  local c status
  for c in crm-postgres crm-backend crm-frontend; do
    status=$(docker inspect "$c" --format '{{.State.Health.Status}}' 2>/dev/null || echo "no-healthcheck")
    case "$status" in
      healthy)        printf "  ${GREEN}✅${NC}  %-20s %s\n" "$c" "$status" ;;
      starting)       printf "  ${YELLOW}⏳${NC}  %-20s %s\n" "$c" "$status" ;;
      no-healthcheck) printf "  ${DIM}⏭${NC}   %-20s %s\n" "$c" "$status" ;;
      *)              printf "  ${RED}❌${NC}  %-20s %s\n" "$c" "$status" ;;
    esac
  done
  printf "\n  ${CYAN}Postgres parameters:${NC}\n"
  local param v
  for param in max_connections shared_buffers effective_cache_size statement_timeout idle_in_transaction_session_timeout autovacuum_vacuum_scale_factor log_min_duration_statement; do
    v=$(docker exec crm-postgres psql -U postgres -t -c "SHOW $param;" 2>/dev/null | tr -d ' ' || echo "?")
    printf "  %-40s = %s\n" "$param" "$v"
  done

  # Sumario
  step_header "📊" "Resumo"
  printf "  ${GREEN}Otimizacoes aplicadas em ${DOCKER_DIR}.${NC}\n\n"
  printf "  ${CYAN}Backups:${NC}\n"
  printf "    %s\n"   "$BAK_COMPOSE"
  printf "    %s\n\n" "$BAK_ENV"
  printf "  ${CYAN}Rollback (se algo der errado):${NC}\n"
  printf "    ${DIM}sudo cp %s %s${NC}\n" "$BAK_COMPOSE" "$CUR_COMPOSE"
  printf "    ${DIM}cd %s && docker compose --env-file .env.docker up -d --force-recreate${NC}\n\n" "$DOCKER_DIR"
  printf "  ${CYAN}Logs do backend:${NC}\n"
  printf "    ${DIM}docker logs crm-backend --tail 100 -f${NC}\n\n"
  printf "${GREEN}✅  Concluido.${NC}\n\n"
  return 0
}
