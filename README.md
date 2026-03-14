# Developer Shell Setup

Automates Zsh, Oh My Zsh, Powerlevel10k theme, plugins, and fonts on Ubuntu/Debian.

## Quick Start

```bash
# Local usage
sudo ./bootstrap-shell.sh install
sudo ./bootstrap-shell.sh uninstall
```

## Install via Curl

Run directly from GitHub without cloning:

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/tspyder7/bootstrap-shell/main/bootstrap-shell.sh | sudo bash -s -- install

# Uninstall
curl -fsSL https://raw.githubusercontent.com/tspyder7/bootstrap-shell/main/bootstrap-shell.sh | sudo bash -s -- uninstall
```

## Usage

```bash
sudo ./bootstrap-shell.sh install    # Install everything
sudo ./bootstrap-shell.sh uninstall   # Remove everything
```

## What's Installed

- Zsh with Oh My Zsh
- Powerlevel10k theme
- Plugins: zsh-autosuggestions, zsh-completions, zsh-syntax-highlighting, autojump
- fzf fuzzy finder
- JetBrains Mono font

## Requirements

- Ubuntu/Debian
- sudo access
- Internet connection

## After Install

```bash
exec zsh
```

For Powerlevel10k configuration: `p10k configure`
