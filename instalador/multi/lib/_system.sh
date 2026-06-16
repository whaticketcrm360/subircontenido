#!/bin/bash
# 
# system management

#######################################
# creates user
# Arguments:
#   None
#######################################
system_create_user() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos criar o usuário para deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # Tenta criar o usuário e verifica se foi bem-sucedido
  if ! sudo su - root <<EOF
  useradd -m -p $(openssl passwd $deploy_password) -s /bin/bash -G sudo deploycrm
  usermod -aG sudo deploycrm
EOF
  then
    print_banner
    printf "${RED} ❌ Erro ao criar o usuário deploycrm!${NC}\n\n"
    printf "${WHITE} Possíveis soluções:${NC}\n"
    printf "${YELLOW} 1. Execute manualmente: ${NC}sudo adduser deploycrm\n"
    printf "${YELLOW} 2. Ou reinicie o processo de instalação${NC}\n\n"
    printf "${WHITE} Pressione qualquer tecla para sair...${NC}\n"
    read -n 1 -s
    exit 1
  fi

  sleep 2
}

#######################################
# creates folder
# Arguments:
#   None
#######################################
system_create_folder() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos criar a nova pasta...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  mkdir ${folder_name}
EOF

  sleep 2
}

#######################################
# move folder
# Arguments:
#   None
#######################################
system_mv_folder() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos mover a nova pasta...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}/../crm.zip" /home/deploycrm/${folder_name}/
EOF

  sleep 2
}

#######################################
# set timezone
# Arguments:
#   None
#######################################
system_set_timezone() {
  print_banner
  printf "${WHITE} 💻 Setando timezone...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  timedatectl set-timezone America/Tegucigalpa
EOF

  sleep 2
}


#######################################
# unzip crm
# Arguments:
#   None
#######################################
system_unzip_crm() {
  print_banner
  printf "${WHITE} 💻 Fazendo unzip crm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  unzip /home/deploycrm/${folder_name}/crm.zip -d /home/deploycrm/${folder_name}
EOF

  sleep 2
}

#######################################
# updates system
# Arguments:
#   None
#######################################
system_update() {
  print_banner
  printf "${WHITE} 💻 Vamos atualizar o sistema...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  export NEEDRESTART_SUSPEND=1
  apt-get -y update
  apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade
EOF

  sleep 2
}

#######################################
# verifica se ha reboot pendente apos full-upgrade
# Se houver, pede para o usuario reiniciar antes de seguir com a instalacao
# Arguments:
#   None
#######################################
system_reboot_check() {
  print_banner
  printf "${WHITE} 🔁 Verificando se reinicio e necessario...${GRAY_LIGHT}"
  printf "\n\n"

  if [ ! -f /var/run/reboot-required ]; then
    printf "${GREEN} ✅ Nenhum reinicio pendente. Seguindo com a instalacao.${NC}\n\n"
    sleep 1
    return 0
  fi

  printf "${YELLOW} ⚠️  Reinicio pendente detectado apos o full-upgrade.${NC}\n\n"
  if [ -f /var/run/reboot-required.pkgs ]; then
    printf "${WHITE} Pacotes que pediram reboot:${NC}\n"
    sed 's/^/   • /' /var/run/reboot-required.pkgs
    printf "\n"
  fi
  printf "${WHITE} Continuar sem reiniciar pode quebrar Docker/networking/libc.${NC}\n"
  printf "${WHITE} Apos o boot, rode novamente o instalador.${NC}\n\n"
  read -p " Reiniciar agora? (S/n) > " reboot_confirm

  if [ "$reboot_confirm" = "n" ] || [ "$reboot_confirm" = "N" ]; then
    printf "\n${RED} ❌ Instalacao abortada. Reinicie manualmente (sudo reboot) e rode novamente.${NC}\n\n"
    exit 1
  fi

  printf "\n${WHITE} Reiniciando em 3 segundos...${NC}\n\n"
  sleep 3
  sudo reboot
  exit 0
}

#######################################
# installs node
# Arguments:
#   None
#######################################
system_node_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nodejs...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E bash -
  apt-get install -y nodejs
EOF

  sleep 2
}

#######################################
# installs docker
# Arguments:
#   None
#######################################
system_docker_install() {
  print_banner
  printf "${WHITE} 💻 Instalando docker...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt install -y apt-transport-https \
                 ca-certificates curl \
                 software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
  apt install -y docker-ce
EOF

  sleep 2
}

