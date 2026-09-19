#!/usr/bin/env bash
# install-uv.sh -- make sure uv (Astral's Python package/venv manager) is on
# PATH, on whatever this machine is.  .aliases wraps uv for its
# virtualenvwrapper-style commands, so every platform needs it.
#
# Per platform:
#
#   * Guix (System or foreign distro): uv is in %base-packages in
#     home/common.scm, so `make apply' installs it.  This script does NOT
#     fall back to Astral's installer there: its Linux build expects the FHS
#     glibc loader, which Guix System does not have (the same problem
#     bin/install-claude.sh works around for Claude Code).
#   * macOS: Homebrew's formula, so upgrades ride along with `brew upgrade'.
#   * Other Linux (apt/yum/pacman, WSL without Guix): Astral's official
#     standalone installer, into ~/.local/bin (already on PATH via .zshrc).
#     UV_NO_MODIFY_PATH keeps it from appending to shell rc files this repo
#     manages.
#
# Safe to re-run at any time: if `uv' already runs, it exits without touching
# anything.

set -euo pipefail

INSTALLER_URL="https://astral.sh/uv/install.sh"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if command -v uv >/dev/null 2>&1 && uv --version >/dev/null 2>&1; then
    log "uv already installed: $(uv --version)"
    exit 0
fi

if command -v guix >/dev/null 2>&1; then
    log "uv comes from Guix Home on this machine -- run 'make apply'"
    exit 0
fi

if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    log "installing uv with Homebrew"
    brew install uv
else
    command -v curl >/dev/null 2>&1 || die "curl is required (brew/apt/yum/pacman install curl)"
    log "running the official installer ($INSTALLER_URL)"
    curl -LsSf "$INSTALLER_URL" | env UV_NO_MODIFY_PATH=1 sh
fi

# The installer's target may not be on this shell's PATH yet.
PATH="$HOME/.local/bin:$PATH" uv --version >&2 \
    || die "uv installed but does not run"
