#!/bin/bash
DNF="/usr/bin/dnf5.real"
set -ouex pipefail

echo "Configuro CampiOS..."

# DNF più veloce
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
  sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

# Pacchetti base di sistema
$DNF install -y \
  git \
  curl \
  wget \
  just \
  podman \
  distrobox \
  flatpak \
  seahorse \
  lxpolkit \
  iotop \
  sysstat

# App utente essenziali
$DNF install -y \
  nautilus \
  kitty \
  gnome-terminal \
  gnome-system-monitor \
  gnome-calculator \
  loupe \
  mpv

# niri
$DNF install -y \
  niri \
  bibata-cursor-theme

# DMS / DankMaterialShell repo
curl --output-dir "/etc/yum.repos.d/" \
  --remote-name "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"

$DNF install -y \
  quickshell \
  dms \
  greetd \
  dms-greeter \
  --allowerasing

# ==========================================
# CONFIGURAZIONE GREETD E DMS-GREETER
# ==========================================

# 1. Creiamo i gruppi e l'utente greeter
getent group video || groupadd -r video
getent group render || groupadd -r render
id -u greeter &>/dev/null || useradd -r -M -G video,render greeter

# 2. FIX PER DMS-GREETER: Creiamo la cartella di cache mancante!
mkdir -p /var/cache/dms-greeter
chown greeter:greeter /var/cache/dms-greeter

# 3. Creiamo la configurazione di greetd
mkdir -p /etc/greetd/
cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF

# 4. Impostiamo Greetd come Display Manager predefinito (forzato)
rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

# Avvia DMS nella sessione grafica dei nuovi utenti
mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -sf /usr/lib/systemd/user/dms.service \
  /etc/skel/.config/systemd/user/graphical-session.target.wants/dms.service

# Config niri predefinita, se presente nel repo
mkdir -p /etc/skel/.config/niri
if [[ -f /ctx/dot_config/niri/config.kdl ]]; then
  cp -f /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/config.kdl
fi

# Podman socket
systemctl enable podman.socket

# Schemi GLib
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Pulizia
$DNF -y clean all
rm -rf /run/dnf
rm -rf /var/lib/dnf
