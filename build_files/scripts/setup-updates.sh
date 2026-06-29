#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup aggiornamenti automatici (bootc + notifica al login) ==="

# Aggiornamenti in due parti, per separare il privilegio dalla sessione:
#
#   1) SISTEMA (root): il timer bootc-fetch-apply-updates scarica e PREPARA
#      l'aggiornamento in background (attivo al prossimo reboot, non riavvia da
#      solo). Un ExecStartPost scrive un flag in /run quando c'è un deployment
#      in staging.
#   2) UTENTE (sessione): al login un service utente legge quel flag e mostra
#      una notifica. Non tocca bootc, quindi niente sudo/polkit nella sessione.
#
# Le due vie utente (globale + /etc/skel) vanno tenute allineate come per DMS.

# ==========================================================
# Parte 1 — Auto-update di sistema (timer bootc)
# ==========================================================
# Il timer e il service sono forniti dal pacchetto bootc della base: qui li
# abilitiamo e ne ritocchiamo la cadenza, senza riscriverli.
if [ -f /usr/lib/systemd/system/bootc-fetch-apply-updates.timer ]; then
  systemctl enable bootc-fetch-apply-updates.timer

  # Cadenza CampiOS: un check ~10 min dopo il boot (così il flag è già pronto
  # quando l'utente si logga) + ricontrollo periodico. RandomizedDelaySec evita
  # picchi simultanei su molte macchine. I trigger si aggiungono al default.
  install -d /usr/lib/systemd/system/bootc-fetch-apply-updates.timer.d
  cat > /usr/lib/systemd/system/bootc-fetch-apply-updates.timer.d/10-campios.conf <<'EOF'
[Timer]
OnBootSec=10min
OnUnitActiveSec=6h
RandomizedDelaySec=30min
EOF

  install -d /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d

  # Il service della base gira "bootc update --apply": --apply RIAVVIA SUBITO la
  # macchina appena trova un'immagine nuova. CampiOS vuole invece solo scaricare
  # e mettere in STAGING (applicato al prossimo reboot manuale, segnalato dalla
  # notifica al login), quindi sovrascriviamo l'ExecStart togliendo --apply.
  # Senza questo override il PC si riavvia da solo, senza preavviso, a metà
  # sessione (la riga vuota "ExecStart=" azzera quella ereditata dalla base).
  cat > /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/20-campios-stage-only.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/bootc update --quiet
EOF

  # Dopo ogni run del service, calcola/azzera il flag "update pronto".
  cat > /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-campios-flag.conf <<'EOF'
[Service]
ExecStartPost=/usr/libexec/campios-update-flag
EOF
else
  echo "ATTENZIONE: bootc-fetch-apply-updates.timer non trovato nella base; auto-update non abilitato" >&2
fi

# --- Helper di sistema: scrive il flag se c'è un deployment in staging ---
install -d /usr/libexec
cat > /usr/libexec/campios-update-flag <<'EOF'
#!/usr/bin/env bash
# Gira come root da ExecStartPost di bootc-fetch-apply-updates.service.
# Non deve MAI far fallire il service: esce sempre 0.
set -uo pipefail

FLAG_DIR="/run/campios"
FLAG="$FLAG_DIR/update-staged"
install -d "$FLAG_DIR"

staged="no"
ver=""
if command -v bootc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  json="$(bootc status --format json 2>/dev/null || true)"
  if [ -n "$json" ]; then
    staged="$(printf '%s' "$json" | jq -r 'if .status.staged != null then "yes" else "no" end' 2>/dev/null || echo no)"
    # Stringa di versione "best effort" solo per il testo della notifica.
    ver="$(printf '%s' "$json" | jq -r '.status.staged.image.version // .status.staged.image.image.image // empty' 2>/dev/null || true)"
  fi
fi

if [ "$staged" = "yes" ]; then
  printf '%s\n' "${ver:-update}" > "$FLAG"
else
  rm -f "$FLAG"
fi
exit 0
EOF
chmod +x /usr/libexec/campios-update-flag

# ==========================================================
# Parte 2 — Notifica al login (service utente)
# ==========================================================
# --- Helper utente: notifica se il flag esiste (non tocca bootc) ---
cat > /usr/libexec/campios-notify-update <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

FLAG="/run/campios/update-staged"
STAMP="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/campios-update-notified"

[ -f "$FLAG" ] || exit 0

# Non rinotificare più volte nella stessa sessione di boot per lo stesso update.
if [ -f "$STAMP" ] && cmp -s "$FLAG" "$STAMP"; then
  exit 0
fi

command -v notify-send >/dev/null 2>&1 || exit 0

ver="$(cat "$FLAG" 2>/dev/null || true)"
body="Riavvia per applicare l'ultima versione di CampiOS."
[ -n "$ver" ] && [ "$ver" != "update" ] && body="Versione: $ver. $body"

# Il demone di notifiche (DMS) potrebbe non essere ancora pronto: riprova.
for _ in $(seq 1 30); do
  if notify-send -a CampiOS -u normal \
       "Aggiornamento di sistema pronto" "$body"; then
    cp -f "$FLAG" "$STAMP" 2>/dev/null || :
    exit 0
  fi
  sleep 2
done
exit 0
EOF
chmod +x /usr/libexec/campios-notify-update

# --- Service utente: parte ad ogni login, dopo che DMS è su ---
cat > /usr/lib/systemd/user/campios-notify-update.service <<'EOF'
[Unit]
Description=CampiOS: notifica se è pronto un aggiornamento di sistema
After=dms.service
Wants=dms.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/campios-notify-update

[Install]
WantedBy=graphical-session.target
EOF

# Abilita per tutti (systemd user globale) + fallback /etc/skel per i nuovi utenti.
systemctl --global enable campios-notify-update.service || true
mkdir -p /etc/skel/.config/systemd/user/graphical-session.target.wants
ln -sf /usr/lib/systemd/user/campios-notify-update.service \
  /etc/skel/.config/systemd/user/graphical-session.target.wants/campios-notify-update.service
