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

# pacchetti per verificare firma kernel dopo
$DNF install -y \
  sbsigntools \
  pesign

# ==========================================================
# App utente CampiOS
# ==========================================================

$DNF install -y \
  nautilus \
  kitty \
  loupe

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
# KDE Connect
# ==========================================================

$DNF install -y \
  kde-connect \
  kdeconnectd \
  fuse-sshfs \
  dolphin

# ==========================================================
# DMS plugin: Phone Connect / DankKDEConnect
# ==========================================================

DMS_PLUGIN_TMP="$(mktemp -d)"

git clone --depth=1 --filter=blob:none --sparse \
  https://github.com/AvengeMedia/dms-plugins.git "$DMS_PLUGIN_TMP"

git -C "$DMS_PLUGIN_TMP" sparse-checkout set DankKDEConnect

install -d /etc/xdg/quickshell/dms-plugins
rm -rf /etc/xdg/quickshell/dms-plugins/DankKDEConnect
cp -a "$DMS_PLUGIN_TMP/DankKDEConnect" /etc/xdg/quickshell/dms-plugins/

rm -rf "$DMS_PLUGIN_TMP"

install -d /etc/skel/.config/DankMaterialShell

cat > /etc/skel/.config/DankMaterialShell/plugin_settings.json <<'EOF'
{
  "dankKDEConnect": {
    "enabled": true
  }
}
EOF

# ==========================================================
# Greetd come display manager
# ==========================================================

mkdir -p /etc/greetd/

# ==========================================================
# Utente greeter per greetd / dms-greeter
# ==========================================================

cat > /usr/lib/sysusers.d/campios-greeter.conf <<'EOF'
u greeter - "System Greeter" /var/lib/greeter /bin/bash
EOF

cat > /usr/lib/tmpfiles.d/campios-greeter.conf <<'EOF'
d /var/lib/greeter 0755 greeter greeter -
EOF

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

# Abilita DMS per tutti gli utenti via systemd user globale
systemctl --global enable dms.service || true
# Fallback per nuovi utenti creati da /etc/skel
mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/

mkdir -p /etc/skel/.config/niri/
cp -rf /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/

# ==========================================================
# Config CampiOS gestita per utenti esistenti
# ==========================================================

install -d /usr/share/campios/niri
install -m 0644 /ctx/dot_config/niri/config.kdl /usr/share/campios/niri/config.kdl

cat > /usr/libexec/campios-sync-user-configs <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SRC="/usr/share/campios/niri/config.kdl"

for home in /home/*; do
  [ -d "$home" ] || continue

  user="$(basename "$home")"
  id "$user" >/dev/null 2>&1 || continue

  target_dir="$home/.config/niri"
  target="$target_dir/config.kdl"

  install -d -o "$user" -g "$user" "$target_dir"

  # Se non esiste, crea il symlink alla config gestita da CampiOS
  if [ ! -e "$target" ]; then
    ln -s "$SRC" "$target"
    chown -h "$user:$user" "$target"
    continue
  fi

  # Se è già il symlink corretto, non fare nulla
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$SRC" ]; then
    continue
  fi

  # Se esiste già un file reale, lo salvo e lo sostituisco con il symlink CampiOS
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    cp -a "$target" "$target.user-backup"
    rm -f "$target"
    ln -s "$SRC" "$target"
    chown -h "$user:$user" "$target"
  fi
done
EOF

chmod +x /usr/libexec/campios-sync-user-configs

cat > /usr/lib/systemd/system/campios-sync-user-configs.service <<'EOF'
[Unit]
Description=Sync CampiOS user configs
After=local-fs.target
ConditionPathExists=/usr/share/campios/niri/config.kdl

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-sync-user-configs

[Install]
WantedBy=multi-user.target
EOF

systemctl enable campios-sync-user-configs.service

# ==========================================================
# Container image policy
# ==========================================================

install -d /etc/containers
install -m 0644 /ctx/etc/containers/policy.json /etc/containers/policy.json

# ==========================================================
# Podman
# ==========================================================

systemctl enable podman.socket

# Remove waybar
$DNF -y remove waybar || true

# ==========================================================
# Plymouth CampiOS boot logo
# ==========================================================

$DNF install -y plymouth plymouth-plugin-script

install -d /usr/share/plymouth/themes/campios
install -m 0644 /ctx/plymouth/campios/campios.plymouth /usr/share/plymouth/themes/campios/
install -m 0644 /ctx/plymouth/campios/campios.script /usr/share/plymouth/themes/campios/
install -m 0644 /ctx/plymouth/campios/logo.png /usr/share/plymouth/themes/campios/

cat > /etc/plymouth/plymouthd.conf <<'EOF'
[Daemon]
Theme=campios
ShowDelay=0
DeviceTimeout=8
EOF

install -d /etc/dracut.conf.d

cat > /etc/dracut.conf.d/99-campios-plymouth.conf <<'EOF'
add_dracutmodules+=" plymouth "
install_items+=" /etc/plymouth/plymouthd.conf "
install_items+=" /usr/share/plymouth/themes/campios/campios.plymouth "
install_items+=" /usr/share/plymouth/themes/campios/campios.script "
install_items+=" /usr/share/plymouth/themes/campios/logo.png "
EOF

plymouth-set-default-theme campios
#dracut --regenerate-all --force

# ==========================================================
# Default Flatpaks
# ==========================================================

install -d /usr/libexec
install -m 0755 /ctx/scripts/campios-install-flatpaks /usr/libexec/campios-install-flatpaks

install -d /usr/share/campios/flatpaks
install -m 0644 /ctx/flatpaks/default-apps.txt /usr/share/campios/flatpaks/default-apps.txt
install -m 0644 /ctx/flatpaks/remove-apps.txt /usr/share/campios/flatpaks/remove-apps.txt

cat > /usr/lib/systemd/system/campios-install-flatpaks.service <<'EOF'
[Unit]
Description=Install CampiOS default Flatpaks
Wants=network-online.target
After=network-online.target
ConditionPathExists=/usr/bin/flatpak

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-install-flatpaks
Restart=on-failure
RestartSec=30
TimeoutStartSec=15min

[Install]
WantedBy=multi-user.target
EOF

systemctl enable campios-install-flatpaks.service

# ==========================================================
# Schemi GLib
# ==========================================================

glib-compile-schemas /usr/share/glib-2.0/schemas/

# ==========================================================
# CampiOS Secure Boot
# ==========================================================

/ctx/scripts/sign-secureboot.sh
/ctx/scripts/install-mok-enroll-script.sh

# ==========================================================
# bootc install defaults
# ==========================================================

install -d /usr/lib/bootc/install

cat > /usr/lib/bootc/install/00-campios.toml <<'EOF'
[install.filesystem.root]
type = "ext4"
EOF

# ==========================================================
# Pulizia
# ==========================================================

$DNF -y clean all
rm -rf /run/dnf /run/selinux-policy
rm -rf /var/lib/dnf
