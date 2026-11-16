#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
#  COLOURS
# ----------------------------------------
BLUE="\033[38;2;37;104;151m"
GREEN="\033[0;92m"
YELLOW="\033[0;93m"
RED="\033[0;91m"
RESET="\033[0m"

msg() { echo -e "${BLUE}[SoloLinux]${RESET} $1"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
err() { echo -e "${RED}[ERROR]${RESET} $1"; }

# ----------------------------------------
#  BACKUP FUNCTION
# ----------------------------------------
backup_if_exists() {
    if [ -e "$1" ]; then
        local backup="${1}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -r "$1" "$backup"
        warn "Backed up $1 → $backup"
    fi
}

# ----------------------------------------
#  SUDO CHECK
# ----------------------------------------
if ! sudo -v; then
    err "This script requires sudo access."
    exit 1
fi

cd ~

msg "Installing Git, base-devel…"
sudo slpm install git base-devel

msg "Installing fonts…"
sudo slpm install fontconfig ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-dejavu jq
fc-cache -fv

# ----------------------------------------
#  STARSHIP
# ----------------------------------------
msg "Installing Starship prompt…"
curl -sS https://starship.rs/install.sh | sh -s -- -y

grep -qxF 'eval "$(starship init bash)"' ~/.bashrc 2>/dev/null \
    || echo 'eval "$(starship init bash)"' >> ~/.bashrc
grep -qxF 'eval "$(starship init zsh)"' ~/.zshrc 2>/dev/null \
    || echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# ----------------------------------------
#  ZSH + PLUGINS
# ----------------------------------------
msg "Installing Zsh and plugins…"
sudo slpm install zsh zsh-autosuggestions figlet exa zoxide fzf yad ghc dunst ripgrep

if [ -d ~/.oh-my-zsh ]; then
    backup_if_exists ~/.oh-my-zsh
    rm -rf ~/.oh-my-zsh
fi

RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions

# ----------------------------------------
#  YAY AUR HELPER
# ----------------------------------------
if ! command -v yay &> /dev/null; then
    msg "Installing yay AUR helper…"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf yay
fi

# ----------------------------------------
#  AUR PACKAGES
# ----------------------------------------
msg "Installing AUR packages…"
yay -S --noconfirm brave-bin hyprshade visual-studio-code-insiders-bin waypaper sddm-theme-mountain-git git-credential-manager hyprshot-gui

# ----------------------------------------
#  BACKUP CONFIGS
# ----------------------------------------
backup_if_exists ~/.zshrc
backup_if_exists ~/.config
mkdir -p ~/.config

# ----------------------------------------
#  Fetch SoloLinux GUI Config
# ----------------------------------------
msg "Pulling SoloLinux GUI config…"
rm -rf SoloLinux_GUI 2>/dev/null || true
git clone https://github.com/Solomon-DbW/SoloLinux_GUI

cp SoloLinux_GUI/zshrcfile ~/.zshrc

for item in SoloLinux_GUI/*; do
    name=$(basename "$item")
    if [[ "$name" != "zshrcfile" && "$name" != ".git" && "$name" != "README.md" ]]; then
        cp -r "$item" ~/.config/ 2>/dev/null || true
    fi
done

sudo cp -r SoloLinux_GUI/sddm.conf.d /etc/

rm -rf SoloLinux_GUI SoloLinux 2>/dev/null || true

# ----------------------------------------
#  HYPRLAND + CORE PACKAGES
# ----------------------------------------
msg "Installing Hyprland environment…"

sudo slpm install \
    hyprland hyprpaper hyprlock waybar rofi fastfetch cpufetch brightnessctl \
    kitty virt-manager networkmanager nvim emacs sddm uwsm nautilus \
    xdg-desktop-portal-hyprland qt5-wayland qt6-wayland \
    polkit-kde-agent meson wireplumber pulseaudio pavucontrol \
    archiso qemu yazi virtualbox

# ----------------------------------------
#  SERVICES
# ----------------------------------------
msg "Enabling required services…"
sudo systemctl enable NetworkManager
sudo systemctl enable sddm

# ----------------------------------------
#  SCRIPT PERMISSIONS
# ----------------------------------------
chmod +x ~/.config/hypr/scripts/* 2>/dev/null || true
chmod +x ~/.config/waybar/switch_theme.sh ~/.config/waybar/scripts/* 2>/dev/null || true

# ----------------------------------------
#  SHELL CHANGE
# ----------------------------------------
chsh -s "$(which zsh)"

ok "Setup complete!"
echo -e "${BLUE}Log out and log back in, then choose Hyprland to start SoloLinux GUI.${RESET}"

# #!/usr/bin/env bash
# set -euo pipefail
#
# # ----------------------------------------
# #  COLOURS
# # ----------------------------------------
# BLUE="\033[38;2;37;104;151m"
# GREEN="\033[0;92m"
# YELLOW="\033[0;93m"
# RED="\033[0;91m"
# RESET="\033[0m"
#
# msg() { echo -e "${BLUE}[SoloLinux]${RESET} $1"; }
# ok()  { echo -e "${GREEN}[OK]${RESET} $1"; }
# warn(){ echo -e "${YELLOW}[WARN]${RESET} $1"; }
# err() { echo -e "${RED}[ERROR]${RESET} $1"; }
#
# # ----------------------------------------
# #  BACKUP FUNCTION
# # ----------------------------------------
# backup_if_exists() {
#     if [ -e "$1" ]; then
#         local backup="${1}.backup.$(date +%Y%m%d_%H%M%S)"
#         cp -r "$1" "$backup"
#         warn "Backed up $1 → $backup"
#     fi
# }
#
# # ----------------------------------------
# #  SUDO CHECK
# # ----------------------------------------
# if ! sudo -v; then
#     err "This script requires sudo access."
#     exit 1
# fi
#
# cd ~
#
# msg "Installing Git, base-devel…"
# sudo slpm install git base-devel
#
# msg "Installing fonts…"
# sudo slpm install fontconfig ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-dejavu jq
# fc-cache -fv
#
# # ----------------------------------------
# #  STARSHIP
# # ----------------------------------------
# msg "Installing Starship prompt…"
# curl -sS https://starship.rs/install.sh | sh -s -- -y
#
# grep -qxF 'eval "$(starship init bash)"' ~/.bashrc 2>/dev/null \
#     || echo 'eval "$(starship init bash)"' >> ~/.bashrc
# grep -qxF 'eval "$(starship init zsh)"' ~/.zshrc 2>/dev/null \
#     || echo 'eval "$(starship init zsh)"' >> ~/.zshrc
#
# # ----------------------------------------
# #  ZSH + PLUGINS
# # ----------------------------------------
# msg "Installing Zsh and plugins…"
# sudo slpm install zsh zsh-autosuggestions figlet exa zoxide fzf yad ghc dunst ripgrep
#
# if [ -d ~/.oh-my-zsh ]; then
#     backup_if_exists ~/.oh-my-zsh
#     rm -rf ~/.oh-my-zsh
# fi
#
# RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
#
# rm -rf ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
# git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
#
# # ----------------------------------------
# #  YAY AUR HELPER
# # ----------------------------------------
# if ! command -v yay &> /dev/null; then
#     msg "Installing yay AUR helper…"
#     git clone https://aur.archlinux.org/yay.git
#     cd yay
#     makepkg -si --noconfirm
#     cd ~
#     rm -rf yay
# fi
#
# # ----------------------------------------
# #  AUR PACKAGES
# # ----------------------------------------
# msg "Installing AUR packages…"
# yay -S --noconfirm brave-bin hyprshade visual-studio-code-bin waypaper sddm-theme-mountain-git git-credential-manager hyprshot-gui
#
# # ----------------------------------------
# #  BACKUP CONFIGS
# # ----------------------------------------
# backup_if_exists ~/.zshrc
# backup_if_exists ~/.config
# mkdir -p ~/.config
#
# # ----------------------------------------
# #  Fetch SoloLinux GUI Config
# # ----------------------------------------
# msg "Pulling SoloLinux GUI config…"
# rm -rf SoloLinux_GUI 2>/dev/null || true
# git clone https://github.com/Solomon-DbW/SoloLinux_GUI
#
# cp SoloLinux_GUI/zshrcfile ~/.zshrc
#
# for item in SoloLinux_GUI/*; do
#     name=$(basename "$item")
#     if [[ "$name" != "zshrcfile" && "$name" != ".git" && "$name" != "README.md" ]]; then
#         cp -r "$item" ~/.config/ 2>/dev/null || true
#     fi
# done
#
# sudo cp -r SoloLinux_GUI/sddm.conf.d /etc/
#
# rm -rf SoloLinux_GUI SoloLinux 2>/dev/null || true
#
# # ----------------------------------------
# #  HYPRLAND + CORE PACKAGES
# # ----------------------------------------
# msg "Installing Hyprland environment…"
#
# sudo slpm install \
#     hyprland hyprpaper hyprlock waybar rofi fastfetch cpufetch brightnessctl \
#     kitty virt-manager networkmanager nvim emacs sddm uwsm \
#     xdg-desktop-portal-hyprland qt5-wayland qt6-wayland \
#     polkit-kde-agent meson wireplumber pulseaudio pavucontrol \
#     archiso qemu yazi virtualbox
#
# # ----------------------------------------
# #  SERVICES
# # ----------------------------------------
# msg "Enabling required services…"
# sudo systemctl enable NetworkManager
# sudo systemctl enable sddm
#
# # ----------------------------------------
# #  SCRIPT PERMISSIONS
# # ----------------------------------------
# chmod +x ~/.config/hypr/scripts/* 2>/dev/null || true
# chmod +x ~/.config/waybar/switch_theme.sh ~/.config/waybar/scripts/* 2>/dev/null || true
#
# # ----------------------------------------
# #  SHELL CHANGE
# # ----------------------------------------
# chsh -s "$(which zsh)"
#
# ok "Setup complete!"
# echo -e "${BLUE}Log out and log back in, then choose Hyprland to start SoloLinux GUI.${RESET}"

