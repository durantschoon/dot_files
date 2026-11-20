#!/usr/bin/env -S zsh -f
# -*- mode: sh; -*-
#
# tests/remindme/smoke.zsh -- smoke tests for bin/remindme.
#
#   ./tests/remindme/smoke.zsh          (also: make check-remindme-tests)

emulate -L zsh
setopt no_nomatch

SCRIPT_UNDER_TEST="${0:A:h}/../../bin/remindme"
[[ -x "$SCRIPT_UNDER_TEST" ]] || chmod +x "$SCRIPT_UNDER_TEST"
[[ -x "$SCRIPT_UNDER_TEST" ]] || { print -u2 "missing or not executable: $SCRIPT_UNDER_TEST"; exit 1 }

SCRATCH="${TMPDIR:-/tmp}/remindme-smoke-$$"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM HUP

typeset -i FAILED=0
ok()   { print "  ok: $1" }
fail() { print -u2 "  FAIL: $1"; FAILED=$(( FAILED + 1 )) }

mkdir -p "$SCRATCH/bin" "$SCRATCH/empty" "$SCRATCH/notes"

# Fake glow binary that records its arguments and prints file contents
cat > "$SCRATCH/bin/glow" <<'EOF'
#!/bin/sh
printf 'GLOW_ARGS:%s\n' "$*"
last=''
for a in "$@"; do last=$a; done
if [ -f "$last" ]; then
    cat "$last"
fi
EOF
chmod +x "$SCRATCH/bin/glow"

export PATH="$SCRATCH/bin:$PATH"

print "==> 1. uninitialized directory refuses with submodule hint"
out=$(REMINDME_DIR="$SCRATCH/empty" "$SCRIPT_UNDER_TEST" ewm 2>&1)
rc=$?
if (( rc != 0 )) && [[ "$out" == *"submodule update --init remindme/private"* ]]; then
    ok "uninitialized directory exits non-zero and prints submodule hint"
else
    fail "expected non-zero + submodule hint, got rc=$rc out=$out"
fi

# Seed notes directory
cat > "$SCRATCH/notes/README.md" <<'EOF'
# Private Reminders Repo
Should be ignored by list and search.
EOF

cat > "$SCRATCH/notes/ewm.md" <<'EOF'
# EWM (Emacs Wayland Manager)
Launch with `make ewm-launch` from TTY2.
Return to GNOME with `sudo -i herd start xorg-server`.
EOF

cat > "$SCRATCH/notes/guix.md" <<'EOF'
# Guix Quick Reference
Roll back home with `guix home roll-back`.
EOF

export REMINDME_DIR="$SCRATCH/notes"

print "==> 2. --list shows topics with headings and skips README.md"
out=$("$SCRIPT_UNDER_TEST" --list 2>&1)
rc=$?
if (( rc == 0 )) && [[ "$out" == *"ewm"* ]] && [[ "$out" == *"EWM (Emacs Wayland Manager)"* ]] \
   && [[ "$out" == *"guix"* ]] && [[ "$out" != *"README"* ]]; then
    ok "--list shows ewm and guix with titles, omits README"
else
    fail "--list unexpected: rc=$rc out=$out"
fi

print "==> 3. remindme ewm (and ewm.md) renders via glow"
out=$("$SCRIPT_UNDER_TEST" ewm 2>&1)
rc=$?
if (( rc == 0 )) && [[ "$out" == *"GLOW_ARGS:-s dark $SCRATCH/notes/ewm.md"* ]] \
   && [[ "$out" == *"make ewm-launch"* ]]; then
    ok "remindme ewm calls glow -s dark on ewm.md"
else
    fail "remindme ewm unexpected: rc=$rc out=$out"
fi

out_md=$("$SCRIPT_UNDER_TEST" ewm.md 2>&1)
if [[ "$out_md" == "$out" ]]; then
    ok "remindme ewm.md strips .md extension cleanly"
else
    fail "remindme ewm.md differed from remindme ewm"
fi

print "==> 4. remindme -p ewm passes -p to glow"
out=$("$SCRIPT_UNDER_TEST" -p ewm 2>&1)
if [[ "$out" == *"GLOW_ARGS:-s dark -p $SCRATCH/notes/ewm.md"* ]]; then
    ok "remindme -p ewm passes -p to glow"
else
    fail "remindme -p ewm unexpected: $out"
fi

print "==> 5. remindme -e creates/edits topic via EDITOR"
EDITOR='sh -c '\''printf "# Test Note\nhello\n" > "$1"'\'' --' "$SCRIPT_UNDER_TEST" -e testnote
if [[ -f "$SCRATCH/notes/testnote.md" ]] && grep -q "hello" "$SCRATCH/notes/testnote.md"; then
    ok "remindme -e testnote writes testnote.md"
else
    fail "remindme -e testnote did not create expected file"
fi

print "==> 6. remindme -s searches across notes"
out=$("$SCRIPT_UNDER_TEST" -s "roll-back" 2>&1)
rc=$?
if (( rc == 0 )) && [[ "$out" == *"guix.md"* ]] && [[ "$out" == *"roll-back"* ]]; then
    ok "remindme -s finds matching line in guix.md"
else
    fail "remindme -s unexpected: rc=$rc out=$out"
fi

print "==> 7. remindme --path prints directory or file path"
p1=$("$SCRIPT_UNDER_TEST" --path)
p2=$("$SCRIPT_UNDER_TEST" --path ewm)
if [[ "$p1" == "$SCRATCH/notes" && "$p2" == "$SCRATCH/notes/ewm.md" ]]; then
    ok "--path returns directory and topic file path"
else
    fail "--path unexpected: p1=$p1 p2=$p2"
fi

print "==> 8. missing topic exits non-zero and lists available reminders"
out=$("$SCRIPT_UNDER_TEST" nonexistent 2>&1)
rc=$?
if (( rc != 0 )) && [[ "$out" == *"no reminder named 'nonexistent'"* ]] && [[ "$out" == *"Available reminders:"* ]]; then
    ok "missing topic exits non-zero and lists available topics"
else
    fail "missing topic unexpected: rc=$rc out=$out"
fi

if (( FAILED > 0 )); then
    print -u2 "\nFAILED: $FAILED check(s)"
    exit 1
fi
print "\nAll remindme smoke checks passed."
