#!/usr/bin/env bash
# install-claude.sh -- install (or update) Claude Code, with Guix System support.
#
# Claude Code's official installer ships a dynamically linked binary that
# expects the FHS glibc loader (/lib64/ld-linux-x86-64.so.2). Guix System is
# not FHS, so the binary fails at exec. Fix: after installing, patchelf the
# binary to use the loader and libstdc++/libgcc from a Guix profile.
#
# macOS and Debian derivatives are FHS-friendly, so the stock installer is
# all they need.
#
# Safe to re-run at any time: if `claude` already runs, this script exits
# without touching anything (pass --force to reinstall/update anyway). That
# also makes it self-healing on Guix -- when the auto-updater replaces the
# patched binary with an unpatched one, --version fails and a re-run
# reinstalls and re-patches.

set -euo pipefail

INSTALLER_URL="https://claude.ai/install.sh"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run_official_installer() {
    # $1 = "lenient" to tolerate installer failure (on Guix its post-install
    # self-check runs the still-unpatched binary and fails; the download
    # itself has already landed by then).
    local mode="${1:-strict}"
    command -v curl >/dev/null 2>&1 || die "curl is required (guix/brew/apt install curl)"
    log "running the official installer ($INSTALLER_URL)"
    if [ "$mode" = lenient ]; then
        curl -fsSL "$INSTALLER_URL" | bash || \
            log "installer exited non-zero (expected pre-patch on Guix); continuing"
    else
        curl -fsSL "$INSTALLER_URL" | bash
    fi
}

# ---------------------------------------------------------------------------
# Guix System: patch the downloaded binary against a Guix profile's glibc
# ---------------------------------------------------------------------------

# Profiles searched for the loader and C++ runtime, most specific first.
guix_profile_lib_dirs() {
    printf '%s\n' \
        "$HOME/.guix-profile/lib" \
        "$HOME/.guix-home/profile/lib" \
        "/run/current-system/profile/lib"
}

loader_glob() {
    case "$(uname -m)" in
        x86_64)  echo 'ld-linux-x86-64.so.*' ;;
        aarch64) echo 'ld-linux-aarch64.so.*' ;;
        *)       die "unsupported architecture: $(uname -m)" ;;
    esac
}

# Print the first profile lib dir containing a file matching $1, else fail.
guix_locate_lib_dir() {
    local pattern="$1" dir
    while IFS= read -r dir; do
        if compgen -G "$dir/$pattern" >/dev/null; then
            printf '%s\n' "$dir"
            return 0
        fi
    done < <(guix_profile_lib_dirs)
    return 1
}

# Install whatever the patch step needs but no profile currently provides.
guix_ensure_patch_deps() {
    local missing=()
    guix_locate_lib_dir "$(loader_glob)"  >/dev/null || missing+=(glibc)
    guix_locate_lib_dir 'libstdc++.so.*'  >/dev/null || missing+=(gcc-toolchain)
    command -v patchelf >/dev/null 2>&1              || missing+=(patchelf)
    if [ "${#missing[@]}" -gt 0 ]; then
        log "installing patch dependencies into ~/.guix-profile: ${missing[*]}"
        guix install "${missing[@]}"
        # A fresh profile's bin/ may not be on PATH in this shell yet.
        export PATH="$HOME/.guix-profile/bin:$PATH"
        hash -r
    fi
}

is_elf() {
    [ "$(head -c 4 "$1" 2>/dev/null)" = "$(printf '\x7fELF')" ]
}

# Patch every ELF the installer left behind: the launcher target in
# ~/.local/bin plus any versioned binaries under ~/.local/share/claude.
guix_patch_claude_binaries() {
    local loader_dir stdcxx_dir loader rpath
    loader_dir="$(guix_locate_lib_dir "$(loader_glob)")" || die "no glibc loader in any Guix profile"
    stdcxx_dir="$(guix_locate_lib_dir 'libstdc++.so.*')" || die "no libstdc++ in any Guix profile"
    loader="$(compgen -G "$loader_dir/$(loader_glob)" | head -n1)"
    rpath="$loader_dir:$stdcxx_dir"

    local candidates=()
    if [ -e "$HOME/.local/bin/claude" ]; then
        candidates+=("$(readlink -f "$HOME/.local/bin/claude")")
    fi
    if [ -d "$HOME/.local/share/claude" ]; then
        while IFS= read -r f; do
            candidates+=("$f")
        done < <(find "$HOME/.local/share/claude" -type f -perm -u+x 2>/dev/null)
    fi
    [ "${#candidates[@]}" -gt 0 ] || die "no installed claude binary found under ~/.local"

    local f patched=0
    while IFS= read -r f; do
        is_elf "$f" || continue
        log "patching $f"
        patchelf --set-interpreter "$loader" --set-rpath "$rpath" "$f"
        patched=$((patched + 1))
    done < <(printf '%s\n' "${candidates[@]}" | sort -u)
    [ "$patched" -gt 0 ] || die "found claude files but none were ELF binaries; nothing patched"
}

guix_verify() {
    log "verifying: claude --version"
    "$HOME/.local/bin/claude" --version || die "patched binary still fails to run"
}

guix_autoupdate_note() {
    cat <<'EOF'

NOTE (Guix): Claude Code's auto-updater will replace the patched binary with
an unpatched one and it will stop launching. Either disable auto-updates:

    export DISABLE_AUTOUPDATER=1   # add to your shell env

and re-run `make install-claude` when you want a newer version, or leave
updates on and re-run `make install-claude` whenever `claude` stops starting.
EOF
}

# ---------------------------------------------------------------------------
# OS dispatch
# ---------------------------------------------------------------------------

# True when a working claude is already reachable (PATH or ~/.local/bin).
claude_already_works() {
    local candidate
    for candidate in "$(command -v claude 2>/dev/null || true)" "$HOME/.local/bin/claude"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        "$candidate" --version >/dev/null 2>&1 && return 0
    done
    return 1
}

main() {
    if [ "${1:-}" != --force ] && claude_already_works; then
        log "claude already installed and working; nothing to do (--force to reinstall)"
        return 0
    fi

    # /run/current-system exists only on Guix System (see Makefile setup-keyd
    # note: `which guix` also succeeds on Pop!_OS, so it is not a valid test).
    if [ -e /run/current-system ]; then
        log "Guix System detected"
        guix_ensure_patch_deps
        run_official_installer lenient
        guix_patch_claude_binaries
        guix_verify
        guix_autoupdate_note
    elif [ "$(uname -s)" = Linux ]; then
        # Covers Debian derivatives, other FHS distros, and WSL alike --
        # the official installer handles all of them unpatched.
        log "Linux detected ($(uname -m))"
        run_official_installer strict
    elif [ "$(uname -s)" = Darwin ]; then
        log "macOS detected"
        run_official_installer strict
    else
        die "unhandled OS: $(uname -s) (native Windows: winget install Anthropic.ClaudeCode)"
    fi

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) log "reminder: add ~/.local/bin to PATH so 'claude' resolves" ;;
    esac
}

main "$@"
