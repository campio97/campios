#!/bin/bash

set -ouex pipefail

echo "Configuro CampiOS..."

# Usa dnf in modo compatibile con la base
DNF="$(command -v dnf5 || command -v dnf)"

# DNF più veloce
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
  sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

# ==========================================================
# Pacchetti base scelti da Config 2
# ==========================================================

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

# App utente scelte da Config 2
$DNF install -y \
  nautilus \
  kitty \
  gnome-terminal \
  gnome-system-monitor \
  gnome-calculator \
  loupe \
  mpv

# ==========================================================
# Niri
# ==========================================================

$DNF install -y \
  niri \
  bibata-cursor-theme

# ==========================================================
# Dank Material Shell / DMS Greeter
# ==========================================================

curl -Lo /etc/yum.repos.d/avengemedia-dms.repo \
  "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"

$DNF install -y \
  quickshell \
  dms \
  greetd \
  dms-greeter \
  --allowerasing

# Assicura user/directory del greeter anche su immagini bootc/immutabili
systemd-sysusers /usr/lib/sysusers.d/dms-greeter.conf || true
systemd-tmpfiles --create /usr/lib/tmpfiles.d/dms-greeter.conf || true

# Permessi cache greeter
install -d -m 0750 -o greeter -g greeter /var/cache/dms-greeter
install -d -m 0755 -o greeter -g greeter /var/lib/greeter

# Gruppi opzionali utili per accesso grafico/render
getent group video >/dev/null || groupadd -r video
getent group render >/dev/null || groupadd -r render
usermod -aG video,render greeter || true

# ==========================================================
# Greetd come display manager
# ==========================================================

mkdir -p /etc/greetd

cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/dms-greeter --command niri"
EOF

rm -f /etc/systemd/system/display-manager.service
ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service

systemctl enable --force greetd.service
systemctl set-default graphical.target

# ==========================================================
# Avvio DMS nella sessione dei nuovi utenti
# ==========================================================

mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants

ln -sf /usr/lib/systemd/user/dms.service \
  /etc/skel/.config/systemd/user/graphical-session.target.wants/dms.service

# Config Niri predefinita
mkdir -p /etc/skel/.config/niri

if [[ -f /ctx/dot_config/niri/config.kdl ]]; then
  cp -f /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/config.kdl
fi

# ==========================================================
# Podman
# ==========================================================

systemctl enable podman.socket

# Schemi GLib
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Pulizia
$DNF -y clean all
rm -rf /run/dnf
rm -rf /run/selinux-policy
rm -rf /var/lib/dnf
