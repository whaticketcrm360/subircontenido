#!/bin/bash
#
# Print banner art.

_crm_BANNER_SHOWN=0

# Animated left-to-right logo sweep (opencode-style cursor scan).
# Renders the logo dim first, then sweeps a bright yellow cursor across it
# column by column — revealed chars become bright green, upcoming stay dim.
# Ends with the full gradient render used by the static version.
_logo_sweep() {
  local -a _L=(
    " ███       ███ "
    " ███       ███      ███         ███   ██      █████  █████  "
    " ███  ███  ███     ███         ███    ██     ███  ██  ███  "
    " ███ ██ ██ ███       ███         ███ ███       ███  ██  ███  "
    " █████   █████         ███         ███    ██     ███      ███  "
    " ███       ███        █████   ███     ██    ███      ███  "
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

  # 3. Final: gradient green (same look as the static shadow version)
  printf "\033[%dA" "$_N"
  printf "\033[1;92m"
  printf "  █████████   ███████       ███      ███\n"
  printf "\033[92m"
  printf "███         ███   ██      █████  █████\n"
  printf "\033[1;32m"
  printf " ███         ███    ██     ███  ██  ███ \n"
  printf " ███         ███ ███       ███  ██  ███ \n"
  printf "\033[0;32m"
  printf "███         ███    ██     ███      ███\n"
  printf "█████████   ███     ██    ███      ███\n"
  printf "\033[0m"
}

print_banner() {
  clear
  printf "${GREEN}${DLINE}${NC}\n"

  if [[ $_crm_BANNER_SHOWN -eq 0 ]]; then
    _logo_sweep
    _crm_BANNER_SHOWN=1
  else
    # Static render: dim shadow (+1 char right) then gradient logo on top
    printf "\033[2;32m"
    printf "  █████████   ███████       ███      ███\n"
    printf "  ███         ███   ██      █████  █████\n"
    printf "  ███         ███    ██     ███  ██  ███ \n"
    printf "  ███         ███ ███       ███  ██  ███ \n"
    printf "  ███         ███    ██     ███      ███\n"
    printf "  █████████   ███     ██    ███      ███\n"
    printf "\033[0m"
    printf "\033[6A"
    printf "\033[1;92m"
    printf " █████████   ███████       ███      ███\n"
    printf "\033[92m"
    printf "  ███         ███   ██      █████  █████\n"
    printf "\033[1;32m"
    printf " ███         ███    ██     ███  ██  ███\n"
    printf " ███         ███ ███       ███  ██  ███ \n"
    printf "\033[0;32m"
    printf " ███         ███    ██     ███      ███\n"
    printf " █████████   ███     ██    ███      ███\n"
    printf "\033[0m"
  fi

  printf "${DIM}  Plataforma Multiservicio — WhaTitan  |  © WhaTitan — https://whatitan.online/${NC}\n"
  printf "${DIM}  Compartir sin autorización es un delito (Art. 184 CP).${NC}\n"
  printf "${GREEN}${LINE}${NC}\n"
  local _cpu _cores _ram_total _ram_used _ram_free _disk_total _disk_used
  _cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs | cut -c1-30 || echo "N/D")
  _cores=$(nproc 2>/dev/null || echo "?")
  _ram_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "?")
  _ram_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo "?")
  _ram_free=$(free -h 2>/dev/null | awk '/^Mem:/{print $4}' || echo "?")
  _disk_total=$(df -h / 2>/dev/null | awk 'NR==2{print $2}' || echo "?")
  _disk_used=$(df -h / 2>/dev/null | awk 'NR==2{print $3}' || echo "?")

  printf "${DIM}  CPU: ${NC}${_cpu} ${DIM}(${_cores}c)  RAM: ${NC}${_ram_used}${DIM}/${_ram_free}/${_ram_total}  Disco: ${NC}${_disk_used}${DIM}/${_disk_total}  —  Presione ${YELLOW}Ctrl+C${DIM} cerrar${NC}\n"
  printf "${GREEN}${DLINE}${NC}\n"

  # progress bar — visible only during installation (_STEP_TOTAL > 0)
  _render_progress_bar
}
