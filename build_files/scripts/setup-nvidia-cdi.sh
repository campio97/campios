#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup CDI NVIDIA per i container ==="

# Il pacchetto nvidia-container-toolkit e' installato da packages/install.txt.
# Qui: la unit che genera lo spec CDI, cioe' il file che descrive a podman quali
# device e librerie del driver montare dentro al container per dargli la GPU
# (`podman run --device nvidia.com/gpu=all ...`, anche rootless).
#
# Perche' a RUNTIME e non a build-time:
#   - `nvidia-ctk cdi generate` enumera i nodi /dev/nvidia*, che nel container di
#     build non esistono: a build-time il comando non avrebbe nulla da descrivere;
#   - lo spec e' legato alla versione ESATTA del driver (i path delle librerie
#     sono versionati). Su bootc il driver arriva dall'immagine e cambia insieme
#     al deployment, quindi uno spec congelato si disallineerebbe al primo
#     `bootc upgrade` che porta una base con driver nuovo -> GPU invisibile ai
#     container finche' non lo si rigenera a mano.
#
# Perche' in /run/cdi e non in /etc/cdi:
# podman scandisce entrambe le directory. /run e' tmpfs, quindi lo spec si
# rigenera pulito a ogni boot ed e' per costruzione allineato al driver in
# esecuzione; niente file stale da ricordarsi di rifare dopo un aggiornamento.
# (Il pacchetto possiede /etc/cdi/nvidia.yaml come %ghost e non lo popola mai:
# lasciamo quel path vuoto.)

cat > /usr/lib/systemd/system/campios-nvidia-cdi.service <<'EOF'
[Unit]
Description=CampiOS: genera lo spec CDI NVIDIA per i container
Documentation=https://github.com/NVIDIA/nvidia-container-toolkit
After=local-fs.target systemd-modules-load.service
# Se la GPU NVIDIA non c'e' (o il driver non ha caricato) la unit si salta in
# silenzio invece di fallire: l'immagine deve restare avviabile lo stesso.
ConditionPathExistsGlob=/dev/nvidia[0-9]*

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/mkdir -p /run/cdi
ExecStart=/usr/bin/nvidia-ctk cdi generate --output=/run/cdi/nvidia.yaml

[Install]
WantedBy=multi-user.target
EOF

systemctl enable campios-nvidia-cdi.service
