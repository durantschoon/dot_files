#!/bin/sh
# Smoke test for bin/check-orbstack.
#
# Drives the script down every branch by passing make's context as variables,
# with launchctl, pgrep and the docker/orb CLIs replaced by stubs on a private
# PATH inside a mktemp -d. Never touches the network, ~/.ssh, ~/.gnupg, launchd,
# or anything outside its temp dir.
#
# Stub behaviour is chosen per case with STUB_* variables:
#   STUB_LOADED      space-separated launchctl targets that `print` finds
#   STUB_DISABLED    lines `print-disabled` emits (label => state)
#   STUB_PGREP       output of pgrep (empty: no match, exit 1)
#   STUB_CONTEXT     output of `docker context show`
#   STUB_SERVER      output of `docker version --format ...`

here=$(cd "$(dirname "$0")/../.." && pwd)
script="$here/bin/check-orbstack"
tmp=$(mktemp -d) || exit 1
trap 'command rm -rf "$tmp"' EXIT INT TERM

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/OrbStack.app/bin" "$tmp/plain"

cat > "$tmp/bin/launchctl" <<'EOF'
#!/bin/sh
case "$1" in
  print)
    for t in $STUB_LOADED; do
      [ "$t" = "$2" ] && exit 0
    done
    exit 113 ;;
  print-disabled)
    [ -n "$STUB_DISABLED" ] && printf '%s\n' "$STUB_DISABLED"
    exit 0 ;;
esac
exit 2
EOF
cat > "$tmp/bin/pgrep" <<'EOF'
#!/bin/sh
[ -n "$STUB_PGREP" ] || exit 1
printf '%s\n' "$STUB_PGREP"
EOF
cat > "$tmp/OrbStack.app/bin/docker" <<'EOF'
#!/bin/sh
case "$1" in
  context) [ -n "$STUB_CONTEXT" ] && echo "$STUB_CONTEXT" ;;
  version) [ -n "$STUB_SERVER" ] && echo "$STUB_SERVER" ;;
esac
exit 0
EOF
cp "$tmp/OrbStack.app/bin/docker" "$tmp/plain/docker"
printf '#!/bin/sh\nexit 0\n' > "$tmp/orb"
chmod +x "$tmp/bin/launchctl" "$tmp/bin/pgrep" "$tmp/OrbStack.app/bin/docker" \
         "$tmp/plain/docker" "$tmp/orb"
ln -s "$tmp/OrbStack.app/bin/docker" "$tmp/docker-orb"
printf '<plist>repo</plist>\n' > "$tmp/src.plist"
cp "$tmp/src.plist" "$tmp/dst.plist"
printf '<plist>drifted</plist>\n' > "$tmp/drift.plist"

uid=$(id -u)

# run NAME [VAR=value ...]: run the script with good mac defaults, overridden
# by the given assignments; output in $tmp/NAME.out, status in $tmp/NAME.rc.
# Set NO_COLIMA_BIN=1 to leave COLIMA_BIN out of the environment entirely.
run() {
    name=$1; shift
    if [ "${NO_COLIMA_BIN:-}" = 1 ]; then set -- -u COLIMA_BIN "$@"
    else set -- COLIMA_BIN= "$@"; fi
    env -u COLIMA_BIN PATH="$tmp/bin:$PATH" \
        OS=mac OS_MAC=mac \
        ORBSTACK_BIN="$tmp/orb" ORBSTACK_LABEL=test.orbstack-start \
        ORBSTACK_PLIST_SRC="$tmp/src.plist" ORBSTACK_PLIST_DST="$tmp/dst.plist" \
        DOCKER_BIN="$tmp/docker-orb" COLIMA_LABEL=test.colima \
        DOCKER_DESKTOP_LABELS="test.vmnetd test.socket" HOME="$tmp/home" \
        STUB_LOADED="gui/$uid/test.orbstack-start" \
        STUB_DISABLED='"test.vmnetd" => disabled
"test.socket" => true' \
        STUB_PGREP= STUB_CONTEXT=orbstack STUB_SERVER=27.4.0 \
        env "$@" "$script" > "$tmp/$name.out" 2>&1
    echo $? > "$tmp/$name.rc"
}

