#!/usr/bin/env bash
# install-starship.sh -- make sure starship prompt is installed on PATH
#
# Per platform:
#   * Guix (System or foreign distro): starship is in home/common.scm or profile,
#     so `make apply' installs it.
#   * macOS: Homebrew formula (`brew install starship`).
#   * Termux: `pkg install starship`.
#   * Other Linux (apt/yum/pacman, Pop!_OS, Ubuntu, WSL):
#     Official installer from https://starship.rs/install.sh into ~/.local/bin.
#
# Safe to re-run at any time: if `starship` already runs, it exits without touching anything.

set -euo pipefail

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if command -v starship >/dev/null 2>&1 && starship --version >/dev/null 2>&1; then
    log "starship already installed: $(starship --version)"
    exit 0
fi

if command -v guix >/dev/null 2>&1 && [ -d "$HOME/.guix-home" ]; then
    log "starship comes from Guix Home on this machine -- run 'make apply'"
    exit 0
fi

if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    log "installing starship with Homebrew"
    brew install starship
elif [ "$(uname -o 2>/dev/null || true)" = "Android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
    log "installing starship with pkg"
    pkg install -y starship
else
    command -v curl >/dev/null 2>&1 || die "curl is required to install starship"
    log "installing starship via official installer to ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
fi

PATH="$HOME/.local/bin:$PATH" starship --version >&2 \
    || die "starship installed but does not run"
