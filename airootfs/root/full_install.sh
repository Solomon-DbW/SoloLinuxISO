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

### Partition layout: "size_mb:fstype:mountpoint"
### Special fstypes: swap, efi
### size_mb of 0 means "use remaining space"
CONFIG_PARTITIONS=()
CONFIG_USE_CUSTOM_PARTS="n"

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
    echo "  Filesystem : $CONFIG_FS (default root)"
    echo "  Profile    : $CONFIG_PROFILE"
    if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
        echo "  Partitions : custom (${#CONFIG_PARTITIONS[@]} defined)"
    else
        echo "  Partitions : automatic"
    fi
    echo
    echo "Actions:"
    echo "  1) Select Disk"
    echo "  2) Set Hostname"
    echo "  3) Set User"
    echo "  4) Toggle Sudo"
    echo "  5) Toggle Encryption"
    echo "  6) Select Filesystem"
    echo "  7) Select Profile"
    echo "  8) Partition Editor"
    echo "  9) Install"
    echo "  0) Exit"
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
    echo "2) hyprland"
    read -p "Select profile: " p

    case $p in
        1) CONFIG_PROFILE="minimal" ;;
        2) CONFIG_PROFILE="hyprland" ;;
        *) echo "Invalid"; pause ;;
    esac
}

### ==============================
### PARTITION EDITOR
### ==============================

