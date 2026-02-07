# Omarchy Modular Installation Repo

This repository provides a **modular, reproducible setup** for an Omarchy-based Linux environment, including dotfiles, Hyprland overrides, shell configuration, and a **robust SSH agent setup** designed to work seamlessly with devcontainers.

The setup is intentionally **idempotent** and **agent-based**, avoiding SSH key leakage into containers.

---

## Installation

Clone the repository and run:

```bash
./install-all.sh
```

If needed, make it executable first:

```bash
chmod +x install-all.sh
```

The installer is safe to re-run at any time.

---

## How It Works

1. Creates a dotfiles directory, installs required tools, and uses `stow` to symlink configuration into `~/.config`
2. Generates `hyprland-overrides.conf` and automatically adds a `source` entry in:
   ```text
   ~/.config/hypr/hyprland.conf
   ```
3. Shell setup is modular:
   - Bash is default
   - To switch to zsh:
     ```bash
     ./install-zsh.sh
     ./set-shell.sh
     ```

---

## SSH Setup (Agent-Based, Persistent, Container-Friendly)

This repo configures SSH around **a single system-managed SSH agent** with automatic startup and automatic key loading.

Private keys are never copied into containers.

---

## What Is Configured (Linux)

- systemd user `ssh-agent.socket`
- One SSH agent per user session
- Automatic re-add of **all private keys in `~/.ssh`** on login
- Automatic permission fixes:
  - `~/.ssh` → `700`
  - private keys → `600`
- Global export:
  ```bash
  SSH_AUTH_SOCK=/run/user/<uid>/ssh-agent.socket
  ```

Keys are expected **not** to require a passphrase (intentional for dev workflows).

---

## SSH Installation Script

SSH is configured by:

```bash
install-ssh.sh
```

It is safe to run multiple times.

The script:

- Enables and starts `ssh-agent.socket`
- Ensures `SSH_AUTH_SOCK` is exported in `.bashrc` and `.zshrc`
- Installs helper:
  ```text
  ~/.local/bin/ssh-add-all
  ```
- Detects all RSA / ED25519 / ECDSA keys by file content
- Fixes permissions automatically
- Adds keys individually so one bad file does not break the agent
- Installs systemd user service:
  ```text
  ~/.config/systemd/user/ssh-add.service
  ```

---

## Verifying SSH on Host

After install or reboot:

```bash
ssh-add -l
```

Verify socket:

```bash
echo $SSH_AUTH_SOCK
# /run/user/<uid>/ssh-agent.socket
```

---

## SSH in Devcontainers

### Design Principles

- Host `~/.ssh` is **not mounted** into containers by default
- Only the SSH agent socket is forwarded
- Containers authenticate via host agent
- Private keys never enter container filesystem

---

### Linux Behavior

- Uses `$SSH_AUTH_SOCK` if present
- Fallback to:
  ```text
  /run/user/<uid>/ssh-agent.socket
  ```

Works even when started from non-interactive shells.

---

### macOS Behavior

- Uses Docker Desktop socket:
  ```text
  /run/host-services/ssh-auth.sock
  ```

---

## Verifying SSH Inside Container

Inside container:

```bash
echo $SSH_AUTH_SOCK
ssh-add -l
ssh -T git@github.com
```

---

## Notes

- If Git asks for username/password, the remote is likely HTTPS, not SSH
- Agent forwarding is preferred over mounting keys
- Mounting host `~/.ssh` is intentionally disabled by default
