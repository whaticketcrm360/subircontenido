# Instalar e Ativar FireWall
install_firewall() {
  print_banner
  printf "${WHITE} 💻 Instalando o firewall...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt update
  apt install -y ufw
  
  ufw default deny incoming
  ufw default allow outgoing
  
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw allow 9000/tcp
  
  ufw --force enable
  
  ufw status
EOF

  sleep 2
}