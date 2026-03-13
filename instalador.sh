#!/bin/bash

GREEN='\033[1;32m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ARQUIVO_ETAPAS="ETAPA_INSTALACAO"
FFMPEG="$(pwd)/ffmpeg.x"
FFMPEG_DIR="$(pwd)/ffmpeg"
ip_atual=$(curl -s http://checkip.amazonaws.com)
jwt_secret=$(openssl rand -base64 32)
jwt_refresh_secret=$(openssl rand -base64 32)

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script debe ejecutarse como root ${RED} o con privilegios de superusuario${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

banner() {
  printf " ${BLUE}"
  printf "\n\n"
  printf "             🚀 BIENVENIDO A WHATICKET CRM 360 🚀                        \n"
  printf "\n\n"
  printf "  ██╗    ██╗██╗  ██╗ █████╗ ████████╗██╗ ██████╗██╗  ██╗███████╗████████╗ \n"
  printf "  ██║    ██║██║  ██║██╔══██╗╚══██╔══╝██║██╔════╝██║ ██╔╝██╔════╝╚══██╔══╝ \n"
  printf "  ██║ █╗ ██║███████║███████║   ██║   ██║██║     █████╔╝ █████╗     ██║    \n"
  printf "  ██║███╗██║██╔══██║██╔══██║   ██║   ██║██║     ██╔═██╗ ██╔══╝     ██║    \n"
  printf "  ╚███╔███╔╝██║  ██║██║  ██║   ██║   ██║╚██████╗██║  ██╗███████╗   ██║    \n"
  printf "   ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝    \n"
  printf "\n\n"
  printf "                    🔥 Whaticket CRM 360                                  \n"
  printf "                        +50489520312                                      \n"
  printf "                 https://marcablancasaas.store                            \n"
  printf "\n\n"
}

# Función para manejar errores y finalizar el script.
trata_erro() {
  printf "${RED}Error encontrado en el paso $1. Terminando el script.${WHITE}\n"
  salvar_etapa "$1"
  exit 1
}

# Guardar variables
salvar_variaveis() {
  echo "subdominio_backend=${subdominio_backend}" >$ARQUIVO_VARIAVEIS
  echo "subdominio_frontend=${subdominio_frontend}" >>$ARQUIVO_VARIAVEIS
  echo "email_deploy=${email_deploy}" >>$ARQUIVO_VARIAVEIS
  echo "empresa=${empresa}" >>$ARQUIVO_VARIAVEIS
  echo "senha_deploy=${senha_deploy}" >>$ARQUIVO_VARIAVEIS
  echo "subdominio_perfex=${subdominio_perfex}" >>$ARQUIVO_VARIAVEIS
  echo "senha_master=${senha_master}" >>$ARQUIVO_VARIAVEIS
  echo "nome_titulo=${nome_titulo}" >>$ARQUIVO_VARIAVEIS
  echo "numero_suporte=${numero_suporte}" >>$ARQUIVO_VARIAVEIS
  echo "facebook_app_id=${facebook_app_id}" >>$ARQUIVO_VARIAVEIS
  echo "facebook_app_secret=${facebook_app_secret}" >>$ARQUIVO_VARIAVEIS
  echo "github_token=${github_token}" >>$ARQUIVO_VARIAVEIS
  echo "repo_url=${repo_url}" >>$ARQUIVO_VARIAVEIS
  echo "proxy=${proxy}" >>$ARQUIVO_VARIAVEIS
  echo "backend_port=${backend_port}" >>$ARQUIVO_VARIAVEIS
  echo "frontend_port=${frontend_port}" >>$ARQUIVO_VARIAVEIS
}

# Cargar variables
carregar_variaveis() {
  if [ -f $ARQUIVO_VARIAVEIS ]; then
    source $ARQUIVO_VARIAVEIS
  else
    empresa="CRMWHATSAPP"
    nome_titulo="CRMWHATSAPP"
  fi
}

# Guardar paso completado
salvar_etapa() {
  echo "$1" >$ARQUIVO_ETAPAS
}

# Cargar el último paso
carregar_etapa() {
  if [ -f $ARQUIVO_ETAPAS ]; then
    etapa=$(cat $ARQUIVO_ETAPAS)
    if [ -z "$etapa" ]; then
      etapa="0"
    fi
  else
    etapa="0"
  fi
}

# Restablecer pasos y variables
resetar_instalacao() {
  rm -f $ARQUIVO_VARIAVEIS $ARQUIVO_ETAPAS
  printf "${GREEN} >> ¡Reinicio de instalación! Comenzando una nueva instalación...${WHITE}\n"
  sleep 2
  instalacao_base
}

# Pregunta si quieres continuar la tarea nuevamente.
verificar_arquivos_existentes() {
  if [ -f $ARQUIVO_VARIAVEIS ] && [ -f $ARQUIVO_ETAPAS ]; then
    banner
    printf "${YELLOW} >> Datos de instalación anteriores detectados.\n"
    echo
    carregar_etapa
    if [ "$etapa" -eq 21 ]; then
      printf "${WHITE}>> Instalación ya completada.\n"
      printf "${WHITE}>> ¿Quieres restablecer los pasos y empezar desde cero? (S/N): ${WHITE}\n"
      echo
      read -p "> " reset_escolha
      echo
      reset_escolha=$(echo "${reset_escolha}" | tr '[:lower:]' '[:upper:]')
      if [ "$reset_escolha" == "S" ]; then
        resetar_instalacao
      else
        printf "${GREEN} >> Volviendo al menú principal...${WHITE}\n"
        sleep 2
        menu
      fi
    elif [ "$etapa" -lt 21 ]; then
      printf "${YELLOW} >> Instalación incompleta detectada en el paso $etapa. \n"
      printf "${WHITE} >> ¿Quieres continuar donde lo dejaste? (S/N): ${WHITE}\n"
      echo
      read -p "> " escolha
      echo
      escolha=$(echo "${escolha}" | tr '[:lower:]' '[:upper:]')
      if [ "$escolha" == "S" ]; then
        instalacao_base
      else
        printf "${GREEN} >> Volviendo al menú principal...${WHITE}\n"
        printf "${WHITE} >> Si desea restablecer los pasos, elimine los archivos ETAPAS_INSTALAÇÃO de la carpeta raíz...${WHITE}\n"
        sleep 5
        menu
      fi
    fi
  else
    instalacao_base
  fi
}

# Menu principal
menu() {
  while true; do
    banner
    printf "${WHITE} Seleccione la opción deseada a continuación: \n"
    echo
    printf "   [${BLUE}1${WHITE}] Instalar ${nome_titulo}\n"
    printf "   [${BLUE}2${WHITE}] Actualizar ${nome_titulo}\n"
    printf "   [${BLUE}0${WHITE}] Salir\n"
    echo
    read -p "> " option
    case "${option}" in
    1)
      verificar_arquivos_existentes
      ;;
    2)
      atualizar_base
      ;;
    0)
      sair
      ;;
    *)
      printf "${RED}Opción no válida. Intentar otra vez.${WHITE}"
      sleep 2
      ;;
    esac
  done
}

