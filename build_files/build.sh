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

install -y \
  quickshell \
  dms \
  greetd \
  dms-greeter \
  --allowerasing

# greetd + dms-greeter + niri
mkdir -p /etc/greetd/

cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF

# Usa greetd come display manager
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
-y clean all
rm -rf /var/cache/dnf /var/lib/dnf /tmp/*
