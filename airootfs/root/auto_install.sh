#!/bin/bash
set -e
### ==========================================
### CHECK ROOT
### ==========================================
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi
### ==========================================
### DETECT UEFI/BIOS
### ==========================================
if [[ -d /sys/firmware/efi ]]; then
  BOOTMODE="UEFI"
else
  BOOTMODE="BIOS"
fi
echo "[*] Boot mode detected: $BOOTMODE"
### ==========================================
### DISK SELECTION MENU
### ==========================================
echo "[+] Detecting internal disks..."
DISKS=($(lsblk -dno NAME,TYPE,SIZE | awk '
  $2=="disk" {
    gsub("G","",$3)
    if ($3 >= 30) print $1
  }'))
if [ ${#DISKS[@]} -eq 0 ]; then
  echo "ERROR: No suitable install disk found."
  lsblk
  exit 1
fi
echo "Available install disks:"
for i in "${!DISKS[@]}"; do
  echo " [$i] /dev/${DISKS[$i]}"
  lsblk -d /dev/${DISKS[$i]}
done
read -p "Select install disk (index): " DISKIDX
DISK="/dev/${DISKS[$DISKIDX]}"
echo "Selected: $DISK"
read -p "WARNING: ALL DATA on $DISK WILL BE ERASED. Type 'WIPE' to continue: " CONFIRM
if [[ "$CONFIRM" != "WIPE" ]]; then
  echo "Aborted."
  exit 1
fi
### ==========================================
### USER CONFIG PROMPT
### ==========================================
read -p "Enter hostname [sololinux]: " HOSTNAME
HOSTNAME=${HOSTNAME:-sololinux}
read -p "Enter username [solo]: " USERNAME
USERNAME=${USERNAME:-solo}
read -s -p "Enter password for $USERNAME: " PASSWORD1; echo
read -s -p "Confirm password for $USERNAME: " PASSWORD2; echo
if [[ "$PASSWORD1" != "$PASSWORD2" ]]; then
  echo "ERROR: Passwords do not match."
  exit 1
fi
read -s -p "Enter root password: " ROOT1; echo
read -s -p "Confirm root password: " ROOT2; echo
if [[ "$ROOT1" != "$ROOT2" ]]; then
  echo "ERROR: Root passwords do not match."
  exit 1
fi
### ==========================================
### SUDO OPTION PROMPT
### ==========================================
read -p "Should the user '$USERNAME' have sudo (administrator) privileges? [y/N]: " SUDOOPT
SUDOOPT=${SUDOOPT,,} # to lowercase
### ==========================================
### ENCRYPTION OPTION
### ==========================================
read -p "Encrypt root partition with LUKS? [y/N]: " ENCRYPT
ENCRYPT=${ENCRYPT,,} # to lowercase
### ==========================================
### PARTITION DISK
### ==========================================
echo "[+] Partitioning $DISK ..."
if [[ "$BOOTMODE" == "UEFI" ]]; then
  parted --script "$DISK" mklabel gpt
  parted --script "$DISK" mkpart ESP fat32 1MiB 301MiB
  parted --script "$DISK" set 1 boot on
  parted --script "$DISK" mkpart primary linux-swap 301MiB 4297MiB
  parted --script "$DISK" mkpart primary ext4 4297MiB 100%
  # Handle partition naming for both /dev/sdX and /dev/nvmeXnY
  if [[ "$DISK" =~ "nvme" ]]; then
    PESP="${DISK}p1"
    PSWAP="${DISK}p2"
    PROOT="${DISK}p3"
  else
    PESP="${DISK}1"
    PSWAP="${DISK}2"
    PROOT="${DISK}3"
  fi
else
  parted --script "$DISK" mklabel msdos
  parted --script "$DISK" mkpart primary ext4 1MiB 101MiB
  parted --script "$DISK" set 1 boot on
  parted --script "$DISK" mkpart primary linux-swap 101MiB 4197MiB
  parted --script "$DISK" mkpart primary ext4 4197MiB 100%
  if [[ "$DISK" =~ "nvme" ]]; then
    P1="${DISK}p1"
    PSWAP="${DISK}p2"
    PROOT="${DISK}p3"
  else
    P1="${DISK}1"
    PSWAP="${DISK}2"
    PROOT="${DISK}3"
  fi
fi
### ==========================================
### FORMAT PARTITIONS
### ==========================================
set -e
if [[ "$BOOTMODE" == "UEFI" ]]; then
  mkfs.fat -F32 "$PESP"
else
  mkfs.ext4 "$P1"
fi
mkswap "$PSWAP"
if [[ "$ENCRYPT" == y ]]; then
  echo -n "$PASSWORD1" | cryptsetup luksFormat "$PROOT" -
  echo -n "$PASSWORD1" | cryptsetup open "$PROOT" soloroot -
  mkfs.ext4 /dev/mapper/soloroot
  ROOT_MAPPER="/dev/mapper/soloroot"
else
  mkfs.ext4 "$PROOT"
  ROOT_MAPPER="$PROOT"
fi
### ==========================================
### MOUNT
### ==========================================
mount "$ROOT_MAPPER" /mnt
if [[ "$BOOTMODE" == "UEFI" ]]; then
  mkdir -p /mnt/boot/efi
  mount "$PESP" /mnt/boot/efi
else
  mkdir -p /mnt/boot
  mount "$P1" /mnt/boot
fi
swapon "$PSWAP"

### ==========================================
### STAGE GUI SETUP SCRIPT
### ==========================================
# 1. Create the user's home directory mount point
mkdir -p /mnt/home/"$USERNAME"

# 2. Copy the GUI script to the user's future home directory
#    (Assumes the script is available on the live system at /root/solo_gui_setup.sh)
cp /root/solo_gui_setup.sh /mnt/home/"$USERNAME"/
# cp /root/slpm /mnt/home/"$USERNAME"/

mkdir -p /mnt/usr/local/bin
cp /root/slpm /mnt/usr/local/bin/
chmod +x /mnt/usr/local/bin/slpm

# 3. Set the ownership (UID 1000 and GID 1000 is almost always the first non-root user)
#    This ensures the user can execute it after reboot.
chown 1000:1000 /mnt/home/"$USERNAME"/solo_gui_setup.sh
# chown 1000:1000 /mnt/home/"$USERNAME"/slpm

# 4. Make the script executable
chmod +x /mnt/home/"$USERNAME"/solo_gui_setup.sh

echo "[*] GUI setup script staged at /home/$USERNAME/solo_gui_setup.sh"

### ==========================================
### INSTALL ARCH BASE
### ==========================================
echo "[+] Installing base system..."
pacstrap /mnt base linux linux-firmware grub efibootmgr sudo networkmanager nano vim
### ==========================================
### FSTAB GENERATION
### ==========================================
genfstab -U /mnt >> /mnt/etc/fstab
### ==========================================
### PASS VARIABLES INTO CHROOT
### ==========================================
arch-chroot /mnt /bin/bash <<CHROOT_EOF
HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
PASSWORD1='$PASSWORD1'
ROOT1='$ROOT1'
SUDOOPT='$SUDOOPT'
BOOTMODE='$BOOTMODE'
DISK='$DISK'
ENCRYPT='$ENCRYPT'
PROOT='$PROOT'

ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
sed -i 's/#en_GB.UTF-8/en_GB.UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_GB.UTF-8' > /etc/locale.conf
echo "\$HOSTNAME" > /etc/hostname
echo '127.0.0.1 localhost' > /etc/hosts
echo '::1 localhost' >> /etc/hosts
echo "127.0.1.1 \$HOSTNAME.localdomain \$HOSTNAME" >> /etc/hosts
echo "root:\$ROOT1" | chpasswd

if [[ "\$SUDOOPT" == "y" ]]; then
  useradd -m -G wheel -s /bin/bash "\$USERNAME"
  echo "\$USERNAME:\$PASSWORD1" | chpasswd
  mkdir -p /etc/sudoers.d
  echo '%wheel ALL=(ALL) ALL' > /etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
else
  useradd -m -s /bin/bash "\$USERNAME"
  echo "\$USERNAME:\$PASSWORD1" | chpasswd
fi

chown -R "\$USERNAME":"\$USERNAME" /home/"\$USERNAME"

systemctl enable NetworkManager

# Configure encryption if enabled
if [[ "\$ENCRYPT" == "y" ]]; then
  ROOTUUID=\$(blkid -s UUID -o value "\$PROOT")
  sed -i "s/^HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck)/" /etc/mkinitcpio.conf
  mkinitcpio -P
  # Update GRUB to handle encryption
  sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\$ROOTUUID:soloroot root=/dev/mapper/soloroot\"|" /etc/default/grub
fi

# Create custom os-release for SoloLinux
cat > /etc/os-release <<'OS_RELEASE_EOF'
NAME="SoloLinux"
PRETTY_NAME="SoloLinux"
ID=sololinux
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="0;38;2;37;104;151"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://gitlab.archlinux.org/groups/archlinux/-/issues"
PRIVACY_POLICY_URL="https://terms.archlinux.org/docs/privacy-policy/"
LOGO=archlinux-logo
OS_RELEASE_EOF

# Create symlink as some tools check /usr/lib/os-release
ln -sf /etc/os-release /usr/lib/os-release

if [[ "\$BOOTMODE" == "UEFI" ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
  grub-install --target=i386-pc "\$DISK"
fi

# Customize GRUB to display SoloLinux
if [ -f /etc/grub.d/10_linux ]; then
  sed -i 's/Arch Linux/SoloLinux/g' /etc/grub.d/10_linux
  sed -i 's/Arch/SoloLinux/g' /etc/grub.d/10_linux
fi
if [ -f /etc/grub.d/30_os-prober ]; then
  sed -i 's/Arch Linux/SoloLinux/g' /etc/grub.d/30_os-prober
fi

# Also update GRUB defaults to set a custom distributor
echo 'GRUB_DISTRIBUTOR="SoloLinux"' >> /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

### ==========================================
### CLEANUP
### ==========================================
umount -R /mnt
swapoff "$PSWAP"
if [[ "$ENCRYPT" == y ]]; then
  cryptsetup close soloroot
fi

echo "===================================="
echo " SoloLinux Installed Successfully!"
echo " Disk: $DISK"
echo " Username: $USERNAME"
echo " Hostname: $HOSTNAME"
if [[ "$SUDOOPT" == "y" ]]; then
  echo " User '$USERNAME' has sudo privileges."
else
  echo " User '$USERNAME' does NOT have sudo privileges."
fi
if [[ "$ENCRYPT" == "y" ]]; then
  echo " Root partition is LUKS encrypted."
fi
echo "======================================="
echo "========INSTALLATION COMPLETED ========"
echo "======================================="
echo "You can now reboot into your new system."
echo "To set up the desktop environment, log in as $USERNAME and run:"
echo "bash solo_gui_setup.sh"
echo "Run: reboot now"
