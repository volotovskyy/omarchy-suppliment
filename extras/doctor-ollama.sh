#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "[$(date +'%F %T')] $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

require() {
  if ! have "$1"; then
    log "Missing required command: $1"
    exit 1
  fi
}

write_override_env() {
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="HOME=/var/lib/ollama"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"
EOF
}

normalize_model_layout() {
  sudo mkdir -p /var/lib/ollama/models

  # If older layout exists at /var/lib/ollama/{blobs,manifests}, move/merge into /models
  sudo bash -lc '
set -e
mkdir -p /var/lib/ollama/models
for d in blobs manifests; do
  if [ -d "/var/lib/ollama/$d" ]; then
    mkdir -p "/var/lib/ollama/models/$d"
    rsync -a "/var/lib/ollama/$d"/ "/var/lib/ollama/models/$d"/
    rm -rf "/var/lib/ollama/$d"
  fi
done
chown -R ollama:ollama /var/lib/ollama/models
'
}

restart_and_verify() {
  sudo systemctl daemon-reload
  sudo systemctl restart ollama.service

  log "service env:"
  systemctl show ollama -p User -p Group -p Environment -p ExecStart --no-pager || true

  log "listening:"
  ss -ltnp | grep 11434 || true

  log "api/version:"
  curl -sS http://127.0.0.1:11434/api/version || true

  log "api/tags:"
  curl -sS http://127.0.0.1:11434/api/tags || true
}

main() {
  require systemctl
  require ss
  require curl

  if ! have ollama; then
    log "ollama not in PATH. Install first."
    exit 1
  fi

  log "Writing systemd override (HOME + OLLAMA_MODELS)..."
  write_override_env

  log "Normalizing model directory layout..."
  normalize_model_layout

  log "Restarting and verifying..."
  restart_and_verify
}

main "$@"
