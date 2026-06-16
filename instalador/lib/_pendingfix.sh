#!/bin/bash
# 
# system management

#######################################
# installs node
# Arguments:
#   None
#######################################
pending_node_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nodejs...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  apt-get install -y nodejs
EOF

  sleep 2
}

#######################################
# stop all services
# Arguments:
#   None
#######################################
pending_stop_pm2() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos para os serviços no deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 stop all
EOF

  sleep 2
}

#######################################
# move fix folder
# Arguments:
#   None
#######################################
pending_mv_fix() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos mover a migration até o deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cp "${PROJECT_ROOT}"/fix.zip /home/deploycrm/
EOF

  sleep 2
}

#######################################
# delete service file
# Arguments:
#   None
#######################################
pending_delete_service() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos deletar o serviço de envio...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm/crm/backend/dist/services/WbotServices || exit
  rm -f SendMessagesSystemWbot.ts
EOF

  sleep 2
}

#######################################
# unzip fix
# Arguments:
#   None
#######################################
pending_unzip_fix() {
  print_banner
  printf "${WHITE} 💻 Fazendo unzip da migration...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  unzip fix.zip
EOF

  sleep 2
}

#######################################
# delete zip
# Arguments:
#   None
#######################################
pending_delete_zip() {
  print_banner
  printf "${WHITE} 💻 Vamos delete o zip do fix...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  cd /home/deploycrm || exit
  rm -f fix.zip
EOF

  sleep 2
}

#######################################
# stop all services
# Arguments:
#   None
#######################################
pending_restart_pm2() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos reiniciar os serviços no deploycrm...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploycrm <<EOF
  pm2 restart all
EOF

  sleep 2
}