# Paso de instalación
instalacao_base() {
  carregar_etapa
  if [ "$etapa" == "0" ]; then
    questoes_dns_base || trata_erro "questoes_dns_base"
    verificar_dns_base || trata_erro "verificar_dns_base"
    questoes_variaveis_base || trata_erro "questoes_variaveis_base"
    define_proxy_base || trata_erro "define_proxy_base"
    define_portas_base || trata_erro "define_portas_base"
    confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
    salvar_variaveis || trata_erro "salvar_variaveis"
    salvar_etapa 1
  fi
  if [ "$etapa" -le "1" ]; then
    atualiza_vps_base || trata_erro "atualiza_vps_base"
    salvar_etapa 2
  fi
  if [ "$etapa" -le "2" ]; then
    cria_deploy_base || trata_erro "cria_deploy_base"
    salvar_etapa 3
  fi
  if [ "$etapa" -le "3" ]; then
    config_timezone_base || trata_erro "config_timezone_base"
    salvar_etapa 4
  fi
  if [ "$etapa" -le "4" ]; then
    config_firewall_base || trata_erro "config_firewall_base"
    salvar_etapa 5
  fi
  if [ "$etapa" -le "5" ]; then
    instala_puppeteer_base || trata_erro "instala_puppeteer_base"
    salvar_etapa 6
  fi
  if [ "$etapa" -le "6" ]; then
    instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
    salvar_etapa 7
  fi
  if [ "$etapa" -le "7" ]; then
    instala_postgres_base || trata_erro "instala_postgres_base"
    salvar_etapa 8
  fi
  if [ "$etapa" -le "8" ]; then
    instala_node_base || trata_erro "instala_node_base"
    salvar_etapa 9
  fi
  if [ "$etapa" -le "9" ]; then
    instala_redis_base || trata_erro "instala_redis_base"
    salvar_etapa 10
  fi
  if [ "$etapa" -le "10" ]; then
    instala_pm2_base || trata_erro "instala_pm2_base"
    salvar_etapa 11
  fi
  if [ "$etapa" -le "11" ]; then
    if [ "${proxy}" == "nginx" ]; then
      instala_nginx_base || trata_erro "instala_nginx_base"
      salvar_etapa 12
    elif [ "${proxy}" == "traefik" ]; then
      instala_traefik_base || trata_erro "instala_traefik_base"
      salvar_etapa 12
    fi
  fi
  if [ "$etapa" -le "12" ]; then
    cria_banco_base || trata_erro "cria_banco_base"
    salvar_etapa 13
  fi
  if [ "$etapa" -le "13" ]; then
    instala_git_base || trata_erro "instala_git_base"
    salvar_etapa 14
  fi
  if [ "$etapa" -le "14" ]; then
    codifica_clone_base || trata_erro "codifica_clone_base"
    baixa_codigo_base || trata_erro "baixa_codigo_base"
    salvar_etapa 15
  fi
  if [ "$etapa" -le "15" ]; then
    instala_backend_base || trata_erro "instala_backend_base"
    salvar_etapa 16
  fi
  if [ "$etapa" -le "16" ]; then
    instala_frontend_base || trata_erro "instala_frontend_base"
    salvar_etapa 17
  fi
  if [ "$etapa" -le "17" ]; then
    config_cron_base || trata_erro "config_cron_base"
    salvar_etapa 18
  fi
  if [ "$etapa" -le "18" ]; then
    if [ "${proxy}" == "nginx" ]; then
      config_nginx_base || trata_erro "config_nginx_base"
      salvar_etapa 19
    elif [ "${proxy}" == "traefik" ]; then
      config_traefik_base || trata_erro "config_traefik_base"
      salvar_etapa 19
    fi
  fi
  if [ "$etapa" -le "19" ]; then
    config_latencia_base || trata_erro "config_latencia_base"
    salvar_etapa 20
  fi
  if [ "$etapa" -le "20" ]; then
    fim_instalacao_base || trata_erro "fim_instalacao_base"
    salvar_etapa 21
  fi
}

# Paso de instalación
atualizar_base() {
  backup_app_atualizar || trata_erro "backup_app_atualizar"
  instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
  config_cron_base || trata_erro "config_cron_base"
  baixa_codigo_atualizar || trata_erro "baixa_codigo_atualizar"
}

sair() {
  exit 0
}

################################################################
#                         INSTALAÇÃO                           #
################################################################

# Preguntas basicas
questoes_dns_base() {
  # URL de fondo de las tiendas
  banner
  printf "${WHITE} >> Ingrese la URL del dominio Backend Ejemplo https://api.dominio.com: \n"
  echo
  read -p "> " subdominio_backend
  echo
  # URL frontal de las tiendas
  banner
  printf "${WHITE} >> Ingrese la URL del dominio Frontend Ejemplo https://app.dominio.com: \n"
  echo
  read -p "> " subdominio_frontend
  echo
}

