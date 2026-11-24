#!/bin/sh
# Smoke test for bin/agent-resume.
#
# Runs against a fixture problem-stack file and a fake HOME inside a mktemp -d,
# always with --dry-run or a refusal path, so no agent is ever launched and
# nothing outside the temp dir is read or written.

repo=$(cd "$(dirname "$0")/../.." && pwd)
script=$repo/bin/agent-resume
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0
pass=0

mkdir -p "$tmp/central/docs/problem-stack" "$tmp/home/.claude/projects/-work" "$tmp/work" "$tmp/other"
cat > "$tmp/central/docs/problem-stack/testhost.md" <<STACK
# Problem stack - testhost

## Sessions

### claude-aaaa1111 · first task
- Session: aaaa1111-0000-0000-0000-000000000001
- Resume: \`claude --resume aaaa1111-0000-0000-0000-000000000001\`
- cwd: $tmp/work

### claude-aaaa2222 · twin task
- Session: aaaa2222-0000-0000-0000-000000000002
- Resume: \`claude --resume aaaa2222-0000-0000-0000-000000000002\`
- cwd: $tmp/work

### codex-bbbb3333 · codex task
- Session: bbbb3333-0000-0000-0000-000000000003
- Resume: \`codex resume bbbb3333-0000-0000-0000-000000000003\`
- cwd: $tmp/work

### claude-cccc4444 · evil resume line
- Session: cccc4444-0000-0000-0000-000000000004
- Resume: \`rm -rf /\`
- cwd: $tmp/work

### claude-dddd5555 · gone directory
- Session: dddd5555-0000-0000-0000-000000000005
- Resume: \`claude --resume dddd5555-0000-0000-0000-000000000005\`
- cwd: $tmp/does-not-exist

## Closed sessions

### claude-eeee6666 · closed task
- Session: eeee6666-0000-0000-0000-000000000006
- Resume: \`claude --resume eeee6666-0000-0000-0000-000000000006\`
- cwd: $tmp/work

## Resolved

### ps-zzzz · a resolved entry
- Session: claude-ffff7777 · not a root
STACK
cat > "$tmp/central/docs/problem-stack/elsewhere.md" <<STACK
## Sessions

### claude-9999aaaa · remote task
- Session: 9999aaaa-0000-0000-0000-000000000009
- Resume: \`claude --resume 9999aaaa-0000-0000-0000-000000000009\`
- cwd: /root/somewhere
STACK
# A Claude transcript with no stack entry: found by the fallback, cwd read from it.
printf '{"type":"summary"}\n{"cwd":"%s"}\n' "$tmp/work" \
    > "$tmp/home/.claude/projects/-work/77770000-1111-2222-3333-444444444444.jsonl"

run() {  # run <args...>; sets out and rc
    out=$(HOME="$tmp/home" AGENT_RESUME_CENTRAL="$tmp/central" AGENT_RESUME_HOST=testhost \
          "$script" "$@" 2>&1 </dev/null)
    rc=$?
}
check() {  # check <name> <expected rc> <expected substring>
    name=$1 want_rc=$2 want=$3
    if [ "$rc" -eq "$want_rc" ] && printf '%s' "$out" | grep -qF -- "$want"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL %s: rc=%s (want %s), wanted %s in:\n%s\n' "$name" "$rc" "$want_rc" "$want" "$out"
    fi
}

run -n claude-aaaa1111
check "full handle"          0 "claude --resume aaaa1111-0000-0000-0000-000000000001"
run -n aaaa1111
check "bare uuid8"           0 "cd $tmp/work"
run -n aaaa1
check "unique short prefix"  0 "first task"
run -n aaaa
check "ambiguous prefix"     2 "ambiguous"
run -n bbbb3333
check "codex resume line"    0 "codex resume bbbb3333"
run -n claude-bbbb3333
check "wrong agent prefix"   1 "no session matches"
run -n eeee6666
check "closed session"       0 "closed task"
run -n ffff7777
check "resolved is not a root" 1 "no session matches"
run -n cccc4444
check "refuses non-agent command" 1 "refusing to run"
run -n dddd5555
check "missing cwd"          1 "does not exist here"
run -n 9999aaaa
check "other machine's session" 1 "elsewhere"
run -n 77770000
check "transcript fallback"  0 "claude --resume 77770000-1111-2222-3333-444444444444"
run -n ab
check "prefix too short"     2 "at least 4"
run --list
check "list"                 0 "6 session(s)"
run
check "no argument"          2 "usage"

printf 'agent-resume smoke: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
