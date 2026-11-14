#!/usr/bin/env bash
# install-julia.sh -- make sure Julia (managed by juliaup) is on PATH, on
# whatever this machine is.
#
# Why juliaup instead of Guix's packaged `julia`:
#   * Guix's `gnu/packages/julia.scm` is stuck at Julia 1.8.5 (from 2023),
#     built from source against LLVM 13, so `make update-channels` does not
#     bring modern Julia (1.10 LTS / 1.11+ release).
#   * `juliaup`'s Linux binaries are static musl executables (`*-linux-musl`),
#     and the official upstream Julia tarballs it manages bundle their own
#     non-glibc libraries (`../lib/julia` via $ORIGIN RPATH) and need only the
#     standard ELF loader (/lib64/ld-linux-x86-64.so.2, which system/geeeks.scm
#     provides on Guix System via extra-special-file, and which foreign distros
#     and WSL already have).
#   * Updating Julia versions or switching channels on any machine is just:
#       juliaup update
#       juliaup add lts && juliaup default lts
#
# Per platform:
#   * macOS: Homebrew formula (`brew install juliaup`) when brew is present,
#     then ensures the `release` channel is installed and active; falls back to
#     the official installer otherwise.
#   * Linux (Guix System, Guix Home on foreign distros, WSL, Ubuntu/Debian):
#     Runs the official installer (`https://install.julialang.org`) with
#     `-y --add-to-path no` so it never touches read-only Guix Home store
#     symlinks (~/.zshrc, ~/.profile), and symlinks `julia` and `juliaup`
#     into ~/.local/bin (in addition to ~/.juliaup/bin on PATH via
#     .shared.zshenv and home/common.scm).
#   * Termux (Android): Official juliaup binaries do not target Android; exits
#     cleanly with a note.
#
# Safe to re-run at any time: if `julia` already runs, this script exits
# without downloading anything (pass --force to run `juliaup update`).

set -euo pipefail

INSTALLER_URL="https://install.julialang.org"
LOCAL_BIN_DIR="$HOME/.local/bin"
JULIAUP_BIN_DIR="$HOME/.juliaup/bin"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

link_local_bins() {
    if [ -d "$JULIAUP_BIN_DIR" ]; then
        mkdir -p "$LOCAL_BIN_DIR"
        local tool
        for tool in julia juliaup; do
            if [ -x "$JULIAUP_BIN_DIR/$tool" ]; then
                ln -sfn "$JULIAUP_BIN_DIR/$tool" "$LOCAL_BIN_DIR/$tool"
            fi
        done
    fi
}

find_working_bin() {
    local name="$1" candidate
    for candidate in \
        "$(PATH="$LOCAL_BIN_DIR:$JULIAUP_BIN_DIR:$PATH" command -v "$name" 2>/dev/null || true)" \
        "$LOCAL_BIN_DIR/$name" \
        "$JULIAUP_BIN_DIR/$name"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        "$candidate" --version >/dev/null 2>&1 && {
            printf '%s\n' "$candidate"
            return 0
        }
    done
    return 1
}

ensure_default_channel() {
    local julia_bin juliaup_bin
    if find_working_bin julia >/dev/null 2>&1; then
        return 0
    fi
    juliaup_bin="$(find_working_bin juliaup || true)"
    [ -n "$juliaup_bin" ] || die "juliaup binary not found after installation"
    log "installing default Julia 'release' channel via juliaup"
    "$juliaup_bin" add release
    "$juliaup_bin" default release
}

main() {
    # Android / Termux check
    if [ "$(uname -o 2>/dev/null || true)" = "Android" ] || [ -n "${TERMUX_VERSION:-}" ]; then
        log "Termux: juliaup has no official Android binary; work from your phone via SSH"
        return 0
    fi

    local existing_julia=""
    existing_julia="$(find_working_bin julia || true)"

    if [ "${1:-}" != --force ] && [ -n "$existing_julia" ]; then
        link_local_bins
        log "julia already installed: $("$existing_julia" --version)"
        return 0
    fi

    if [ "${1:-}" = --force ] && find_working_bin juliaup >/dev/null 2>&1; then
        local juliaup_bin
        juliaup_bin="$(find_working_bin juliaup)"
        log "updating Julia channels via juliaup update"
        "$juliaup_bin" update
        link_local_bins
        existing_julia="$(find_working_bin julia || true)"
        [ -n "$existing_julia" ] || die "julia does not run after juliaup update"
        log "verified: $("$existing_julia" --version)"
        return 0
    fi

    if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
        log "installing juliaup with Homebrew"
        brew list juliaup >/dev/null 2>&1 || brew install juliaup
        ensure_default_channel
    else
        command -v curl >/dev/null 2>&1 || die "curl is required (guix/brew/apt/yum/pacman install curl)"
        log "running the official juliaup installer ($INSTALLER_URL)"
        curl -fsSL "$INSTALLER_URL" | sh -s -- -y --add-to-path no
        link_local_bins
        ensure_default_channel
        link_local_bins
    fi

    log "verifying: julia --version"
    local julia_bin=""
    julia_bin="$(find_working_bin julia || true)"
    [ -n "$julia_bin" ] || die "julia binary not found or failed to run after installation"
    "$julia_bin" --version >&2

    case ":$PATH:" in
        *":$LOCAL_BIN_DIR:"*|*":$JULIAUP_BIN_DIR:"*) ;;
        *) log "reminder: open a new shell (.shared.zshenv puts ~/.local/bin and ~/.juliaup/bin on PATH)" ;;
    esac
}

main "$@"
