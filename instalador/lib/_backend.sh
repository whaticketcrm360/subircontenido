#!/bin/bash
# 
# functions for setting up app backend

#######################################
# creates docker db
# Arguments:
#   None
#######################################
backend_db_create() {
  step_header "🗄️ " "Creando contenedores de infraestructura" \
    "Inicia 3 contenedores Docker esenciales para el funcionamiento del CRM:"
  printf "  ${DIM}• postgresql  — Base de datos relacional en el puerto 5433 (datos en /data)${NC}\n"
  printf "  ${DIM}• redis-crm  — Caché en memoria en el puerto 6379 (colas, sesiones, pub/sub)${NC}\n"
  printf "  ${DIM}• portainer   — Interfaz de administración de Docker en los puertos 9000 y 9443${NC}\n\n"

  start_spinner "Creando contenedores de PostgreSQL, Redis y Portainer..."
  sudo su - root <<EOF
  usermod -aG docker deploycrm

  mkdir -p /data
  chown -R 999:999 /data

  docker run --name postgresql-crm \
                -e POSTGRES_PASSWORD=${pg_pass} \
                -e TZ="America/Tegucigalpa" \
                -e PGDATA=/var/lib/postgresql/datacrm \
                -p 127.0.0.1:5433:5432 \
                --restart=always \
                -v /data:/var/lib/postgresql/datacrm \
                -d postgres \
                -c shared_buffers=256MB \
                -c work_mem=16MB \
                -c effective_cache_size=1GB \
                -c maintenance_work_mem=128MB \
                -c max_connections=200

  docker run --name redis-crm \
                -e TZ="America/Tegucigalpa" \
                -p 6379:6379 \
                --restart=always \
                -d redis:latest redis-server \
                --appendonly yes \
                --appendfsync everysec \
                --no-appendfsync-on-rewrite yes \
                --maxmemory 2gb \
                --maxmemory-policy noeviction \
                --lazyfree-lazy-eviction yes \
                --lazyfree-lazy-expire yes \
                --lazyfree-lazy-server-del yes \
                --save "900 1" \
                --save "3600 1000" \
                --requirepass "${redis_pass}"
  
  docker run -d --name portainer \
                -p 9000:9000 -p 9443:9443 \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                -e PORTAINER_PASSWORD=${portainer_pass} \
                portainer/portainer-ce
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Error al crear los contenedores Docker."
    log_error "docker create" "Error al crear los contenedores de PostgreSQL/Redis/Portainer"
  else
    stop_spinner "Contenedores creados: postgresql, redis-crm, portainer."
  fi
  sleep 1
}

#######################################
# install_chrome
# Arguments:
#   None
#######################################
backend_chrome_install() {
  step_header "🌐" "Instalando Google Chrome" \
    "Puppeteer utiliza Chrome estable para generar PDF de conversaciones."
  printf "  ${DIM}Se ejecuta en modo sin interfaz gráfica (sin pantalla) — especificado en .env como CHROME_BIN.${NC}\n\n"

  start_spinner "Añadiendo e instalando el repositorio de Google google-chrome-stable..."
  sudo su - root <<EOF
  sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
  wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
  apt-get update
  apt-get install -y google-chrome-stable
EOF
  stop_spinner "Google Chrome instalado."
  sleep 1
}

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  step_header "⚙️ " "Configurando variables de entorno de backend" \
    "Genera contraseñas aleatorias y crea el archivo.env em /home/deploycrm/crm/backend/.env"
  printf "  ${DIM}Contiene: URLs, Credenciales de PostgreSQL, Redis, secretos JWT y límites de uso.${NC}\n\n"

  sleep 1
  
  # Eliminar el archivo de credenciales existente, si lo hay
  if [ -f "${PROJECT_ROOT}"/db_credentials ]; then
    rm -f "${PROJECT_ROOT}"/db_credentials
  fi
  
  # Generar contraseñas aleatorias
  pg_pass=$(openssl rand -base64 32)
  redis_pass=$(openssl rand -base64 32)
  portainer_pass=$(openssl rand -base64 12)

  # Guardar las contraseñas en un archivo para su reutilización
  cat << EOF > "${PROJECT_ROOT}"/db_credentials
