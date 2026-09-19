#!/usr/bin/env bash
# install-agy.sh -- make sure agy (Google's Antigravity CLI) is on PATH, on
# whatever this machine is.  .aliases defines agy-auto on top of it.
#
# agy ships as one dynamically linked Go binary that needs only glibc
# (libc/libm/libdl/libpthread/librt/libresolv) and the FHS loader
# /lib64/ld-linux-x86-64.so.2 -- the same shape as Claude Code, so the same
# Guix System story applies (see bin/install-claude.sh).
#
# Why not just `curl https://antigravity.google/cli/install.sh | bash'?  That
# script's last step runs `agy install', which appends PATH lines to (and
# "purges aliases" from) the shell profiles -- files this repo owns
# (.zshrc already puts ~/.local/bin on PATH).  So this script repeats the
# installer's download steps itself -- platform manifest, SHA-512 check,
# extract -- and skips that step.  Everywhere:
#
#   * macOS and FHS Linux (Debian derivatives, WSL, Guix on a foreign
#     distro): the binary goes straight to ~/.local/bin/agy, exactly where
#     the official installer puts it, so its background self-update works.
#   * Guix System (no /lib64 loader): the unmodified binary goes to
#     ~/.local/share/antigravity-cli/versions/<version>/agy and
#     ~/.local/bin/agy is a wrapper that execs it through the Guix glibc
#     loader.  agy's self-update may not survive the wrapper; if `agy' ever
#     stops starting, `make install-agy' rebuilds it (make apply does too).
#   * Native Windows: not handled here -- see the install-agy Makefile
#     target for the PowerShell one-liner.
#
# Safe to re-run at any time: if `agy' already runs, it exits without
# touching anything (pass --force to reinstall at the latest version).

set -euo pipefail

MANIFEST_BASE_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
BIN_DIR="$HOME/.local/bin"
VERSIONS_DIR="$HOME/.local/share/antigravity-cli/versions"

# Logs go to stderr so functions can return values on stdout.
log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# The manifest name the official installer would pick, e.g. linux_amd64,
# linux_amd64_musl, darwin_arm64.
release_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        *)      die "unhandled OS: $(uname -s) (native Windows: see 'make install-agy')" ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch=amd64 ;;
        arm64|aarch64) arch=arm64 ;;
        *)             die "unsupported architecture: $(uname -m)" ;;
    esac
    if [ "$os" = linux ] && { compgen -G '/lib/libc.musl-*.so.1' >/dev/null \
                              || ldd /bin/ls 2>&1 | grep -q musl; }; then
        printf '%s_%s_musl\n' "$os" "$arch"
    else
        printf '%s_%s\n' "$os" "$arch"
    fi
}

# Pull one string field out of the (flat, one-key-per-line) manifest JSON,
# the same sed the official installer uses -- no jq dependency.
json_field() {
    sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$1"
}

sha512_of() {
    if command -v sha512sum >/dev/null 2>&1; then
        sha512sum "$1" | cut -d' ' -f1
    else
        shasum -a 512 "$1" | cut -d' ' -f1
    fi
}

# Download, verify and unpack the latest release into $1 (a directory);
# the binary lands at $1/agy.  Prints the version on stdout.
download_release() {
    local dest_dir="$1" platform manifest version url sha512 staging
    platform="$(release_platform)"
    manifest="$(curl -fsSL "$MANIFEST_BASE_URL/$platform.json")" \
        || die "could not fetch the release manifest for $platform"
    version="$(json_field "$manifest" version)"
    url="$(json_field "$manifest" url)"
    sha512="$(json_field "$manifest" sha512)"
    [ -n "$url" ] && [ -n "$sha512" ] || die "malformed release manifest for $platform"
    [[ "$version" =~ ^[0-9]+\.[0-9][0-9A-Za-z.+-]*$ ]] || die "unexpected version string: '$version'"

    staging="$(mktemp -d)"
    # Expanded now, not at exit: $staging is local to this function.
    trap "rm -rf '$staging'" EXIT

    log "downloading Antigravity CLI $version ($platform)"
    curl -fsSL -o "$staging/payload" "$url"
    [ "$(sha512_of "$staging/payload")" = "$sha512" ] \
        || die "checksum mismatch for downloaded package -- not installing"
    log "checksum verified"

    mkdir -p "$dest_dir"
    case "$url" in
        *.tar.gz*)
            # The archive's single member is named `antigravity'.
            tar -xzf "$staging/payload" -C "$staging" antigravity
            mv "$staging/antigravity" "$dest_dir/agy.tmp" ;;
        *)
            mv "$staging/payload" "$dest_dir/agy.tmp" ;;
    esac
    chmod 755 "$dest_dir/agy.tmp"
    mv "$dest_dir/agy.tmp" "$dest_dir/agy"
    if [ "$(uname -s)" = Darwin ]; then
        xattr -d com.apple.quarantine "$dest_dir/agy" 2>/dev/null || true
    fi
    printf '%s\n' "$version"
}

