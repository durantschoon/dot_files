#!/usr/bin/env bash
# install-claude.sh -- install (or update) Claude Code, with Guix System support.
#
# Claude Code's native binary is a Bun single-file executable, dynamically
# linked, expecting the FHS glibc loader (/lib64/ld-linux-x86-64.so.2).
# Guix System is not FHS, so the binary cannot exec there. Two things do
# NOT work, learned the hard way:
#
#   * patchelf: Bun binaries locate their embedded JS blob via a trailer at
#     the end of the file; patchelf grows/rewrites the ELF, the trailer is
#     no longer where Bun expects it, and the binary segfaults on startup.
#   * the official installer: its final step runs the downloaded binary to
#     self-install ("$binary" install), which is exactly what cannot exec
#     on Guix yet -- chicken and egg.
#
# What does work: run the UNMODIFIED binary through the Guix glibc loader
# explicitly (`ld-linux-x86-64.so.2 --library-path ... claude`). The binary
# needs only glibc libs (libc/libm/libdl/libpthread/librt -- no libstdc++),
# and Bun's blob discovery survives loader invocation (verified: --version
# works when invoked this way). So on Guix this script mimics the official
# installer -- fetch latest version, checksum-verify, place the binary in
# ~/.local/share/claude/versions/ -- then writes ~/.local/bin/claude as a
# tiny wrapper that execs the loader on it.
#
# macOS and FHS Linuxen just use the official installer.
#
# Safe to re-run at any time: if `claude` already runs, this script exits
# without touching anything (pass --force to reinstall/update anyway). That
# also makes it self-healing on Guix -- if Claude's auto-updater replaces
# the wrapper with a symlink to a new unwrapped binary, --version fails and
# a re-run rebuilds the wrapper around the freshly downloaded version.

set -euo pipefail

INSTALLER_URL="https://claude.ai/install.sh"
DOWNLOAD_BASE_URL="https://downloads.claude.ai/claude-code-releases"

# Logs go to stderr so functions can return values on stdout.
log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run_official_installer() {
    command -v curl >/dev/null 2>&1 || die "curl is required (guix/brew/apt install curl)"
    log "running the official installer ($INSTALLER_URL)"
    curl -fsSL "$INSTALLER_URL" | bash
}

# ---------------------------------------------------------------------------
# Guix System: download the binary ourselves and wrap it with the glibc loader
# ---------------------------------------------------------------------------

# Profiles searched for the loader, most specific first. glibc is in the
# home profile via home/*.scm; ~/.guix-profile is the imperative fallback.
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

release_platform() {
    case "$(uname -m)" in
        x86_64)  echo linux-x64 ;;
        aarch64) echo linux-arm64 ;;
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

guix_ensure_glibc() {
    if ! guix_locate_lib_dir "$(loader_glob)" >/dev/null; then
        log "no glibc loader in any profile; installing glibc into ~/.guix-profile"
        log "(declarative alternative: it is in home/*.scm; 'make apply-wayland')"
        guix install glibc
    fi
}

# Mimic the official installer: fetch the latest version, checksum-verify,
# install to ~/.local/share/claude/versions/<version>. Prints the binary path.
guix_download_claude() {
    local platform version manifest checksum versions_dir bin_path
    platform="$(release_platform)"
    version="$(curl -fsSL "$DOWNLOAD_BASE_URL/latest")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || die "unexpected version string: '$version'"

    versions_dir="$HOME/.local/share/claude/versions"
    mkdir -p "$versions_dir"
    bin_path="$versions_dir/$version"

    log "downloading Claude Code $version ($platform)"
    curl -fsSL -o "$bin_path.tmp" "$DOWNLOAD_BASE_URL/$version/$platform/claude"

    # Same checksum-extraction regex the official install.sh uses.
    manifest="$(curl -fsSL "$DOWNLOAD_BASE_URL/$version/manifest.json")"
    if [[ $manifest =~ \"$platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
        checksum="${BASH_REMATCH[1]}"
        echo "$checksum  $bin_path.tmp" | sha256sum -c - >/dev/null 2>&1 \
            || die "checksum mismatch for downloaded binary"
        log "checksum verified"
    else
        log "warning: could not extract checksum from manifest; skipping verification"
    fi

    chmod 755 "$bin_path.tmp"
    mv "$bin_path.tmp" "$bin_path"
    printf '%s\n' "$bin_path"
}

# Write ~/.local/bin/claude as a wrapper that runs the unmodified binary
# through the Guix glibc loader. Never patch the binary itself (see header).
guix_write_wrapper() {
    local bin_path="$1" loader_dir loader lib_path stdcxx_dir wrapper
    loader_dir="$(guix_locate_lib_dir "$(loader_glob)")" || die "no glibc loader in any Guix profile"
    loader="$(compgen -G "$loader_dir/$(loader_glob)" | head -n1)"
    lib_path="$loader_dir"
    # Not needed by today's binary, but harmless future-proofing if present.
    if stdcxx_dir="$(guix_locate_lib_dir 'libstdc++.so.*')"; then
        lib_path="$lib_path:$stdcxx_dir"
    fi

    wrapper="$HOME/.local/bin/claude"
    mkdir -p "$HOME/.local/bin"
    rm -f "$wrapper"
    cat > "$wrapper" <<EOF
#!/bin/sh
# Generated by dot_files/bin/install-claude.sh -- Guix System launcher.
# Runs the unmodified Claude Code binary via the Guix glibc loader; Guix
# has no FHS /lib64 loader, and patchelf corrupts Bun binaries (embedded
# JS blob trailer). Regenerate with: make install-claude
exec "$loader" --argv0 "$bin_path" --library-path "$lib_path" "$bin_path" "\$@"
EOF
    chmod 755 "$wrapper"
    log "wrote loader wrapper: $wrapper -> $bin_path"
}

guix_verify() {
    log "verifying: claude --version"
    "$HOME/.local/bin/claude" --version >&2 || die "wrapped binary still fails to run"
}

guix_autoupdate_note() {
    cat <<'EOF'

NOTE (Guix): Claude Code's auto-updater replaces the wrapper with a symlink
to a new binary that cannot exec on Guix. Either disable auto-updates:

    export DISABLE_AUTOUPDATER=1   # add to your shell env

and re-run `install-claude.sh --force` when you want a newer version, or
leave updates on and re-run `make install-claude` whenever `claude` stops
starting (make apply / apply-wayland / update do this automatically).
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
        command -v curl >/dev/null 2>&1 || die "curl is required (it is in home/*.scm; make apply-wayland)"
        guix_ensure_glibc
        local bin_path
        bin_path="$(guix_download_claude)"
        guix_write_wrapper "$bin_path"
        guix_verify
        guix_autoupdate_note
    elif [ "$(uname -s)" = Linux ]; then
        # Covers Debian derivatives, other FHS distros, and WSL alike --
        # the official installer handles all of them unpatched.
        log "Linux detected ($(uname -m))"
        run_official_installer
    elif [ "$(uname -s)" = Darwin ]; then
        log "macOS detected"
        run_official_installer
    else
        die "unhandled OS: $(uname -s) (native Windows: winget install Anthropic.ClaudeCode)"
    fi

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) log "reminder: add ~/.local/bin to PATH so 'claude' resolves" ;;
    esac
}

main "$@"
