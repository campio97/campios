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
  jq \
  just \
  podman \
  distrobox \
  flatpak \
  seahorse \
  lxpolkit \
  iotop \
  sysstat \
  fish

# pacchetti per verificare firma kernel dopo
$DNF install -y \
  sbsigntools \
  pesign

# ==========================================================
# Rust / Cargo (via rustup)
# ==========================================================
# Su una distro immutabile non si "bakea" il toolchain in /usr: lo si lascia
# gestire all'utente con rustup. Si installa SOLO rustup nell'immagine (in
# /usr, read-only), mentre il toolchain vero (rustc, cargo, std) vive in
# ~/.rustup e ~/.cargo, cioè nella home mutabile.
#
# Vantaggio: l'utente aggiorna Rust con `rustup update` SENZA rebuildare
# l'immagine, e può avere più toolchain (stable/nightly) in parallelo.
#
# NB: il pacchetto rustup installa SOLO /usr/bin/rustup-init: rustc/cargo/rustup
# veri non esistono finché non si fa il bootstrap del toolchain. Per non lasciare
# all'utente quel passo manuale, lo automatizziamo con un service utente che gira
# una tantum al primo login (vedi campios-rust-init.service più sotto).
$DNF install -y rustup

# --- PATH verso ~/.cargo/bin (proxy cargo/rustc + binari `cargo install`) ---
# Profile globale per shell POSIX/bash, vale per tutti.
cat > /etc/profile.d/campios-cargo.sh <<'EOF'
# CampiOS: toolchain Rust gestito da rustup nella home utente
case ":$PATH:" in
  *":$HOME/.cargo/bin:"*) ;;
  *) [ -n "$HOME" ] && PATH="$HOME/.cargo/bin:$PATH" ;;
esac
EOF

# fish NON legge /etc/profile.d/*.sh: serve uno snippet dedicato in conf.d.
install -d /etc/fish/conf.d
cat > /etc/fish/conf.d/campios-cargo.fish <<'EOF'
# CampiOS: toolchain Rust gestito da rustup nella home utente
if test -d "$HOME/.cargo/bin"
    fish_add_path -gP "$HOME/.cargo/bin"
end
EOF

# --- Bootstrap automatico del toolchain (una tantum, per utente) ---
# rustup-init scarica da internet: il service riprova finché la rete è su.
cat > /usr/libexec/campios-rust-init <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

# Già inizializzato? Niente da fare.
[ -x "$HOME/.cargo/bin/cargo" ] && exit 0
command -v rustup-init >/dev/null 2>&1 || exit 0

# Installa il toolchain stable nella home senza toccare i file rc della shell
# (il PATH lo gestiamo noi via profile.d / fish conf.d).
for _ in $(seq 1 30); do
  if rustup-init -y --no-modify-path --profile default --default-toolchain stable; then
    exit 0
  fi
  sleep 10
done
exit 1
EOF
chmod +x /usr/libexec/campios-rust-init

cat > /usr/lib/systemd/user/campios-rust-init.service <<'EOF'
[Unit]
Description=CampiOS: bootstrap toolchain Rust (rustup) al primo login
ConditionPathExists=!%h/.cargo/bin/cargo

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-rust-init

[Install]
WantedBy=default.target
EOF

# Abilita il service utente per tutti + fallback via /etc/skel per i nuovi utenti.
systemctl --global enable campios-rust-init.service || true
mkdir -p /etc/skel/.config/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/campios-rust-init.service \
  /etc/skel/.config/systemd/user/default.target.wants/campios-rust-init.service

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

  # --- Shell di login: fish per tutti gli utenti gestiti da CampiOS ---
  if [ -x /usr/bin/fish ]; then
    cur_shell="$(getent passwd "$user" | cut -d: -f7)"
    if [ "$cur_shell" != "/usr/bin/fish" ]; then
      usermod -s /usr/bin/fish "$user" || true
    fi
  fi

  # --- Plugin DankKDEConnect: abilitato di default anche per utenti esistenti ---
  # Merge non distruttivo: preserva eventuali altre impostazioni dei plugin e
  # NON forza il valore se l'utente lo ha esplicitamente cambiato.
  dms_dir="$home/.config/DankMaterialShell"
  dms_file="$dms_dir/plugin_settings.json"
  install -d -o "$user" -g "$user" "$dms_dir"

  if [ ! -e "$dms_file" ]; then
    echo '{"dankKDEConnect":{"enabled":true}}' > "$dms_file"
    chown "$user:$user" "$dms_file"
  elif command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    if jq 'if (.dankKDEConnect.enabled == null) then (.dankKDEConnect.enabled = true) else . end' \
         "$dms_file" > "$tmp" 2>/dev/null; then
      # Sovrascrive solo se cambiato e mantiene proprietario/inode del file utente
      if ! cmp -s "$tmp" "$dms_file"; then
        cat "$tmp" > "$dms_file"
        chown "$user:$user" "$dms_file"
      fi
    fi
    rm -f "$tmp"
  fi

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
add_dracutmodules+=" plymouth ostree "
hostonly="no"
install_items+=" /etc/plymouth/plymouthd.conf "
install_items+=" /usr/share/plymouth/themes/campios/campios.plymouth "
install_items+=" /usr/share/plymouth/themes/campios/campios.script "
install_items+=" /usr/share/plymouth/themes/campios/logo.png "
EOF

plymouth-set-default-theme campios
# NB: l'initramfs viene rigenerato DOPO la firma Secure Boot (vedi più sotto),
# così da includere il tema CampiOS e i moduli kernel già firmati.

# Kernel cmdline per uno splash pulito, gestito da bootc tramite kargs.d.
# I parametri vengono applicati al bootloader a ogni deploy/upgrade.
install -d /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/10-campios.toml <<'EOF'
# quiet                       -> riduce i log del kernel sulla console
# splash                      -> attiva lo splash grafico di Plymouth
# rd.systemd.show_status=false-> nasconde i messaggi di stato systemd nell'initramfs
kargs = ["quiet", "splash", "rd.systemd.show_status=false"]
EOF

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
# Rigenerazione initramfs (DOPO la firma dei moduli)
# ==========================================================
# L'immagine base (rakuos) porta un initramfs col PROPRIO tema Plymouth: va
# rigenerato perché il logo CampiOS compaia anche al boot a freddo. Si includono
# esplicitamente "ostree" (necessario per bootc, non auto-rilevato in container)
# e "plymouth", e si rigenera dopo la firma così i moduli NVIDIA nell'initramfs
# sono già firmati per Secure Boot.

for kver in /usr/lib/modules/*/; do
  kver="$(basename "$kver")"
  [[ -f "/usr/lib/modules/$kver/vmlinuz" ]] || continue
  echo "Rigenero initramfs per kernel: $kver"
  dracut --force --no-hostonly --reproducible \
    --add "ostree plymouth" \
    --kver "$kver" \
    "/usr/lib/modules/$kver/initramfs.img"
done

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
