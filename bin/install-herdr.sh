#!/usr/bin/env bash
# install-herdr.sh -- make sure herdr (the AI agent multiplexer) is on PATH,
# on whatever this machine is.
#
# Herdr is a terminal workspace manager for AI coding agents with a local
# Unix socket API, sidebar status tracking, and background persistence.
# Skills (like skills/herdr-notify) and job runners (.agent-jobs.zsh,
# .jobs.zsh) interact with it via the `herdr` CLI.
#
# Per platform:
#
#   * macOS: Homebrew formula (`brew install herdr`) when brew is present,
#     so upgrades ride along with `brew upgrade`; falls back to the official
#     installer script into ~/.local/bin otherwise.
#   * Linux (Guix System, Guix Home on foreign distros, WSL, Ubuntu/Debian):
#     Herdr's Linux release binaries are static-PIE executables with no
#     external dynamic loader or glibc dependencies, so they run unmodified
#     even on non-FHS systems like Guix System. The official installer
#     (https://herdr.dev/install.sh) downloads the verified binary directly
#     into ~/.local/bin/herdr (already on PATH via .zshrc and .shared.zshenv).
#   * Termux (Android): Herdr release binaries do not support Android;
#     SSH to a supported host instead.
#   * Native Windows: not handled here -- see the install-herdr Makefile
#     target for PowerShell.
#
# Safe to re-run at any time: if `herdr` already runs, this script exits
# without touching anything (pass --force to reinstall/update anyway).

set -euo pipefail

INSTALLER_URL="https://herdr.dev/install.sh"
BIN_DIR="$HOME/.local/bin"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

herdr_already_works() {
    local candidate
    for candidate in "$(command -v herdr 2>/dev/null || true)" "$BIN_DIR/herdr"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        "$candidate" --version >/dev/null 2>&1 && return 0
    done
    return 1
}

main() {
    if [ "${1:-}" != --force ] && herdr_already_works; then
        local version
        version="$(PATH="$BIN_DIR:$PATH" herdr --version 2>&1 || true)"
        log "herdr already installed: $version"
        return 0
    fi

    # Android / Termux check
    if [ "$(uname -o 2>/dev/null || true)" = "Android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
        log "Termux: herdr has no native Android binary; work from your phone via SSH"
        return 0
    fi

    if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
        log "installing herdr with Homebrew"
        brew install herdr
    else
        command -v curl >/dev/null 2>&1 || die "curl is required (guix/brew/apt/yum/pacman install curl)"
        log "running the official installer ($INSTALLER_URL)"
        mkdir -p "$BIN_DIR"
        curl -fsSL "$INSTALLER_URL" | env HERDR_INSTALL_DIR="$BIN_DIR" sh
    fi

    log "verifying: herdr --version"
    local bin=""
    if command -v herdr >/dev/null 2>&1; then
        bin="herdr"
    elif [ -x "$BIN_DIR/herdr" ]; then
        bin="$BIN_DIR/herdr"
    else
        die "herdr binary not found after installation"
    fi

    "$bin" --version >&2 || die "herdr installed but does not run"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) log "reminder: open a new shell (.zshrc puts ~/.local/bin on PATH)" ;;
    esac
}

main "$@"
