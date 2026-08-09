#!/bin/bash

# =========================================================
#                 NEELCRAFT VPS MAKER
# =========================================================

set -o pipefail

# ---------------- COLORS ----------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# ---------------- SETTINGS ----------------

VM_DIR="/var/lib/neelcraft-vps"
IMAGE_DIR="$VM_DIR/images"
DISK_DIR="$VM_DIR/disks"

UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
UBUNTU_IMAGE="$IMAGE_DIR/ubuntu-24.04.img"

# =========================================================
#                    BASIC FUNCTIONS
# =========================================================

line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

pause_screen() {
    echo
    read -rp "Press Enter to continue..."
}

clear_screen() {
    clear
}

banner() {
    clear

    echo -e "${CYAN}"
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
    echo -e "${CYAN}                 NEELCRAFT${RESET}"
    echo
}

root_check() {

    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}✗ Please run this script as root.${RESET}"
        exit 1
    fi
}

command_check() {

    if ! command -v "$1" >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# =========================================================
#                  DEPENDENCY INSTALL
# =========================================================

install_dependencies() {

    echo -e "${GREEN}[+] Installing VPS Maker dependencies...${RESET}"
    echo

    export DEBIAN_FRONTEND=noninteractive

    apt-get update

    apt-get install -y \
        qemu-system-x86 \
        qemu-utils \
        libvirt-daemon-system \
        libvirt-clients \
        virtinst \
        cloud-image-utils \
        curl \
        wget \
        unzip \
        bridge-utils \
        dnsmasq-base \
        openssh-client

    systemctl enable --now libvirtd 2>/dev/null || true

    mkdir -p "$IMAGE_DIR"
    mkdir -p "$DISK_DIR"

    echo
    echo -e "${GREEN}✓ Dependencies installed.${RESET}"
}

# =========================================================
#                     KVM CHECK
# =========================================================

check_kvm() {

    if [ -e /dev/kvm ]; then
        return 0
    fi

    return 1
}

# =========================================================
#                  DOWNLOAD IMAGE
# =========================================================

download_image() {

    mkdir -p "$IMAGE_DIR"

    if [ -f "$UBUNTU_IMAGE" ]; then
        echo -e "${GREEN}✓ Ubuntu image already exists.${RESET}"
        return 0
    fi

    echo
    echo -e "${YELLOW}[+] Downloading Ubuntu 24.04 cloud image...${RESET}"
    echo

    curl -L \
        --fail \
        --progress-bar \
        "$UBUNTU_IMAGE_URL" \
        -o "$UBUNTU_IMAGE"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Image download failed.${RESET}"
        return 1
    fi

    echo -e "${GREEN}✓ Ubuntu image downloaded.${RESET}"
}

# =========================================================
#                 VM INPUT FUNCTION
# =========================================================

get_vm_details() {

    echo
    line
    echo -e "${WHITE}                 VM CONFIGURATION${RESET}"
    line
    echo

    read -rp "VM Name       : " VM_NAME
    read -rp "RAM (MB)      : " VM_RAM
    read -rp "CPU Cores     : " VM_CPU
    read -rp "Disk (GB)     : " VM_DISK
    read -rp "SSH Port      : " VM_SSH_PORT

    if [ -z "$VM_NAME" ]; then
        echo -e "${RED}✗ VM name cannot be empty.${RESET}"
        return 1
    fi

    if [ -z "$VM_RAM" ]; then
        VM_RAM="2048"
    fi

    if [ -z "$VM_CPU" ]; then
        VM_CPU="2"
    fi

    if [ -z "$VM_DISK" ]; then
        VM_DISK="20"
    fi

    if [ -z "$VM_SSH_PORT" ]; then
        VM_SSH_PORT="2222"
    fi

    VM_DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"

    echo
    echo -e "${GREEN}VM Name:${RESET} $VM_NAME"
    echo -e "${GREEN}RAM:${RESET} ${VM_RAM}MB"
    echo -e "${GREEN}CPU:${RESET} ${VM_CPU}"
    echo -e "${GREEN}Disk:${RESET} ${VM_DISK}GB"
    echo -e "${GREEN}SSH Port:${RESET} ${VM_SSH_PORT}"
    echo
}

# =========================================================
#                  CREATE DISK
# =========================================================

create_disk() {

    if [ -f "$VM_DISK_PATH" ]; then

        echo -e "${YELLOW}⚠ Disk already exists.${RESET}"

        read -rp "Use existing disk? [Y/n]: " USE_EXISTING

        if [[ "$USE_EXISTING" =~ ^[Nn]$ ]]; then
            return 1
        fi

        return 0
    fi

    echo
    echo -e "${GREEN}[+] Creating VM disk...${RESET}"

    qemu-img create \
        -f qcow2 \
        -F qcow2 \
        -b "$UBUNTU_IMAGE" \
        "$VM_DISK_PATH" \
        "${VM_DISK}G"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Disk creation failed.${RESET}"
        return 1
    fi

    echo -e "${GREEN}✓ Disk created.${RESET}"
}

# =========================================================
#                    CLOUD INIT
# =========================================================

create_cloud_init() {

    CLOUD_DIR="$VM_DIR/cloud-init/$VM_NAME"

    mkdir -p "$CLOUD_DIR"

    echo
    read -rsp "VM Password: " VM_PASSWORD
    echo

    if [ -z "$VM_PASSWORD" ]; then
        echo -e "${RED}✗ Password cannot be empty.${RESET}"
        return 1
    fi

    cat > "$CLOUD_DIR/user-data" <<EOF
#cloud-config

hostname: ${VM_NAME}

users:
  - name: root
    lock_passwd: false
    plain_text_passwd: "${VM_PASSWORD}"

ssh_pwauth: true

package_update: true

packages:
  - openssh-server
  - curl
  - wget

runcmd:
  - systemctl enable ssh
  - systemctl restart ssh
EOF

    cat > "$CLOUD_DIR/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

    cloud-localds \
        "$CLOUD_DIR/seed.iso" \
        "$CLOUD_DIR/user-data" \
        "$CLOUD_DIR/meta-data"

    echo -e "${GREEN}✓ Cloud-init created.${RESET}"
}

# =========================================================
#                     CREATE KVM VM
# =========================================================

create_kvm_vm() {

    banner

    if ! check_kvm; then

        echo -e "${RED}✗ /dev/kvm is not available.${RESET}"
        echo
        echo "KVM cannot be used on this VPS."
        echo "Use option 3 for the No-KVM mode."
        pause_screen
        return
    fi

    echo -e "${GREEN}✓ KVM detected.${RESET}"

    get_vm_details || {
        pause_screen
        return
    }

    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then

        echo
        echo -e "${YELLOW}⚠ A VM named '$VM_NAME' already exists.${RESET}"
        pause_screen
        return
    fi

    download_image || {
        pause_screen
        return
    }

    create_disk || {
        pause_screen
        return
    }

    create_cloud_init || {
        pause_screen
        return
    }

    echo
    echo -e "${GREEN}[+] Creating KVM virtual machine...${RESET}"
    echo

    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM" \
        --vcpus "$VM_CPU" \
        --disk path="$VM_DISK_PATH",format=qcow2 \
        --disk path="$VM_DIR/cloud-init/$VM_NAME/seed.iso",device=cdrom \
        --os-variant ubuntu24.04 \
        --network network=default,model=virtio \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ VM creation failed.${RESET}"
        pause_screen
        return
    fi

    echo
    echo -e "${GREEN}✓ KVM VM created successfully.${RESET}"

    echo
    echo -e "${CYAN}VM Information${RESET}"
    echo "Name       : $VM_NAME"
    echo "RAM        : ${VM_RAM}MB"
    echo "CPU        : $VM_CPU"
    echo "Disk       : ${VM_DISK}GB"
    echo

    virsh dominfo "$VM_NAME" | grep -E "Name|State|CPU|Max memory"

    pause_screen
}

# =========================================================
#                 NO KVM / TCG MODE
# =========================================================

create_no_kvm_vm() {

    banner

    echo -e "${YELLOW}NO-KVM MODE${RESET}"
    echo
    echo "This mode uses QEMU software emulation."
    echo "Performance will be significantly slower than KVM."
    echo

    get_vm_details || {
        pause_screen
        return
    }

    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then

        echo -e "${RED}✗ VM already exists.${RESET}"
        pause_screen
        return
    fi

    download_image || {
        pause_screen
        return
    }

    create_disk || {
        pause_screen
        return
    }

    create_cloud_init || {
        pause_screen
        return
    }

    echo
    echo -e "${GREEN}[+] Creating software-emulated VM...${RESET}"
    echo

    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM" \
        --vcpus "$VM_CPU" \
        --disk path="$VM_DISK_PATH",format=qcow2 \
        --disk path="$VM_DIR/cloud-init/$VM_NAME/seed.iso",device=cdrom \
        --os-variant ubuntu24.04 \
        --network network=default,model=virtio \
        --graphics none \
        --console pty,target_type=serial \
        --import \
        --noautoconsole \
        --virt-type qemu

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ No-KVM VM creation failed.${RESET}"
        pause_screen
        return
    fi

    echo
    echo -e "${GREEN}✓ No-KVM VM created.${RESET}"

    pause_screen
}

# =========================================================
#                      RDX TOOL
# =========================================================

rdx_tool() {

    banner

    echo -e "${WHITE}                    RDX TOOL${RESET}"
    line
    echo

    echo -e "${YELLOW}RDX Tool is not connected yet.${RESET}"
    echo
    echo "Put your existing RDX command/script inside this function."
    echo

    # Example:
    #
    # bash <(curl -fsSL YOUR_RDX_RAW_GITHUB_URL)

    pause_screen
}

# =========================================================
#                    ALL SETUP
# =========================================================

all_setup() {

    banner

    echo -e "${WHITE}                 ALL SETUP${RESET}"
    line
    echo

    echo "[1] Installing dependencies"
    echo "[2] Checking KVM"
    echo "[3] Preparing VM environment"
    echo

    read -rp "Continue? [Y/n]: " CONFIRM

    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        return
    fi

    install_dependencies

    echo
    line

    if check_kvm; then

        echo
        echo -e "${GREEN}✓ KVM is available.${RESET}"
        echo

        read -rp "Create a KVM VM now? [Y/n]: " CREATE_VM

        if [[ ! "$CREATE_VM" =~ ^[Nn]$ ]]; then
            create_kvm_vm
            return
        fi

    else

        echo
        echo -e "${YELLOW}⚠ KVM is not available.${RESET}"
        echo "No-KVM mode can be used."
        echo

    fi

    pause_screen
}

# =========================================================
#                     VPS MENU
# =========================================================

vps_menu() {

    while true; do

        banner

        echo -e "${CYAN}┌──────────────────────────────────────────┐${RESET}"
        echo -e "${CYAN}│             DEVELOPMENT MENU             │${RESET}"
        echo -e "${CYAN}└──────────────────────────────────────────┘${RESET}"
        echo

        echo -e "${GREEN}[1]${RESET} RDX Tool"
        echo
        echo -e "${YELLOW}[2]${RESET} Run VM 1 - KVM"
        echo
        echo -e "${BLUE}[3]${RESET} Run VM 2 - No KVM"
        echo
        echo -e "${CYAN}[4]${RESET} Run VM 3 - ALL SETUP"
        echo
        echo -e "${RED}[5]${RESET} Exit"

        echo
        line

        read -rp "Select Option → " OPTION

        case "$OPTION" in

            1)
                rdx_tool
                ;;

            2)
                create_kvm_vm
                ;;

            3)
                create_no_kvm_vm
                ;;

            4)
                all_setup
                ;;

            5)
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
#                         START
# =========================================================

root_check
vps_menu
