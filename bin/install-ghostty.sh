#!/usr/bin/env bash
# install-ghostty.sh -- ensure Ghostty terminal emulator is installed on
# macOS or Linux.
#
# Per platform:
#   * macOS: Homebrew cask (`brew install --cask ghostty`)
#   * Linux (Debian/Ubuntu): `apt install ghostty` if packaged in repo, or
#     notes on community deb / AppImage / source build.
#   * Linux (Arch): `pacman -S ghostty`
#   * Linux (Guix): Ghostty is a graphical terminal requiring Zig, GTK4 and
#     libadwaita; install via native host package, AppImage, or Flatpak.
#
# Safe to re-run at any time: if Ghostty is already installed, exits cleanly.

set -euo pipefail

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ghostty_already_works() {
    if command -v ghostty >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$(uname -s)" == Darwin ]] && ([ -d "/Applications/Ghostty.app" ] || [ -d "$HOME/Applications/Ghostty.app" ]); then
        return 0
    fi
    return 1
}

main() {
    if ghostty_already_works; then
        log "Ghostty already installed"
        exit 0
    fi

    if [[ "$(uname -s)" == Darwin ]]; then
        if command -v brew >/dev/null 2>&1; then
            log "installing Ghostty with Homebrew cask"
            brew install --cask ghostty
        else
            die "Homebrew is required to install Ghostty on macOS (https://brew.sh)"
        fi
    elif [[ "$(uname -s)" == Linux ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            log "attempting to install Ghostty via apt"
            if sudo apt-get update && sudo apt-get install -y ghostty 2>/dev/null; then
                log "Ghostty installed via apt"
            else
                log "Ghostty is not in the default apt repositories for this distro."
                log "See https://ghostty.org/docs/install for Linux packages (AppImage, deb, or source build)."
            fi
        elif command -v pacman >/dev/null 2>&1; then
            log "installing Ghostty via pacman"
            sudo pacman -S --noconfirm ghostty
        else
            log "Linux: install Ghostty via your distribution package manager or https://ghostty.org/docs/install"
        fi
    fi
}

main "$@"
