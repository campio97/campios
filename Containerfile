# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
# rakuos ha migrato le immagini da ghcr.io -> GitLab -> quay.io (merge con Origami
# Linux, release 44 del 2026-06-02). La vecchia ghcr.io/rakuos/rakuos-base-nvidia
# e' ferma a Fedora 43 / nvidia 595 (ultimo tag 2026-04-19); quay.io e' ricostruita
# ogni giorno (Fedora 44 / nvidia 610). quay.io e' gia' fidata in policy.json.
FROM quay.io/rakuos/rakuos-base-nvidia:latest

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=campios_mok_key,target=/run/secrets/campios_mok_key \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# bootc-image-builder non conosce l'ID "rakuos".
# Lo dichiariamo come Fedora derivative per permettere la generazione ISO/QCOW2.
RUN sed -i 's/^ID=.*/ID=fedora/' /etc/os-release && \
    sed -i 's/^NAME=.*/NAME="CampiOS"/' /etc/os-release && \
    sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="CampiOS"/' /etc/os-release && \
    grep -q '^ID_LIKE=' /etc/os-release \
      && sed -i 's/^ID_LIKE=.*/ID_LIKE="fedora rakuos"/' /etc/os-release \
      || echo 'ID_LIKE="fedora rakuos"' >> /etc/os-release

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
