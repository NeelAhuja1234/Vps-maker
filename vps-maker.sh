#!/bin/bash

set -o pipefail

# =========================================================
#                 NEELCRAFT VPS MAKER
# =========================================================

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

VM_DIR="/var/lib/neelcraft-vps"
IMAGE_DIR="$VM_DIR/images"
DISK_DIR="$VM_DIR/disks"
CLOUD_DIR="$VM_DIR/cloud-init"

UBUNTU_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
UBUNTU_IMAGE="$IMAGE_DIR/ubuntu-24.04.img"

# =========================================================
# BASIC
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

prepare_dirs() {
    mkdir -p "$IMAGE_DIR"
    mkdir -p "$DISK_DIR"
    mkdir -p "$CLOUD_DIR"
}

# =========================================================
# DEPENDENCIES
# =========================================================

install_dependencies() {

    echo -e "${GREEN}[+] Installing dependencies...${RESET}"
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

    prepare_dirs

    echo
    echo -e "${GREEN}✓ Dependencies installed.${RESET}"
}

# =========================================================
# KVM CHECK
# =========================================================

check_kvm() {
    [ -e /dev/kvm ]
}

# =========================================================
# IMAGE
# =========================================================

download_image() {

    prepare_dirs

    if [ -f "$UBUNTU_IMAGE" ]; then
        echo -e "${GREEN}✓ Ubuntu 24.04 image already exists.${RESET}"
        return 0
    fi

    echo
    echo -e "${YELLOW}[+] Downloading Ubuntu 24.04 image...${RESET}"
    echo

    curl -L \
        --fail \
        --progress-bar \
        "$UBUNTU_IMAGE_URL" \
        -o "$UBUNTU_IMAGE"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Image download failed.${RESET}"
        rm -f "$UBUNTU_IMAGE"
        return 1
    fi

    echo -e "${GREEN}✓ Image downloaded.${RESET}"
}