pg_pass=${pg_pass}
redis_pass=${redis_pass}
portainer_pass=${portainer_pass}
deploy_password=${deploy_password}
EOF

  # ensure idempotency + sanitiza CR/whitespace/trailing-;,/aspas — incidente CSP helmet (FRONTEND_URL=https://host;)
  backend_url=$(printf '%s' "${backend_url}" | tr -d '\r\n\t "'\''' | sed -E 's/[[:space:];,]+$//' | sed -E 's/^[[:space:]]+//')
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=$(echo "${backend_url/http:\/\/}")
  backend_url=${backend_url%%/*}
  if [ -z "${backend_url}" ]; then
    printf "\n${RED}❌  BACKEND_URL Inválido tras la sanitización. Cancelando la configuración .env.${NC}\n\n"
    log_error "backend_set_env" "backend_url Vacío tras la sanitización"
    return 1
  fi
  backend_url=https://$backend_url

  frontend_url=$(printf '%s' "${frontend_url}" | tr -d '\r\n\t "'\''' | sed -E 's/[[:space:];,]+$//' | sed -E 's/^[[:space:]]+//')
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=$(echo "${frontend_url/http:\/\/}")
  frontend_url=${frontend_url%%/*}
  if [ -z "${frontend_url}" ]; then
    printf "\n${RED}❌  FRONTEND_URL Inválido tras la sanitización. Cancelando la configuración .env.${NC}\n\n"
    log_error "backend_set_env" "frontend_url Vacío tras la sanitización"
    return 1
  fi
  frontend_url=https://$frontend_url

  # Generar secretos dinámicos
  jwt_secret=$(openssl rand -base64 32)
  jwt_refresh_secret=$(openssl rand -base64 32)

sudo su - deploycrm << EOF
  cat <<[-]EOF > /home/deploycrm/crm/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
ADMIN_DOMAIN=crm

PROXY_PORT=443
PORT=3000

# Conexión a la base de datos (puerto 5433 para evitar usar el predeterminado 5432)
DB_DIALECT=postgres
DB_PORT=5433
DB_TIMEZONE=-00:00
POSTGRES_HOST=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=postgres

# Claves para el cifrado de tokens JWT
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

# Datos de conexión a REDIS
#IO_REDIS_SERVER=localhost
#IO_REDIS_PASSWORD=${redis_pass}
#IO_REDIS_PORT=6379
#IO_REDIS_DB_SESSION=2

#CHROME_BIN=/usr/bin/google-chrome
CHROME_BIN=/usr/bin/google-chrome-stable

# Hora para generar aleatoriamente mensajes de horario laboral
MIN_SLEEP_BUSINESS_HOURS=1000
MAX_SLEEP_BUSINESS_HOURS=2000

# Hora para generar aleatoriamente mensajes del bot
MIN_SLEEP_AUTO_REPLY=400
MAX_SLEEP_AUTO_REPLY=600

# Hora para generar aleatoriamente mensajes generales
MIN_SLEEP_INTERVAL=200
MAX_SLEEP_INTERVAL=500

# Datos de RabbitMQ / Para no usarlo, simplemente comente la variable AMQP_URL
# RABBITMQ_DEFAULT_USER=crm
# RABBITMQ_DEFAULT_PASS=${rabbit_pass}
# AMQP_URL='amqp://crm:${rabbit_pass}@localhost:5672?connection_attempts=5&retry_delay=5'

# API oficial (integración en desarrollo)
API_URL_360=https://waba-sandbox.360dialog.io

# Se utiliza para mostrar opciones que normalmente no están disponibles.
ADMIN_DOMAIN=crm

# Datos para usar el canal de Facebook
FACEBOOK_APP_ID=3237415623048660
FACEBOOK_APP_SECRET_KEY=3266214132b8c98ac59f3e957a5efeaaa13500

# Limitar el uso de CRM: Usuarios y Conexiones
USER_LIMIT=99
CONNECTIONS_LIMIT=99
[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
backend_node_dependencies() {
  step_header "📦" "Instalando dependencias del backend" \
    "Executa npm install --force em /home/deploycrm/crm/backend."
  printf "  ${DIM}Instala Todos los paquetes de package.json: Express, Sequelize, Baileys,${NC}\n"
  printf "  ${DIM}Socket.IO, Bull, Puppeteer y otras dependencias. Pode levar 3-5 minutos.${NC}\n\n"

  start_spinner "Instalando paquetes npm del backend (puede tardar unos minutos)..."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npm install --force
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Error al instalar las dependencias del backend."
    log_error "npm install backend" "Error al instalar las dependencias del backend"
  else
    stop_spinner "Dependencias del backend instaladas."
  fi
  sleep 1
}

#######################################
# compiles backend code
# Arguments:
#   None
#######################################
backend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando el código del backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npm run build
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_update() {
  print_banner
  printf "${WHITE} 💻 Actualizando el backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  pm2 stop all
  npm r whatsapp-web.js
  npm i whatsapp-web.js
  pm2 restart all
EOF

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
backend_db_migrate() {
  step_header "🗄️ " "Ejecutando migraciones de la base de datos" \
    "npx sequelize db:migrate — Crea y actualiza tablas en PostgreSQL."
  printf "  ${DIM}Las migraciones definen el esquema completo: tenants, usuários, tickets, contatos,${NC}\n"
  printf "  ${DIM}Mensajes, sesiones de WhatsApp, colas, configuración y otras entidades.${NC}\n\n"

  start_spinner "Aplicando migraciones a PostgreSQL (puerto 5433)..."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npx sequelize db:migrate
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Error al aplicar las migraciones."
    log_error "db:migrate" "Error al ejecutar las migraciones de la base de datos"
  else
    stop_spinner "Migraciones aplicadas. Esquema de la base de datos creado."
  fi
  sleep 1
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  step_header "🌱" "Rellenar la base de datos (datos iniciales)" \
    "npx sequelize db:seed:all — Inserta los datos iniciales necesarios en la base de datos."
  printf "  ${DIM}Seeds incluye: superadmin (superadmin@crm), Administrador predeterminado (admin@crm),${NC}\n"
  printf "  ${DIM}Accede a perfiles, planes, configuración del sistema e inquilino inicial.${NC}\n\n"

  start_spinner "Insertando datos iniciales en la base de datos (superadministrador, administrador, configuración)...."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  npx sequelize db:seed:all
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Error al aplicar las semillas."
    log_error "db:seed" "Error al ejecutar las semillas de la base de datos."
  else
    stop_spinner "Semillas aplicadas. Datos iniciales insertados en la base de datos."
  fi
  sleep 1
}

#######################################
# starts backend using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
backend_start_pm2() {
  step_header "🚀" "Iniciando el backend con PM2" \
    "Inicia el servidor Node.js de producción con PM2."
  printf "  ${DIM}Proceso: crm-backend | Archivo: dist/server.js | Memoria: 2048 MB${NC}\n"
  printf "  ${DIM}PM2 mantiene el proceso activo, lo reinicia en caso de fallo y guarda la lista de procesos.${NC}\n\n"

  start_spinner "Iniciando crm-backend com 2GB de heap..."
  sudo su - deploycrm <<EOF
  cd /home/deploycrm/crm/backend
  pm2 start dist/server.js --name crm-backend --node-args="--max-old-space-size=2048"
  pm2 save
EOF
  if [ $? -ne 0 ]; then
    stop_spinner_error "Error al iniciar el backend en PM2."
    log_error "pm2 start backend" "Error al iniciar crm-backend en PM2"
  else
    stop_spinner "Backend iniciado. Proceso crm-backend activo en PM2."
  fi
  sleep 1
}

#######################################
# installs node
# Arguments:
#   None
#######################################
backend_bd_update() {
  step_header "🗄️ " "Corrigindo permissões do PostgreSQL" \
    "Garante que o usuário 'postgres' dentro do container seja dono dos arquivos de dados."
  printf "  ${DIM}Necessário quando o diretório /data é criado pelo root e depois montado no container.${NC}\n\n"

  start_spinner "Verificando e corrigindo permissões em /var/lib/postgresql/data..."
  sudo su - root <<EOF
  if docker ps -q -f name=postgresql; then
    docker exec -u root postgresql bash -c "chown -R postgres:postgres /var/lib/postgresql/data"
  else
    echo "Container postgresql não está em execução — pulando."
  fi
EOF
  stop_spinner "Permissões do PostgreSQL verificadas."
  sleep 1
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_nginx_setup() {
  step_header "🌐" "Configurando nginx para o backend" \
    "Cria /etc/nginx/sites-available/crm-backend e ativa o vhost."
  printf "  ${DIM}O nginx recebe requisições HTTPS no domínio ${backend_url} e encaminha${NC}\n"
  printf "  ${DIM}para o backend Node.js rodando em http://127.0.0.1:3000.${NC}\n\n"

  sleep 1

  backend_hostname=$(echo "${backend_url/https:\/\/}")

sudo su - root << EOF

cat > /etc/nginx/sites-available/crm-backend << 'END'
server {
  server_name $backend_hostname;

  location / {
    proxy_pass http://127.0.0.1:3000;
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

  error_page 502 503 504 = @backend_offline;

  location @backend_offline {
    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Requested-With' always;
    add_header 'Content-Type' 'application/json' always;
    return 502 '{"error":"backend_offline","message":"Backend temporariamente indisponivel"}';
  }
}
END

ln -s /etc/nginx/sites-available/crm-backend /etc/nginx/sites-enabled
EOF

  sleep 2
}

#######################################
# reinicia o Portainer
# Arguments:
#   None
#######################################
portainer_restart() {
  print_banner
  printf "${WHITE} 💻 Reiniciando o Portainer...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker restart portainer
EOF

  sleep 2
}

#######################################
# remove o Portainer e seus volumes
# Arguments:
#   None
#######################################
portainer_remove() {
  print_banner
  printf "${WHITE} 💻 Removendo o Portainer e seus volumes...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker stop portainer
  docker rm portainer
  docker volume rm portainer_data
EOF

  sleep 2
}

#######################################
# recria o Portainer
# Arguments:
#   None
#######################################
portainer_recreate() {
  print_banner
  printf "${WHITE} 💻 Recriando o Portainer...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker run -d --name portainer \
                -p 9000:9000 -p 9443:9443 \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                -e PORTAINER_PASSWORD=${portainer_pass} \
                portainer/portainer-ce
EOF

  sleep 2

  # Obter IP da máquina
  IP=$(hostname -I | awk '{print $1}')

  print_banner
  printf "${GREEN} ✅ ¡Portainer recreado correctamente!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 URLs de acesso:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Interface Web: http://${IP}:9000"
  printf "\n"
  printf "  • Interface Segura: https://${IP}:9443"
  printf "\n"
  printf "  • Contraseña: ${portainer_pass}"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Recuerda configurar tu firewall para permitir el acceso a estos puertos si es necesario.${NC}"
  printf "\n\n"
}

#######################################
# Instala e configura Prometheus
# Arguments:
#   None
#######################################
setup_prometheus() {
  print_banner
  printf "${WHITE} 💻 Instalación y configuración de Prometheus...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Remover containers existentes se houver
  docker stop prometheus node-exporter || true
  docker rm prometheus node-exporter || true

  # Criar diretório para dados do Prometheus
  mkdir -p /data/prometheus
  chown -R 65534:65534 /data/prometheus
  chmod -R 777 /data/prometheus

  # Criar arquivo de configuração
  cat > /data/prometheus/prometheus.yml << 'END'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'crm'
    static_configs:
      - targets: ['crm-backend:3000']
END

  # Iniciar Prometheus
  docker run -d --name prometheus \
    -p 9090:9090 \
    -v /data/prometheus:/prometheus \
    -v /data/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
    --user 65534:65534 \
    --restart=always \
    prom/prometheus \
    --storage.tsdb.path=/prometheus \
    --web.console.libraries=/usr/share/prometheus/console_libraries \
    --web.console.templates=/usr/share/prometheus/consoles

  # Iniciar Node Exporter
  docker run -d --name node-exporter \
    -p 9100:9100 \
    --restart=always \
    prom/node-exporter
EOF

  sleep 2

  # Obter IP da máquina
  IP=$(hostname -I | awk '{print $1}')

  print_banner
  printf "${GREEN} ✅ Prometheus e Node Exporter instalados com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 URLs de acesso:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Prometheus: http://${IP}:9090"
  printf "\n"
  printf "  • Node Exporter: http://${IP}:9100"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Lembre-se de configurar o firewall para permitir acesso a estas portas se necessário${NC}"
  printf "\n\n"
}

#######################################
# Instala e configura Grafana
# Arguments:
#   None
#######################################
setup_grafana() {
  print_banner
  printf "${WHITE} 💻 Instalando e configurando Grafana...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Remover container existente se houver
  docker stop grafana || true
  docker rm grafana || true

  # Criar diretório para dados do Grafana
  mkdir -p /data/grafana
  chown -R 472:472 /data/grafana
  chmod -R 777 /data/grafana

  # Iniciar Grafana
  docker run -d --name grafana \
    -p 3022:3000 \
    -v /data/grafana:/var/lib/grafana \
    --user 472:472 \
    --restart=always \
    grafana/grafana

  # Aguardar Grafana iniciar
  sleep 10

  # Configurar datasource do Prometheus
  curl -X POST "http://localhost:3022/api/datasources" \
    -H "Content-Type: application/json" \
    -u admin:admin \
    -d '{
      "name":"Prometheus",
      "type":"prometheus",
      "url":"http://prometheus:9090",
      "access":"proxy",
      "basicAuth":false
    }'
EOF

  sleep 2

  # Obter IP da máquina
  IP=$(hostname -I | awk '{print $1}')

  print_banner
  printf "${GREEN} ✅ Grafana instalado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 URLs de acesso:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Grafana: http://${IP}:3022"
  printf "\n"
  printf "  • Credenciais padrão: admin/admin"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Lembre-se de alterar a senha padrão após o primeiro login${NC}"
  printf "\n\n"
}

#######################################
# Configura backup personalizado
# Arguments:
#   None
#######################################
setup_backup() {
  print_banner
  printf "${WHITE} 💻 Configurando backup personalizado...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Criar diretório para backups
  mkdir -p /backup/crm
  chown -R root:root /backup/crm

  # Criar script de backup
  cat > /usr/local/bin/crm-backup.sh << 'END'
#!/bin/bash
BACKUP_DIR="/backup/crm"
DATE=\$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/crm/backup.log"

# Função para registrar logs
log_message() {
  echo "[\$(date +"%Y-%m-%d %H:%M:%S")] \$1" >> \$LOG_FILE
}

# Função para extrair configurações do .env
get_db_config() {
  local env_file="\$1"
  local config=()
  
  if [ -f "\$env_file" ]; then
    config[0]=\$(grep "POSTGRES_USER=" "\$env_file" | cut -d'=' -f2)
    config[1]=\$(grep "POSTGRES_PASSWORD=" "\$env_file" | cut -d'=' -f2)
    config[2]=\$(grep "POSTGRES_DB=" "\$env_file" | cut -d'=' -f2)
    config[3]=\$(grep "POSTGRES_HOST=" "\$env_file" | cut -d'=' -f2)
    config[4]=\$(grep "DB_PORT=" "\$env_file" | cut -d'=' -f2)
  fi
  
  echo "\${config[@]}"
}

log_message "Iniciando backup"

# Encontrar todas as instâncias crm dentro de /home/deploycrm
find /home/deploycrm -type d -name "crm" | while read -r instance_path; do
  # Extrair nome da instância do caminho
  instance_name=\$(echo "\$instance_path" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
  if [ -z "\$instance_name" ]; then
    instance_name="primeira_instancia"
  fi
  
  log_message "Backup da instância: \$instance_name"
  
  # Criar diretório para backup da instância
  instance_backup_dir="\$BACKUP_DIR/\$instance_name"
  mkdir -p "\$instance_backup_dir"
  
  # Backup dos arquivos da instância
  log_message "Fazendo backup dos arquivos"
  tar -czf "\$instance_backup_dir/files_\$DATE.tar.gz" "\$instance_path"
  
  # Verificar se existe arquivo .env no backend
  env_file="\$instance_path/backend/.env"
  if [ -f "\$env_file" ]; then
    # Extrair configurações do banco
    read -r -a db_config <<< "\$(get_db_config "\$env_file")"
    
    if [ \${#db_config[@]} -ge 5 ]; then
      # Fazer backup do banco de dados
      log_message "Fazendo backup do banco de dados"
      PGPASSWORD="\${db_config[1]}" pg_dump -h "\${db_config[3]}" -p "\${db_config[4]}" -U "\${db_config[0]}" "\${db_config[2]}" > "\$instance_backup_dir/db_\$DATE.sql"
    fi
  fi
  
  # Manter apenas os últimos 7 backups para esta instância
  log_message "Removendo backups antigos"
  find "\$instance_backup_dir" -type f -mtime +7 -delete
done

# Backup do Prometheus e Grafana
if [ -d "/data/prometheus" ]; then
  log_message "Fazendo backup do Prometheus"
  tar -czf "\$BACKUP_DIR/prometheus_\$DATE.tar.gz" /data/prometheus
fi

if [ -d "/data/grafana" ]; then
  log_message "Fazendo backup do Grafana"
  tar -czf "\$BACKUP_DIR/grafana_\$DATE.tar.gz" /data/grafana
fi

# Manter apenas os últimos 7 backups dos serviços
find "\$BACKUP_DIR" -type f -name "prometheus_*.tar.gz" -mtime +7 -delete
find "\$BACKUP_DIR" -type f -name "grafana_*.tar.gz" -mtime +7 -delete

log_message "Backup concluído com sucesso"
END

  chmod +x /usr/local/bin/crm-backup.sh
  chown root:root /usr/local/bin/crm-backup.sh

  # Criar diretório para logs
  mkdir -p /var/log/crm
  chown -R root:root /var/log/crm

  # Adicionar ao crontab do root
  echo "0 2 * * * /usr/local/bin/crm-backup.sh" | crontab -
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Backup personalizado configurado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 Informações do Backup:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Diretório de backup: /backup/crm"
  printf "\n"
  printf "  • Logs: /var/log/crm/backup.log"
  printf "\n"
  printf "  • Agendamento: Todos os dias às 2h da manhã"
  printf "\n"
  printf "  • Retenção: Últimos 7 dias"
  printf "\n"
  printf "  • O backup inclui:${NC}"
  printf "\n"
  printf "  • Todas as instâncias crm encontradas em /home/deploycrm"
  printf "\n"
  printf "  • Bancos de dados de cada instância"
  printf "\n"
  printf "  • Dados do Prometheus e Grafana"
  printf "\n\n"
  printf "${WHITE} 📊 Comandos úteis:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Ver logs em tempo real: tail -f /var/log/crm/backup.log"
  printf "\n"
  printf "  • Listar backups: ls -lh /backup/crm"
  printf "\n"
  printf "  • Ver backups de uma instância: ls -lh /backup/crm/NOME_DA_INSTANCIA"
  printf "\n"
  printf "  • Executar backup manualmente: sudo /usr/local/bin/crm-backup.sh"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Os backups são mantidos por 7 dias e são executados automaticamente${NC}"
  printf "\n\n"
}

#######################################
# Configura Rate Limiting
# Arguments:
#   None
#######################################
setup_rate_limiting() {
  print_banner
  printf "${WHITE} 💻 Configurando Rate Limiting...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Instalar fail2ban
  apt-get install -y fail2ban

  # Criar diretório para logs do rate limiting
  mkdir -p /var/log/nginx/rate-limiting
  chown -R www-data:www-data /var/log/nginx/rate-limiting

  # Configurar rate limiting no nginx
  cat > /etc/nginx/conf.d/rate-limiting.conf << 'END'
# Configuração de zonas para rate limiting
limit_req_zone \$binary_remote_addr zone=one:10m rate=1r/s;
limit_conn_zone \$binary_remote_addr zone=addr:10m;

# Configuração de logging
log_format rate_limiting '\$remote_addr - \$remote_user [\$time_local] '
                        '"\$request" \$status \$body_bytes_sent '
                        '"\$http_referer" "\$http_user_agent" '
                        'Rate-Limited: \$limit_req_status '
                        'Connections: \$limit_conn_status';

access_log /var/log/nginx/rate-limiting/access.log rate_limiting;

server {
    location / {
        # Limitar requisições
        limit_req zone=one burst=10 nodelay;
        # Limitar conexões
        limit_conn addr 10;
        
        # Configurações adicionais
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
END

  # Reiniciar nginx
  systemctl restart nginx
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Rate Limiting configurado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 Informações do Rate Limiting:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Logs: /var/log/nginx/rate-limiting/access.log"
  printf "\n"
  printf "  • Configuração: /etc/nginx/conf.d/rate-limiting.conf"
  printf "\n"
  printf "  • Limites configurados:${NC}"
  printf "\n"
  printf "  • Requisições: 1 por segundo (burst de 10)"
  printf "\n"
  printf "  • Conexões simultâneas: 10 por IP"
  printf "\n\n"
  printf "${WHITE} 📊 Comandos úteis:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Ver logs em tempo real: tail -f /var/log/nginx/rate-limiting/access.log"
  printf "\n"
  printf "  • Ver status do nginx: systemctl status nginx"
  printf "\n"
  printf "  • Ver configuração: cat /etc/nginx/conf.d/rate-limiting.conf"
  printf "\n\n"
  printf "${YELLOW} ⚠️  IPs que excederem os limites serão temporariamente bloqueados${NC}"
  printf "\n\n"
}

#######################################
# Configura Fail2ban
# Arguments:
#   None
#######################################
setup_fail2ban() {
  print_banner
  printf "${WHITE} 💻 Configurando Fail2ban...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Configurar fail2ban
  cat > /etc/fail2ban/jail.local << 'END'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 3600

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 3600

[nginx-dos]
enabled = true
port = http,https
filter = nginx-dos
logpath = /var/log/nginx/access.log
maxretry = 3
bantime = 3600
END

  # Reiniciar fail2ban
  systemctl restart fail2ban

  # Criar diretório para logs do fail2ban
  mkdir -p /var/log/fail2ban
  chown -R root:root /var/log/fail2ban
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Fail2ban configurado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 Informações do Fail2ban:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Logs: /var/log/fail2ban/fail2ban.log"
  printf "\n"
  printf "  • Configuração: /etc/fail2ban/jail.local"
  printf "\n"
  printf "  • Monitoramento:${NC}"
  printf "\n"
  printf "  • SSH - Bloqueia após 3 tentativas falhas"
  printf "\n"
  printf "  • Nginx Auth - Protege contra tentativas de login"
  printf "\n"
  printf "  • Nginx Bot - Bloqueia bots maliciosos"
  printf "\n"
  printf "  • Nginx DoS - Protege contra ataques DoS"
  printf "\n\n"
  printf "${WHITE} 📊 Comandos úteis:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Ver status: sudo fail2ban-client status"
  printf "\n"
  printf "  • Ver logs em tempo real: tail -f /var/log/fail2ban/fail2ban.log"
  printf "\n"
  printf "  • Ver IPs banidos: sudo fail2ban-client status sshd"
  printf "\n"
  printf "  • Desbanir IP: sudo fail2ban-client set sshd unbanip IP_ADDRESS"
  printf "\n\n"
  printf "${YELLOW} ⚠️  O banimento padrão é de 1 hora após 3 tentativas falhas${NC}"
  printf "\n\n"
}

#######################################
# Configura Health Check
# Arguments:
#   None
#######################################
setup_health_check() {
  print_banner
  printf "${WHITE} 💻 Configurando Health Check...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Criar diretório para logs do health check
  mkdir -p /var/log/crm
  chown -R deploycrm:deploycrm /var/log/crm

  # Criar script de health check
  cat > /usr/local/bin/crm-health-check.sh << 'END'
#!/bin/bash

LOG_FILE="/var/log/crm/health-check.log"
DATE=\$(date +"%Y-%m-%d %H:%M:%S")

# Função para registrar logs
log_message() {
  echo "[\$DATE] \$1" >> \$LOG_FILE
}

# Verificar status do PM2
if ! sudo -u deploycrm pm2 list | grep -q "online"; then
  log_message "PM2 não está rodando"
  exit 1
else
  log_message "PM2 está rodando normalmente"
fi

# Verificar status do PostgreSQL
if ! docker ps | grep -q "postgresql"; then
  log_message "PostgreSQL não está rodando"
  exit 1
else
  log_message "PostgreSQL está rodando normalmente"
fi

# Verificar status do Redis
if ! docker ps | grep -q "redis-crm"; then
  log_message "Redis não está rodando"
  exit 1
else
  log_message "Redis está rodando normalmente"
fi

# Verificar uso de disco
DISK_USAGE=\$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ \$DISK_USAGE -gt 90 ]; then
  log_message "Uso de disco acima de 90%"
  exit 1
else
  log_message "Uso de disco: \$DISK_USAGE%"
fi

# Verificar uso de memória
MEM_USAGE=\$(free | awk '/Mem:/ {print int(\$3/\$2 * 100)}')
if [ \$MEM_USAGE -gt 90 ]; then
  log_message "Uso de memória acima de 90%"
  exit 1
else
  log_message "Uso de memória: \$MEM_USAGE%"
fi

log_message "Health check concluído com sucesso"
exit 0
END

  chmod +x /usr/local/bin/crm-health-check.sh
  chown deploycrm:deploycrm /usr/local/bin/crm-health-check.sh

  # Adicionar ao crontab do usuário deploycrm
  sudo -u deploycrm bash -c 'echo "*/5 * * * * /usr/local/bin/crm-health-check.sh" | crontab -'
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Health Check configurado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 Informações do Health Check:${GRAY_LIGHT}"
  printf "\n"
  printf "  • Logs: /var/log/crm/health-check.log"
  printf "\n"
  printf "  • Verificação: A cada 5 minutos"
  printf "\n"
  printf "  • Monitora:${NC}"
  printf "\n"
  printf "  • Status do PM2"
  printf "\n"
  printf "  • Status do PostgreSQL"
  printf "\n"
  printf "  • Status do Redis"
  printf "\n"
  printf "  • Uso de disco"
  printf "\n"
  printf "  • Uso de memória"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Para verificar os logs em tempo real, use: tail -f /var/log/crm/health-check.log${NC}"
  printf "\n\n"
}

#######################################
# Configura Firewall
# Arguments:
#   None
#######################################
setup_firewall() {
  print_banner
  printf "${WHITE} 💻 Configurando Firewall...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Instalar UFW se não estiver instalado
  if ! command -v ufw &> /dev/null; then
    apt-get update
    apt-get install -y ufw
  fi

  # Resetar configurações do UFW
  ufw --force reset

  # Configurar regras padrão
  ufw default deny incoming
  ufw default allow outgoing

  # Permitir portas essenciais
  ufw allow 22/tcp    # SSH
  ufw allow 80/tcp    # HTTP
  ufw allow 81/tcp    # HTTP Alternativo
  ufw allow 443/tcp   # HTTPS
  ufw allow 9000/tcp  # Porta para serviços
  ufw allow 9007/tcp  # Portainer
  ufw allow 3011/tcp  # Grafana
  ufw allow 3022/tcp  # Grafana
  ufw allow 9090/tcp  # Prometheus

  # Habilitar UFW
  ufw --force enable

  # Mostrar status
  ufw status numbered
EOF

  sleep 2

  print_banner
  printf "${GREEN} ✅ Firewall configurado com sucesso!${GRAY_LIGHT}"
  printf "\n\n"
  printf "${WHITE} 📊 Portas configuradas:${GRAY_LIGHT}"
  printf "\n"
  printf "  • 22/tcp   - SSH"
  printf "\n"
  printf "  • 80/tcp   - HTTP"
  printf "\n"
  printf "  • 81/tcp   - HTTP Alternativo"
  printf "\n"
  printf "  • 443/tcp  - HTTPS"
  printf "\n"
  printf "  • 9000/tcp - Serviços"
  printf "\n"
  printf "  • 9007/tcp - Portainer"
  printf "\n"
  printf "  • 3011/tcp - Grafana"
  printf "\n"
  printf "  • 3022/tcp - Grafana"
  printf "\n"
  printf "  • 9090/tcp - Prometheus"
  printf "\n\n"
  printf "${YELLOW} ⚠️  Todas as outras portas estão bloqueadas por padrão${NC}"
  printf "\n\n"
}

#######################################
# Configurações Avançadas
# Arguments:
#   None
#######################################
advanced_settings() {
  print_banner
  printf "${WHITE} 💻 O que você deseja configurar?${GRAY_LIGHT}"
  printf "\n\n"
  printf "  [1] Configurar backup personalizado\n"
  printf "  [2] Configurar Rate Limiting\n"
  printf "  [3] Configurar Fail2ban\n"
  printf "  [4] Configurar Health Check\n"
  printf "  [5] Configurar Firewall\n"
  printf "  [6] Configurar tudo\n"
  printf "\n\n"
  read -p "> " advanced_option

  case "${advanced_option}" in
    1) setup_backup ;;
    2) setup_rate_limiting ;;
    3) setup_fail2ban ;;
    4) setup_health_check ;;
    5) setup_firewall ;;
    6)
      setup_backup
      setup_rate_limiting
      setup_fail2ban
      setup_health_check
      setup_firewall
      ;;
    *) exit ;;
  esac
}

#######################################
# Altera subdomínio da crm
# Arguments:
#   None
#######################################
change_subdomain() {
  print_banner
  printf "${WHITE} 💻 Alterando domínios da crm...${GRAY_LIGHT}"
  printf "\n\n"

  # Mapear instâncias existentes
  instances=()
  while IFS= read -r instance; do
    instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
    fi
    instances+=("$instance_name")
  done < <(find /home/deploycrm -type d -name "crm")

  if [ ${#instances[@]} -eq 0 ]; then
    printf "${RED} ❌ Nenhuma instância crm encontrada!${NC}\n\n"
    return 1
  fi

  # Mostrar instâncias disponíveis
  printf "${WHITE} 📊 Instâncias encontradas:${GRAY_LIGHT}\n\n"
  for i in "${!instances[@]}"; do
    printf "  [$(($i+1))] ${instances[$i]}\n"
  done
  printf "\n"

  # Perguntar qual instância alterar
  read -p "> Digite o número da instância que deseja alterar: " instance_number
  if [ "$instance_number" -lt 1 ] || [ "$instance_number" -gt ${#instances[@]} ]; then
    printf "${RED} ❌ Opção inválida!${NC}\n\n"
    return 1
  fi

  selected_instance=${instances[$(($instance_number-1))]}
  
  # Definir o caminho correto da instância
  if [ "$selected_instance" = "primeira_instancia" ]; then
    instance_path="/home/deploycrm/crm"
  else
    instance_path="/home/deploycrm/$selected_instance/crm"
  fi

  # Buscar portas dinamicamente
  # Frontend (Next.js): PORT vem de .env.local; legado Vue tinha em .env;
  # fallback final = vhost nginx, default 4444 (porta padrao crm frontend).
  frontend_port=$(grep -oP '^PORT=\K[0-9]+' "$instance_path/frontend/.env.local" 2>/dev/null)
  [ -z "$frontend_port" ] && frontend_port=$(grep -oP '^PORT=\K[0-9]+' "$instance_path/frontend/.env" 2>/dev/null)
  [ -z "$frontend_port" ] && frontend_port=$(grep -oP 'proxy_pass\s+http://127\.0\.0\.1:\K[0-9]+' /etc/nginx/sites-available/crm-frontend 2>/dev/null | head -n1)
  frontend_port="${frontend_port:-4444}"
  backend_port=$(grep -oP '^PORT=\K[0-9]+' "$instance_path/backend/.env")

  if [ -z "$frontend_port" ]; then
    printf "${RED} ❌ Não foi possível encontrar a porta do frontend!${NC}\n\n"
    return 1
  fi

  if [ -z "$backend_port" ]; then
    printf "${RED} ❌ Não foi possível encontrar a porta do backend!${NC}\n\n"
    return 1
  fi

  # Perguntar novos domínios
  read -p "> Digite o novo domínio do backend (ex: api.novo.crm): " new_backend_domain
  new_backend_domain=$(printf '%s' "${new_backend_domain}" | tr -d '\r\n\t "'\''' | sed -E 's|^https?://||; s|/.*$||; s/[[:space:];,]+$//; s/^[[:space:]]+//')
  if [ -z "$new_backend_domain" ]; then
    printf "${RED} ❌ Domínio do backend inválido!${NC}\n\n"
    return 1
  fi

  read -p "> Digite o novo domínio do frontend (ex: novo.crm): " new_frontend_domain
  new_frontend_domain=$(printf '%s' "${new_frontend_domain}" | tr -d '\r\n\t "'\''' | sed -E 's|^https?://||; s|/.*$||; s/[[:space:];,]+$//; s/^[[:space:]]+//')
  if [ -z "$new_frontend_domain" ]; then
    printf "${RED} ❌ Domínio do frontend inválido!${NC}\n\n"
    return 1
  fi

  # Extrair domínio base
  base_domain=$(echo "$new_frontend_domain" | cut -d'.' -f2-)

  # Alterar .env do backend
  if [ -f "$instance_path/backend/.env" ]; then
    sed -i "s|BACKEND_URL=.*|BACKEND_URL=https://$new_backend_domain|" "$instance_path/backend/.env"
    sed -i "s|FRONTEND_URL=.*|FRONTEND_URL=https://$new_frontend_domain|" "$instance_path/backend/.env"
  fi

  # Alterar env do frontend — cobre Vue legado, Next.js oficial e cenário 3 (Next paralelo)
  # Vue legado: frontend/.env com URL_API=
  if [ -f "$instance_path/frontend/.env" ] && grep -q '^URL_API=' "$instance_path/frontend/.env" 2>/dev/null; then
    sed -i "s|^URL_API=.*|URL_API=https://$new_backend_domain|" "$instance_path/frontend/.env"
  fi
  # Next.js oficial (PLANO_FRONTNOVO_OFICIAL): frontend/.env.local com NEXT_PUBLIC_API_URL=
  if [ -f "$instance_path/frontend/.env.local" ]; then
    if grep -q '^NEXT_PUBLIC_API_URL=' "$instance_path/frontend/.env.local"; then
      sed -i "s|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=https://$new_backend_domain|" "$instance_path/frontend/.env.local"
    else
      printf '\nNEXT_PUBLIC_API_URL=https://%s\n' "$new_backend_domain" >> "$instance_path/frontend/.env.local"
    fi
  fi
  # Cenário 3 (Vue + Next paralelo em frontNovo/): frontNovo/.env.local com NEXT_PUBLIC_API_URL=
  if [ -f "$instance_path/frontNovo/.env.local" ]; then
    if grep -q '^NEXT_PUBLIC_API_URL=' "$instance_path/frontNovo/.env.local"; then
      sed -i "s|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=https://$new_backend_domain|" "$instance_path/frontNovo/.env.local"
    else
      printf '\nNEXT_PUBLIC_API_URL=https://%s\n' "$new_backend_domain" >> "$instance_path/frontNovo/.env.local"
    fi
  fi

  # Configurar nginx
  if [ "$selected_instance" = "primeira_instancia" ]; then
    backend_config="crm-backend"
    frontend_config="crm-frontend"
  else
    backend_config="${selected_instance}-crm-backend"
    frontend_config="${selected_instance}-crm-frontend"
  fi

  # Remover configurações antigas do nginx
  rm -f "/etc/nginx/sites-available/$backend_config"
  rm -f "/etc/nginx/sites-available/$frontend_config"
  rm -f "/etc/nginx/sites-enabled/$backend_config"
  rm -f "/etc/nginx/sites-enabled/$frontend_config"

  # Configurar backend no nginx
  cat > "/etc/nginx/sites-available/$backend_config" << EOF
server {
  server_name $new_backend_domain;

  location / {
    proxy_pass http://127.0.0.1:$backend_port;
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

  error_page 502 503 504 = @backend_offline;

  location @backend_offline {
    add_header 'Access-Control-Allow-Origin' "\$http_origin" always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, PATCH, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Requested-With' always;
    add_header 'Content-Type' 'application/json' always;
    return 502 '{"error":"backend_offline","message":"Backend temporariamente indisponivel"}';
  }
}
EOF

  # Configurar frontend no nginx
  cat > "/etc/nginx/sites-available/$frontend_config" << EOF
server {
  server_name $new_frontend_domain;

  location / {
    proxy_pass http://127.0.0.1:$frontend_port;
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
EOF

  # Ativar configurações do nginx
  ln -sf "/etc/nginx/sites-available/$backend_config" "/etc/nginx/sites-enabled/"
  ln -sf "/etc/nginx/sites-available/$frontend_config" "/etc/nginx/sites-enabled/"

  # Capturar email para o certbot
  read -p "> Digite o email para o certificado SSL: " ssl_email
  if [ -z "$ssl_email" ]; then
    printf "${RED} ❌ Email inválido!${NC}\n\n"
    return 1
  fi

  # Gerar certificados SSL
  certbot --nginx -d $new_backend_domain -d $new_frontend_domain --redirect --non-interactive --agree-tos --email $ssl_email

  # Verificar se o nginx está rodando
  if ! systemctl is-active --quiet nginx; then
    printf "${YELLOW} ⚠️  Nginx não está rodando, tentando iniciar...${NC}\n"
    systemctl start nginx
  fi

  # Verificar configuração do nginx
  if ! nginx -t; then
    printf "${RED} ❌ Erro na configuração do nginx! Verifique os logs.${NC}\n\n"
    return 1
  fi

  # Tentar reiniciar o nginx
  if ! systemctl restart nginx; then
    printf "${YELLOW} ⚠️  Erro ao reiniciar o nginx, tentando forçar reinicialização...${NC}\n"
    # Forçar parada de todos os processos nginx
    killall nginx 2>/dev/null || true
    # Remover arquivo PID se existir
    rm -f /run/nginx.pid
    # Tentar iniciar novamente
    if ! systemctl start nginx; then
      printf "${RED} ❌ Erro ao reiniciar o nginx após tentativa forçada! Verifique os logs.${NC}\n\n"
      return 1
    fi
  fi

  # Reconstruir frontend
  sudo -u deploycrm bash -c "cd $instance_path/frontend && npm run build"

  # Reiniciar serviços
  sudo -u deploycrm pm2 restart all

  print_banner
  printf "${GREEN} ✅ Domínios alterados com sucesso!${GRAY_LIGHT}\n\n"
  printf "${WHITE} 📊 Informações:${GRAY_LIGHT}\n"
  printf "  • Instância: $selected_instance\n"
  printf "  • Novo domínio do backend: $new_backend_domain (porta: $backend_port)\n"
  printf "  • Novo domínio do frontend: $new_frontend_domain (porta: $frontend_port)\n"
  printf "  • Configurações nginx: $backend_config e $frontend_config\n\n"
  printf "${YELLOW} ⚠️  Lembre-se de atualizar o DNS dos novos domínios para apontar para este servidor${NC}\n\n"
}

#######################################
# recria o Redis para uma instância específica
# Arguments:
#   None
#######################################
recreate_redis() {
  print_banner
  printf "${WHITE} 💻 Recriando Redis...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # Mapear instâncias existentes
  instances=()
  while IFS= read -r instance; do
    instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
    fi
    instances+=("$instance_name")
  done < <(find /home/deploycrm -type d -name "crm")

  if [ ${#instances[@]} -eq 0 ]; then
    printf "${RED} ❌ Nenhuma instância crm encontrada!${NC}\n\n"
    return 1
  fi

  # Mostrar instâncias disponíveis
  printf "${WHITE} 📊 Instâncias encontradas:${GRAY_LIGHT}\n\n"
  for i in "${!instances[@]}"; do
    printf "  [$(($i+1))] ${instances[$i]}\n"
  done
  printf "\n"

  # Perguntar qual instância atualizar
  read -p "> Digite o número da instância que deseja atualizar: " instance_number
  if [ "$instance_number" -lt 1 ] || [ "$instance_number" -gt ${#instances[@]} ]; then
    printf "${RED} ❌ Opção inválida!${NC}\n\n"
    return 1
  fi

  selected_instance=${instances[$(($instance_number-1))]}
  
  # Definir o caminho correto da instância
  if [ "$selected_instance" = "primeira_instancia" ]; then
    instance_path="/home/deploycrm/crm"
    container_name="redis-crm"
  else
    instance_path="/home/deploycrm/$selected_instance/crm"
    container_name="${selected_instance}-redis-crm"
  fi

  # Verificar se existe arquivo .env no backend
  env_file="$instance_path/backend/.env"
  if [ -f "$env_file" ]; then
    # Extrair configurações do Redis
    redis_port=$(grep "IO_REDIS_PORT=" "$env_file" | cut -d'=' -f2)
    redis_pass=$(grep "IO_REDIS_PASSWORD=" "$env_file" | sed 's/IO_REDIS_PASSWORD=//')
    
    if [ ! -z "$redis_port" ] && [ ! -z "$redis_pass" ]; then
      sudo su - root <<EOF
      # Parar e remover container existente se houver
      docker stop "$container_name" 2>/dev/null || true
      docker rm "$container_name" 2>/dev/null || true
      
      # Criar novo container Redis com a senha existente
      docker run --name "$container_name" \
        -e TZ="America/Tegucigalpa" \
        -p "${redis_port}:6379" \
        --restart=always \
        -d redis:latest redis-server \
        --appendonly yes \
        --appendfsync everysec \
        --no-appendfsync-on-rewrite yes \
        --maxmemory 2gb \
        --maxmemory-policy noeviction \
        --lazyfree-lazy-eviction yes \
        --lazyfree-lazy-expire yes \
        --lazyfree-lazy-server-del yes \
        --save "900 1" \
        --save "3600 1000" \
        --requirepass "${redis_pass}"
EOF
      printf "${GREEN} ✅ Redis recriado para a instância $selected_instance na porta $redis_port${NC}\n"
      printf "${YELLOW} ⚠️  Usando a senha existente do arquivo .env${NC}\n"
      
      # Reiniciar todos os processos PM2
      sudo -u deploycrm pm2 restart all
      printf "${GREEN} ✅ Todos os processos PM2 reiniciados${NC}\n"
    else
      printf "${YELLOW} ⚠️  Configurações do Redis não encontradas para a instância $selected_instance${NC}\n"
    fi
  else
    printf "${YELLOW} ⚠️  Arquivo .env não encontrado para a instância $selected_instance${NC}\n"
  fi

  sleep 2
}

#######################################
# Instala a interface do webchat
# Arguments:
#   None
#######################################
install_webchat() {
  print_banner
  printf "${WHITE} 💻 Instalando interface do webchat...${GRAY_LIGHT}"
  printf "\n\n"

  # Mapear instâncias existentes
  instances=()
  while IFS= read -r instance; do
    instance_name=$(echo "$instance" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
    fi
    instances+=("$instance_name")
  done < <(find /home/deploycrm -type d -name "crm")

  if [ ${#instances[@]} -eq 0 ]; then
    printf "${RED} ❌ Nenhuma instância crm encontrada!${NC}\n\n"
    return 1
  fi

  # Mostrar instâncias disponíveis
  printf "${WHITE} 📊 Instâncias encontradas:${GRAY_LIGHT}\n\n"
  for i in "${!instances[@]}"; do
    printf "  [$(($i+1))] ${instances[$i]}\n"
  done
  printf "\n"

  # Perguntar qual instância atualizar
  read -p "> Digite o número da instância que deseja instalar o webchat: " instance_number
  if [ "$instance_number" -lt 1 ] || [ "$instance_number" -gt ${#instances[@]} ]; then
    printf "${RED} ❌ Opção inválida!${NC}\n\n"
    return 1
  fi

  selected_instance=${instances[$(($instance_number-1))]}
  
  # Definir o caminho correto da instância
  if [ "$selected_instance" = "primeira_instancia" ]; then
    instance_path="/home/deploycrm/crm"
    nginx_config="crm-webchat"
  else
    instance_path="/home/deploycrm/$selected_instance/crm"
    nginx_config="${selected_instance}-crm-webchat"
  fi

  # Perguntar porta e URL do webchat
  read -p "> Digite a porta do webchat (ex: 3019): " webchat_port
  if [ -z "$webchat_port" ]; then
    printf "${RED} ❌ Porta inválida!${NC}\n\n"
    return 1
  fi

  read -p "> Digite a URL do webchat (ex: chat.seudominio.com): " webchat_url
  if [ -z "$webchat_url" ]; then
    printf "${RED} ❌ URL inválida!${NC}\n\n"
    return 1
  fi

  # Capturar email para o certbot
  read -p "> Digite o email para o certificado SSL: " ssl_email
  if [ -z "$ssl_email" ]; then
    printf "${RED} ❌ Email inválido!${NC}\n\n"
    return 1
  fi

  # Atualizar .env do backend
  env_file="$instance_path/backend/.env"
  if [ -f "$env_file" ]; then
    # Verificar se as variáveis já existem
    if grep -q "WSS_URL=" "$env_file"; then
      sed -i "s|WSS_URL=.*|WSS_URL=https://$webchat_url|" "$env_file"
    else
      echo "WSS_URL=https://$webchat_url" >> "$env_file"
    fi

    if grep -q "WSS_PORT=" "$env_file"; then
      sed -i "s|WSS_PORT=.*|WSS_PORT=$webchat_port|" "$env_file"
    else
      echo "WSS_PORT=$webchat_port" >> "$env_file"
    fi
  else
    printf "${RED} ❌ Arquivo .env não encontrado!${NC}\n\n"
    return 1
  fi

  # Configurar nginx
  sudo su - root <<EOF
  # Remover configuração antiga se existir
  rm -f "/etc/nginx/sites-available/$nginx_config"
  rm -f "/etc/nginx/sites-enabled/$nginx_config"

  # Criar nova configuração
  cat > "/etc/nginx/sites-available/$nginx_config" << 'END'
server {
  server_name $webchat_url;

  location / {
    proxy_pass http://127.0.0.1:$webchat_port;
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

  # Ativar configuração
  ln -sf "/etc/nginx/sites-available/$nginx_config" "/etc/nginx/sites-enabled/"

  # Verificar configuração do nginx
  if ! nginx -t; then
    printf "${RED} ❌ Erro na configuração do nginx!${NC}\n\n"
    exit 1
  fi

  # Reiniciar nginx
  systemctl restart nginx

  # Gerar certificado SSL
  certbot --nginx -d $webchat_url --redirect --non-interactive --agree-tos --email $ssl_email

  # Liberar porta no UFW
  ufw allow $webchat_port/tcp

  # Reiniciar todos os processos PM2
  sudo -u deploycrm pm2 restart all
  printf "${GREEN} ✅ Todos os processos PM2 reiniciados${NC}\n"
EOF

  print_banner
  printf "${GREEN} ✅ Webchat instalado com sucesso!${GRAY_LIGHT}\n\n"
  printf "${WHITE} 📊 Informações da instalação:${GRAY_LIGHT}\n"
  printf "  • Instância: $selected_instance\n"
  printf "  • URL do webchat: https://$webchat_url\n"
  printf "  • Porta do webchat: $webchat_port\n"
  printf "  • Configuração nginx: $nginx_config\n"
  printf "  • Porta liberada no UFW: $webchat_port/tcp\n\n"
  printf "${YELLOW} ⚠️  Lembre-se de atualizar o DNS do domínio para apontar para este servidor${NC}\n\n"

  sleep 2
}
