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

$DNF install -y plymouth plymouth-plugin-script || true

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

if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme campios || true
fi

# Serve perché Plymouth viene caricato presto nel boot.
# Se dracut è disponibile nella base, rigenera l'initramfs.
if command -v dracut >/dev/null 2>&1; then
  dracut --regenerate-all --force || true
fi

# ==========================================================
# Default Flatpaks
# ==========================================================

install -d /usr/libexec
install -m 0755 /ctx/scripts/campios-install-flatpaks /usr/libexec/campios-install-flatpaks

install -d /usr/share/campios/flatpaks
install -m 0644 /ctx/flatpaks/default-apps.txt /usr/share/campios/flatpaks/default-apps.txt

cat > /usr/lib/systemd/system/campios-install-flatpaks.service <<'EOF'
[Unit]
Description=Install CampiOS default Flatpaks
Wants=network-online.target
After=network-online.target
ConditionPathExists=/usr/bin/flatpak

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-install-flatpaks

[Install]
WantedBy=multi-user.target
EOF

systemctl enable campios-install-flatpaks.service

# Nel caso siano presenti come Flatpak system-wide
flatpak uninstall --system -y --noninteractive \
  org.mozilla.firefox \
  org.mozilla.Thunderbird \
  || true

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
