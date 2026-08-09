#!/bin/bash

# =========================================================
#                 NEELCRAFT VPS MAKER
# =========================================================

set -euo pipefail

# ---------------- COLORS ----------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ---------------- REPOSITORIES ----------------

KVM_REPO="https://raw.githubusercontent.com/NeelAhuja1234/kvm-vps/main/vm.sh"
NOKVM_REPO="https://raw.githubusercontent.com/NeelAhuja1234/kvm-vps/main/nokvm.sh"

# =========================================================
# BASIC FUNCTIONS
# =========================================================

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

pause_screen() {
    echo
    read -rp "Press Enter to continue..."
}

banner() {
    clear

    echo -e "${GREEN}"
    cat <<'EOF'
███╗   ██╗███████╗███████╗██╗      ██████╗██████╗  █████╗ ███████╗████████╗
████╗  ██║██╔════╝██╔════╝██║     ██╔════╝██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
██╔██╗ ██║█████╗  █████╗  ██║     ██║     ██████╔╝███████║█████╗     ██║
██║╚██╗██║██╔══╝  ██╔══╝  ██║     ██║     ██╔══██╗██╔══██║██╔══╝     ██║
██║ ╚████║███████╗███████╗███████╗╚██████╗██║  ██║██║  ██║██║        ██║
╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝        ╚═╝
EOF
    echo -e "${RESET}"

    echo -e "${WHITE}                 VPS MAKER${RESET}"
    echo -e "${GREEN}                 NEELCRAFT${RESET}"
    echo
}

root_check() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}✗ Please run this script as root.${RESET}"
        exit 1
    fi
}

# =========================================================
# INTERNET CHECK
# =========================================================

internet_check() {

    echo -e "${CYAN}[+] Checking internet connection...${RESET}"

    if curl -fsSI --max-time 10 https://github.com >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Internet connection OK.${RESET}"
        return 0
    fi

    echo -e "${RED}✗ Internet connection unavailable.${RESET}"
    return 1
}

# =========================================================
# INSTALL KVM DEPENDENCIES
# =========================================================

install_kvm_dependencies() {

    banner

    echo -e "${WHITE}             KVM DEPENDENCIES${RESET}"
    line
    echo

    export DEBIAN_FRONTEND=noninteractive

    echo -e "${GREEN}[+] Updating package lists...${RESET}"

    apt-get update

    echo
    echo -e "${GREEN}[+] Installing KVM/QEMU dependencies...${RESET}"

    apt-get install -y \
        qemu-system-x86 \
        qemu-utils \
        cloud-image-utils \
        wget \
        curl \
        openssl \
        ca-certificates \
        iproute2 \
        procps \
        net-tools

    echo
    echo -e "${GREEN}✓ KVM dependencies installed.${RESET}"

    echo
    echo -e "${CYAN}Checking KVM...${RESET}"

    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}✓ /dev/kvm detected.${RESET}"
    else
        echo -e "${YELLOW}⚠ /dev/kvm is not available.${RESET}"
        echo "KVM mode will not work on this VPS."
        echo "You can still use the No-KVM option."
    fi

    pause_screen
}

# =========================================================
# RUN KVM SETUP
# =========================================================

run_kvm() {

    banner

    echo -e "${WHITE}                 KVM VPS${RESET}"
    line
    echo

    if ! internet_check; then
        pause_screen
        return
    fi

    if [ ! -e /dev/kvm ]; then

        echo -e "${RED}✗ KVM is not available on this VPS.${RESET}"
        echo
        echo "Expected:"
        echo "/dev/kvm"
        echo
        echo "Check your VPS/hypervisor configuration."
        echo

        pause_screen
        return
    fi

    echo -e "${GREEN}✓ Hardware KVM detected.${RESET}"
    echo

    echo -e "${CYAN}[+] Downloading your existing KVM manager...${RESET}"

    TMP_KVM="/tmp/neelcraft-vm.sh"

    if ! curl -fsSL "$KVM_REPO" -o "$TMP_KVM"; then
        echo -e "${RED}✗ Failed to download KVM setup.${RESET}"
        rm -f "$TMP_KVM"
        pause_screen
        return
    fi

    chmod +x "$TMP_KVM"

    echo -e "${GREEN}✓ KVM setup downloaded.${RESET}"
    echo

    echo -e "${GREEN}[+] Starting your KVM VPS manager...${RESET}"
    echo

    bash "$TMP_KVM"

    rm -f "$TMP_KVM"
}

# =========================================================
# RUN NO-KVM SETUP
# =========================================================

