#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup dev-box (distrobox: VSCode + Rust + Python) ==="

# Modello OS-immutabile: l'ambiente di sviluppo NON si bakea in /usr. Le distrobox
# sono per-utente (podman rootless, storage nella home mutabile), quindi la box
# "dev-box" si crea al PRIMO LOGIN tramite un service utente oneshot — stesso
# schema del vecchio bootstrap rustup. Qui depositiamo il manifest `distrobox
# assemble` (dato), il creatore e il service, e li abilitiamo per tutti.

# --- Manifest assemble (dato) in posizione gestita read-only ---
install -d /usr/share/campios/distrobox
install -m 0644 /ctx/distrobox/dev-box.ini /usr/share/campios/distrobox/dev-box.ini

# --- Creatore della dev-box (gira come utente al primo login) ---
install -d /usr/libexec
cat > /usr/libexec/campios-create-devbox <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

INI="/usr/share/campios/distrobox/dev-box.ini"
BOX="dev-box"

command -v distrobox >/dev/null 2>&1 || exit 0
[ -f "$INI" ] || exit 0

# Già creata? Niente da fare (il service è oneshot ma parte ad ogni login).
if distrobox list 2>/dev/null | grep -qw "$BOX"; then
  exit 0
fi

# `distrobox assemble` scarica l'immagine e installa i pacchetti: serve la rete.
# Al primo boot la connessione potrebbe non essere ancora pronta: riprova.
for _ in $(seq 1 30); do
  if distrobox assemble create --file "$INI"; then
    exit 0
  fi
  sleep 10
done
exit 1
EOF
chmod +x /usr/libexec/campios-create-devbox

# --- Service utente: crea la dev-box una tantum al primo login ---
cat > /usr/lib/systemd/user/campios-dev-box.service <<'EOF'
[Unit]
Description=CampiOS: crea la distrobox dev-box (VSCode + Rust + Python) al primo login
ConditionPathExists=/usr/share/campios/distrobox/dev-box.ini

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-create-devbox
TimeoutStartSec=30min

[Install]
WantedBy=default.target
EOF

# Abilita il service utente per tutti + fallback via /etc/skel per i nuovi utenti.
systemctl --global enable campios-dev-box.service || true
mkdir -p /etc/skel/.config/systemd/user/default.target.wants
ln -sf /usr/lib/systemd/user/campios-dev-box.service \
  /etc/skel/.config/systemd/user/default.target.wants/campios-dev-box.service
