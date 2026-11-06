#!/usr/bin/env bash
# install-radicle.sh -- make sure rad, radicle-node, and git-remote-rad are installed.
#
# Per platform:
#   * macOS: Homebrew formula (`brew install radicle`)
#   * Guix (System or foreign distro): Guix Home layer 'radicle' (`make apply`)
#   * Native Linux: official installer https://radicle.xyz/install into ~/.local/bin
#
# Safe to re-run at any time: if `rad` and `radicle-node` already run, exits 0.

set -euo pipefail

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if command -v rad >/dev/null 2>&1 && command -v radicle-node >/dev/null 2>&1; then
    log "radicle already installed: $(rad --version 2>&1 || true)"
    exit 0
fi

if command -v guix >/dev/null 2>&1 && [ -d "$HOME/.guix-home" ]; then
    log "radicle comes from Guix Home on this machine -- run 'make apply' (layer 'radicle')"
    exit 0
fi

if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
    log "installing radicle with Homebrew"
    brew install radicle
else
    command -v curl >/dev/null 2>&1 || die "curl is required to install radicle"
    log "installing radicle via official installer into ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    curl -sSL https://radicle.xyz/install | sh -s -- --prefix="$HOME/.local" --no-modify-path
fi

PATH="$HOME/.local/bin:$PATH" rad --version >&2 \
    || die "radicle installed but does not run"
