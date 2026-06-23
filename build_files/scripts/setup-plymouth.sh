#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup Plymouth boot splash ==="

# I pacchetti plymouth/plymouth-plugin-script sono in packages/install.txt.
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
add_dracutmodules+=" plymouth ostree "
hostonly="no"
install_items+=" /etc/plymouth/plymouthd.conf "
install_items+=" /usr/share/plymouth/themes/campios/campios.plymouth "
install_items+=" /usr/share/plymouth/themes/campios/campios.script "
install_items+=" /usr/share/plymouth/themes/campios/logo.png "
EOF

plymouth-set-default-theme campios
# NB: l'initramfs viene rigenerato DOPO la firma Secure Boot (vedi
# regenerate-initramfs.sh), così da includere il tema CampiOS e i moduli kernel
# già firmati.

# Kernel cmdline per uno splash pulito, gestito da bootc tramite kargs.d.
# I parametri vengono applicati al bootloader a ogni deploy/upgrade.
install -d /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/10-campios.toml <<'EOF'
# quiet                       -> riduce i log del kernel sulla console
# splash                      -> attiva lo splash grafico di Plymouth
# rd.systemd.show_status=false-> nasconde i messaggi di stato systemd nell'initramfs
kargs = ["quiet", "splash", "rd.systemd.show_status=false"]
EOF