# ---------------------------------------------------------------------------
# Guix System: wrap the unmodified binary with the Guix glibc loader
# ---------------------------------------------------------------------------

# Print the first Guix profile lib dir holding the glibc loader, else fail.
# glibc is in the home profile via home/*.scm; ~/.guix-profile is the
# imperative fallback that install-claude.sh installs into.
guix_loader_dir() {
    local pattern dir
    case "$(uname -m)" in
        x86_64)  pattern='ld-linux-x86-64.so.*' ;;
        aarch64) pattern='ld-linux-aarch64.so.*' ;;
        *)       die "unsupported architecture: $(uname -m)" ;;
    esac
    for dir in "$HOME/.guix-profile/lib" "$HOME/.guix-home/profile/lib" \
               "/run/current-system/profile/lib"; do
        compgen -G "$dir/$pattern" >/dev/null && { printf '%s\n' "$dir"; return 0; }
    done
    return 1
}

guix_install() {
    local loader_dir loader version bin_path
    loader_dir="$(guix_loader_dir)" || {
        log "no glibc loader in any profile; installing glibc into ~/.guix-profile"
        guix install glibc
        loader_dir="$(guix_loader_dir)" || die "still no glibc loader after 'guix install glibc'"
    }
    loader="$(compgen -G "$loader_dir/ld-linux-*.so.*" | head -n1)"

    local staging_dir="$VERSIONS_DIR/.staging"
    version="$(download_release "$staging_dir")"
    bin_path="$VERSIONS_DIR/$version/agy"
    mkdir -p "$(dirname "$bin_path")"
    mv "$staging_dir/agy" "$bin_path"
    rmdir "$staging_dir" 2>/dev/null || true

    mkdir -p "$BIN_DIR"
    rm -f "$BIN_DIR/agy"
    cat > "$BIN_DIR/agy" <<EOF
#!/bin/sh
# Generated by dot_files/bin/install-agy.sh -- Guix System launcher.
# Runs the unmodified Antigravity CLI binary via the Guix glibc loader;
# Guix has no FHS /lib64 loader.  Regenerate with: make install-agy
exec "$loader" --argv0 "$bin_path" --library-path "$loader_dir" "$bin_path" "\$@"
EOF
    chmod 755 "$BIN_DIR/agy"
    log "wrote loader wrapper: $BIN_DIR/agy -> $bin_path"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

# True when a working agy is already reachable (PATH or ~/.local/bin).
agy_already_works() {
    local candidate
    for candidate in "$(command -v agy 2>/dev/null || true)" "$BIN_DIR/agy"; do
        [ -n "$candidate" ] && [ -x "$candidate" ] || continue
        "$candidate" --version >/dev/null 2>&1 && return 0
    done
    return 1
}

main() {
    if [ "${1:-}" != --force ] && agy_already_works; then
        log "agy already installed: $(PATH="$BIN_DIR:$PATH" agy --version 2>&1)"
        return 0
    fi
    command -v curl >/dev/null 2>&1 || die "curl is required (guix/brew/apt install curl)"

    # /run/current-system exists only on Guix System (`command -v guix' also
    # succeeds on a foreign distro, which has the FHS loader and needs no
    # wrapper).
    if [ -e /run/current-system ]; then
        log "Guix System detected"
        guix_install
    else
        download_release "$BIN_DIR" >/dev/null
    fi

    log "verifying: agy --version"
    "$BIN_DIR/agy" --version >&2 || die "agy installed but does not run"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) log "reminder: open a new shell (.zshrc puts ~/.local/bin on PATH)" ;;
    esac
    log "run 'agy' once to sign in"
}

main "$@"