# Validar si el dominio o subdominio apunta a la IP del VPS
verificar_dns_base() {
  banner
  printf "${WHITE} >> Comprobar el DNS de dominios/subdominios...\n"
  echo
  sleep 2
  sudo apt-get install dnsutils -y >/dev/null 2>&1
  subdominios_incorretos=""

  verificar_dns() {
    local domain=$1
    local resolved_ip
    local cname_target

    cname_target=$(dig +short CNAME ${domain})

    if [ -n "${cname_target}" ]; then
      resolved_ip=$(dig +short ${cname_target})
    else
      resolved_ip=$(dig +short ${domain})
    fi

    if [ "${resolved_ip}" != "${ip_atual}" ]; then
      echo "el dominio ${domain} (resuelto a ${resolved_ip}) no apunta a la IP pública actual (${ip_atual})."
      subdominios_incorretos+="${domain} "
      sleep 2
    fi
  }

  verificar_dns ${subdominio_backend}
  verificar_dns ${subdominio_frontend}

  if [ -n "${subdominios_incorretos}" ]; then
    echo
    echo "Verifique las entradas DNS para los siguientes subdominios: ${subdominios_incorretos}"
    echo
    while true; do
      echo "¿Quieres continuar de todos modos, si esta seguro que sus sub dominios y dominios si estan apuntando correctamente puede continuar, es posible que solo sus subdominios apunten al servidor pero por decision propia el dominio principal no apunta a la IP y por eso no se detectan correctamente.?"
      echo "1) Sí"
      echo "2) No"
      read -p "Elige una opción: " escolha

      case $escolha in
        1)
          echo "Elegiste continuar."
          sleep 2
          break
          ;;
        2)
          echo "Decidiste no continuar. El proceso se detendrá."
          sleep 2
          menu
          return 0
          ;;
        *)
          echo "Opción no válida. Por favor elige 1 o 2."
          ;;
      esac
    done
  else
    echo "Todos los subdominios apuntan correctamente a la IP pública del VPS.."
    sleep 2
  fi

  echo
  printf "${WHITE} >> Continuar...\n"
  sleep 2
  echo
}

questoes_variaveis_base() {
  # ESTABLECER CORREO ELECTRÓNICO
  banner
  printf "${WHITE} >> Introduce un correo electrónico valido para SSL: \n"
  echo
  read -p "> " email_deploy
  echo
  # DEFINIR NOMBRE DE LA EMPRESA
  banner
  printf "${WHITE} >> Ingrese el nombre de su empresa (letras minúsculas y sin espacios): \n"
  echo
  read -p "> " empresa
  echo
  # ESTABLECER CONTRASEÑA BASE
  banner
  printf "${WHITE} >> Ingrese la contraseña para el usuario deploy, Redis y Base de datos ${RED}IMPORTANTE${WHITE}: No utilices caracteres especiales.\n"
  echo
  read -p "> " senha_deploy
  echo
  # URL de fondo de las tiendas
  banner
  printf "${WHITE} >> Introduzca la URL de PerfexCRM: \n"
  echo
  read -p "> " subdominio_perfex
  echo
  # ESTABLECER CONTRASEÑA MAESTRA
  banner
  printf "${WHITE} >> Introduzca la contraseña para el MASTER: \n"
  echo
  read -p "> " senha_master
  echo
  # CONFIGURAR EL TÍTULO DE LA APLICACIÓN EN EL NAVEGADOR
  banner
  printf "${WHITE} >> Ingrese el nombre de la aplicacion (espacio permitido): \n"
  echo
  read -p "> " nome_titulo
  echo
  # CONFIGURAR SOPORTE PARA TELÉFONO
  banner
  printf "${WHITE} >> Ingrese el número de teléfono de soporte: \n"
  echo
  read -p "> " numero_suporte
  echo
  # DEFINIR FACEBOOK_APP_ID
  banner
  printf "${WHITE} >> Introduzca el FACEBOOK_APP_ID si tienes: \n"
  echo
  read -p "> " facebook_app_id
  echo
  # DEFINIR FACEBOOK_APP_SECRET
  banner
  printf "${WHITE} >> Introduzca el FACEBOOK_APP_SECRET si tienes: \n"
  echo
  read -p "> " facebook_app_secret
  echo
  # DEFINIR TOKEN DE GITHUB
  banner
  printf "${WHITE} >> Introduce tu TOKEN acceso personalo GitHub: \n"
  printf "${WHITE} >> Paso a paso para generar tu TOKEN da clic en el link ${BLUE}https://bit.ly/token-github ${WHITE} \n"
  echo
  read -p "> " github_token
  echo
  # DEFINIR ENLACE DE REPO DE GITHUB
  banner
  printf "${WHITE} >> Introduzca el URL desde el repositorio privado en GitHub: \n"
  echo
  read -p "> " repo_url
  echo
}

# Define el proxy utilizado
define_proxy_base() {
  banner
  while true; do
    printf "${WHITE} >> Instalar usando Nginx o Traefik? (Nginx/Traefik): ${WHITE}\n"
    echo
    read -p "> " proxy
    echo
    proxy=$(echo "${proxy}" | tr '[:upper:]' '[:lower:]')

    if [ "${proxy}" = "nginx" ] || [ "${proxy}" = "traefik" ]; then
      sleep 2
      break
    else
      printf "${RED} >> Por favor ingresa 'Nginx' o 'Traefik' continuar... ${WHITE}\n"
      echo
    fi
  done
  export proxy
}

# Define los puertos backend y frontend
define_portas_base() {
  banner
  printf "${WHITE} >> Usar puertos predeterminados para Backend (8080) y Frontend (3000) ? (S/N) si seran puertos diferentes ingrese N: ${WHITE}\n"
  echo
  read -p "> " use_default_ports
  use_default_ports=$(echo "${use_default_ports}" | tr '[:upper:]' '[:lower:]')
  echo

  default_backend_port=8080
  default_frontend_port=3000

  if [ "${use_default_ports}" = "s" ]; then
    backend_port=${default_backend_port}
    frontend_port=${default_frontend_port}
  else
    while true; do
      printf "${WHITE} >> ¿Qué puerto desea para el Backend? ${WHITE}\n"
      echo
      read -p "> " backend_port
      echo
      if ! lsof -i:${backend_port} &>/dev/null; then
        break
      else
        printf "${RED} >> El puerto ${backend_port} ya está en uso. Por favor elige otro.${WHITE}\n"
        echo
      fi
    done

    while true; do
      printf "${WHITE} >> ¿Qué puerto desea para el Frontend? ${WHITE}\n"
      echo
      read -p "> " frontend_port
      echo
      if ! lsof -i:${frontend_port} &>/dev/null; then
        break
      else
        printf "${RED} >> El puerto ${frontend_port} ya está en uso. Por favor elige otro.${WHITE}\n"
        echo
      fi
    done
  fi

  sleep 2
}

