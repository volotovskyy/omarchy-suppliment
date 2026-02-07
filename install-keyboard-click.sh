#!/usr/bin/env bash
set -euo pipefail

need_cmd() { command -v "$1" >/dev/null 2>&1; }

AUR_DIR="${AUR_DIR:-$HOME/.local/src/aur}"
CFG_DIR="$HOME/.config/wl-kbptr"
CFG_FILE="$CFG_DIR/config"

install_pacman_deps() {
  echo "→ Installing build deps via pacman (requires sudo)"
  sudo pacman -S --needed --noconfirm git base-devel
}

aur_build_install() {
  local pkg="$1"
  local url="https://aur.archlinux.org/${pkg}.git"
  local dir="${AUR_DIR}/${pkg}"

  if pacman -Q "$pkg" >/dev/null 2>&1; then
    echo "✓ $pkg already installed"
    return 0
  fi

  mkdir -p "$AUR_DIR"

  if [[ -d "$dir/.git" ]]; then
    echo "→ Updating AUR repo: $pkg"
    git -C "$dir" pull --ff-only
  else
    echo "→ Cloning AUR repo: $pkg"
    git clone "$url" "$dir"
  fi

  echo "→ Building + installing: $pkg"
  (cd "$dir" && makepkg -si --noconfirm)
}

write_wl_kbptr_config() {
  echo "→ Writing wl-kbptr config (no scroll mode; use wlrctl for scroll binds)"
  mkdir -p "$CFG_DIR"

  cat > "$CFG_FILE" <<'EOF'
[general]
modes=floating,click

[mode_floating]
source=detect
label_color=#ffff00ff
label_select_color=#ffd000ff
label_font_family=sans-serif
label_font_size=18 50% 100
label_symbols=abcdefghijklmnopqrstuvwxyz

[mode_click]
button=left
EOF

  echo "✓ Config written: $CFG_FILE"
}

main() {
  install_pacman_deps

  # wl-kbptr (AUR)
  aur_build_install "wl-kbptr"

  # wlrctl (AUR) for Hyprland scroll binds (optional but recommended)
  # Comment this out if you don't want it.
  aur_build_install "wlrctl"

  write_wl_kbptr_config

  echo "→ Verifying"
  wl-kbptr --version
  if need_cmd wlrctl; then
    echo "✓ wlrctl installed"
  else
    echo "ℹ wlrctl not installed"
  fi

  echo "✓ Done"
  echo "  wl-kbptr: run 'wl-kbptr' or trigger your Hyprland bind"
  echo "  scroll: use your Hyprland wlrctl binds"
}

main "$@"

