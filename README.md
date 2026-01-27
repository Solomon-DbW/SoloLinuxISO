# SoloLinux

<img src="SoloLinux_Blue_And_WHite_Text_Dark.png" alt="SoloLinux Logo" width="400"/>

The SoloLinux project, a Linux operating system based on Arch Linux.

## Installation
### !!!WARNING!!!
- The SoloLinux installation script doesn't yet support dual booting and isn't fully tested yet, so ensure to backup all necessary data before proceeding with the installation.
### Direct install
 [Install ISO file](https://drive.google.com/file/d/1tR0WJT6EbkYpp-XuzMLWYjR9TVVFVKmi/view?usp=drive_link)
### Requirements
- Ensure `git` and `archiso` are installed on your system before proceeding with the installation.
### Building the ISO
1. Run this command to clone this repository: `git clone https://github.com/Solomon-DbW/SoloLinuxISO-With-Custom-Install-Script.git`.
   
2. Navigate to the cloned dorectory: `cd https://github.com/Solomon-DbW/SoloLinuxISO-With-Custom-Install-Script.git`.
   
3. Run `sudo mkarchiso -v .` to generate the ISO file.
   
4. Use a USB flashing application (e.g. BalenaEtcher or GNOME Disks) to burn the ISO file (located at SoloLinuxISO-With-Custom-Install-Script/out) onto a USB drive.
### Installing SoloLinux
1. Reboot your computer and boot into the USB drive using your computer's boot menu.
2. Boot into the SoloLinux Install Medium (x86/64).
3. Run `./install_sl.sh` to begin the installation process and follow the instructions in the installer.
4. After the installation script finishes, reboot into your new SoloLinux system
5. Log in to your SoloLinux system and run `solo_gui_setup.sh` to install the SoloLinux Graphical User Interface
6. Reboot your computer one last time and enjoy SoloLinux!
