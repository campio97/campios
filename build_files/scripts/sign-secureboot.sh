#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS Secure Boot signing ==="

KEY_SECRET="/run/secrets/campios_mok_key"
CERT_PEM="/ctx/secureboot/campios-mok.pem"
CERT_DER="/ctx/secureboot/campios-mok.der"

if [[ ! -f "$KEY_SECRET" ]]; then
  echo "ERRORE: secret non trovato: $KEY_SECRET"
  exit 1
fi

if [[ ! -f "$CERT_PEM" || ! -f "$CERT_DER" ]]; then
  echo "ERRORE: certificati CampiOS non trovati in /ctx/secureboot"
  exit 1
fi

install -d /etc/pki/campios/secureboot
install -m 0644 "$CERT_DER" /etc/pki/campios/secureboot/campios-mok.der
install -m 0644 "$CERT_PEM" /etc/pki/campios/secureboot/campios-mok.pem

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

install -m 0600 "$KEY_SECRET" "$TMPDIR/campios-mok.key"
install -m 0644 "$CERT_PEM" "$TMPDIR/campios-mok.pem"

echo
echo "=== Signing kernels ==="

for kernel in /usr/lib/modules/*/vmlinuz; do
  [[ -f "$kernel" ]] || continue

  echo "Signing kernel: $kernel"

  unsigned="${kernel}.unsigned"
  cp -a "$kernel" "$unsigned"

  sbsign \
    --key "$TMPDIR/campios-mok.key" \
    --cert "$TMPDIR/campios-mok.pem" \
    --output "$kernel" \
    "$unsigned"

  chmod --reference="$unsigned" "$kernel"
  rm -f "$unsigned"
done

echo
echo "=== Signing kernel modules ==="

for kdir in /usr/lib/modules/*; do
  [[ -d "$kdir" ]] || continue

  kver="$(basename "$kdir")"
  sign_file="$kdir/build/scripts/sign-file"

  if [[ ! -x "$sign_file" ]]; then
    sign_file="/usr/src/kernels/$kver/scripts/sign-file"
  fi

  if [[ ! -x "$sign_file" ]]; then
    echo "WARNING: scripts/sign-file non trovato per $kver, salto firma moduli."
    continue
  fi

  echo "Signing modules for kernel: $kver"

  find "$kdir" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' \) | while read -r mod; do
    case "$mod" in
      *.ko)
        "$sign_file" sha256 "$TMPDIR/campios-mok.key" "$TMPDIR/campios-mok.pem" "$mod"
        ;;

      *.ko.xz)
        unxz "$mod"
        raw="${mod%.xz}"
        "$sign_file" sha256 "$TMPDIR/campios-mok.key" "$TMPDIR/campios-mok.pem" "$raw"
        xz -f "$raw"
        ;;

      *.ko.zst)
        unzstd -q "$mod"
        raw="${mod%.zst}"
        "$sign_file" sha256 "$TMPDIR/campios-mok.key" "$TMPDIR/campios-mok.pem" "$raw"
        zstd -q -f "$raw" -o "$mod"
        rm -f "$raw"
        ;;
    esac
  done

  depmod "$kver"
done

echo
echo "=== Verifying kernel signatures ==="

for kernel in /usr/lib/modules/*/vmlinuz; do
  [[ -f "$kernel" ]] || continue

  echo "Checking Secure Boot signature for: $kernel"

  sbverify --list "$kernel" | tee /tmp/campios-kernel-signature.txt

  if ! grep -Ei 'CampiOS Secure Boot|RakuOS|Fedora|ublue|Microsoft' /tmp/campios-kernel-signature.txt; then
    echo "ERRORE: kernel non firmato o firmato con chiave inattesa: $kernel"
    cat /tmp/campios-kernel-signature.txt
    exit 1
  fi
done

echo "CampiOS Secure Boot signing OK."