_part_list() {
    if [[ ${#CONFIG_PARTITIONS[@]} -eq 0 ]]; then
        echo "  (no custom partitions defined)"
    else
        echo "  #   Size       Filesystem   Mount"
        echo "  -----------------------------------------------"
        for i in "${!CONFIG_PARTITIONS[@]}"; do
            IFS=: read -r sz fs mp <<< "${CONFIG_PARTITIONS[$i]}"
            local size_disp
            if [[ "$sz" -eq 0 ]]; then
                size_disp="remainder"
            else
                size_disp="${sz}MiB"
            fi
            printf "  [%d] %-10s %-12s %s\n" "$i" "$size_disp" "$fs" "$mp"
        done
    fi
    echo
}

_part_validate_custom() {
    local has_root=0
    local has_swap=0
    local remainder_count=0

    for p in "${CONFIG_PARTITIONS[@]}"; do
        IFS=: read -r sz fs mp <<< "$p"
        [[ "$mp" == "/" ]] && has_root=1
        [[ "$fs" == "swap" ]] && has_swap=1
        [[ "$sz" -eq 0 ]] && (( remainder_count++ ))
    done

    local ok=1

    if [[ "$has_root" -eq 0 ]]; then
        echo "  [!] No root (/) partition defined"
        ok=0
    fi

    if [[ "$remainder_count" -gt 1 ]]; then
        echo "  [!] Only one partition can use the remaining space (size 0)"
        ok=0
    fi

    if [[ "$BOOTMODE" == "UEFI" ]]; then
        local has_efi=0
        for p in "${CONFIG_PARTITIONS[@]}"; do
            IFS=: read -r sz fs mp <<< "$p"
            [[ "$fs" == "efi" ]] && has_efi=1
        done
        if [[ "$has_efi" -eq 0 ]]; then
            echo "  [!] UEFI system requires an EFI partition (filesystem: efi)"
            ok=0
        fi
    fi

    return $(( 1 - ok ))
}

_part_add() {
    header
    echo "[ Add Partition ]"
    echo
    echo "Filesystem types: ext4, btrfs, xfs, fat32, efi, swap"
    echo "Size: enter MiB (e.g. 512 for 512MiB), or 0 to use remaining space"
    echo

    read -p "Mount point (e.g. /, /home, swap): " mp
    if [[ -z "$mp" ]]; then
        echo "Mount point cannot be empty"
        pause
        return
    fi

    local fs_default="ext4"
    [[ "$mp" == "swap" ]] && fs_default="swap"
    [[ "$mp" == "/boot/efi" ]] && fs_default="efi"

    read -p "Filesystem [$fs_default]: " fs
    fs=${fs:-$fs_default}

    case "$fs" in
        ext4|btrfs|xfs|fat32|efi|swap) ;;
        *)
            echo "Unsupported filesystem: $fs"
            pause
            return
            ;;
    esac

    read -p "Size in MiB (0 = use remaining space): " sz
    if ! [[ "$sz" =~ ^[0-9]+$ ]]; then
        echo "Invalid size"
        pause
        return
    fi

    CONFIG_PARTITIONS+=("${sz}:${fs}:${mp}")
    echo "Partition added: ${sz}MiB ${fs} -> ${mp}"
    pause
}

_part_remove() {
    header
    echo "[ Remove Partition ]"
    echo
    _part_list

    if [[ ${#CONFIG_PARTITIONS[@]} -eq 0 ]]; then
        pause
        return
    fi

    read -p "Enter index to remove: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [[ -z "${CONFIG_PARTITIONS[$idx]}" ]]; then
        echo "Invalid index"
        pause
        return
    fi

    unset 'CONFIG_PARTITIONS[$idx]'
    CONFIG_PARTITIONS=("${CONFIG_PARTITIONS[@]}")
    echo "Partition removed."
    pause
}

_part_move() {
    header
    echo "[ Reorder Partition ]"
    echo
    _part_list

    if [[ ${#CONFIG_PARTITIONS[@]} -lt 2 ]]; then
        echo "Need at least 2 partitions to reorder."
        pause
        return
    fi

    read -p "Index to move: " src
    read -p "New index position: " dst

    local max=$(( ${#CONFIG_PARTITIONS[@]} - 1 ))
    if ! [[ "$src" =~ ^[0-9]+$ && "$dst" =~ ^[0-9]+$ ]] \
        || [[ "$src" -gt "$max" ]] || [[ "$dst" -gt "$max" ]] \
        || [[ "$src" -eq "$dst" ]]; then
        echo "Invalid indices"
        pause
        return
    fi

    local tmp="${CONFIG_PARTITIONS[$src]}"
    CONFIG_PARTITIONS[$src]="${CONFIG_PARTITIONS[$dst]}"
    CONFIG_PARTITIONS[$dst]="$tmp"
    echo "Partitions swapped."
    pause
}

_part_load_default() {
    CONFIG_PARTITIONS=()
    if [[ "$BOOTMODE" == "UEFI" ]]; then
        CONFIG_PARTITIONS+=("300:efi:/boot/efi")
    fi
    CONFIG_PARTITIONS+=("4096:swap:swap")
    CONFIG_PARTITIONS+=("0:${CONFIG_FS}:/")
    echo "Default layout loaded (EFI + swap + root)."
    pause
}

_part_clear() {
    read -p "Clear all partitions? [y/N]: " yn
    [[ "$yn" == "y" ]] && CONFIG_PARTITIONS=() && echo "Cleared." && pause
}

partition_editor() {
    while true; do
        header
        echo "[ Partition Editor ]"
        echo
        echo "Mode: $( [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]] && echo "custom" || echo "automatic" )"
        echo
        _part_list

        echo "  a) Add partition"
        echo "  r) Remove partition"
        echo "  m) Reorder partitions"
        echo "  d) Load default layout as starting point"
        echo "  c) Clear all partitions"
        echo
        if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
            echo "  t) Switch to automatic partitioning"
        else
            echo "  t) Switch to custom partitioning"
        fi
        echo "  v) Validate layout"
        echo "  q) Back to main menu"
        echo

        read -p "Select option: " opt
        case $opt in
            a) _part_add ;;
            r) _part_remove ;;
            m) _part_move ;;
            d) _part_load_default; CONFIG_USE_CUSTOM_PARTS="y" ;;
            c) _part_clear ;;
            t)
                if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
                    CONFIG_USE_CUSTOM_PARTS="n"
                    echo "Switched to automatic partitioning."
                else
                    CONFIG_USE_CUSTOM_PARTS="y"
                    echo "Switched to custom partitioning."
                    if [[ ${#CONFIG_PARTITIONS[@]} -eq 0 ]]; then
                        read -p "Load default layout as starting point? [Y/n]: " yn
                        [[ "${yn:-y}" != "n" ]] && _part_load_default
                    fi
                fi
                pause
                ;;
            v)
                header
                echo "[ Validating layout ]"
                echo
                _part_validate_custom && echo "  Layout looks valid." || true
                pause
                ;;
            q) return ;;
        esac
    done
}

### ==============================
### VALIDATION
### ==============================
validate_config() {
    [[ -z "$CONFIG_DISK" ]] && echo "Disk not set" && return 1
    [[ -z "$CONFIG_PASSWORD" ]] && echo "User password not set" && return 1
    [[ -z "$CONFIG_ROOTPASS" ]] && echo "Root password not set" && return 1

    if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
        _part_validate_custom || return 1
    fi

    return 0
}

### ==============================
### PARTITION HELPERS
### ==============================

# Returns the partition device path for a given index (1-based)
_part_dev() {
    local disk="$1"
    local idx="$2"
    if [[ "$disk" =~ nvme|loop|mmcblk ]]; then
        echo "${disk}p${idx}"
    else
        echo "${disk}${idx}"
    fi
}

# Build parted commands and format/mount partitions from CONFIG_PARTITIONS
apply_custom_partitions() {
    local disk="$CONFIG_DISK"

    echo "[+] Partitioning (custom layout)..."

    parted --script "$disk" mklabel gpt

    local start=1  # MiB
    local idx=1

    for p in "${CONFIG_PARTITIONS[@]}"; do
        IFS=: read -r sz fs mp <<< "$p"

        if [[ "$sz" -eq 0 ]]; then
            local end="100%"
        else
            local end=$(( start + sz ))MiB
        fi

        local fstype_parted
        case "$fs" in
            efi|fat32) fstype_parted="fat32" ;;
            swap)      fstype_parted="linux-swap" ;;
            btrfs)     fstype_parted="btrfs" ;;
            *)         fstype_parted="ext4" ;;
        esac

        parted --script "$disk" mkpart primary "$fstype_parted" "${start}MiB" "$end"

        [[ "$fs" == "efi" ]] && parted --script "$disk" set "$idx" boot on

        (( start = (sz == 0) ? start : start + sz ))
        (( idx++ ))
    done

    echo "[+] Formatting partitions..."

    local part_idx=1
    local root_dev=""
    local efi_dev=""
    local swap_dev=""
    declare -A MOUNT_MAP  # mountpoint -> device

    for p in "${CONFIG_PARTITIONS[@]}"; do
        IFS=: read -r sz fs mp <<< "$p"
        local dev
        dev=$(_part_dev "$disk" "$part_idx")

        case "$fs" in
            efi|fat32)
                mkfs.fat -F32 "$dev"
                efi_dev="$dev"
                MOUNT_MAP["/boot/efi"]="$dev"
                ;;
            swap)
                mkswap "$dev"
                swap_dev="$dev"
                ;;
            btrfs)
                mkfs.btrfs -f "$dev"
                ;;
            xfs)
                mkfs.xfs -f "$dev"
                ;;
            ext4)
                mkfs.ext4 "$dev"
                ;;
        esac

        if [[ "$mp" == "/" ]]; then
            if [[ "$CONFIG_ENCRYPT" == "y" ]]; then
                echo -n "$CONFIG_PASSWORD" | cryptsetup luksFormat "$dev" -
                echo -n "$CONFIG_PASSWORD" | cryptsetup open "$dev" soloroot -
                root_dev="/dev/mapper/soloroot"
                # Re-format the mapper device with the correct fs
                case "$fs" in
                    btrfs) mkfs.btrfs -f "$root_dev" ;;
                    xfs)   mkfs.xfs -f "$root_dev" ;;
                    *)     mkfs.ext4 "$root_dev" ;;
                esac
            else
                root_dev="$dev"
            fi
            MOUNT_MAP["/"]="$root_dev"
        elif [[ "$mp" != "swap" ]]; then
            MOUNT_MAP["$mp"]="$dev"
        fi

        (( part_idx++ ))
    done

    echo "[+] Mounting..."

    mount "${MOUNT_MAP["/"]}" /mnt

    # Mount other non-root, non-swap partitions, deepest last
    local sorted_mounts
    sorted_mounts=$(printf '%s\n' "${!MOUNT_MAP[@]}" | grep -v '^/$' | sort)

    for mp in $sorted_mounts; do
        mkdir -p "/mnt${mp}"
        mount "${MOUNT_MAP[$mp]}" "/mnt${mp}"
    done

    [[ -n "$swap_dev" ]] && swapon "$swap_dev"

    INSTALLED_SWAP="$swap_dev"
    INSTALLED_EFI="${MOUNT_MAP["/boot/efi"]:-}"
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
    if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
        echo " Partitions : custom"
        for p in "${CONFIG_PARTITIONS[@]}"; do
            IFS=: read -r sz fs mp <<< "$p"
            local sd="$( [[ "$sz" -eq 0 ]] && echo "remainder" || echo "${sz}MiB" )"
            echo "   $sd  $fs  $mp"
        done
    else
        echo " Partitions : automatic"
    fi
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
    INSTALLED_SWAP=""
    INSTALLED_EFI=""

    if [[ "$CONFIG_USE_CUSTOM_PARTS" == "y" ]]; then
        apply_custom_partitions
    else
        echo "[+] Partitioning (automatic)..."

        if [[ "$BOOTMODE" == "UEFI" ]]; then
            parted --script "$DISK" mklabel gpt
            parted --script "$DISK" mkpart ESP fat32 1MiB 301MiB
            parted --script "$DISK" set 1 boot on
            parted --script "$DISK" mkpart primary linux-swap 301MiB 4297MiB
            parted --script "$DISK" mkpart primary ${CONFIG_FS} 4297MiB 100%
            [[ "$DISK" =~ nvme|loop|mmcblk ]] && PESP="${DISK}p1" || PESP="${DISK}1"
            [[ "$DISK" =~ nvme|loop|mmcblk ]] && PSWAP="${DISK}p2" || PSWAP="${DISK}2"
            [[ "$DISK" =~ nvme|loop|mmcblk ]] && PROOT="${DISK}p3" || PROOT="${DISK}3"
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

        INSTALLED_SWAP="$PSWAP"
        INSTALLED_EFI="$PESP"
    fi

    local EXTRA_PKGS=""
    if [[ "$CONFIG_PROFILE" == "hyprland" ]]; then
        EXTRA_PKGS="\
            git base-devel curl zsh zsh-autosuggestions \
            fontconfig ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-dejavu jq \
            figlet eza zoxide fzf yad ghc dunst ripgrep \
            hyprland hyprpaper hyprlock hyprshade \
            waybar rofi kitty \
            xdg-desktop-portal-hyprland qt5-wayland qt6-wayland xdg-utils xdg-user-dirs \
            polkit-kde-agent meson wireplumber pulseaudio pavucontrol pipewire pipewire-pulse \
            sddm uwsm \
            fastfetch cpufetch brightnessctl \
            networkmanager neovim emacs \
            virt-manager qemu virtualbox archiso \
            yazi"
    fi

    pacstrap /mnt base linux linux-firmware grub efibootmgr sudo networkmanager nano vim $EXTRA_PKGS
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