# Proporciona datos de instalación.
dados_instalacao_base() {
  printf "   ${WHITE}Anota los datos a continuación\n\n"
  printf "   ${WHITE}Subdominio Backend: ---->> ${YELLOW}${subdominio_backend}\n"
  printf "   ${WHITE}Subdominiio Frontend: -->> ${YELLOW}${subdominio_frontend}\n"
  printf "   ${WHITE}Su Email: ------------->> ${YELLOW}${email_deploy}\n"
  printf "   ${WHITE}Nombre de Empresa: ------->> ${YELLOW}${empresa}\n"
  printf "   ${WHITE}Contraseña Deploy: ---------->> ${YELLOW}${senha_deploy}\n"
  printf "   ${WHITE}Subdominio Perfex: ----->> ${YELLOW}${subdominio_perfex}\n"
  printf "   ${WHITE}Contraseña Master: ---------->> ${YELLOW}${senha_master}\n"
  printf "   ${WHITE}Título de la solicitud: --->> ${YELLOW}${nome_titulo}\n"
  printf "   ${WHITE}Número de soporte: ----->> ${YELLOW}${numero_suporte}\n"
  printf "   ${WHITE}FACEBOOK_APP_ID: ------->> ${YELLOW}${facebook_app_id}\n"
  printf "   ${WHITE}FACEBOOK_APP_SECRET: --->> ${YELLOW}${facebook_app_secret}\n"
  printf "   ${WHITE}Token GitHub: ---------->> ${YELLOW}${github_token}\n"
  printf "   ${WHITE}URL del repositorio: ---->> ${YELLOW}${repo_url}\n"
  printf "   ${WHITE}Proxy Usado: ----------->> ${YELLOW}${proxy}\n"
  printf "   ${WHITE}Porta Backend: --------->> ${YELLOW}${backend_port}\n"
  printf "   ${WHITE}Porta Frontend: -------->> ${YELLOW}${frontend_port}\n"
}

# Confirmar datos de instalación
confirma_dados_instalacao_base() {
  printf " >> Consulta los detalles de esta instalación a continuación! \n"
  echo
  dados_instalacao_base
  echo
  printf "${WHITE} >> los datos son correctos? ${GREEN}S/${RED}N:${WHITE} \n"
  echo
  read -p "> " confirmacao
  echo
  confirmacao=$(echo "${confirmacao}" | tr '[:lower:]' '[:upper:]')
  if [ "${confirmacao}" == "S" ]; then
    printf "${GREEN} >> Continuando con la instalación... ${WHITE} \n"
    echo
  else
    printf "${GREEN} >> Volver al menú principal... ${WHITE} \n"
    echo
    sleep 2
    menu
  fi
}

# Actualizar sistema operativo
atualiza_vps_base() {
  UPDATE_FILE="$(pwd)/update.x"
  {
    sudo DEBIAN_FRONTEND=noninteractive apt update -y && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo DEBIAN_FRONTEND=noninteractive apt-get install build-essential -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils
    touch "${UPDATE_FILE}"
    sleep 2
  } || trata_erro "atualiza_vps_base"
}

# Crear usuario de implementación
cria_deploy_base() {
  banner
  printf "${WHITE} >> Ahora vamos a crear el usuario para deploy...\n"
  echo
  {
    sudo useradd -m -p $(openssl passwd -1 ${senha_deploy}) -s /bin/bash -G sudo deploy
    sudo usermod -aG sudo deploy
    sleep 2
  } || trata_erro "cria_deploy_base"
}

# Configurar zona horaria
config_timezone_base() {
  banner
  printf "${WHITE} >> Configurando Timezone...\n"
  echo "Escoge tu zona horaria aquí: https://www.zeitverschiebung.net/es"
  echo "Por ejemplo: America/Mexico_City"
  read -p "Introduce la zona horaria deseada (o presiona Enter para usar America/Mexico_City): " timezone

  # Si el usuario no introduce nada, usar valor por defecto
  timezone=${timezone:-America/Mexico_City}

  {
    sudo su - root <<EOF
  timedatectl set-timezone $timezone
EOF
    sleep 2
  } || trata_erro "config_timezone_base"
  
  echo "Zona horaria configurada a $timezone."
}


# Configurar firewall
config_firewall_base() {
  banner
  printf "${WHITE} >> Configurando el firewall Puertos 80 e 443...\n"
  echo
  {
    if [ "${ARCH}" = "x86_64" ]; then
      sudo su - root <<EOF >/dev/null 2>&1
  ufw allow 80/tcp && ufw allow 22/tcp && ufw allow 443/tcp
EOF
      sleep 2

    elif [ "${ARCH}" = "aarch64" ]; then
      sudo su - root <<EOF >/dev/null 2>&1
  sudo iptables -F &&
  sudo iptables -A INPUT -i lo -j ACCEPT &&
  sudo iptables -A OUTPUT -o lo -j ACCEPT &&
  sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT &&
  sudo iptables -A INPUT -p udp --dport 80 -j ACCEPT &&
  sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT &&
  sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT &&
  sudo service netfilter-persistent save
EOF
      sleep 2

    else
      echo "Arquitectura no compatible."
    fi
  } || trata_erro "config_firewall_base"
}

# Instalar la dependencia del titiritero
instala_puppeteer_base() {
  banner
  printf "${WHITE} >> Instalación de dependencias de puppeteer...\n"
  echo
  {
    sudo su - root <<EOF
apt-get install -y libaom-dev libass-dev libfreetype6-dev libfribidi-dev \
                   libharfbuzz-dev libgme-dev libgsm1-dev libmp3lame-dev \
                   libopencore-amrnb-dev libopencore-amrwb-dev libopenmpt-dev \
                   libopus-dev libfdk-aac-dev librubberband-dev libspeex-dev \
                   libssh-dev libtheora-dev libvidstab-dev libvo-amrwbenc-dev \
                   libvorbis-dev libvpx-dev libwebp-dev libx264-dev libx265-dev \
                   libxvidcore-dev libzmq3-dev libsdl2-dev build-essential \
                   yasm cmake libtool libc6 libc6-dev unzip wget pkg-config texinfo zlib1g-dev \
                   libxshmfence-dev libgcc1 libgbm-dev fontconfig locales gconf-service libasound2 \
                   libatk1.0-0 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc-s1 \
                   libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 \
                   libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
                   libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
                   libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 \
                   lsb-release xdg-utils

if grep -q "20.04" /etc/os-release; then
    apt-get install -y libsrt-dev
else
    apt-get install -y libsrt-openssl-dev
fi

EOF
    sleep 2
  } || trata_erro "instala_puppeteer_base"
}

