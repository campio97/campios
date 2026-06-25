#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup os-prober (dual boot Windows nel menu GRUB) ==="

# Obiettivo: far comparire Windows (o altri OS su altri dischi) nel menu GRUB.
#
# La rilevazione NON può avvenire a build-time: dentro il container di build non
# esiste /boot e non sono visibili gli altri dischi. os-prober deve girare sulla
# MACCHINA REALE. Quindi qui ci limitiamo a PREPARARE l'immagine:
#   1) os-prober è installato (packages/install.txt) e abilitato in /etc/default/grub;
#   2) /usr/bin/campios-regenerate-grub rigenera il grub.cfg scansionando gli altri OS;
#   3) campios-detect-os.service lo lancia UNA TANTUM al primo boot, così Windows
#      compare da solo dopo il primo reboot, senza bloccare l'avvio.
# In qualsiasi momento l'utente può ri-scansionare con: sudo campios-regenerate-grub
#
# Stessa ricetta usata da Bazzite/ublue (`ujust regenerate-grub`) su questo stesso
# stack bootc: grub2-mkconfig verso /etc/grub2-efi.cfg (UEFI) o /etc/grub2.cfg (BIOS).

# ==========================================================
# 1) Abilita os-prober in /etc/default/grub
# ==========================================================
# Fedora ha deprecato os-prober e di default lo disattiva: lo riattiviamo
# esplicitamente, altrimenti grub2-mkconfig non aggiunge gli altri OS.
touch /etc/default/grub
if grep -q '^[#[:space:]]*GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
  sed -i 's|^[#[:space:]]*GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' /etc/default/grub
else
  echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
fi

# ==========================================================
# 2) Helper: rigenera il grub.cfg includendo gli altri OS
# ==========================================================
# Va eseguito da root (il service lo è già; l'utente lo lancia con sudo, e se
# scordato ci ri-eleviamo da soli). /boot e /boot/efi sono ro a runtime: li
# rimontiamo rw solo per il tempo della rigenerazione.
install -d /usr/bin
cat > /usr/bin/campios-regenerate-grub <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Serve root: se l'utente l'ha lanciato senza sudo, ci ri-eleviamo.
if [ "$(id -u)" -ne 0 ]; then
  exec sudo "$0" "$@"
fi

echo "CampiOS: scansione altri sistemi operativi (os-prober) e rigenerazione GRUB..."

# Rimonta in scrittura /boot (e /boot/efi se montata) solo per la rigenerazione.
boot_remounted=0
efi_remounted=0
if mountpoint -q /boot && mount -o remount,rw /boot; then boot_remounted=1; fi
if mountpoint -q /boot/efi && mount -o remount,rw /boot/efi; then efi_remounted=1; fi

# UEFI vs BIOS: /etc/grub2-efi.cfg e /etc/grub2.cfg sono i symlink Fedora verso
# il grub.cfg corretto. Scriviamo tramite il symlink, come fa ublue/Bazzite.
if [ -d /sys/firmware/efi ]; then
  grub2-mkconfig -o /etc/grub2-efi.cfg
else
  grub2-mkconfig -o /etc/grub2.cfg
fi

# Riporta /boot in sola lettura (best-effort, non far fallire lo script).
if [ "$efi_remounted" = 1 ]; then mount -o remount,ro /boot/efi || true; fi
if [ "$boot_remounted" = 1 ]; then mount -o remount,ro /boot || true; fi

echo "CampiOS: menu GRUB aggiornato. Gli OS rilevati compaiono al prossimo riavvio."
EOF
chmod +x /usr/bin/campios-regenerate-grub

# ==========================================================
# 3) Service one-shot: rileva gli altri OS al primo boot
# ==========================================================
# Gira una sola volta (stamp persistente in /var), DOPO multi-user.target, così
# non è sul percorso critico del boot: se os-prober fosse lento non blocca il login.
# Per ri-scansionare in futuro (es. nuovo disco) basta: sudo campios-regenerate-grub
cat > /usr/lib/systemd/system/campios-detect-os.service <<'EOF'
[Unit]
Description=CampiOS: rileva altri OS (Windows) e aggiorna il menu GRUB (una tantum)
After=multi-user.target
ConditionPathExists=!/var/lib/campios/os-detected.stamp

[Service]
Type=oneshot
ExecStart=/usr/bin/campios-regenerate-grub
ExecStartPost=/usr/bin/install -d /var/lib/campios
ExecStartPost=/usr/bin/touch /var/lib/campios/os-detected.stamp
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF

systemctl enable campios-detect-os.service
