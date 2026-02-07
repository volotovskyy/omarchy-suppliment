#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "[$(date +'%F %T')] $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

ensure_curl() {
  if have curl; then return 0; fi
  log "curl missing; installing..."
  if have pacman; then sudo pacman -S --noconfirm curl
  elif have apt-get; then sudo apt-get update && sudo apt-get install -y curl
  elif have dnf; then sudo dnf install -y curl
  else
    log "No supported package manager found to install curl."
    exit 1
  fi
}

install_arch() {
  log "Installing via pacman..."
  sudo pacman -Syu --noconfirm ollama
}

install_official() {
  log "Installing via official install script..."
  ensure_curl
  curl -fsSL https://ollama.com/install.sh | sh
}

start_service() {
  if systemctl list-unit-files | grep -q '^ollama\.service'; then
    sudo systemctl enable --now ollama.service
    sudo systemctl restart ollama.service || true
  else
    log "No systemd unit found after install (unexpected)."
    exit 1
  fi
}

main() {
  if ! have ollama; then
    if have pacman; then install_arch; else install_official; fi
  else
    log "ollama already present: $(ollama --version 2>/dev/null || true)"
  fi

  start_service

  log "systemd status:"
  systemctl status ollama --no-pager || true

  log "daemon version:"
  ensure_curl
  curl -sS http://127.0.0.1:11434/api/version || true
}

main "$@"