# Instalar FFMPEG 6.1 de forma robusta
instala_ffmpeg_base() {
  banner
  printf "${WHITE} >> Instalación FFMPEG 6.1...\n\n"

  # Verificar si ya está instalado
  if [ -f "${FFMPEG}" ]; then
    printf " >> FFMPEG ya ha sido instalado. Continuando con la instalación...\n"
    return
  fi

  # Actualizar repositorios e instalar versión base de Ubuntu (dependencias)
  sudo apt update
  sudo apt install ffmpeg -y >/dev/null 2>&1

  # Comprobar arquitectura
  if [ "${ARCH}" = "x86_64" ]; then
    FFMPEG_FILE="ffmpeg-n6.1-latest-linux64-gpl-6.1.tar.xz"
  elif [ "${ARCH}" = "aarch64" ]; then
    FFMPEG_FILE="ffmpeg-n6.1-latest-linuxarm64-gpl-6.1.tar.xz"
  else
    printf "${RED} >> Arquitectura no compatible: ${ARCH}${WHITE}\n"
    exit 1
  fi

  # Descargar FFMPEG 6.1 desde GitHub
  URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${FFMPEG_FILE}"
  wget -q --show-progress "${URL}" -O "${FFMPEG_FILE}"
  if [ $? -ne 0 ]; then
    printf "${RED} >> No se pudo descargar FFMPEG automáticamente. Descarga manualmente desde:\n${URL}${WHITE}\n"
    exit 1
  fi

  # Extraer y copiar binarios
  mkdir -p "${FFMPEG_DIR}"
  tar -xf "${FFMPEG_FILE}" -C "${FFMPEG_DIR}" --strip-components=1
  sudo cp -f "${FFMPEG_DIR}/bin/ffmpeg" /usr/bin/
  sudo cp -f "${FFMPEG_DIR}/bin/ffprobe" /usr/bin/
  sudo cp -f "${FFMPEG_DIR}/bin/ffplay" /usr/bin/

  # Limpiar archivos temporales
  rm -rf "${FFMPEG_DIR}" "${FFMPEG_FILE}"

  # Marcar como instalado
  touch "${FFMPEG}"

  # Verificar versión instalada
  INSTALLED_VERSION=$(ffmpeg -version | head -n1)
  printf "${GREEN} >> FFMPEG instalado correctamente: ${INSTALLED_VERSION}${WHITE}\n"
}

# Instalar PostgreSQL 15
instala_postgres_base() {
  banner
  printf "${WHITE} >> Instalación PostgreSQL 15...\n"
  echo

  # Instalar dependencias y agregar repositorio oficial
  sudo apt-get install -y gnupg wget lsb-release
  sudo sh -c "echo 'deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
  wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

  # Actualizar repos y instalar PostgreSQL
  sudo apt-get update -y
  sudo apt-get install -y postgresql-15 postgresql-client-15 postgresql-contrib-15

  # Iniciar el servicio y habilitarlo
  sudo systemctl enable postgresql
  sudo systemctl start postgresql

  printf "${GREEN} >> PostgreSQL 15 instalado correctamente.${WHITE}\n"
}

# Instalar NodeJS
instala_node_base() {
  banner
  printf "${WHITE} >> Instalando nodejs...\n"
  echo
  {
    sudo su - root <<EOF
  curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
  sudo sh -c "echo deb https://deb.nodesource.com/node_20.x focal main \
  > /etc/apt/sources.list.d/nodesource.list"
  sudo apt-get update && apt-get install nodejs -y
EOF
    sleep 2
  } || trata_erro "instala_node_base"
}

# Instalar Redis
instala_redis_base() {
  {
    sudo su - root <<EOF
  apt install redis-server -y
  systemctl enable redis-server.service
  sed -i 's/# requirepass foobared/requirepass ${senha_deploy}/g' /etc/redis/redis.conf
  sed -i 's/^appendonly no/appendonly yes/g' /etc/redis/redis.conf
  systemctl restart redis-server.service
EOF
    sleep 2
  } || trata_erro "instala_redis_base"
}

# Instalar PM2
instala_pm2_base() {
  banner
  printf "${WHITE} >> Instalando pm2...\n"
  echo
  {
    sudo su - root <<EOF
  npm install -g pm2
  pm2 startup ubuntu -u deploy
  env PATH=\${PATH}:/usr/bin pm2 startup ubuntu -u deploy --hp /home/deploy
EOF
    sleep 2
  } || trata_erro "instala_pm2_base"
}

# Instalar Nginx y dependencias
instala_nginx_base() {
  banner
  printf "${WHITE} >> Instalando Nginx...\n"
  echo
  {
    sudo su - root <<EOF
    apt install -y nginx
    rm /etc/nginx/sites-enabled/default
EOF

  sleep 2

echo "¿Es esta la primera instalación o ya existe una instalación previa?"
echo "1) Sí, es la primera instalación"
echo "2) No, esta es una instalación adicional"
read -p "Seleccione una opción (1 o 2): " instalacion

if [ "$instalacion" -eq 1 ]; then
    # Si es la primera instalación, ejecuta el siguiente bloque de configuración
    sleep 2
    sudo su - root <<EOF
echo 'client_max_body_size 100M;' > /etc/nginx/conf.d/${empresa}.conf
EOF
    echo "Configuración de Nginx aplicada."
else
    echo "Configuración de Nginx omitida para instalación adicional."
fi

    sleep 2

    sudo su - root <<EOF
  service nginx restart
EOF

    sleep 2

    sudo su - root <<EOF
  apt install -y snapd
  snap install core
  snap refresh core
EOF

    sleep 2

    sudo su - root <<EOF
  apt-get remove certbot
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
EOF

    sleep 2
  } || trata_erro "instala_nginx_base"
}

