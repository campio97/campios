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
# CONFIGURAZIONE GREETD E NIRI CORRETTA
# ==========================================

# 1. Assicuriamoci che l'utente esista e abbia i permessi GPU
useradd -M -G video,render greeter || true
usermod -aG video,render greeter || true

# 2. Creiamo la cartella e il file di configurazione
mkdir -p /etc/greetd/

cat > /etc/greetd/config.toml << 'EOF'
[terminal]
# Cambiamo vt da 1 a 7 per non litigare con Plymouth durante l'avvio
vt = 7

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF

# 3. Ripristiniamo la sicurezza SELinux per evitare blocchi
chcon -t etc_t /etc/greetd/config.toml || true

# 4. Impostiamo i servizi
systemctl disable gdm.service || true
systemctl disable sddm.service || true
systemctl disable cosmic-greeter.service || true
systemctl enable greetd.service

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
rm -rf /var/cache/dnf /var/lib/dnf /tmp/*
