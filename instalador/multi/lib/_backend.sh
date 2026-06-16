#!/bin/bash
# 
# functions for setting up app backend

#######################################
# creates docker db
# Arguments:
#   None
#######################################
backend_db_create() {
  print_banner
  printf "${WHITE} 💻 Criando banco de dados...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  usermod -aG docker deploycrm
  
  # Parar e remover container existente se houver
  docker stop ${folder_name}-postgresql 2>/dev/null || true
  docker rm ${folder_name}-postgresql 2>/dev/null || true

  # Apagar diretório de dados do PostgreSQL
  rm -rf /var/lib/postgresql/data-${folder_name}
  
  # Criar novo container PostgreSQL
  docker run --name ${folder_name}-postgresql \
                -e POSTGRES_PASSWORD=${pg_pass} \
                -e TZ="America/Tegucigalpa" \
                -p 127.0.0.1:${pg_port}:5432 \
                --restart=always \
                -v /data:/var/lib/postgresql/data-${folder_name} \
                -d postgres \
                -c shared_buffers=256MB \
                -c work_mem=16MB \
                -c effective_cache_size=1GB \
                -c maintenance_work_mem=128MB \
                -c max_connections=200

  # Aguardar o PostgreSQL iniciar
  sleep 5

  # Verificar se o container está rodando
  if ! docker ps | grep -q "${folder_name}-postgresql"; then
    echo "Erro: Container PostgreSQL não está rodando"
    exit 1
  fi

  # Verificar se o usuário foi criado usando a porta correta
  docker exec ${folder_name}-postgresql psql -U postgres -d postgres -c "SELECT 1" | grep -q 1 || echo "Erro: PostgreSQL não está respondendo corretamente"

  docker run --name ${folder_name}-redis-crm \
                -e TZ="America/Tegucigalpa" \
                -p ${redis_port}:6379 \
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

  sleep 2
}

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # Remover arquivo de credenciais existente se houver
  if [ -f "${PROJECT_ROOT}"/db_credentials ]; then
    rm -f "${PROJECT_ROOT}"/db_credentials
  fi

  # Gerar senhas aleatórias
  pg_pass=$(openssl rand -base64 32)
  redis_pass=$(openssl rand -base64 32)

  # Salvar as senhas em um arquivo para reutilização
  cat << EOF > "${PROJECT_ROOT}"/db_credentials
