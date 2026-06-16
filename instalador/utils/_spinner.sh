#!/bin/bash
#
# Spinner animado, barra de progresso e utilitários de apresentação de etapas.

# --- progresso global ---
_STEP_CURRENT=0
_STEP_TOTAL=0
_STEP_LABEL=""

# --- spinner ---
_SPINNER_PID=""

#######################################
# Inicializa a barra de progresso para uma operação com N etapas.
# Chamar uma vez antes do início das etapas.
# Arguments:
#   $1 - total de etapas
#######################################
init_progress() {
  _STEP_TOTAL="${1:-0}"
  _STEP_CURRENT=0
  _STEP_LABEL=""
}

#######################################
# Avança um passo no progresso e atualiza o rótulo exibido na barra.
# Chamado internamente por step_header.
# Arguments:
#   $1 - rótulo da etapa atual
#######################################
advance_step() {
  _STEP_LABEL="${1:-}"
  _STEP_CURRENT=$(( _STEP_CURRENT + 1 ))
}

#######################################
# Renderiza a barra de progresso abaixo do banner.
# Não exibe nada se _STEP_TOTAL = 0.
# Arguments:
#   None
#######################################
_render_progress_bar() {
  [ "${_STEP_TOTAL:-0}" -eq 0 ] && return

  local current="${_STEP_CURRENT:-0}"
  local total="${_STEP_TOTAL}"
  local label="${_STEP_LABEL:-}"
  local bar_width=48
  local filled=$(( current * bar_width / total ))
  local empty=$(( bar_width - filled ))
  local pct=0
  [ "$total" -gt 0 ] && pct=$(( current * 100 / total ))

  # linha superior da barra
  printf "  ${GREEN}[${NC}"
  local i
  printf "${GREEN}"
  for (( i=0; i<filled; i++ )); do printf "█"; done
  printf "${NC}${DIM}"
  for (( i=0; i<empty;  i++ )); do printf "░"; done
  printf "${NC}${GREEN}]${NC}"
  printf "  ${WHITE}${current}/${total}${NC}  ${DIM}${pct}%%${NC}\n"

  # rótulo da etapa atual
  if [ -n "$label" ]; then
    printf "  ${DIM}↳ ${label}${NC}\n"
  else
    printf "\n"
  fi

  printf "${GREEN}${DLINE}${NC}\n"
}

#######################################
# Exibe cabeçalho de etapa consistente:
# avança o progresso → redesenha o banner (com barra atualizada) → mostra título.
# Arguments:
#   $1 - ícone  $2 - título  $3 - descrição (opcional)
#######################################
step_header() {
  local icon="${1}"
  local title="${2}"
  local description="${3:-}"

  # avança ANTES de chamar print_banner para que a barra mostre o valor correto
  advance_step "${title}"

  print_banner

  printf "${CYAN_LIGHT}  ${icon}  ${title}${NC}\n"
  printf "${LINE}\n"
  [ -n "$description" ] && printf "${DIM}  ${description}${NC}\n"
  printf "\n"
}

#######################################
# Inicia spinner animado em background.
# Arguments:
#   $1 - mensagem
#######################################
start_spinner() {
  local msg="${1:-Processando...}"
  (
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while true; do
      printf "\r  \033[1;36m${frames[$((i % 10))]}\033[0m  \033[2;37m${msg}\033[0m\033[K"
      i=$(( i + 1 ))
      sleep 0.08
    done
  ) 2>/dev/null &
  _SPINNER_PID=$!
}

#######################################
# Para o spinner e exibe mensagem de sucesso.
# Arguments:
#   $1 - mensagem de conclusão
#######################################
stop_spinner() {
  local label="${1:-Concluído}"
  _kill_spinner
  printf "\r  ${GREEN}✅${NC}  ${label}\033[K\n"
}

#######################################
# Para o spinner e exibe mensagem de erro.
# Arguments:
#   $1 - mensagem de erro
#######################################
stop_spinner_error() {
  local label="${1:-Erro}"
  _kill_spinner
  printf "\r  ${RED}❌${NC}  ${label}\033[K\n"
}

_kill_spinner() {
  if [ -n "${_SPINNER_PID:-}" ]; then
    kill "$_SPINNER_PID" 2>/dev/null
    wait "$_SPINNER_PID" 2>/dev/null || true
    _SPINNER_PID=""
  fi
}
