#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[install-ssh]"
AUTH_SOCK_LINE='export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"'

XDG_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_PATH="$XDG_USER_DIR/ssh-add.service"

LOCAL_BIN_DIR="${HOME}/.local/bin"
HELPER_PATH="${LOCAL_BIN_DIR}/ssh-add-all"

say() { echo "${LOG_PREFIX} $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "${LOG_PREFIX} ERROR: missing command: $1" >&2
    exit 1
  }
}

append_line_if_missing() {
  local file="$1"
  local line="$2"

  [[ -f "$file" ]] || touch "$file"

  if grep -Fqx "$line" "$file"; then
    say "OK: line already present in $file"
    return 0
  fi

  {
    echo ""
    echo "# Added by install-ssh.sh (ssh-agent via systemd user socket)"
    echo "$line"
  } >>"$file"

  say "Added SSH_AUTH_SOCK export to $file"
}

ensure_systemd_agent_socket() {
  say "Ensuring systemd user ssh-agent.socket is enabled and started..."
  systemctl --user enable --now ssh-agent.socket >/dev/null
  systemctl --user is-enabled ssh-agent.socket >/dev/null
  systemctl --user is-active ssh-agent.socket >/dev/null
  say "OK: ssh-agent.socket enabled and active"
}

write_helper_script() {
  mkdir -p "$LOCAL_BIN_DIR"

  cat >"$HELPER_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ssh-add-all
# - Fixes ~/.ssh permissions
# - Detects private keys by file content headers (not filenames)
# - Adds each key individually so one failure doesn't break the whole run

SSH_DIR="${HOME}/.ssh"
SOCK="${SSH_AUTH_SOCK:-}"

log() { echo "[ssh-add-all] $*"; }

if [[ -z "$SOCK" ]]; then
  log "ERROR: SSH_AUTH_SOCK is empty"
  exit 1
fi

if [[ ! -d "$SSH_DIR" ]]; then
  log "No ~/.ssh directory; nothing to do."
  exit 0
fi

# Strict perms
chmod 700 "$SSH_DIR" || true

# Reasonable defaults for common files (avoid OpenSSH warnings)
# - private keys: 600
# - *.pub / known_hosts*: 644
# - config / authorized_keys: 600
while IFS= read -r f; do
  base="$(basename "$f")"

  if [[ "$base" == *.pub || "$base" == known_hosts* ]]; then
    chmod 644 "$f" 2>/dev/null || true
    continue
  fi

  if [[ "$base" == config || "$base" == authorized_keys ]]; then
    chmod 600 "$f" 2>/dev/null || true
    continue
  fi

  # For everything else, if it looks like a private key, lock it down.
  # Detect by header content.
  if head -n 2 "$f" 2>/dev/null | grep -Eq 'BEGIN (OPENSSH|[A-Z0-9 ]+) PRIVATE KEY'; then
    chmod 600 "$f" 2>/dev/null || true
  fi
done < <(find "$SSH_DIR" -maxdepth 1 -type f 2>/dev/null)

# Find candidate private keys by header signatures.
# Covers:
# - OpenSSH new format: -----BEGIN OPENSSH PRIVATE KEY-----
# - PEM keys (RSA/EC/DSA/PKCS8): -----BEGIN ... PRIVATE KEY-----
# - Some edge cases with "ssh-" markers in first line(s)
mapfile -t candidates < <(
  find "$SSH_DIR" -maxdepth 1 -type f 2>/dev/null | sort -u | while read -r f; do
    base="$(basename "$f")"

    # Skip obvious non-keys
    case "$base" in
      *.pub|known_hosts|known_hosts.old|config|authorized_keys|environment|rc|README)
        continue
        ;;
    esac

    # Content-based detection
    if head -n 5 "$f" 2>/dev/null | grep -Eq 'BEGIN (OPENSSH|[A-Z0-9 ]+) PRIVATE KEY'; then
      echo "$f"
      continue
    fi

    if head -n 5 "$f" 2>/dev/null | grep -Eq '^ssh-(rsa|ed25519|ecdsa)'; then
      echo "$f"
      continue
    fi
  done
)

if ((${#candidates[@]} == 0)); then
  log "No private keys detected in ~/.ssh"
  exit 0
fi

log "Detected keys:"
printf '  - %s\n' "${candidates[@]}"

# Add each key individually so a single bad key doesn't fail the unit.
added=0
failed=0
for k in "${candidates[@]}"; do
  # Ensure private key perms are strict enough before add
  chmod 600 "$k" 2>/dev/null || true

  if ssh-add "$k" >/dev/null 2>&1; then
    log "Added: $k"
    ((added+=1))
  else
    log "Skipped (not a valid key / wrong format / needs passphrase / etc): $k"
    ((failed+=1))
  fi
done

log "Done. added=${added}, skipped=${failed}"
exit 0
EOF

  chmod 755 "$HELPER_PATH"
  say "Installed helper: $HELPER_PATH"
}

write_service() {
  mkdir -p "$XDG_USER_DIR"

  cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Add SSH keys to ssh-agent (all keys in ~/.ssh)
After=ssh-agent.socket
Wants=ssh-agent.socket

[Service]
Type=oneshot
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=${HELPER_PATH}
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

  say "Wrote service: $SERVICE_PATH"

  systemctl --user daemon-reload >/dev/null
  systemctl --user enable ssh-add.service >/dev/null || true
  systemctl --user restart ssh-add.service >/dev/null || true
}

verify() {
  say "Verifying SSH_AUTH_SOCK in this session..."
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.bashrc" 2>/dev/null || true
  fi

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    say "WARN: SSH_AUTH_SOCK is empty in this session. Open a new terminal or run: source ~/.bashrc"
  else
    say "OK: SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
  fi

  say "Identities:"
  ssh-add -l || true
}

main() {
  need_cmd systemctl
  need_cmd ssh-agent
  need_cmd ssh-add
  need_cmd find
  need_cmd grep
  need_cmd head
  need_cmd sort

  ensure_systemd_agent_socket

  append_line_if_missing "$HOME/.bashrc" "$AUTH_SOCK_LINE"
  if [[ -f "$HOME/.zshrc" ]]; then
    append_line_if_missing "$HOME/.zshrc" "$AUTH_SOCK_LINE"
  fi

  write_helper_script
  write_service
  verify

  say "Done. (optional) Reboot and run: ssh-add -l"
}

main "$@"

