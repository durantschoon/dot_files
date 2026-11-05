#!/bin/sh
# Hermetic checks for bin/link-dotfile. Scratch directory only.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

script="$root/bin/link-dotfile"

fail() {
    echo "link-dotfile-smoke: $*" >&2
    exit 1
}

src1="$tmp/repo/aliases"
src2="$tmp/repo/tmux.conf"
mkdir -p "$tmp/repo"
echo "alias foo=bar" > "$src1"
echo "set -g mouse on" > "$src2"

# 1. Fresh link creation
"$script" "$src1" "$tmp/home/.aliases" || fail "fresh link failed"
test -L "$tmp/home/.aliases" || fail "not a symlink"
test "$(readlink "$tmp/home/.aliases")" = "$src1" || fail "target mismatch"

# 2. Idempotent re-run (must exit 0 and not fail even if non-interactive)
"$script" "$src1" "$tmp/home/.aliases" < /dev/null || fail "idempotent re-run failed"

# 3. Leading tilde expansion
mkdir -p "$tmp/home/repo"
echo "set -g mouse on" > "$tmp/home/repo/tmux.conf"
HOME="$tmp/home" "$script" "~/repo/tmux.conf" "~/.tmux.conf" || fail "tilde expansion failed"
test -L "$tmp/home/.tmux.conf" || fail "~/.tmux.conf not created"
HOME="$tmp/home" "$script" "~/repo/tmux.conf" "~/.tmux.conf" < /dev/null || fail "tilde expansion idempotent re-run failed"

# 4. .zshrc real file backup
echo "old zshrc" > "$tmp/home/.zshrc"
"$script" "$src1" "$tmp/home/.zshrc" || fail ".zshrc backup and link failed"
test -f "$tmp/home/.zshrc.bak" || fail ".zshrc.bak missing"
test "$(cat "$tmp/home/.zshrc.bak")" = "old zshrc" || fail ".zshrc.bak content mismatch"
test -L "$tmp/home/.zshrc" || fail ".zshrc is not a symlink"
# Re-running on .zshrc must be idempotent and not re-backup
"$script" "$src1" "$tmp/home/.zshrc" < /dev/null || fail ".zshrc idempotent re-run failed"

# 5. Broken symlink replacement
ln -s "/nonexistent/path/debris" "$tmp/home/broken"
"$script" "$src1" "$tmp/home/broken" || fail "broken link replacement failed"
test "$(readlink "$tmp/home/broken")" = "$src1" || fail "broken link not pointed to src"

# 6. Relative symlink already pointing to same file
ln -s "../repo/aliases" "$tmp/home/relative-link"
"$script" "$src1" "$tmp/home/relative-link" < /dev/null || fail "relative symlink match failed"

# 7. Conflict in non-interactive mode must fail cleanly without clobbering
echo "pre-existing" > "$tmp/home/conflict"
if "$script" "$src1" "$tmp/home/conflict" < /dev/null 2>/dev/null; then
    fail "conflict unexpectedly succeeded non-interactively"
fi
test -f "$tmp/home/conflict" || fail "conflict file was removed"
test ! -L "$tmp/home/conflict" || fail "conflict file was turned into symlink"

echo "link-dotfile-smoke: ok"