if [[ "$CONFIG_PROFILE" == "hyprland" ]]; then
    systemctl enable NetworkManager
    systemctl enable sddm

    # Ensure wheel group has sudo for makepkg / yay to work
    echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/wheel

    # slpm shim — maps slpm to pacman inside the new system
    cat > /usr/local/bin/slpm <<'SLPM'
#!/bin/bash
exec pacman "$@"
SLPM
    chmod +x /usr/local/bin/slpm

    # ------------------------------------------------
    # First-boot user setup script (runs as $USERNAME)
    # ------------------------------------------------
    cat > /home/$USERNAME/solo-setup.sh <<'SOLOEOF'
#!/usr/bin/env bash
set -euo pipefail

BLUE="\033[38;2;37;104;151m"; GREEN="\033[0;92m"; YELLOW="\033[0;93m"; RED="\033[0;91m"; RESET="\033[0m"
msg() { echo -e "${BLUE}[SoloLinux]${RESET} $1"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; }

backup_if_exists() {
    if [ -e "$1" ]; then
        cp -r "$1" "${1}.backup.$(date +%Y%m%d_%H%M%S)"
        warn "Backed up $1"
    fi
}

cd ~

fc-cache -fv

# ---- Starship ----
msg "Installing Starship prompt..."
curl -sS https://starship.rs/install.sh | sh -s -- -y
grep -qxF 'eval "$(starship init bash)"' ~/.bashrc 2>/dev/null || echo 'eval "$(starship init bash)"' >> ~/.bashrc
grep -qxF 'eval "$(starship init zsh)"'  ~/.zshrc  2>/dev/null || echo 'eval "$(starship init zsh)"'  >> ~/.zshrc

