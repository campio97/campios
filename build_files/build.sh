#!/bin/bash

set -ouex pipefail

echo "Configuro CampiOS..."

# Usa dnf in modo compatibile con la base
if [[ -x /usr/bin/dnf5.real ]]; then
  DNF="/usr/bin/dnf5.real"
else
  DNF="$(command -v dnf5 || command -v dnf)"
fi

# DNF più veloce
grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf || \
  sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf

# ==========================================================
# Pacchetti base CampiOS
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

# ==========================================================
# App utente CampiOS
# ==========================================================

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

curl --output-dir "/etc/yum.repos.d/" \
  --remote-name \
  "https://copr.fedorainfracloud.org/coprs/avengemedia/dms/repo/fedora-$(rpm -E %fedora)/avengemedia-dms-fedora-$(rpm -E %fedora).repo"

$DNF install -y \
  quickshell \
  dms \
  greetd \
  dms-greeter \
  --allowerasing

# ==========================================================
# Greetd come display manager
# ==========================================================

mkdir -p /etc/greetd/

# Assicura che l'utente usato da greetd esista
if ! getent passwd greeter >/dev/null; then
  useradd --system \
    --home-dir /var/lib/greeter \
    --create-home \
    --shell /usr/sbin/nologin \
    greeter
fi

cat > /etc/greetd/config.toml << EOF
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "dms-greeter --command niri"
EOF

rm -f /etc/systemd/system/display-manager.service
ln -s /usr/lib/systemd/system/greetd.service /etc/systemd/system/display-manager.service
systemctl enable --force greetd.service

# ==========================================================
# Config utente predefinita
# ==========================================================

mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/

mkdir -p /etc/skel/.config/niri/
cp -rf /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/

# ==========================================================
# Podman
# ==========================================================

systemctl enable podman.socket

# ==========================================================
# Schemi GLib
# ==========================================================

glib-compile-schemas /usr/share/glib-2.0/schemas/

# ==========================================================
# Pulizia
# ==========================================================

$DNF -y clean all
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/dnf
