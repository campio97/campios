#!/usr/bin/env bash
set -euo pipefail

echo "=== CampiOS: setup Rust (rustup) ==="

# Su una distro immutabile non si "bakea" il toolchain in /usr: lo si lascia
# gestire all'utente con rustup. Il pacchetto 'rustup' (in packages/install.txt)
# installa SOLO /usr/bin/rustup-init nell'immagine read-only, mentre il toolchain
# vero (rustc, cargo, std) vive in ~/.rustup e ~/.cargo, cioè nella home mutabile.
#
# Vantaggio: l'utente aggiorna Rust con `rustup update` SENZA rebuildare
# l'immagine, e può avere più toolchain (stable/nightly) in parallelo.
#
# NB: rustc/cargo/rustup veri non esistono finché non si fa il bootstrap del
# toolchain. Per non lasciare all'utente quel passo manuale, lo automatizziamo
# con un service utente che gira una tantum al primo login.

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
install -d /usr/libexec
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
