#!/usr/bin/env bash
set -Eeuo pipefail

need() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$*"; }

need yay || die "yay is required"

log "[asdf] installing/updating asdf-vm (AUR)"
yay -S --noconfirm --needed asdf-vm

need asdf || die "asdf binary not found after install"

# ---- shell integration (idempotent, existing rc files only) ----

ASDF_LINE_1='export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"'
ASDF_LINE_2='export PATH="$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:$PATH"'
GO_ENV_LINE='. ${ASDF_DATA_DIR:-$HOME/.asdf}/plugins/golang/set-env.bash'

ensure_line_if_file_exists() {
  local file="$1" line="$2"
  [[ -f "$file" ]] || return 0
  grep -qxF "$line" "$file" || printf '\n%s\n' "$line" >>"$file"
}

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  ensure_line_if_file_exists "$rc" "$ASDF_LINE_1"
  ensure_line_if_file_exists "$rc" "$ASDF_LINE_2"
  ensure_line_if_file_exists "$rc" "$GO_ENV_LINE"
done

# Make asdf usable in this run
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
mkdir -p "$ASDF_DATA_DIR"
export PATH="$ASDF_DATA_DIR/bin:$ASDF_DATA_DIR/shims:$PATH"

# ---- build deps (Ruby + native extensions) ----

log "[deps] installing build dependencies"
yay -S --noconfirm --needed \
  base-devel gcc make \
  openssl readline zlib libyaml libffi \
  rust git

# ---- helpers ----

plugin_add_if_missing() {
  local name="$1" url="$2"
  if asdf plugin list 2>/dev/null | grep -qx "$name"; then
    log "[asdf] plugin already present: $name"
  else
    log "[asdf] adding plugin: $name"
    asdf plugin add "$name" "$url"
  fi
}

GLOBAL_TOOL_VERSIONS="$HOME/.tool-versions"
touch "$GLOBAL_TOOL_VERSIONS"

tool_versions_get() {
  local tool="$1"
  awk -v t="$tool" '$1==t {print $2; exit 0}' "$GLOBAL_TOOL_VERSIONS"
}

ensure_global_tool() {
  local tool="$1" url="$2"

  plugin_add_if_missing "$tool" "$url"

  local pinned
  pinned="$(tool_versions_get "$tool" || true)"

  if [[ -n "$pinned" ]]; then
    if ! asdf list "$tool" 2>/dev/null | awk '{print $1}' | grep -qx "$pinned"; then
      log "[asdf] installing pinned $tool $pinned"
      asdf install "$tool" "$pinned"
    else
      log "[asdf] pinned $tool $pinned already installed"
    fi
  else
    log "[asdf] setting global default for $tool (latest)"
    asdf install "$tool" latest
    asdf set -u "$tool" latest
  fi
}

# ---- tools ----

ensure_global_tool golang "https://github.com/asdf-community/asdf-golang.git"
ensure_global_tool nodejs "https://github.com/asdf-vm/asdf-nodejs.git"
ensure_global_tool ruby  "https://github.com/asdf-vm/asdf-ruby.git"

log "Done."
log "Restart your shell, then verify:"
log "  asdf current"
log "  go version"
log "  node -v"
log "  ruby -v"

