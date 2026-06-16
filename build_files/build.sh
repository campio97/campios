#!/bin/bash

set -ouex pipefail

echo "Installazione ambienti desktop..."

# 1. Installa Niri e il suo ecosistema essenziale
rpm-ostree install \
    niri \
    waybar \
    fuzzel \
    swaybg \
    mako

# Spiegazione dei pacchetti:
# niri   -> Il compositor (il motore grafico e gestore finestre)
# waybar -> La barra di stato in alto (orologio, batteria, ecc.)
# fuzzel -> Il lanciatore di applicazioni (tipo Spotlight su Mac)
# swaybg -> Per impostare l'immagine di sfondo
# mako   -> Il demone per le notifiche a comparsa

# 2. Installa COSMIC e il suo gestore di accessi (Opzionale, se li vuoi entrambi)
rpm-ostree install \
    cosmic-desktop \
    cosmic-greeter

# 3. Imposta il gestore di login
systemctl disable gdm.service || true
systemctl enable cosmic-greeter.service

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
#dnf5 install -y tmux 

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

#systemctl enable podman.socket
