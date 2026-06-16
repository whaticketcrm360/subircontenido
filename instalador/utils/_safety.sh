#!/bin/bash
#
# _safety.sh — guards compartilhados pra operacoes destrutivas/arriscadas.
# Fonte unica pro aviso de snapshot obrigatorio.

#######################################
# Avisa o usuario que a operacao pode danificar dados / impedir o servico de
# subir, e exige confirmacao explicita "SIM" (nao basta Y/y) — atrito de
# proposito pra evitar que rode sem snapshot.
#
# Arguments:
#   $1 - nome curto da operacao (ex: "Aplicar otimizacoes Docker compose")
#   $2 - (opcional) detalhes adicionais sobre o risco
#
# Returns:
#   0 se confirmado, 1 se cancelado.
#######################################
require_snapshot_confirmation() {
  local op="${1:-Operacao}"
  local extra="${2:-}"

  printf "\n"
  printf "${YELLOW}${DLINE}${NC}\n"
  printf "  ${YELLOW}⚠️   ATENCIÓN: Se requiere una snapshot de VPS antes${NC}\n"
  printf "${YELLOW}${DLINE}${NC}\n\n"

  printf "  Operación: ${WHITE}%s${NC}\n\n" "$op"
  printf "  Esta operación afecta a la infraestructura ${WHITE}irreversiblemente${NC}. si un\n"
  printf "  El parámetro no es compatible con el hardware. (ex: ${WHITE}shared_buffers${NC}\n"
  printf "  más grande que la RAM, ${WHITE}max_connections${NC} excesivo, etc), el servicio puede\n"
  printf "  no sube y los datos son inaccesibles hasta que se restaure la snapshot.\n\n"

  if [ -n "$extra" ]; then
    printf "  ${DIM}%s${NC}\n\n" "$extra"
  fi

  printf "  ${RED}Sin una snapshot, la recuperación puede ser imposible.${NC}\n\n"
  printf "  Tome una snapshot a través del panel de su proveedor antes de continuar:\n"
  printf "    ${DIM}• Hetzner / DigitalOcean / Vultr / Linode -> Snapshots${NC}\n"
  printf "    ${DIM}• Contabo / OVH -> Backup${NC}\n"
  printf "    ${DIM}• AWS / GCP / Azure -> Snapshot de disco/instancia${NC}\n\n"

  printf "  Confirmar escribiendo ${WHITE}SIM${NC} (en mayúsculas) que ya tomaste snapshot: "
  read -r _snap_ans
  if [ "$_snap_ans" != "SÍ" ]; then
    printf "\n${YELLOW}  Operación cancelada: no se cambió nada.${NC}\n"
    printf "${YELLOW}${DLINE}${NC}\n\n"
    return 1
  fi
  printf "\n"
  return 0
}