# ---- Oh My Zsh ----
msg "Installing Oh My Zsh..."
[ -d ~/.oh-my-zsh ] && { backup_if_exists ~/.oh-my-zsh; rm -rf ~/.oh-my-zsh; }
RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# ---- yay ----
if ! command -v yay &>/dev/null; then
    msg "Installing yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    ( cd /tmp/yay-build && makepkg -si --noconfirm )
    rm -rf /tmp/yay-build
fi

# ---- AUR packages ----
msg "Installing AUR packages..."
yay -S --noconfirm brave-bin hyprshade visual-studio-code-bin waypaper sddm-theme-mountain-git git-credential-manager hyprshot-gui

# ---- Dotfiles ----
msg "Pulling SoloLinux GUI config..."
backup_if_exists ~/.zshrc
backup_if_exists ~/.config
mkdir -p ~/.config

rm -rf ~/SoloLinux_GUI
git clone https://github.com/Solomon-DbW/SoloLinux_GUI ~/SoloLinux_GUI

cp ~/SoloLinux_GUI/zshrcfile ~/.zshrc

for item in ~/SoloLinux_GUI/*; do
    name=$(basename "$item")
    [[ "$name" == "zshrcfile" || "$name" == ".git" || "$name" == "README.md" ]] && continue
    cp -r "$item" ~/.config/ 2>/dev/null || true
done

sudo cp -r ~/SoloLinux_GUI/sddm.conf.d /etc/ 2>/dev/null || true

rm -rf ~/SoloLinux_GUI

# ---- Script permissions ----
chmod +x ~/.config/hypr/scripts/*        2>/dev/null || true
chmod +x ~/.config/waybar/switch_theme.sh 2>/dev/null || true
chmod +x ~/.config/waybar/scripts/*       2>/dev/null || true

# ---- Default shell ----
chsh -s "$(which zsh)"

# ---- Self-destruct the one-shot service ----
systemctl --user disable solo-firstboot.service 2>/dev/null || true
rm -f ~/.config/systemd/user/solo-firstboot.service
rm -f ~/solo-setup.sh

ok "SoloLinux GUI setup complete!"
echo -e "${BLUE}Log out and back in, then choose Hyprland from SDDM.${RESET}"
SOLOEOF

    chmod +x /home/$USERNAME/solo-setup.sh
    chown $USERNAME:$USERNAME /home/$USERNAME/solo-setup.sh

    # ---- Systemd user one-shot to run setup on first login ----
    mkdir -p /home/$USERNAME/.config/systemd/user
    cat > /home/$USERNAME/.config/systemd/user/solo-firstboot.service <<SVCEOF
[Unit]
Description=SoloLinux first-boot GUI setup
After=network-online.target
ConditionPathExists=%h/solo-setup.sh

[Service]
Type=oneshot
ExecStart=%h/solo-setup.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=default.target
SVCEOF

    # Enable the user service (loginctl linger lets it run at login without a full session)
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/systemd
    loginctl enable-linger $USERNAME
    # Enable via symlink since we can't run systemctl --user as $USERNAME inside chroot
    mkdir -p /home/$USERNAME/.config/systemd/user/default.target.wants
    ln -sf /home/$USERNAME/.config/systemd/user/solo-firstboot.service \
           /home/$USERNAME/.config/systemd/user/default.target.wants/solo-firstboot.service
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/systemd
fi
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

    umount -R /mnt
    [[ -n "$INSTALLED_SWAP" ]] && swapoff "$INSTALLED_SWAP"

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
            8) partition_editor ;;
            9) run_install ;;
            0) exit 0 ;;
        esac
    done
}

main
