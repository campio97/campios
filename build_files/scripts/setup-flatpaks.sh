#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup default Flatpaks (installer + service) ==="

# I Flatpak NON si installano a build-time (niente rete/D-Bus utile nel
# container): si installano al primo boot. Qui depositiamo l'installer e le
# liste-dato (default-apps.txt / remove-apps.txt) e abilitiamo il service.

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
