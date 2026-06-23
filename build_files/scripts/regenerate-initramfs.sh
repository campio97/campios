#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: rigenerazione initramfs ==="

# DEVE girare DOPO la firma Secure Boot (sign-secureboot.sh). L'immagine base
# (rakuos) porta un initramfs col PROPRIO tema Plymouth: va rigenerato perché il
# logo CampiOS compaia anche al boot a freddo. Si includono esplicitamente
# "ostree" (necessario per bootc, non auto-rilevato in container) e "plymouth";
# rigenerando dopo la firma, i moduli NVIDIA nell'initramfs sono già firmati.

for kver in /usr/lib/modules/*/; do
  kver="$(basename "$kver")"
  [[ -f "/usr/lib/modules/$kver/vmlinuz" ]] || continue
  echo "Rigenero initramfs per kernel: $kver"
  dracut --force --no-hostonly --reproducible \
    --add "ostree plymouth" \
    --kver "$kver" \
    "/usr/lib/modules/$kver/initramfs.img"
done
