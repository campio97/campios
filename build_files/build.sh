#!/bin/bash

set -ouex pipefail

echo "Configuro CampiOS..."

# build.sh è l'ORCHESTRATORE: definisce l'ordine (load-bearing) e mantiene inline
# solo il glue breve e ordine-dipendente. I sottosistemi complessi e indipendenti
# stanno in /ctx/scripts/*.sh (stesso criterio di sign-secureboot.sh).
# Le liste di pacchetti sono dati: packages/install.txt e flatpaks/*.txt.

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
# Pacchetti CampiOS
# ==========================================================
# La lista "semplice" dei pacchetti DNF vive in packages/install.txt
# (un pacchetto per riga, '#' per i commenti). Restano inline solo i casi
# speciali: il gruppo DMS (repo COPR + --allowerasing) e la rimozione di
# waybar (dopo l'install di DMS), entrambi più sotto.

mapfile -t CAMPIOS_PACKAGES < <(
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    /ctx/packages/install.txt | grep -v '^$'
)
$DNF install -y "${CAMPIOS_PACKAGES[@]}"

# ==========================================================
# Dev-box (distrobox: VSCode + Rust/Cargo + Python)
# ==========================================================
# L'ambiente di sviluppo non si bakea nell'immagine immutabile: si crea una
# distrobox per-utente al primo login (storage mutabile nella home). VSCode,
# Rust/Cargo e Python vivono lì dentro, non in /usr.
/ctx/scripts/setup-devbox.sh

# ==========================================================
# Shell di default: fish
# ==========================================================
# I nuovi utenti creati con useradd nascono con fish come login shell.
# Gli utenti GIÀ esistenti vengono allineati da campios-sync-user-configs.
if grep -q '^SHELL=' /etc/default/useradd; then
  sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd
else
  echo 'SHELL=/usr/bin/fish' >> /etc/default/useradd
fi

# ==========================================================
# Dank Material Shell / DMS Greeter
# ==========================================================
# Caso speciale (resta inline): repo COPR + --allowerasing.
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
# KDE Connect (firewall + plugin DMS DankKDEConnect)
# ==========================================================
/ctx/scripts/setup-kdeconnect.sh

# ==========================================================
# greetd come display manager
# ==========================================================
/ctx/scripts/setup-greetd.sh

# ==========================================================
# Config sessione utente (DMS + niri, nuovi ed esistenti)
# ==========================================================
/ctx/scripts/setup-user-configs.sh

# ==========================================================
# Container image policy
# ==========================================================
install -d /etc/containers
install -m 0644 /ctx/etc/containers/policy.json /etc/containers/policy.json

# ==========================================================
# Podman
# ==========================================================
systemctl enable podman.socket

# Remove waybar (DOPO l'install di DMS, che potrebbe tirarlo come dipendenza)
$DNF -y remove waybar || true

# ==========================================================
# Plymouth CampiOS boot logo (tema + kargs; initramfs più sotto)
# ==========================================================
/ctx/scripts/setup-plymouth.sh

# ==========================================================
# Bluetooth MediaTek MT7922 — workaround regressione driver
# ==========================================================
# Sul kernel CachyOS la ricezione Bluetooth del MT7922 (driver mt7921e/btmtk)
# si rompe: il controller scandisce ma NON consegna advertising report, quindi
# i dispositivi in pairing (es. tastiere/mouse BLE) restano invisibili. Hardware
# e antenna sono ok (su Windows, stesso PC, funziona). Il guasto è legato al
# risparmio energetico della radio condivisa WiFi/BT: la teniamo sveglia.
#  - btusb enable_autosuspend=0 : il transport USB del BT non va in autosuspend
#  - mt7921e disable_aspm=1     : niente ASPM sul lato PCIe (WiFi) del chip
install -d /usr/lib/modprobe.d
cat > /usr/lib/modprobe.d/mt7922-bluetooth.conf <<'EOF'
# CampiOS: la radio del MT7922 non deve dormire, altrimenti il BT non riceve.
options btusb enable_autosuspend=0
options mt7921e disable_aspm=1
EOF

# Doppia sicurezza dal boot: il Bluetooth è su USB, disattiviamo l'autosuspend USB.
install -d /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/15-mt7922-bt.toml <<'EOF'
# CampiOS: niente autosuspend USB -> il controller Bluetooth MT7922 (USB)
# resta sempre attivo e non smette di ricevere advertising.
kargs = ["usbcore.autosuspend=-1"]
EOF

# ==========================================================
# Default Flatpaks (installer + service, eseguiti al primo boot)
# ==========================================================
/ctx/scripts/setup-flatpaks.sh

# ==========================================================
# Schemi GLib
# ==========================================================
glib-compile-schemas /usr/share/glib-2.0/schemas/

# ==========================================================
# CampiOS Secure Boot (firma kernel/moduli + helper enroll MOK)
# ==========================================================
/ctx/scripts/sign-secureboot.sh
/ctx/scripts/install-mok-enroll-script.sh

# ==========================================================
# Rigenerazione initramfs — DEVE stare DOPO la firma Secure Boot
# ==========================================================
/ctx/scripts/regenerate-initramfs.sh

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
