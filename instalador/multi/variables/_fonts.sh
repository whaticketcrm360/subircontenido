#!/bin/bash
#
# Variables to be used for font styling.

# colors — foreground
readonly RED="\033[1;31m"
readonly GREEN="\033[1;32m"
readonly WHITE="\033[1;37m"
readonly YELLOW="\033[1;33m"
readonly GRAY_LIGHT="\033[0;37m"
readonly CYAN_LIGHT="\033[1;36m"
readonly BLUE="\033[1;34m"
readonly MAGENTA="\033[1;35m"
readonly CYAN="\033[0;36m"
readonly DIM="\033[2;37m"
readonly ORANGE="\033[0;33m"

# thickness
readonly BOLD=$(tput bold)
readonly NORMAL=$(tput sgr0)

# layout separators
readonly LINE="──────────────────────────────────────────────────────────────"
readonly DLINE="══════════════════════════════════════════════════════════════"
