#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup KDE Connect ==="

# I pacchetti (kde-connect, kdeconnectd, fuse-sshfs, dolphin) sono installati da
# packages/install.txt. Qui: porte firewall + plugin DMS DankKDEConnect.

# ----------------------------------------------------------
# Firewall: KDE Connect usa TCP+UDP 1714-1764. Senza queste
# porte aperte il discovery/pairing dei dispositivi fallisce.
# A build-time firewalld non gira, quindi si usa la variante
# offline (firewall-cmd richiederebbe il daemon attivo).
# ----------------------------------------------------------
if command -v firewall-offline-cmd >/dev/null 2>&1; then
  firewall-offline-cmd --add-service=kdeconnect 2>/dev/null \
    || firewall-offline-cmd \
         --add-port=1714-1764/tcp \
         --add-port=1714-1764/udp
fi

# ----------------------------------------------------------
# DMS plugin: Phone Connect / DankKDEConnect
# ----------------------------------------------------------
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
