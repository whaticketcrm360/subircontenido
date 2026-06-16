#!/bin/bash
#
# Print banner art.

_crm_BANNER_SHOWN=0

#######################################
# Animated left-to-right logo sweep (opencode-style cursor scan).
# Globals:
#   None
# Arguments:
#   None
#######################################
_logo_sweep() {
  local -a _L=(
    "  █████████      ███████         █████████"
    "        ███      ███    ██       ███      "
    "      ███        ███    ███      ███      "
    "    ███          ███    ███      ███  ████"
    "  ███            ███    ██       ███    ██"
    "  █████████      ███████         █████████"
  )
  local _N=${#_L[@]}
  local _W=42
  local _i _col _line _len

  # 1. Initial dim render (unscanned / "dark" state)
  printf "\033[2;32m"
  for _line in "${_L[@]}"; do
    printf "%s\n" "$_line"
  done
  printf "\033[0m"

  # 2. Column sweep: bright green revealed | bright yellow cursor | dim ahead
  for (( _col = 0; _col <= _W + 1; _col++ )); do
    printf "\033[%dA" "$_N"
    for (( _i = 0; _i < _N; _i++ )); do
      _line="${_L[$_i]}"
      _len=${#_line}
      if (( _col >= _len )); then
        printf "\033[1;32m%s\033[0m\n" "$_line"
      else
        printf "\033[1;32m%s\033[1;93m%s\033[2;32m%s\033[0m\n" \
          "${_line:0:$_col}" \
          "${_line:$_col:1}" \
          "${_line:$(( _col + 1 ))}"
      fi
    done
    sleep 0.018
  done

  # 3. Final: solid bright green
  printf "\033[%dA" "$_N"
  printf "\033[1;92m"
  printf "  █████████      ███████         █████████\n"
  printf "\033[92m"
  printf "        ███      ███    ██       ███      \n"
  printf "\033[1;32m"
  printf "      ███        ███    ███      ███      \n"
  printf "    ███          ███    ███      ███  ████\n"
  printf "\033[0;32m"
  printf "  ███            ███    ██       ███    ██\n"
  printf "  █████████      ███████         █████████\n"
  printf "\033[0m"
}

#######################################
# Print a board.
# Globals:
#   GREEN  DIM  NC  LINE  DLINE  YELLOW
# Arguments:
#   None
#######################################
print_banner() {
  clear
  printf "\n"
  printf "${GREEN}${DLINE}${NC}\n"

  if [[ $_crm_BANNER_SHOWN -eq 0 ]]; then
    _logo_sweep
    _crm_BANNER_SHOWN=1
  else
    printf "${GREEN}"
    printf "  █████████      ███████         █████████\n"
    printf "        ███      ███    ██       ███      \n"
    printf "      ███        ███    ███      ███      \n"
    printf "    ███          ███    ███      ███  ████\n"
    printf "  ███            ███    ██       ███    ██\n"
    printf "  █████████      ███████         █████████\n"
    printf "${NC}"
  fi

  printf "\n"
  printf "${DIM}  Plataforma de Multiatendimento — Z-PRO${NC}\n"
  printf "${GREEN}${LINE}${NC}\n"
  # hardware info
  local _cpu _cores _ram_total _ram_used _ram_free _disk_total _disk_used
  _cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "N/D")
  _cores=$(nproc 2>/dev/null || echo "?")
  _ram_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")
  _ram_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo "?")
  _ram_free=$(free -h 2>/dev/null | awk '/^Mem:/{print $4}' || echo "?")
  _disk_total=$(df -h / 2>/dev/null | awk 'NR==2{print $2}' || echo "?")
  _disk_used=$(df -h / 2>/dev/null | awk 'NR==2{print $3}' || echo "?")

  printf "${DIM}  CPU : ${NC}${_cpu} ${DIM}(${_cores} cores)${NC}\n"
  printf "${DIM}  RAM : ${NC}${_ram_used} ${DIM}usado / ${NC}${_ram_free} ${DIM}livre / ${NC}${_ram_total} ${DIM}total${NC}\n"
  printf "${DIM}  Disco: ${NC}${_disk_used} ${DIM}usado / ${NC}${_disk_total} ${DIM}total${NC}\n"
  printf "${GREEN}${LINE}${NC}\n"
  printf "${DIM}  © ZDG & crm - https://zdg.com.br/${NC}\n"
  printf "${DIM}  Compartilhar sem autorização é crime (Art. 184 CP).${NC}\n"
  printf "${DIM}  Pressione ${YELLOW}Ctrl+C${NC}${DIM} para fechar o instalador.${NC}\n"
  printf "${GREEN}${DLINE}${NC}\n"
  printf "\n"
}
