#!/bin/bash

# Install all packages in order!

# run individually to switch for zsh
# ./install-zsh.sh
# ./set-shell.sh

./install-asdf.sh
./install-postgresql.sh
./install-ghostty.sh
./install-tmux.sh
./install-stow.sh
./install-dotfiles.sh
./install-hyprland-overrides.sh

# run separately after ensured that there are ssh keys in ~/.ssh
# ./install-ssh.sh