# =========================================================
# VM DETAILS
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

    if [ -z "$VM_NAME" ]; then
        echo -e "${RED}✗ VM name cannot be empty.${RESET}"
        return 1
    fi

    if [[ ! "$VM_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo -e "${RED}✗ Invalid VM name.${RESET}"
        return 1
    fi

    VM_RAM="${VM_RAM:-2048}"
    VM_CPU="${VM_CPU:-2}"
    VM_DISK="${VM_DISK:-20}"

    if ! [[ "$VM_RAM" =~ ^[0-9]+$ &&
            "$VM_CPU" =~ ^[0-9]+$ &&
            "$VM_DISK" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}✗ RAM/CPU/Disk must be numbers.${RESET}"
        return 1
    fi

    VM_DISK_PATH="$DISK_DIR/${VM_NAME}.qcow2"
    VM_CLOUD_DIR="$CLOUD_DIR/$VM_NAME"

    echo
    echo -e "${GREEN}VM Name:${RESET} $VM_NAME"
    echo -e "${GREEN}RAM:${RESET} ${VM_RAM} MB"
    echo -e "${GREEN}CPU:${RESET} ${VM_CPU}"
    echo -e "${GREEN}Disk:${RESET} ${VM_DISK} GB"
    echo
}

# =========================================================
# PASSWORD
# =========================================================

get_vm_password() {

    echo
    read -rsp "VM Root Password : " VM_PASSWORD
    echo

    if [ -z "$VM_PASSWORD" ]; then
        echo -e "${RED}✗ Password cannot be empty.${RESET}"
        return 1
    fi
}

# =========================================================
# DISK
# =========================================================

create_disk() {

    if [ -f "$VM_DISK_PATH" ]; then
        echo -e "${YELLOW}⚠ Disk already exists.${RESET}"
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
# CLOUD INIT
# =========================================================

create_cloud_init() {

    mkdir -p "$VM_CLOUD_DIR"

    cat > "$VM_CLOUD_DIR/user-data" <<EOF
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

    cat > "$VM_CLOUD_DIR/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

    cloud-localds \
        "$VM_CLOUD_DIR/seed.iso" \
        "$VM_CLOUD_DIR/user-data" \
        "$VM_CLOUD_DIR/meta-data"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Cloud-init creation failed.${RESET}"
        return 1
    fi

    echo -e "${GREEN}✓ Cloud-init configured.${RESET}"
}

# =========================================================
# VM IP
# =========================================================

get_vm_ip() {

    local IP=""

    for i in {1..30}; do

        IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null |
            awk '/ipv4/ {print $4}' |
            cut -d/ -f1 |
            head -n1)

        if [ -n "$IP" ]; then
            echo "$IP"
            return 0
        fi

        sleep 2
    done

    return 1
}

# =========================================================
# CREATE KVM
# =========================================================

create_kvm_vm() {

    banner

    if ! check_kvm; then
        echo -e "${RED}✗ KVM is not available on this VPS.${RESET}"
        echo
        echo "Use No-KVM mode instead."
        pause_screen
        return
    fi

    echo -e "${GREEN}✓ KVM detected.${RESET}"

    get_vm_details || {
        pause_screen
        return
    }

    if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
        echo -e "${RED}✗ VM '$VM_NAME' already exists.${RESET}"
        pause_screen
        return
    fi

    get_vm_password || {
        pause_screen
        return
    }

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
    echo -e "${GREEN}[+] Creating KVM VM...${RESET}"
    echo

    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM" \
        --vcpus "$VM_CPU" \
        --disk path="$VM_DISK_PATH",format=qcow2 \
        --disk path="$VM_CLOUD_DIR/seed.iso",device=cdrom \
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
    echo -e "${GREEN}✓ VM created successfully.${RESET}"
    echo
    echo "Waiting for VM IP..."

    VM_IP=$(get_vm_ip)

    echo
    line
    echo -e "${GREEN}             VM CREATED${RESET}"
    line
    echo
    echo "Name       : $VM_NAME"
    echo "RAM        : ${VM_RAM} MB"
    echo "CPU        : $VM_CPU"
    echo "Disk       : ${VM_DISK} GB"
    echo "Status     : $(virsh domstate "$VM_NAME")"

    if [ -n "$VM_IP" ]; then
        echo "IP         : $VM_IP"
        echo
        echo "SSH:"
        echo "ssh root@$VM_IP"
    else
        echo
        echo -e "${YELLOW}⚠ IP not detected yet.${RESET}"
        echo "Run VM Info later to check it."
    fi

    echo
    line

    pause_screen
}

# =========================================================
# NO KVM
# =========================================================

create_no_kvm_vm() {

    banner

    echo -e "${YELLOW}                 NO-KVM MODE${RESET}"
    echo
    echo "QEMU software emulation will be used."
    echo "Performance is lower than hardware KVM."
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

    get_vm_password || {
        pause_screen
        return
    }

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
    echo -e "${GREEN}[+] Creating No-KVM VM...${RESET}"

    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM" \
        --vcpus "$VM_CPU" \
        --disk path="$VM_DISK_PATH",format=qcow2 \
        --disk path="$VM_CLOUD_DIR/seed.iso",device=cdrom \
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
# VM MANAGEMENT
# =========================================================

list_vms() {

    banner

    echo -e "${WHITE}                    VM LIST${RESET}"
    line
    echo

    if ! virsh list --all; then
        echo -e "${RED}Unable to list VMs.${RESET}"
    fi

    echo
    pause_screen
}

choose_vm() {

    read -rp "VM Name: " SELECTED_VM

    if [ -z "$SELECTED_VM" ]; then
        echo -e "${RED}✗ VM name required.${RESET}"
        return 1
    fi

    if ! virsh dominfo "$SELECTED_VM" >/dev/null 2>&1; then
        echo -e "${RED}✗ VM not found.${RESET}"
        return 1
    fi

    return 0
}

start_vm() {

    banner
    echo -e "${GREEN}START VM${RESET}"
    line
    echo

    choose_vm || {
        pause_screen
        return
    }

    virsh start "$SELECTED_VM"

    pause_screen
}

stop_vm() {

    banner
    echo -e "${YELLOW}STOP VM${RESET}"
    line
    echo

    choose_vm || {
        pause_screen
        return
    }

    virsh shutdown "$SELECTED_VM"

    pause_screen
}

restart_vm() {

    banner
    echo -e "${BLUE}RESTART VM${RESET}"
    line
    echo

    choose_vm || {
        pause_screen
        return
    }

    virsh reboot "$SELECTED_VM"

    pause_screen
}

delete_vm() {

    banner
    echo -e "${RED}DELETE VM${RESET}"
    line
    echo

    choose_vm || {
        pause_screen
        return
    }

    echo
    echo -e "${RED}WARNING: This will permanently delete the VM.${RESET}"
    read -rp "Type DELETE to continue: " CONFIRM

    if [ "$CONFIRM" != "DELETE" ]; then
        echo "Cancelled."
        pause_screen
        return
    fi

    virsh destroy "$SELECTED_VM" 2>/dev/null || true
    virsh undefine "$SELECTED_VM" --remove-all-storage 2>/dev/null || true

    rm -rf "$CLOUD_DIR/$SELECTED_VM"

    echo
    echo -e "${GREEN}✓ VM deleted.${RESET}"

    pause_screen
}

vm_info() {

    banner
    echo -e "${CYAN}VM INFO${RESET}"
    line
    echo

    choose_vm || {
        pause_screen
        return
    }

    echo
    virsh dominfo "$SELECTED_VM"

    echo
    echo "Network:"
    virsh domifaddr "$SELECTED_VM" 2>/dev/null || true

    pause_screen
}

# =========================================================
# VM MANAGEMENT MENU
# =========================================================

vm_management() {

    while true; do

        banner

        echo -e "${WHITE}                 VM MANAGEMENT${RESET}"
        line
        echo

        echo -e "${GREEN}[1]${RESET} List VMs"
        echo
        echo -e "${GREEN}[2]${RESET} Start VM"
        echo
        echo -e "${YELLOW}[3]${RESET} Stop VM"
        echo
        echo -e "${BLUE}[4]${RESET} Restart VM"
        echo
        echo -e "${RED}[5]${RESET} Delete VM"
        echo
        echo -e "${CYAN}[6]${RESET} VM Info"
        echo
        echo -e "${WHITE}[7]${RESET} Back"

        echo
        line

        read -rp "Select Option → " OPTION

        case "$OPTION" in
            1) list_vms ;;
            2) start_vm ;;
            3) stop_vm ;;
            4) restart_vm ;;
            5) delete_vm ;;
            6) vm_info ;;
            7) return ;;
            *) echo -e "${RED}✗ Invalid option.${RESET}"; sleep 1 ;;
        esac

    done
}

