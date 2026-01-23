# Omarchy modular installation repo

## installation
Clone and run `./install-all.sh`
Make it executable if needed `chmod +x install-all.sh`

## how it works ?

1. Create dotfiles directory, install specified tools and `stow` (symlink) everything to `~/.config`
2. Create hyprland-overrides.conf and auto-add a source in
   `~/.config/hypr/hyprland.conf` to apply changes
3. To switch for zsh run `install-zsh.sh` then `set-shell.sh` separately