# Instalar Traefik
instala_traefik_base() {
  useradd --system --shell /bin/false --user-group --no-create-home traefik
  cd /tmp
  mkdir traefik
  cd traefik/
  if [ "${ARCH}" = "x86_64" ]; then
    traefik_arch="amd64"
  elif [ "${ARCH}" = "aarch64" ]; then
    traefik_arch="arm64"
  else
    echo "Arquitectura no compatible: ${ARCH}"
    exit 1
  fi
  traefik_url="https://github.com/traefik/traefik/releases/download/v2.10.5/traefik_v2.10.5_linux_${traefik_arch}.tar.gz"
  curl --remote-name --location "${traefik_url}"
  tar -zxf traefik_v2.10.5_linux_${traefik_arch}.tar.gz
  cp traefik /usr/local/bin/traefik
  chmod a+x /usr/local/bin/traefik
  cd ..
  rm -rf traefik
  mkdir --parents /etc/traefik
  mkdir --parents /etc/traefik/conf.d

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.toml << 'END'
################################################################
# Global configuration
################################################################
[global]
  checkNewVersion = "false"
  sendAnonymousUsage = "true"

################################################################
# Entrypoints configuration
################################################################
[entryPoints]
  [entryPoints.websecure]
    address = ":443"
  [entryPoints.web]
    address = ":80"

################################################################
# CertificatesResolvers configuration for Let's Encrypt
################################################################
[certificatesResolvers.letsencryptresolver.acme]
  email = "${email_deploy}"
  storage = "/etc/traefik/acme.json"
  [certificatesResolvers.letsencryptresolver.acme.httpChallenge]
    # Define the entrypoint which will receive the HTTP challenge
    entryPoint = "web"

################################################################
# Log configuration
################################################################
[log]
  level = "INFO"
  format = "json"
  filePath = "/var/log/traefik/traefik.log"

################################################################
# Access Log configuration
################################################################
[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "common"

################################################################
# API and Dashboard configuration
################################################################
[api]
  dashboard = false
  insecure = false
  # [entryPoints.dashboard]
  #   address = ":9090"

################################################################
# Providers configuration
################################################################
# Since the original setup was intended for Docker and this setup is for systemd,
# we don't use Docker provider settings but we keep file provider.
[providers]
  [providers.file]
    directory = "/etc/traefik/conf.d/"
    watch = "true"
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.service << 'END'
# Systemd Traefik service
[Unit]
Description=Traefik - Proxy
Documentation=https://docs.traefik.io
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
AssertFileIsExecutable=/usr/local/bin/traefik
AssertPathExists=/etc/traefik/traefik.toml
#RequiresMountsFor=/var/log

[Service]
User=traefik
AmbientCapabilities=CAP_NET_BIND_SERVICE
Type=notify
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.toml
Restart=always
WatchdogSec=2s

LogsDirectory=traefik

[Install]
WantedBy=multi-user.target
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/conf.d/tls.toml << 'END'
[tls.options]
  [tls.options.default]
    sniStrict = true
    minVersion = "VersionTLS12"
END
EOF
  sleep 2

  cp /etc/traefik/traefik.service /etc/systemd/system/
  chown -R traefik:traefik /etc/traefik/
  rm -rf /etc/traefik/traefik.service
  systemctl daemon-reload
  sleep 2
  systemctl enable --now traefik.service
  sleep 2
}

# Crear base de datos y usuario de la aplicación
cria_banco_base() {
  banner
  printf "${WHITE} >> Creando base de datos y usuario en PostgreSQL...\n"
  echo

  # Ejecutar comandos SQL como usuario postgres
  sudo -i -u postgres psql <<EOF
CREATE USER ${empresa} WITH SUPERUSER INHERIT CREATEDB CREATEROLE PASSWORD '${senha_deploy}';
CREATE DATABASE ${empresa} OWNER ${empresa};
\q
EOF

  printf "${GREEN} >> Base de datos y usuario creados correctamente.${WHITE}\n"
}

# Instalar Git
instala_git_base() {
  banner
  printf "${WHITE} >> Instalando o GIT...\n"
  echo
  {
    sudo su - root <<EOF
  apt install -y git
  apt -y autoremove
EOF
    sleep 2
  } || trata_erro "instala_git_base"
}

# Função para codificar URL de clone
codifica_clone_base() {
  local length="${#1}"
  for ((i = 0; i < length; i++)); do
    local c="${1:i:1}"
    case $c in
    [a-zA-Z0-9.~_-]) printf "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Clona código de repositorio privado
baixa_codigo_base() {
  banner
  printf "${WHITE} >> Descargando el ${nome_titulo}...\n"
  echo
  {
    if [ -z "${repo_url}" ] || [ -z "${github_token}" ]; then
      printf "${WHITE} >> Error: URL del repositorio o token de GitHub no definido.\n"
      exit 1
    fi

    github_token_encoded=$(codifica_clone_base "${github_token}")
    github_url=$(echo ${repo_url} | sed "s|https://|https://${github_token_encoded}@|")

    dest_dir="/home/deploy/${empresa}/"

    git clone ${github_url} ${dest_dir}
    echo
    if [ $? -eq 0 ]; then
      printf "${WHITE} >> Código descargado, continuando la instalación....\n"
      echo
    else
      printf "${WHITE} >> ¡No se pudo descargar el código! Consulta la información proporcionada...\n"
      echo
      exit 1
    fi

    mkdir -p /home/deploy/${empresa}/backend/public/
    chown deploy:deploy -R /home/deploy/${empresa}/
    chmod 775 -R /home/deploy/${empresa}/backend/public/
    sleep 2
  } || trata_erro "baixa_codigo_base"
}

# Instalar y configurar el backend
instala_backend_base() {
  banner
  printf "${WHITE} >> Configurar variables de entorno ${BLUE}backend${WHITE}...\n"
  echo
  {
    sleep 2
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    subdominio_frontend=$(echo "${subdominio_frontend/https:\/\//}")
    subdominio_frontend=${subdominio_frontend%%/*}
    subdominio_frontend=https://${subdominio_frontend}
    subdominio_perfex=$(echo "${subdominio_perfex/https:\/\//}")
    subdominio_perfex=${subdominio_perfex%%/*}
    subdominio_perfex=https://${subdominio_perfex}
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/backend/.env
NODE_ENV=
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
PROXY_PORT=443
PORT=${backend_port}
SUPPORT_WHATSAPP=${numero_suporte}

# CREDENCIAIS BD
DB_HOST=localhost
DB_DIALECT=postgres
DB_PORT=5432
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}

# DADOS REDIS
REDIS_URI=redis://:${senha_deploy}@127.0.0.1:6379
# REDIS_URI_ACK=redis://:${senha_deploy}@127.0.0.1:6379
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000
# BULL_BOARD=true
# BULL_USER=${email_deploy}
# BULL_PASS=${senha_deploy}

TIMEOUT_TO_IMPORT_MESSAGE=1000

# SECRETS
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

PERFEX_URL=${subdominio_perfex}
PERFEX_MODULE=CRMWHATSAPP
VERIFY_TOKEN=whaticket
FACEBOOK_APP_ID=${facebook_app_id}
FACEBOOK_APP_SECRET=${facebook_app_secret}
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Instalando dependencias ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  export PUPPETEER_SKIP_DOWNLOAD=true
  npm install --force
  npm install puppeteer-core --force
  npm run build
EOF

    sleep 2

    sudo su - deploy <<EOF
  sed -i 's|npm3Binary = .*|npm3Binary = "/usr/bin/ffmpeg";|' ${empresa}/backend/node_modules/@ffmpeg-installer/ffmpeg/index.js
  mkdir -p /home/deploy/${empresa}/backend/node_modules/@ffmpeg-installer/linux-x64/ && \
  echo '{ "version": "1.1.0", "name": "@ffmpeg-installer/linux-x64" }' > ${empresa}/backend/node_modules/@ffmpeg-installer/linux-x64/package.json
EOF

sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend

  # Preparar SQL para producción
  echo ">> Preparando database.sql"
  mkdir -p dist/database/sql
  cp src/database/sql/database.sql dist/database/sql/database.sql
  chown deploy:deploy dist/database/sql/database.sql
  chmod 644 dist/database/sql/database.sql

  # Ejecutar SQL completo usando credenciales del .env
  echo ">> Migrando base de datos desde database.sql"
  export PGPASSWORD=$(grep DB_PASS .env | cut -d '=' -f2)
  DB_HOST=$(grep DB_HOST .env | cut -d '=' -f2)
  DB_PORT=$(grep DB_PORT .env | cut -d '=' -f2)
  DB_USER=$(grep DB_USER .env | cut -d '=' -f2)
  DB_NAME=$(grep DB_NAME .env | cut -d '=' -f2)

  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f dist/database/sql/database.sql

EOF


    sleep 2

    banner
    printf "${WHITE} >> Correr db:seed...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  
EOF

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}backend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/backend
  pm2 start dist/server.js --name ${empresa}-backend
EOF

    sleep 2
  } || trata_erro "instala_backend_base"
}

# Instalar y configurar la interfaz
instala_frontend_base() {
  banner
  printf "${WHITE} >> Instalando dependencias ${BLUE}frontend${WHITE}...\n"
  echo
  {
    sudo su - deploy <<EOF
  cd /home/deploy/${empresa}/frontend
  npm install --force
  npx browserslist@latest --update-db
EOF

    sleep 2

    banner
    printf "${WHITE} >> Configurar variables circundantes ${BLUE}frontend${WHITE}...\n"
    echo
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    frontend_chatbot_url=$(echo "${frontend_chatbot_url/https:\/\//}")
    frontend_chatbot_url=${frontend_chatbot_url%%/*}
    frontend_chatbot_url=https://${frontend_chatbot_url}
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/frontend/.env
REACT_APP_BACKEND_URL=${subdominio_backend}
REACT_APP_FACEBOOK_APP_ID=${facebook_app_id}
REACT_APP_REQUIRE_BUSINESS_MANAGEMENT=TRUE
REACT_APP_NAME_SYSTEM=${nome_titulo}
REACT_APP_NUMBER_SUPPORT=${numero_suporte}
SERVER_PORT=${frontend_port}
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Compilando el código ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
    cd /home/deploy/${empresa}/frontend
    sed -i 's/3000/'"${frontend_port}"'/g' server.js
    npm run build
EOF

    sleep 2

    banner
    printf "${WHITE} >> Iniciando pm2 ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<EOF
    cd /home/deploy/${empresa}/frontend
    pm2 start server.js --name ${empresa}-frontend
    pm2 save
EOF

    sleep 2
  } || trata_erro "instala_frontend_base"
}

# Configurar el cron de actualización de datos de la carpeta pública
config_cron_base() {
  printf "${GREEN} >> Agregar uso público de actualización cron a las 3 a.m....${WHITE} \n"
  echo
  {
    if ! command -v cron >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y cron
    fi
    sleep 2
    wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh >/dev/null 2>&1
    chmod +x /home/deploy/atualiza_public.sh >/dev/null 2>&1
    chown deploy:deploy /home/deploy/atualiza_public.sh >/dev/null 2>&1
    echo '#!/bin/bash
pm2 restart all' >/home/deploy/reinicia_instancia.sh
    chmod +x /home/deploy/reinicia_instancia.sh
    chown deploy:deploy /home/deploy/reinicia_instancia.sh >/dev/null 2>&1
    sudo su - deploy <<'EOF'
        CRON_JOB1="0 3 * * * wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh && bash /home/deploy/atualiza_public.sh >> /home/deploy/cron.log 2>&1"
        CRON_JOB2="0 1 * * * /bin/bash /home/deploy/reinicia_instancia.sh >> /home/deploy/cron.log 2>&1"
        CRON_EXISTS1=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB1}")
        CRON_EXISTS2=$(crontab -l 2>/dev/null | grep -F "${CRON_JOB2}")

        if [[ -z "${CRON_EXISTS1}" ]] || [[ -z "${CRON_EXISTS2}" ]]; then
            printf "${GREEN} >> Cron no detectado, programando ahora...${WHITE} "
            {
                crontab -l 2>/dev/null
                [[ -z "${CRON_EXISTS1}" ]] && echo "${CRON_JOB1}"
                [[ -z "${CRON_EXISTS2}" ]] && echo "${CRON_JOB2}"
            } | crontab -
        else
            printf "${GREEN} >> Los crones ya existen, continuando...${WHITE} \n"
        fi
EOF

    sleep 2
  } || trata_erro "config_cron_base"
}

# Configurar Nginx
config_nginx_base() {
  banner
  printf "${WHITE} >> Configurando nginx ${BLUE}frontend${WHITE}...\n"
  echo
  {
    frontend_hostname=$(echo "${subdominio_frontend/https:\/\//}")
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-frontend << 'END'
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${frontend_port};
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
ln -s /etc/nginx/sites-available/${empresa}-frontend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Configurando Nginx ${BLUE}backend${WHITE}...\n"
    echo
    backend_hostname=$(echo "${subdominio_backend/https:\/\//}")
    sudo su - root <<EOF
cat > /etc/nginx/sites-available/${empresa}-backend << 'END'
upstream ${empresa}backend {
        server 127.0.0.1:${backend_port};
        keepalive 32;
    }
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://${empresa}backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_buffering on;
  }
}
END
ln -s /etc/nginx/sites-available/${empresa}-backend /etc/nginx/sites-enabled
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitir SSL desde ${subdominio_backend}...\n"
    echo
    backend_domain=$(echo "${subdominio_backend/https:\/\//}")
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${backend_domain}
EOF

    sleep 2

    banner
    printf "${WHITE} >> Emitir SSL desde ${subdominio_frontend}...\n"
    echo
    frontend_domain=$(echo "${subdominio_frontend/https:\/\//}")
    sudo su - root <<EOF
    certbot -m ${email_deploy} \
            --nginx \
            --agree-tos \
            -n \
            -d ${frontend_domain}
EOF

    sleep 2
  } || trata_erro "config_nginx_base"
}

# Configurar Traefik
config_traefik_base() {
  {
    source /home/deploy/${empresa}/backend/.env
    subdominio_backend=$(echo ${BACKEND_URL} | sed 's|https://||')
    subdominio_frontend=$(echo ${FRONTEND_URL} | sed 's|https://||')
    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_backend}.toml << 'END'
[http.routers]
  [http.routers.backend]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.backend-secure]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["websecure"]
    [http.routers.backend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.backend]
    [http.services.backend.loadBalancer]
      [[http.services.backend.loadBalancer.servers]]
        url = "http://127.0.0.1:${backend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2

    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_frontend}.toml << 'END'
[http.routers]
  [http.routers.frontend]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.frontend-secure]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["websecure"]
    [http.routers.frontend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.frontend]
    [http.services.frontend.loadBalancer]
      [[http.services.frontend.loadBalancer.servers]]
        url = "http://127.0.0.1:${frontend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2
  } || trata_erro "config_traefik_base"
}

# Ajusta la latencia: requiere reiniciar el VPS para que realmente funcione
config_latencia_base() {
  banner
  printf "${WHITE} >> Reducir la latencia...\n"
  echo
  {
    sudo su - root <<EOF
cat >> /etc/hosts << 'END'
127.0.0.1   ${subdominio_backend}
127.0.0.1   ${subdominio_frontend}
END
EOF

    sleep 2

    sudo su - deploy <<EOF
  pm2 restart all
EOF

    sleep 2
  } || trata_erro "config_latencia_base"
}

# Completa la instalación y muestra los datos de acceso.
fim_instalacao_base() {
  banner
  printf "   ${GREEN} >> Instalación completa...\n"
  echo
  printf "   ${WHITE}Banckend: ${BLUE}${subdominio_backend}\n"
  printf "   ${WHITE}Frontend: ${BLUE}${subdominio_frontend}\n"
  echo
  printf "   ${WHITE}Usuario ${BLUE}admin@admin.com\n"
  printf "   ${WHITE}password   ${BLUE}123456j\n"
  echo
  printf "${WHITE}>> Presione cualquier tecla para regresar al menú principal o CTRL+C para finalizar este script\n"
  read -p ""
  echo
}

################################################################
#                         ACTUALIZAR                          #
################################################################

backup_app_atualizar() {
  carregar_variaveis
  source /home/deploy/${empresa}/backend/.env
  {
    banner
    printf "${WHITE} >> Antes de actualizar, ¿desea hacer una copia de seguridad de la base de datos? ${GREEN}S/${RED}N:${WHITE}\n"
    echo
    read -p "> " confirmacao_backup
    echo
    confirmacao_backup=$(echo "${confirmacao_backup}" | tr '[:lower:]' '[:upper:]')
    if [ "${confirmacao_backup}" == "S" ]; then
      db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
      [ ! -d "/home/deploy/backups" ] && mkdir -p "/home/deploy/backups"
      backup_file="/home/deploy/backups/${empresa}_$(date +%d-%m-%Y_%Hh).sql"
      PGPASSWORD="${db_password}" pg_dump -U ${empresa} -h localhost ${empresa} >"${backup_file}"
      printf "${GREEN} >> Copia de seguridad de la base de datos ${empresa} terminado. Archivo de copia de seguridad: ${backup_file}\n"
      sleep 2
    else
      printf " >> Continuando con la actualización...\n"
      echo
    fi

    sleep 2
  } || trata_erro "backup_app_atualizar"
}

baixa_codigo_atualizar() {
  banner
  printf "${WHITE} >> Recuperar permisos... \n"
  echo
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  banner
  printf "${WHITE} >> Detener instancias... \n"
  echo
  sleep 2
  sudo su - deploy <<EOF
  pm2 stop all
EOF

  sleep 2

  otimiza_banco_atualizar

  banner
  printf "${WHITE} >> Actualización de la aplicación... \n"
  echo
  sleep 2

  source /home/deploy/${empresa}/frontend/.env
  frontend_port=${SERVER_PORT:-3000}
  sudo su - deploy <<EOF
printf "${WHITE} >> Atualizando Backend...\n"
echo
cd /home/deploy/${empresa}
git checkout main > /dev/null 2>&1
git fetch origin > /dev/null 2>&1
git reset --hard origin/main > /dev/null 2>&1
git pull
cd /home/deploy/${empresa}/backend
npm prune --force > /dev/null 2>&1
export PUPPETEER_SKIP_DOWNLOAD=true
npm install --force
npm install puppeteer-core --force
npm run build
sleep 2
printf "${WHITE} >> Atualizando BD...\n"
echo
sleep 2
npx sequelize db:migrate
sleep 2
printf "${WHITE} >> Atualizando Frontend...\n"
echo
sleep 2
cd /home/deploy/${empresa}/frontend
npm prune --force > /dev/null 2>&1
npm install --force
sed -i 's/3000/'"$frontend_port"'/g' server.js
npm run build
sleep 2
pm2 flush
pm2 start all
EOF

  sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
    else
      printf "${GREEN}No se están ejecutando servicios de proxy (Nginx o Traefik).${WHITE}"
    fi
EOF

  echo
  printf "${WHITE} >> Actualización de ${nome_titulo} terminado...\n"
  echo
  sleep 5
  menu
}

otimiza_banco_atualizar() {
  banner
  printf "${WHITE} >> Realizar el mantenimiento de la base de datos... \n"
  echo
  {
    db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
    sudo su - root <<EOF
    PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h localhost -d "${empresa}" --full --analyze
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "REINDEX DATABASE ${empresa};"
    PGPASSWORD="$db_password" psql -U ${empresa} -h 127.0.0.1 -d ${empresa} -c "ANALYZE;"
EOF

    sleep 2
  } || trata_erro "otimiza_banco_atualizar"
}

carregar_variaveis
menu
