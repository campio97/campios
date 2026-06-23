#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup greetd display manager ==="

mkdir -p /etc/greetd/

# Utente greeter per greetd / dms-greeter
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
