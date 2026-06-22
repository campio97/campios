#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing CampiOS MOK enrollment helper ==="

install -d /usr/libexec

cat > /usr/libexec/campios-enroll-mok <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CERT="/etc/pki/campios/secureboot/campios-mok.der"
PASSWORD="campios"

if [[ ! -d /sys/firmware/efi ]]; then
  echo "UEFI non rilevato. Salto enrollment MOK."
  exit 0
fi

if [[ ! -f "$CERT" ]]; then
  echo "Certificato CampiOS MOK non trovato: $CERT"
  exit 1
fi

if mokutil --test-key "$CERT" >/dev/null 2>&1; then
  echo "CampiOS MOK gia' enrollata."
  exit 0
fi

mokutil --timeout -1 || true

printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | mokutil --import "$CERT"

echo
echo "Richiesta MOK CampiOS creata."
echo "Riavvia e nel MokManager scegli:"
echo "  Enroll MOK -> Continue -> Yes"
echo "Password: $PASSWORD"
EOF

chmod +x /usr/libexec/campios-enroll-mok

echo "Installed: /usr/libexec/campios-enroll-mok"