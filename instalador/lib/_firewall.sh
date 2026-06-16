# Instalar e Ativar FireWall
install_firewall() {
  step_header "🛡️ " "Configurando Firewall (UFW)" \
    "Instala e ativa o UFW (Uncomplicated Firewall) com política de negar tudo por padrão."
  printf "  ${DIM}Portas liberadas:${NC}\n"
  printf "  ${DIM}• 22/tcp   — SSH (acesso ao servidor)${NC}\n"
  printf "  ${DIM}• 80/tcp   — HTTP (necessário para Certbot renovar SSL)${NC}\n"
  printf "  ${DIM}• 443/tcp  — HTTPS (frontend e backend)${NC}\n"
  printf "  ${DIM}• 9000/tcp — Portainer (interface de gerenciamento Docker)${NC}\n\n"

  start_spinner "Instalando UFW e aplicando regras de firewall..."
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
  stop_spinner "Firewall ativo. Portas 22, 80, 443 e 9000 liberadas."
  sleep 1
}
