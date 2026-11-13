#!/usr/bin/env bash
# install-bazel.sh -- make sure `bazel` is on PATH, on whatever this machine is.
#
# Bazel is installed as bazelisk, Bazel's official launcher: `bazel` runs the
# Bazel version a workspace pins in .bazelversion (or the latest release),
# downloading it into ~/.cache/bazelisk on first use.  Guix does not package
# Bazel, so this runs from apply/apply-wayland/setup-native like install-herdr.
#
# Per platform:
#
#   * macOS: Homebrew formula `bazelisk`, which also provides `bazel`.
#   * Linux (Guix Home on foreign distros, WSL, Ubuntu/Debian, Guix System):
#     the pinned bazelisk release binary (a static Go executable), checked
#     against its published sha256, into ~/.local/bin/bazelisk, with
#     ~/.local/bin/bazel -> bazelisk.  On Guix System the Bazel binaries that
#     bazelisk downloads are dynamically linked against an FHS glibc and will
#     not start outside `guix shell --container --emulate-fhs`.
#   * Termux (Android): Bazel has no Android host build; handled (skipped) in
#     the Makefile target.
#
# Safe to re-run: if `bazel` already runs, this exits without touching
# anything.  Pass --force to reinstall (e.g. after bumping BAZELISK_VERSION).

set -euo pipefail

BAZELISK_VERSION="v1.30.0"
RELEASE_URL="https://github.com/bazelbuild/bazelisk/releases/download/$BAZELISK_VERSION"
BIN_DIR="$HOME/.local/bin"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

force=0
[ "${1:-}" = "--force" ] && force=1

if [ "$force" = 0 ] && command -v bazel >/dev/null 2>&1; then
    log "bazel found ($(command -v bazel)); pass --force to reinstall"
    exit 0
fi

case "$(uname -s)" in
    Darwin)
        command -v brew >/dev/null 2>&1 || die "Homebrew not found; install it, then re-run"
        log "installing bazelisk (provides bazel) with Homebrew"
        brew install bazelisk
        exit 0
        ;;
    Linux) ;;
    *) die "unsupported OS $(uname -s)" ;;
esac

case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) die "no bazelisk release for $(uname -m)" ;;
esac

asset="bazelisk-linux-$arch"
download_dir=$(mktemp -d)
trap 'command rm -rf -- "$download_dir"' EXIT

log "downloading $asset $BAZELISK_VERSION"
curl -fsSL --retry 3 -o "$download_dir/$asset" "$RELEASE_URL/$asset"
curl -fsSL --retry 3 -o "$download_dir/$asset.sha256" "$RELEASE_URL/$asset.sha256"

# The .sha256 file holds "<hash>  <name>"; compare the hash alone so the
# file name inside it does not matter.
expected_hash=$(awk '{ print $1; exit }' "$download_dir/$asset.sha256")
actual_hash=$(sha256sum "$download_dir/$asset" | awk '{ print $1 }')
[ -n "$expected_hash" ] && [ "$expected_hash" = "$actual_hash" ] \
    || die "sha256 mismatch for $asset (expected $expected_hash, got $actual_hash)"

mkdir -p "$BIN_DIR"
install -m 0755 "$download_dir/$asset" "$BIN_DIR/bazelisk"
ln -sfn bazelisk "$BIN_DIR/bazel"
log "installed $BIN_DIR/bazelisk ($BAZELISK_VERSION) and $BIN_DIR/bazel -> bazelisk"
