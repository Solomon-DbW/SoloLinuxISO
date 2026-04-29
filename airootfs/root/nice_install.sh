#!/bin/bash
set -e

### ==============================
### GLOBAL STATE
### ==============================
CONFIG_DISK=""
CONFIG_HOSTNAME="sololinux"
CONFIG_USERNAME="solo"
CONFIG_PASSWORD=""
CONFIG_ROOTPASS=""
CONFIG_SUDO="n"
CONFIG_ENCRYPT="n"
BOOTMODE=""

### ==============================
### UI HELPERS
### ==============================
header() {
    clear
    echo "======================================="
    echo "         SoloLinux Installer"
    echo "======================================="
    echo
}

menu() {
    header
    echo "Configuration:"
    echo "  Disk       : ${CONFIG_DISK:-<not set>}"
    echo "  Hostname   : $CONFIG_HOSTNAME"
    echo "  Username   : $CONFIG_USERNAME"
    echo "  Sudo       : $CONFIG_SUDO"
    echo "  Encryption : $CONFIG_ENCRYPT"
    echo
    echo "Actions:"
    echo "  1) Select Disk"
    echo "  2) Set Hostname"
    echo "  3) Set User"
    echo "  4) Toggle Sudo"
    echo "  5) Toggle Encryption"
    echo "  6) Install"
    echo "  7) Exit"
    echo
}

pause() {
    read -p "Press Enter to continue..."
}

### ==============================
### DETECT BOOT MODE
### ==============================
detect_boot() {
    if [[ -d /sys/firmware/efi ]]; then
        BOOTMODE="UEFI"
    else
        BOOTMODE="BIOS"
    fi
}

### ==============================
### DISK SELECTION
### ==============================
select_disk() {
    header
    echo "[ Disk Selection ]"
    echo

    mapfile -t DISKS < <(lsblk -dno NAME,TYPE | awk '$2!="rom" {print $1}')

    for i in "${!DISKS[@]}"; do
        echo " [$i] /dev/${DISKS[$i]}"
    done

    echo
    read -p "Select disk: " idx
    CONFIG_DISK="/dev/${DISKS[$idx]}"
}

### ==============================
### USER SETUP
### ==============================
set_user() {
    header
    read -p "Username [$CONFIG_USERNAME]: " u
    CONFIG_USERNAME=${u:-$CONFIG_USERNAME}

    read -s -p "Password: " p1; echo
    read -s -p "Confirm: " p2; echo

    if [[ "$p1" != "$p2" ]]; then
        echo "Passwords do not match"
        pause
        return
    fi

    CONFIG_PASSWORD="$p1"

    read -s -p "Root password: " r1; echo
    read -s -p "Confirm root: " r2; echo

    if [[ "$r1" != "$r2" ]]; then
        echo "Root passwords do not match"
        pause
        return
    fi

    CONFIG_ROOTPASS="$r1"
}

### ==============================
### INSTALL EXECUTION
### ==============================
run_install() {
    header

    if [[ -z "$CONFIG_DISK" ]]; then
        echo "Disk not selected!"
        pause
        return
    fi

    echo "Starting installation..."
    sleep 1

    ### ---- YOUR EXISTING LOGIC HERE ---- ###
    ### (partitioning, pacstrap, chroot etc.)
}

### ==============================
### MAIN LOOP
### ==============================
main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Run as root."
        exit 1
    fi

    detect_boot

    while true; do
        menu
        read -p "Select option: " opt

        case $opt in
            1) select_disk ;;
            2)
                read -p "Hostname [$CONFIG_HOSTNAME]: " h
                CONFIG_HOSTNAME=${h:-$CONFIG_HOSTNAME}
                ;;
            3) set_user ;;
            4)
                [[ "$CONFIG_SUDO" == "y" ]] && CONFIG_SUDO="n" || CONFIG_SUDO="y"
                ;;
            5)
                [[ "$CONFIG_ENCRYPT" == "y" ]] && CONFIG_ENCRYPT="n" || CONFIG_ENCRYPT="y"
                ;;
            6) run_install ;;
            7) exit 0 ;;
        esac
    done
}

main
