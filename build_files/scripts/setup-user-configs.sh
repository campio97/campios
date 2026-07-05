#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup user session configs (DMS + niri + kitty) ==="

# Modello config OS-immutabile: i default per i NUOVI utenti vivono in /etc/skel,
# mentre gli utenti GIÀ esistenti vengono riconciliati al boot da
# campios-sync-user-configs.service. Le due vie vanno tenute allineate.

# --- DMS abilitato per tutti gli utenti (systemd user globale) ---
systemctl --global enable dms.service || true
# Fallback per nuovi utenti creati da /etc/skel
mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -s /usr/lib/systemd/user/dms.service /etc/skel/.config/systemd/user/graphical-session.target.wants/

# --- niri: config di default per i nuovi utenti via /etc/skel ---
mkdir -p /etc/skel/.config/niri/
cp -rf /ctx/dot_config/niri/config.kdl /etc/skel/.config/niri/

# --- niri: config gestita + reconciliation per gli utenti ESISTENTI ---
install -d /usr/share/campios/niri
install -m 0644 /ctx/dot_config/niri/config.kdl /usr/share/campios/niri/config.kdl

# --- kitty: config di default per i nuovi utenti via /etc/skel ---
mkdir -p /etc/skel/.config/kitty/
cp -rf /ctx/dot_config/kitty/kitty.conf /etc/skel/.config/kitty/

# --- kitty: config gestita per gli utenti ESISTENTI (via sync al boot) ---
install -d /usr/share/campios/kitty
install -m 0644 /ctx/dot_config/kitty/kitty.conf /usr/share/campios/kitty/kitty.conf

install -d /usr/libexec
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

  # --- kitty: default solo se l'utente non ha già una config propria ---
  # Symlink alla config gestita, così gli aggiornamenti dell'immagine si
  # propagano; un file reale creato dall'utente non viene MAI toccato.
  kitty_dir="$home/.config/kitty"
  kitty_target="$kitty_dir/kitty.conf"
  if [ ! -e "$kitty_target" ] && [ ! -L "$kitty_target" ]; then
    install -d -o "$user" -g "$user" "$kitty_dir"
    ln -s /usr/share/campios/kitty/kitty.conf "$kitty_target"
    chown -h "$user:$user" "$kitty_target"
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