run_nokvm() {

    banner

    echo -e "${WHITE}                NO-KVM VPS${RESET}"
    line
    echo

    if ! internet_check; then
        pause_screen
        return
    fi

    echo -e "${YELLOW}⚠ No-KVM mode uses software emulation.${RESET}"
    echo "Performance will be lower than hardware KVM."
    echo

    read -rp "Continue? [y/N]: " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        return
    fi

    echo
    echo -e "${CYAN}[+] Downloading No-KVM manager...${RESET}"

    TMP_NOKVM="/tmp/neelcraft-nokvm.sh"

    if ! curl -fsSL "$NOKVM_REPO" -o "$TMP_NOKVM"; then
        echo -e "${RED}✗ Failed to download No-KVM setup.${RESET}"
        rm -f "$TMP_NOKVM"
        pause_screen
        return
    fi

    chmod +x "$TMP_NOKVM"

    echo -e "${GREEN}✓ No-KVM setup downloaded.${RESET}"
    echo

    echo -e "${GREEN}[+] Starting No-KVM VPS manager...${RESET}"
    echo

    bash "$TMP_NOKVM"

    rm -f "$TMP_NOKVM"
}

# =========================================================
# RDX TOOL
# =========================================================

run_rdx() {

    banner

    echo -e "${WHITE}                  RDX TOOL${RESET}"
    line
    echo

    echo -e "${YELLOW}RDX Tool is not connected yet.${RESET}"
    echo
    echo "Add the RDX GitHub raw script here when you have it."
    echo

    pause_screen
}

# =========================================================
# ALL SETUP
# =========================================================

all_setup() {

    banner

    echo -e "${WHITE}                 ALL SETUP${RESET}"
    line
    echo

    echo "NEELCRAFT will prepare this VPS for the VPS Maker."
    echo
    echo "Components:"
    echo " • QEMU"
    echo " • KVM support"
    echo " • QEMU utilities"
    echo " • Cloud-init"
    echo " • wget"
    echo " • curl"
    echo " • OpenSSL"
    echo

    read -rp "Continue? [Y/n]: " CONFIRM

    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        return
    fi

    export DEBIAN_FRONTEND=noninteractive

    echo
    echo -e "${GREEN}[1/3] Updating repositories...${RESET}"

    apt-get update

    echo
    echo -e "${GREEN}[2/3] Installing dependencies...${RESET}"

    apt-get install -y \
        qemu-system-x86 \
        qemu-utils \
        cloud-image-utils \
        wget \
        curl \
        openssl \
        ca-certificates \
        iproute2 \
        procps \
        net-tools

    echo
    echo -e "${GREEN}[3/3] Checking KVM...${RESET}"

    if [ -e /dev/kvm ]; then
        echo
        echo -e "${GREEN}✓ KVM is available.${RESET}"
        echo
        echo "Your existing KVM manager can now be used."
    else
        echo
        echo -e "${YELLOW}⚠ KVM is not available.${RESET}"
        echo
        echo "No-KVM mode is available."
    fi

    echo
    echo -e "${GREEN}✓ ALL SETUP completed.${RESET}"

    pause_screen
}

# =========================================================
# SYSTEM CHECK
# =========================================================

system_check() {

    banner

    echo -e "${WHITE}                SYSTEM CHECK${RESET}"
    line
    echo

    echo -e "${CYAN}Hostname:${RESET} $(hostname)"
    echo -e "${CYAN}OS:${RESET} $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo -e "${CYAN}Kernel:${RESET} $(uname -r)"
    echo -e "${CYAN}Architecture:${RESET} $(uname -m)"
    echo

    echo -e "${CYAN}CPU:${RESET}"
    nproc
    echo

    echo -e "${CYAN}RAM:${RESET}"
    free -h
    echo

    echo -e "${CYAN}Disk:${RESET}"
    df -h /
    echo

    echo -e "${CYAN}KVM:${RESET}"

    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}AVAILABLE${RESET}"
    else
        echo -e "${RED}NOT AVAILABLE${RESET}"
    fi

    echo
    line

    pause_screen
}

# =========================================================
# MAIN MENU
# =========================================================

vps_menu() {

    while true; do

        banner

        echo -e "${GREEN}┌──────────────────────────────────────────┐${RESET}"
        echo -e "${GREEN}│              VPS MAKER                   │${RESET}"
        echo -e "${GREEN}└──────────────────────────────────────────┘${RESET}"
        echo

        echo -e "${GREEN}[1]${RESET} RDX Tool"
        echo
        echo -e "${GREEN}[2]${RESET} Run VM 1 - KVM"
        echo
        echo -e "${GREEN}[3]${RESET} Run VM 2 - No KVM"
        echo
        echo -e "${GREEN}[4]${RESET} Run VM 3 - ALL SETUP"
        echo
        echo -e "${GREEN}[5]${RESET} System Check"
        echo
        echo -e "${RED}[6]${RESET} Exit"

        echo
        line

        read -rp "Select Option → " OPTION

        case "$OPTION" in

            1)
                run_rdx
                ;;

            2)
                run_kvm
                ;;

            3)
                run_nokvm
                ;;

            4)
                all_setup
                ;;

            5)
                system_check
                ;;

            6)
                clear
                exit 0
                ;;

            *)
                echo
                echo -e "${RED}✗ Invalid option.${RESET}"
                sleep 1
                ;;

        esac

    done
}

# =========================================================
# START
# =========================================================

root_check
vps_menu