# expect NAME RC LINE...: assert the exit status and that each line appears.
expect() {
    name=$1; want_rc=$2; shift 2
    got_rc=$(cat "$tmp/$name.rc")
    if [ "$got_rc" = "$want_rc" ]; then ok "$name exits $want_rc"
    else bad "$name exits $want_rc (got $got_rc)"; sed 's/^/     | /' "$tmp/$name.out"; fi
    for line in "$@"; do
        if grep -qxF -- "$line" "$tmp/$name.out"; then ok "$name: $line"
        else bad "$name: $line"; sed 's/^/     | /' "$tmp/$name.out"; fi
    done
}

# 1. Off macOS: the ifneq branch.
run linux OS=linux
expect linux 0 "==> OrbStack container runtime" "    skipped: mac-only (detected linux)"
if [ "$(wc -l < "$tmp/linux.out")" -eq 2 ]; then ok "linux: prints exactly two lines"
else bad "linux: prints exactly two lines"; fi

# 2. macOS, everything as wanted.
run good
expect good 0 \
    "    CLI:     $tmp/orb" \
    "    startup: test.orbstack-start (in sync, loaded)" \
    "    Colima:  not installed" \
    "    process: no Colima/Lima helpers running" \
    "    Desktop: test.vmnetd disabled" \
    "    Desktop: test.socket disabled" \
    "    process: no Docker Desktop helpers running" \
    "    Docker:  $tmp/docker-orb -> $tmp/OrbStack.app/bin/docker" \
    "    context: orbstack" \
    "    engine:  reachable (Docker 27.4.0)"

# 3. macOS, everything wrong.
run bad ORBSTACK_BIN="$tmp/no-orb" ORBSTACK_PLIST_DST="$tmp/missing.plist" \
    STUB_LOADED="gui/$uid/test.colima system/test.vmnetd" STUB_DISABLED= \
    STUB_PGREP="123 /opt/homebrew/bin/colima start" \
    DOCKER_BIN="$tmp/plain/docker" STUB_CONTEXT=default STUB_SERVER=
expect bad 1 \
    "    MISSING: $tmp/no-orb" \
    "    NOT DEPLOYED: $tmp/missing.plist" \
    "    CONFLICT: test.colima is still loaded" \
    "    CONFLICT: Colima-related processes remain:" \
    "              123 /opt/homebrew/bin/colima start" \
    "    CONFLICT: Docker Desktop helper test.vmnetd is loaded" \
    "    Desktop: test.socket is not persistently disabled" \
    "    CONFLICT: Docker Desktop processes remain:" \
    "    WRONG CLI: $tmp/plain/docker -> not a symlink" \
    "    WRONG CONTEXT: default (wanted orbstack)" \
    "    ENGINE DOWN: Docker server did not answer"

# 4. Drifted plist; Colima installed and persistently disabled; no context.
mkdir -p "$tmp/home/.colima"
run drift ORBSTACK_PLIST_DST="$tmp/drift.plist" \
    STUB_DISABLED='"test.colima" => disabled
"test.vmnetd" => disabled
"test.socket" => disabled' STUB_CONTEXT=
expect drift 1 \
    "    DRIFT: deployed OrbStack LaunchAgent differs from the repo" \
    "-<plist>repo</plist>" \
    "+<plist>drifted</plist>" \
    "    Colima:  startup disabled" \
    "    WRONG CONTEXT: unavailable (wanted orbstack)"

# 5. In sync but not loaded; Colima installed (COLIMA_BIN) and not disabled.
run unloaded STUB_LOADED= COLIMA_BIN="$tmp/orb"
expect unloaded 1 \
    "    NOT LOADED: gui/$uid/test.orbstack-start" \
    "    Colima:  not loaded, but not persistently disabled"

# 6. Missing context: exit 64 with a usage line, for every required variable.
for var in OS OS_MAC ORBSTACK_BIN ORBSTACK_LABEL ORBSTACK_PLIST_SRC \
           ORBSTACK_PLIST_DST DOCKER_BIN COLIMA_LABEL DOCKER_DESKTOP_LABELS HOME; do
    run "unset-$var" "$var="
    expect "unset-$var" 64
    if grep -q '^usage: ' "$tmp/unset-$var.out"; then ok "unset-$var: usage line"
    else bad "unset-$var: usage line"; fi
done
# COLIMA_BIN may be empty but must be set: env -u removes it entirely.
NO_COLIMA_BIN=1 run unset-COLIMA_BIN
expect unset-COLIMA_BIN 64
if grep -q '^usage: ' "$tmp/unset-COLIMA_BIN.out"; then ok "unset-COLIMA_BIN: usage line"
else bad "unset-COLIMA_BIN: usage line"; fi

echo "check-orbstack smoke: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
