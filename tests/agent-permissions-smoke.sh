#!/bin/sh
# Hermetic checks for bin/agent-permissions.  Scratch HOME only.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

export HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR CODEX_HOME CURSOR_CONFIG_DIR
mkdir -p "$HOME"
script=$root/bin/agent-permissions

fail() {
    echo "agent-permissions-smoke: $*" >&2
    exit 1
}

# A gap report must not create files.
if "$script" --check >/dev/null 2>&1; then
    fail "--check succeeded on an empty home"
fi
test ! -e "$HOME/.claude/settings.json"
test ! -e "$HOME/.codex/rules/dot_files.rules"
test ! -e "$HOME/.cursor/cli-config.json"

"$script" >/dev/null
"$script" --check >/dev/null

python3 - "$HOME" <<'PY'
import json, pathlib, sys
home = pathlib.Path(sys.argv[1])
claude = json.loads((home / ".claude/settings.json").read_text())
cursor = json.loads((home / ".cursor/cli-config.json").read_text())
want_claude = [
    "Bash(git branch -D:*)",
    "Bash(git -C * branch -D *)",
    "Bash(git worktree remove:*)",
    "Bash(git -C * worktree remove *)",
    "Bash(git worktree prune:*)",
    "Bash(git -C * worktree prune*)",
]
want_cursor = [
    "Shell(git:branch -D*)",
    "Shell(git:-C * branch -D*)",
    "Shell(git:worktree remove*)",
    "Shell(git:-C * worktree remove*)",
    "Shell(git:worktree prune*)",
    "Shell(git:-C * worktree prune*)",
]
assert claude["permissions"]["allow"] == want_claude, claude
assert cursor["version"] == 1
assert cursor["permissions"]["allow"] == want_cursor, cursor
assert cursor["permissions"]["deny"] == []
rules = (home / ".codex/rules/dot_files.rules").read_text()
assert 'pattern=["git", "branch", "-D"]' in rules
assert 'pattern=["git", "worktree", ["remove", "prune"]]' in rules
PY

# Second apply is a no-op.
cp "$HOME/.claude/settings.json" "$tmp/claude-once"
cp "$HOME/.codex/rules/dot_files.rules" "$tmp/codex-once"
cp "$HOME/.cursor/cli-config.json" "$tmp/cursor-once"
"$script" >/dev/null
cmp "$tmp/claude-once" "$HOME/.claude/settings.json"
cmp "$tmp/codex-once" "$HOME/.codex/rules/dot_files.rules"
cmp "$tmp/cursor-once" "$HOME/.cursor/cli-config.json"

# Existing keys, an unrelated allow entry, and a permissions object that
# has deny but no allow all survive.  A stale Codex file is replaced.
export HOME="$tmp/merge"
unset CLAUDE_CONFIG_DIR CODEX_HOME CURSOR_CONFIG_DIR
mkdir -p "$HOME/.claude" "$HOME/.cursor" "$HOME/.codex/rules"
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "model": "kept",
  "permissions": {
    "allow": [
      "Bash(git status:*)"
    ]
  }
}
EOF
cat > "$HOME/.cursor/cli-config.json" <<'EOF'
{
  "version": 1,
  "editor": { "vimMode": true },
  "permissions": {
    "deny": ["Shell(rm)"],
    "allow": ["Shell(ls)"]
  }
}
EOF
printf '%s\n' 'prefix_rule(pattern=["echo"], decision="allow")' > "$HOME/.codex/rules/dot_files.rules"
before_claude=$(cat "$HOME/.claude/settings.json")
"$script" >/dev/null
"$script" --check >/dev/null

python3 - "$HOME" "$before_claude" <<'PY'
import json, pathlib, sys
home = pathlib.Path(sys.argv[1])
before = sys.argv[2]
claude_text = (home / ".claude/settings.json").read_text()
assert '"model": "kept"' in claude_text
assert "Bash(git status:*)" in claude_text
assert "Bash(git branch -D:*)" in claude_text
# The original entry stays the first allow element; we only append.
assert claude_text.index("Bash(git status:*)") < claude_text.index("Bash(git branch -D:*)")
# Nothing before the allow array is rewritten.
assert claude_text.startswith(before.split('"Bash(git status:*)"')[0] + '"Bash(git status:*)"')
claude = json.loads(claude_text)
assert claude["model"] == "kept"
assert claude["permissions"]["allow"][0] == "Bash(git status:*)"
cursor = json.loads((home / ".cursor/cli-config.json").read_text())
assert cursor["editor"]["vimMode"] is True
assert cursor["permissions"]["deny"] == ["Shell(rm)"]
assert cursor["permissions"]["allow"][0] == "Shell(ls)"
assert "Shell(git:branch -D*)" in cursor["permissions"]["allow"]
rules = (home / ".codex/rules/dot_files.rules").read_text().splitlines()
assert rules[0].startswith("prefix_rule(pattern=[\"git\", \"branch\", \"-D\"]")
assert len(rules) == 2
PY

# permissions object with deny and no allow.
export HOME="$tmp/deny-only"
mkdir -p "$HOME/.claude" "$HOME/.cursor" "$HOME/.codex/rules"
printf '%s\n' '{ "keep": true, "permissions": { "deny": ["Bash(rm:*)"] } }' > "$HOME/.claude/settings.json"
printf '%s\n' '{}' > "$HOME/.cursor/cli-config.json"
"$script" >/dev/null
python3 - "$HOME" <<'PY'
import json, pathlib, sys
home = pathlib.Path(sys.argv[1])
claude = json.loads((home / ".claude/settings.json").read_text())
assert claude["keep"] is True
assert claude["permissions"]["deny"] == ["Bash(rm:*)"]
assert "Bash(git branch -D:*)" in claude["permissions"]["allow"]
cursor = json.loads((home / ".cursor/cli-config.json").read_text())
assert set(cursor) == {"permissions"}
assert "Shell(git:worktree prune*)" in cursor["permissions"]["allow"]
PY

# A symlink is refused and left in place.  Invalid JSON is refused too.
export HOME="$tmp/refuse"
mkdir -p "$HOME/.claude" "$HOME/.cursor" "$HOME/.codex/rules"
printf '%s\n' '{"untouched": true}' > "$tmp/real-settings.json"
ln -s "$tmp/real-settings.json" "$HOME/.claude/settings.json"
printf '%s\n' '{' > "$HOME/.cursor/cli-config.json"
if "$script" >/dev/null 2>"$tmp/err"; then
    fail "apply succeeded against a symlink and invalid JSON"
fi
grep -q 'symlink' "$tmp/err"
python3 - "$tmp/real-settings.json" <<'PY'
import json, pathlib, sys
assert json.loads(pathlib.Path(sys.argv[1]).read_text()) == {"untouched": True}
PY
# The invalid cursor file is not reached once the symlink fails first.
# Check it on its own.
rm "$HOME/.claude/settings.json"
printf '%s\n' '{ "model": "kept" }' > "$HOME/.claude/settings.json"
if "$script" >/dev/null 2>"$tmp/err"; then
    fail "apply succeeded against invalid JSON"
fi
grep -q 'not valid JSON' "$tmp/err"
python3 - "$HOME/.cursor/cli-config.json" <<'PY'
import pathlib, sys
assert pathlib.Path(sys.argv[1]).read_text() == "{\n"
PY

echo "agent-permissions-smoke: ok"