#######################################
# Ask for file location containing
# multiple URL for streaming.
# Globals:
#   WHITE
#   GRAY_LIGHT
#   BATCH_DIR
#   PROJECT_ROOT
# Arguments:
#   None
#######################################
system_puppeteer_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando puppeteer dependencies...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt-get install -y libxshmfence-dev \
                      libgbm-dev \
                      wget \
                      unzip \
                      fontconfig \
                      locales \
                      gconf-service \
                      libasound2 \
                      libatk1.0-0 \
                      libc6 \
                      libcairo2 \
                      libcups2 \
                      libdbus-1-3 \
                      libexpat1 \
                      libfontconfig1 \
                      libgcc1 \
                      libgconf-2-4 \
                      libgdk-pixbuf2.0-0 \
                      libglib2.0-0 \
                      libgtk-3-0 \
                      libnspr4 \
                      libpango-1.0-0 \
                      libpangocairo-1.0-0 \
                      libstdc++6 \
                      libx11-6 \
                      libx11-xcb1 \
                      libxcb1 \
                      libxcomposite1 \
                      libxcursor1 \
                      libxdamage1 \
                      libxext6 \
                      libxfixes3 \
                      libxi6 \
                      libxrandr2 \
                      libxrender1 \
                      libxss1 \
                      libxtst6 \
                      ca-certificates \
                      fonts-liberation \
                      libappindicator1 \
                      libnss3 \
                      lsb-release \
                      xdg-utils \
                      ffmpeg
EOF

  sleep 2
}

#######################################
# install libs
# Arguments:
#   None
#######################################
system_libs() {
  print_banner
  printf "${WHITE} 💻 Vamos atualizar o sistema...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt-add-repository universe
  apt install -y python2-minimal
  apt-get install -y build-essential
  apt -y update && apt -y full-upgrade
EOF

  sleep 2
}

#######################################
# installs pm2
# Arguments:
#   None
#######################################
system_pm2_install() {
  print_banner
  printf "${WHITE} 💻 Instalando pm2...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  npm install -g pm2
  pm2 startup ubuntu -u deploycrm
  env PATH=\$PATH:/usr/bin pm2 startup ubuntu -u deploycrm --hp /home/deploycrm
EOF

  sleep 2
}

#######################################
# Remove entradas PM2 cujo script aponta para dentro do diretorio do
# instalador. Defesa para o caso de alguem ter rodado, em algum momento,
# `pm2 start <installer>` por engano — o que faz o instalador entrar em
# loop infinito sob PM2 (autorestart=true) e poluir a lista com zumbis.
# Depende de PROJECT_ROOT (definido no entry script).
# Arguments:
#   None
#######################################
pm2_cleanup_installer_zombies() {
  if ! command -v pm2 >/dev/null 2>&1; then
    return 0
  fi
  local installer_dir="${PROJECT_ROOT:-}"
  if [ -z "$installer_dir" ] || [ ! -d "$installer_dir" ]; then
    return 0
  fi
  if ! id deploycrm >/dev/null 2>&1; then
    return 0
  fi

  local zombies
  zombies=$(sudo su - deploycrm -c "pm2 jlist" 2>/dev/null \
    | INSTALLER_DIR="$installer_dir" python3 -c "
import sys, json, os
try:
    target = os.path.realpath(os.environ.get('INSTALLER_DIR', ''))
    if not target:
        sys.exit(0)
    procs = json.loads(sys.stdin.read() or '[]')
    sep = os.sep
    for p in procs:
        pe = p.get('pm2_env') or {}
        script = pe.get('pm_exec_path') or pe.get('script') or ''
        cwd = pe.get('pm_cwd') or ''
        try:
            script_real = os.path.realpath(script) if script else ''
        except Exception:
            script_real = script
        if (script_real and (script_real == target or script_real.startswith(target + sep))) \
           or (cwd and (cwd == target or cwd.startswith(target + sep))):
            pid_ = p.get('pm_id')
            if pid_ is not None:
                print(pid_)
except Exception:
    pass
" 2>/dev/null)

  if [ -z "$zombies" ]; then
    return 0
  fi

  local id removed=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if sudo su - deploycrm -c "pm2 delete $id" >/dev/null 2>&1; then
      removed=$(( removed + 1 ))
      if command -v log_error >/dev/null 2>&1; then
        log_error "pm2 cleanup" "Entrada PM2 zumbi removida (ID=$id) — apontava para o diretorio do instalador"
      fi
    fi
  done <<< "$zombies"

  if [ "$removed" -gt 0 ]; then
    sudo su - deploycrm -c "pm2 save" >/dev/null 2>&1 || true
    printf "  ${YELLOW:-}⚠️   Removidas ${removed} entrada(s) PM2 zumbi(s) do instalador.${NC:-}\n"
  fi
}

#######################################
# installs snapd
# Arguments:
#   None
#######################################
system_snapd_install() {
  print_banner
  printf "${WHITE} 💻 Instalando snapd...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt install -y snapd
  snap install core
  snap refresh core
EOF

  sleep 2
}

#######################################
# installs certbot
# Arguments:
#   None
#######################################
system_certbot_install() {
  print_banner
  printf "${WHITE} 💻 Instalando certbot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt-get remove certbot
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
EOF

  sleep 2
}

#######################################
# installs nginx
# Arguments:
#   None
#######################################
system_nginx_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt install -y nginx
  rm /etc/nginx/sites-enabled/default
EOF

  sleep 2
}