pg_pass=${pg_pass}
redis_pass=${redis_pass}
EOF

  # ensure idempotency + sanitiza CR/whitespace/trailing-;,/aspas — incidente CSP helmet (FRONTEND_URL=https://host;)
  backend_url=$(printf '%s' "${backend_url}" | tr -d '\r\n\t "'\''' | sed -E 's/[[:space:];,]+$//' | sed -E 's/^[[:space:]]+//')
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=$(echo "${backend_url/http:\/\/}")
  backend_url=${backend_url%%/*}
  if [ -z "${backend_url}" ]; then
    printf "\n${RED}❌  BACKEND_URL inválido após sanitização. Abortando configuração do .env.${NC}\n\n"
    log_error "backend_set_env" "backend_url vazio após sanitização (multi)"
    return 1
  fi
  backend_url=https://$backend_url

  frontend_url=$(printf '%s' "${frontend_url}" | tr -d '\r\n\t "'\''' | sed -E 's/[[:space:];,]+$//' | sed -E 's/^[[:space:]]+//')
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=$(echo "${frontend_url/http:\/\/}")
  frontend_url=${frontend_url%%/*}
  if [ -z "${frontend_url}" ]; then
    printf "\n${RED}❌  FRONTEND_URL inválido após sanitização. Abortando configuração do .env.${NC}\n\n"
    log_error "backend_set_env" "frontend_url vazio após sanitização (multi)"
    return 1
  fi
  frontend_url=https://$frontend_url
  
  # Generate dynamic secrets
  jwt_secret=$(openssl rand -base64 32)
  jwt_refresh_secret=$(openssl rand -base64 32)

sudo su - deploycrm << EOF
  cat <<[-]EOF > /home/deploycrm/${folder_name}/crm.io/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
ADMIN_DOMAIN=crm.io

PROXY_PORT=443
PORT=${backend_port}

# conexão com o banco de dados (porta via DB_PORT no .env)
DB_DIALECT=postgres
DB_PORT=${pg_port}
DB_TIMEZONE=-00:00
POSTGRES_HOST=localhost
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=postgres

# Chaves para criptografia do token jwt
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

# Dados de conexão com o REDIS
#IO_REDIS_SERVER=localhost
#IO_REDIS_PASSWORD=${redis_pass}
#IO_REDIS_PORT=${redis_port}
#IO_REDIS_DB_SESSION=2

#CHROME_BIN=/usr/bin/google-chrome
CHROME_BIN=/usr/bin/google-chrome-stable

# tempo para randomização da mensagem de horário de funcionamento
MIN_SLEEP_BUSINESS_HOURS=2500
MAX_SLEEP_BUSINESS_HOURS=5000

# tempo para randomização das mensagens do bot
MIN_SLEEP_AUTO_REPLY=2500
MAX_SLEEP_AUTO_REPLY=5000

# tempo para randomização das mensagens gerais
MIN_SLEEP_INTERVAL=250
MAX_SLEEP_INTERVAL=500

# api oficial (integração em desenvolvimento)
API_URL_360=https://waba-sandbox.360dialog.io

# usado para mosrar opções não disponíveis normalmente.
ADMIN_DOMAIN=crm.io

# Dados para utilização do canal do facebook
FACEBOOK_APP_ID=3237415623048660
FACEBOOK_APP_SECRET_KEY=3266214132b8c98ac59f3e957a5efeaaa13500

# Limitar Uso do crm Usuario e Conexões
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
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/backend
  npm install --force
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
  printf "${WHITE} 💻 Atualizando o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/backend
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
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/backend
  npx sequelize db:migrate
EOF

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/backend
  npx sequelize db:seed:all
EOF

  sleep 2
}

backend_fix_default_users() {

  step_header "👤" "Actualizar usuarios iniciales del CRM" \
    "Cambia los correos por defecto del superadmin y admin del tenantId 1."

  start_spinner "Actualizando usuarios iniciales en PostgreSQL..."

  # Detectar contenedor PostgreSQL
  PG_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^postgresql-crm$|^postgresql$' | head -n 1)

  if [ -z "$PG_CONTAINER" ]; then
    stop_spinner_error "No se encontró contenedor PostgreSQL."
    log_error "postgres-users" "No existe contenedor postgresql-crm ni postgresql activo."
    return 1
  fi

  docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres <<'SQL'
BEGIN;

UPDATE public."Users"
SET
  email = 'superadmin@whatitan.online',
  name = 'Super Administrador',
  profile = 'superadmin',
  "updatedAt" = NOW()
WHERE "tenantId" = 1
  AND profile = 'superadmin';

UPDATE public."Users"
SET
  email = 'admin@whatitan.online',
  name = 'Administrador',
  profile = 'admin',
  "updatedAt" = NOW()
WHERE "tenantId" = 1
  AND profile = 'admin';

COMMIT;

SELECT
  id,
  name,
  email,
  profile,
  "tenantId"
FROM public."Users"
WHERE "tenantId" = 1
ORDER BY id;
SQL

  if [ $? -ne 0 ]; then
    stop_spinner_error "Error actualizando usuarios iniciales."
    log_error "postgres-users" "No se pudieron actualizar los usuarios superadmin/admin."
  else
    stop_spinner "Usuarios iniciales actualizados correctamente."
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
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  cd /home/deploycrm/${folder_name}/crm.io/backend
  pm2 start dist/server.js --name ${folder_name}-crm-backend --node-args="--max-old-space-size=2048"
  pm2 save
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_hostname=$(echo "${backend_url/https:\/\/}")

sudo su - root << EOF

cat > /etc/nginx/sites-available/${folder_name}-crm-backend << 'END'
server {
  server_name $backend_hostname;

  location / {
    proxy_pass http://127.0.0.1:${backend_port};
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

ln -s /etc/nginx/sites-available/${folder_name}-crm-backend /etc/nginx/sites-enabled
EOF

  sleep 2
}

#######################################
# recria o Redis para todas as instalações
# Arguments:
#   None
#######################################
recreate_redis() {
  print_banner
  printf "${WHITE} 💻 Recriando Redis para todas as instalações...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  # Encontrar todas as instâncias crm.io dentro de /home/deploycrm
  find /home/deploycrm -type d -name "crm.io" | while read -r instance_path; do
    # Extrair nome da instância do caminho
    instance_name=$(echo "$instance_path" | grep -oP '(?<=/home/deploycrm/)[^/]+(?=/crm\.io)')
    if [ -z "$instance_name" ]; then
      instance_name="primeira_instancia"
      container_name="redis-crm"
    else
      container_name="$instance_name-redis-crm"
    fi
    
    # Verificar se existe arquivo .env no backend
    env_file="$instance_path/backend/.env"
    if [ -f "$env_file" ]; then
      # Extrair configurações do Redis
      redis_port=$(grep "IO_REDIS_PORT=" "$env_file" | cut -d'=' -f2)
      redis_pass=$(grep "IO_REDIS_PASSWORD=" "$env_file" | cut -d'=' -f2)
      
      if [ ! -z "$redis_port" ] && [ ! -z "$redis_pass" ]; then
        # Parar e remover container existente se houver
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
        
        # Criar novo container Redis
        docker run --name "$container_name" \
          -e TZ="America/Tegucigalpa" \
          -p "$redis_port:6379" \
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
          --requirepass "$redis_pass"
          
        printf "${GREEN} ✅ Redis recriado para a instância $instance_name na porta $redis_port${NC}\n"
      else
        printf "${YELLOW} ⚠️  Configurações do Redis não encontradas para a instância $instance_name${NC}\n"
      fi
    fi
  done
EOF

  sleep 2
}