# =========================================================
# RDX TOOL
# =========================================================

rdx_tool() {

    banner

    echo -e "${WHITE}                    RDX TOOL${RESET}"
    line
    echo

    echo -e "${YELLOW}RDX Tool is not connected yet.${RESET}"
    echo
    echo "Add your RDX GitHub raw URL inside this function."
    echo

    # Example:
    # bash <(curl -fsSL "https://raw.githubusercontent.com/USERNAME/REPO/main/install.sh")

    pause_screen
}

# =========================================================
# ALL SETUP
# =========================================================

all_setup() {

    banner

    echo -e "${WHITE}                  ALL SETUP${RESET}"
    line
    echo

    echo "This will install:"
    echo
    echo " • QEMU"
    echo " • KVM/libvirt"
    echo " • virt-install"
    echo " • cloud-init tools"
    echo " • Networking dependencies"
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
        echo -e "${GREEN}✓ Hardware KVM is available.${RESET}"
        echo

        read -rp "Create a KVM VM now? [Y/n]: " CREATE_VM

        if [[ ! "$CREATE_VM" =~ ^[Nn]$ ]]; then
            create_kvm_vm
            return
        fi

    else
        echo
        echo -e "${YELLOW}⚠ /dev/kvm is unavailable.${RESET}"
        echo
        echo "You can use No-KVM mode from the main menu."
    fi

    pause_screen
}

# =========================================================
# MAIN VPS MENU
# =========================================================

vps_menu() {

    while true; do

        banner

        echo -e "${CYAN}┌──────────────────────────────────────────┐${RESET}"
        echo -e "${CYAN}│               VPS MAKER                  │${RESET}"
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
        echo -e "${WHITE}[5]${RESET} VM Management"
        echo
        echo -e "${RED}[6]${RESET} Exit"

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
                vm_management
                ;;

            6)
                clear
                exit 0
                ;;

            *)
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
prepare_dirs
vps_menu
