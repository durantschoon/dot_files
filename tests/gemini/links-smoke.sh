#!/bin/sh
# Hermetic checks for bin/setup-gemini-links. Scratch directory only.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
script="$root/bin/setup-gemini-links"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
    echo "gemini-links-smoke: $*" >&2
    exit 1
}

assert_link_target() {
    link="$1"
    want="$2"
    test -L "$link" || fail "$link is not a symlink"
    got=$(readlink "$link")
    test "$got" = "$want" || fail "$link points to $got, expected $want"
}

# Build a synthetic dot_files repo with gemini/ and claude/skills/
repo="$tmp/repo"
mkdir -p \
    "$repo/gemini/scripts" \
    "$repo/gemini/skills/recap" \
    "$repo/gemini/skills/overlap" \
    "$repo/claude/skills/prob-tree" \
    "$repo/claude/skills/prob-push" \
    "$repo/claude/skills/overlap"
echo '{}' > "$repo/gemini/hooks.json"
echo '#!/usr/bin/env python3' > "$repo/gemini/scripts/away_check.py"
echo '# recap' > "$repo/gemini/skills/recap/SKILL.md"
echo '# gemini overlap' > "$repo/gemini/skills/overlap/SKILL.md"
echo '# gemini readme' > "$repo/gemini/skills/README.md"
echo '# prob-tree' > "$repo/claude/skills/prob-tree/SKILL.md"
echo '# prob-push' > "$repo/claude/skills/prob-push/SKILL.md"
echo '# claude overlap' > "$repo/claude/skills/overlap/SKILL.md"
echo '# claude readme' > "$repo/claude/skills/README.md"

# 1. Fresh HOME with pre-existing state and mcp_config.json
home1="$tmp/home1"
mkdir -p "$home1/.gemini/config/state"
echo 'keep-me' > "$home1/.gemini/config/state/keep"
echo '{"mcpServers":{}}' > "$home1/.gemini/config/mcp_config.json"

HOME="$home1" "$script" "$repo" < /dev/null || fail "fresh run failed"

assert_link_target "$home1/.gemini/config/hooks.json" "$repo/gemini/hooks.json"
assert_link_target "$home1/.gemini/config/scripts" "$repo/gemini/scripts"
assert_link_target "$home1/.gemini/config/skills/recap" "$repo/gemini/skills/recap"
assert_link_target "$home1/.gemini/config/skills/prob-tree" "$repo/claude/skills/prob-tree"
assert_link_target "$home1/.gemini/config/skills/prob-push" "$repo/claude/skills/prob-push"

# Existing state and mcp_config.json remain untouched
test "$(cat "$home1/.gemini/config/state/keep")" = "keep-me" || fail "state/keep altered"
test "$(cat "$home1/.gemini/config/mcp_config.json")" = '{"mcpServers":{}}' || fail "mcp_config.json altered"

# 2. Collision precedence: gemini/skills wins over claude/skills
assert_link_target "$home1/.gemini/config/skills/overlap" "$repo/gemini/skills/overlap"

# 3. Non-directory files under skills/ are skipped
test ! -e "$home1/.gemini/config/skills/README.md" || fail "README.md should not be linked"
test ! -L "$home1/.gemini/config/skills/README.md" || fail "README.md symlink should not exist"

# 4. Idempotent re-run
HOME="$home1" "$script" "$repo" < /dev/null || fail "idempotent re-run failed"

# 5. Real-directory guard for scripts and skill directories
home2="$tmp/home2"
mkdir -p "$home2/.gemini/config/scripts" "$home2/.gemini/config/skills/prob-tree"
echo 'local' > "$home2/.gemini/config/scripts/local.py"
echo 'local' > "$home2/.gemini/config/skills/prob-tree/LOCAL.md"

out2=$(HOME="$home2" "$script" "$repo" < /dev/null)
printf '%s\n' "$out2" | grep -q 'NOTE: ~/.gemini/config/scripts is a directory' || fail "missing scripts real-dir NOTE"
printf '%s\n' "$out2" | grep -q 'NOTE: ~/.gemini/config/skills/prob-tree is a directory' || fail "missing skill real-dir NOTE"
test ! -L "$home2/.gemini/config/scripts" || fail "real scripts dir replaced with symlink"
test ! -e "$home2/.gemini/config/scripts/scripts" || fail "nested symlink created inside scripts"
test ! -L "$home2/.gemini/config/skills/prob-tree" || fail "real skill dir replaced with symlink"
test ! -e "$home2/.gemini/config/skills/prob-tree/prob-tree" || fail "nested symlink created inside prob-tree"
assert_link_target "$home2/.gemini/config/skills/recap" "$repo/gemini/skills/recap"

# 6. Missing claude/skills directory degrades cleanly with NOTE
repo_noclaude="$tmp/repo_noclaude"
mkdir -p "$repo_noclaude/gemini/skills/recap"
echo '{}' > "$repo_noclaude/gemini/hooks.json"
echo '# recap' > "$repo_noclaude/gemini/skills/recap/SKILL.md"
home3="$tmp/home3"
out3=$(HOME="$home3" "$script" "$repo_noclaude" < /dev/null)
printf '%s\n' "$out3" | grep -q 'NOTE: claude/skills not found' || fail "missing claude/skills NOTE"
assert_link_target "$home3/.gemini/config/hooks.json" "$repo_noclaude/gemini/hooks.json"
assert_link_target "$home3/.gemini/config/skills/recap" "$repo_noclaude/gemini/skills/recap"

echo "gemini-links-smoke: ok"
