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
CONFIG_FS="ext4"
CONFIG_PROFILE="minimal"
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

pause() {
    read -p "Press Enter to continue..."
}

### ==============================
### MENU
### ==============================
menu() {
    header
    echo "Configuration:"
    echo "  Disk       : ${CONFIG_DISK:-<not set>}"
    echo "  Hostname   : $CONFIG_HOSTNAME"
    echo "  Username   : $CONFIG_USERNAME"
    echo "  Sudo       : $CONFIG_SUDO"
    echo "  Encryption : $CONFIG_ENCRYPT"
    echo "  Filesystem : $CONFIG_FS"
    echo "  Profile    : $CONFIG_PROFILE"
    echo
    echo "Actions:"
    echo "  1) Select Disk"
    echo "  2) Set Hostname"
    echo "  3) Set User"
    echo "  4) Toggle Sudo"
    echo "  5) Toggle Encryption"
    echo "  6) Select Filesystem"
    echo "  7) Select Profile"
    echo "  8) Install"
    echo "  9) Exit"
    echo
}

### ==============================
### BOOT MODE
### ==============================
detect_boot() {
    [[ -d /sys/firmware/efi ]] && BOOTMODE="UEFI" || BOOTMODE="BIOS"
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

    if [[ -z "${DISKS[$idx]}" ]]; then
        echo "Invalid selection"
        pause
        return
    fi

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

    [[ "$p1" != "$p2" ]] && echo "Passwords do not match" && pause && return

    CONFIG_PASSWORD="$p1"

    read -s -p "Root password: " r1; echo
    read -s -p "Confirm root: " r2; echo

    [[ "$r1" != "$r2" ]] && echo "Root passwords do not match" && pause && return

    CONFIG_ROOTPASS="$r1"
}

### ==============================
### FILESYSTEM SELECT
### ==============================
select_fs() {
    header
    echo "1) ext4"
    echo "2) btrfs"
    read -p "Select filesystem: " f

    case $f in
        1) CONFIG_FS="ext4" ;;
        2) CONFIG_FS="btrfs" ;;
        *) echo "Invalid"; pause ;;
    esac
}

### ==============================
### PROFILE SELECT
### ==============================
select_profile() {
    header
    echo "1) minimal"
    echo "2) hyprland (coming soon)"
    read -p "Select profile: " p

    case $p in
        1) CONFIG_PROFILE="minimal" ;;
        2) CONFIG_PROFILE="hyprland" ;;
        *) echo "Invalid"; pause ;;
    esac
}

### ==============================
### VALIDATION
### ==============================
validate_config() {
    [[ -z "$CONFIG_DISK" ]] && echo "Disk not set" && return 1
    [[ -z "$CONFIG_PASSWORD" ]] && echo "User password not set" && return 1
    [[ -z "$CONFIG_ROOTPASS" ]] && echo "Root password not set" && return 1
    return 0
}

### ==============================
### INSTALL
### ==============================
run_install() {
    header

    validate_config || { pause; return; }

    echo "======================================="
    echo " INSTALLATION SUMMARY"
    echo "======================================="
    echo " Disk       : $CONFIG_DISK"
    echo " Hostname   : $CONFIG_HOSTNAME"
    echo " Username   : $CONFIG_USERNAME"
    echo " Sudo       : $CONFIG_SUDO"
    echo " Encryption : $CONFIG_ENCRYPT"
    echo " Filesystem : $CONFIG_FS"
    echo " Profile    : $CONFIG_PROFILE"
    echo " Boot Mode  : $BOOTMODE"
    echo "======================================="

    read -p "Type 'INSTALL' to continue: " CONFIRM
    [[ "$CONFIRM" != "INSTALL" ]] && return

    DISK="$CONFIG_DISK"
    HOSTNAME="$CONFIG_HOSTNAME"
    USERNAME="$CONFIG_USERNAME"
    PASSWORD1="$CONFIG_PASSWORD"
    ROOT1="$CONFIG_ROOTPASS"
    SUDOOPT="$CONFIG_SUDO"
    ENCRYPT="$CONFIG_ENCRYPT"

    echo "[+] Partitioning..."

    if [[ "$BOOTMODE" == "UEFI" ]]; then
        parted --script "$DISK" mklabel gpt
        parted --script "$DISK" mkpart ESP fat32 1MiB 301MiB
        parted --script "$DISK" set 1 boot on
        parted --script "$DISK" mkpart primary linux-swap 301MiB 4297MiB
        parted --script "$DISK" mkpart primary ${CONFIG_FS} 4297MiB 100%
        [[ "$DISK" =~ nvme ]] && PESP="${DISK}p1" || PESP="${DISK}1"
        [[ "$DISK" =~ nvme ]] && PSWAP="${DISK}p2" || PSWAP="${DISK}2"
        [[ "$DISK" =~ nvme ]] && PROOT="${DISK}p3" || PROOT="${DISK}3"
    fi

    mkfs.fat -F32 "$PESP"
    mkswap "$PSWAP"

    if [[ "$ENCRYPT" == "y" ]]; then
        echo -n "$PASSWORD1" | cryptsetup luksFormat "$PROOT" -
        echo -n "$PASSWORD1" | cryptsetup open "$PROOT" soloroot -
        ROOT_DEV="/dev/mapper/soloroot"
    else
        ROOT_DEV="$PROOT"
    fi

    if [[ "$CONFIG_FS" == "btrfs" ]]; then
        mkfs.btrfs "$ROOT_DEV"
    else
        mkfs.ext4 "$ROOT_DEV"
    fi

    mount "$ROOT_DEV" /mnt
    mkdir -p /mnt/boot/efi
    mount "$PESP" /mnt/boot/efi
    swapon "$PSWAP"

    pacstrap /mnt base linux linux-firmware grub efibootmgr sudo networkmanager nano vim
    genfstab -U /mnt >> /mnt/etc/fstab

    arch-chroot /mnt /bin/bash <<EOF
echo "$HOSTNAME" > /etc/hostname
echo "root:$ROOT1" | chpasswd

useradd -m $USERNAME
echo "$USERNAME:$PASSWORD1" | chpasswd

if [[ "$SUDOOPT" == "y" ]]; then
    usermod -aG wheel $USERNAME
    echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel
fi

systemctl enable NetworkManager
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

    umount -R /mnt
    swapoff "$PSWAP"

    echo "Installation complete. Reboot."
}

### ==============================
### MAIN LOOP
### ==============================
main() {
    [[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

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
            4) [[ "$CONFIG_SUDO" == "y" ]] && CONFIG_SUDO="n" || CONFIG_SUDO="y" ;;
            5) [[ "$CONFIG_ENCRYPT" == "y" ]] && CONFIG_ENCRYPT="n" || CONFIG_ENCRYPT="y" ;;
            6) select_fs ;;
            7) select_profile ;;
            8) run_install ;;
            9) exit 0 ;;
        esac
    done
}

main