#######################################
# restarts nginx
# Arguments:
#   None
#######################################
system_nginx_restart() {
  print_banner
  printf "${WHITE} 💻 reiniciando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  service nginx restart
EOF

  sleep 2
}

#######################################
# setup for nginx.conf
# Arguments:
#   None
#######################################
system_nginx_conf() {
  print_banner
  printf "${WHITE} 💻 configurando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

sudo su - root << EOF

cat > /etc/nginx/conf.d/crmio.conf << 'END'
client_max_body_size 20M;
proxy_connect_timeout 60;
proxy_read_timeout 86400;
proxy_send_timeout 86400;
END

if [ -f /etc/nginx/nginx.conf ]; then
  sed -i 's/worker_connections 768/worker_connections 2048/' /etc/nginx/nginx.conf
  sed -i 's/# multi_accept on;/multi_accept on;/' /etc/nginx/nginx.conf
fi

EOF

  sleep 2
}

#######################################
# installs nginx
# Arguments:
#   None
#######################################
system_certbot_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando certbot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_domain=$(echo "${backend_url/https:\/\/}")
  frontend_domain=$(echo "${frontend_url/https:\/\/}")
  admin_domain=$(echo "${admin_url/https:\/\/}")

  sudo su - root <<EOF
  certbot -m ${deploy_email} \
          --nginx \
          --agree-tos \
          --redirect \
          --non-interactive \
          --domains $backend_domain,$frontend_domain
EOF

  sleep 2
}

#######################################
# reboot
# Arguments:
#   None
#######################################
system_reboot() {
  print_banner
  printf "${WHITE} 💻 Reboot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  reboot
EOF

  sleep 2
}

#######################################
# creates docker db
# Arguments:
#   None
#######################################
system_docker_start() {
  print_banner
  printf "${WHITE} 💻 Iniciando container docker...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker stop $(docker ps -q)
  docker container start ${folder_name}-postgresql
  docker container start ${folder_name}-redis-crm
EOF

  sleep 2
}

#######################################
# creates docker db
# Arguments:
#   None
#######################################
system_docker_restart() {
  print_banner
  printf "${WHITE} 💻 Iniciando container docker...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker container restart portainer
  docker container restart ${folder_name}-postgresql
EOF

  sleep 10
}

#######################################
# creates final message
# Arguments:
#   None
#######################################
system_success() {
  print_banner
  printf "${GREEN} 💻 Instalação concluída com Sucesso!${NC}"
  printf "${CYAN_LIGHT}";
  printf "\n\n"
  printf "${WHITE} 📊 Informações de Acesso:${GRAY_LIGHT}"
  printf "\n\n"
  printf "  • SuperAdmin: superadmin@crm.io"
  printf "\n"
  printf "  • Senha: 123456"
  printf "\n"
  printf "  • Usuário: admin@crm.io"
  printf "\n"
  printf "  • Senha: 123456"
  printf "\n\n"
  printf "${WHITE} 🌐 URLs do Sistema:${GRAY_LIGHT}"
  printf "\n\n"
  printf "  • Frontend: https://$frontend_domain"
  printf "\n"
  printf "  • Backend: https://$backend_domain"
  printf "\n\n"
  printf "${WHITE} 🔧 Configurações do Sistema:${GRAY_LIGHT}"
  printf "\n\n"
  printf "  • Usuário DB: ${folder_name}crm"
  printf "\n"
  printf "  • Nome DB: ${folder_name}-postgresql"
  printf "\n"
  printf "  • Senha DB: $pg_pass"
  printf "\n"
  printf "  • Senha Redis: $redis_pass"
  printf "\n\n"
  printf "${WHITE} 🔒 Segurança:${GRAY_LIGHT}"
  printf "\n\n"
  printf "  • Firewall ativado"
  printf "\n"
  printf "  • Portas liberadas: 22, 443, 80 e 9000"
  printf "\n\n"
  printf "${WHITE} 📞 Suporte:${GRAY_LIGHT}"
  printf "\n\n"
  printf "  • Suporte: https://wa.me/50489520312/"
  printf "\n"
  printf "  • FAQ: https://crm.passaportezdg.com.br/"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Importante: Guarde estas informações em um local seguro!${NC}"
  printf "\n\n"
  sleep 2
}