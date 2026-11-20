#!/bin/sh
# Smoke test for bin/check-tailscale (stage 24).
#
# Drives every OS/flavor branch by passing the make context as environment
# variables, with tailscale, tailscaled, sysctl, scutil, launchctl, make and
# bin/termux-tailscale replaced by stubs inside a mktemp -d.  The private PATH
# is the stub dir plus /usr/bin:/bin, so no real tailscale is ever run: nothing
# here touches the network, the tailnet, ~/.ssh or ~/.gnupg, and nothing is
# written outside the temp dir.
#
# Not provable by stubs (absolute paths in the recipe):
#   - /Library/LaunchDaemons/<label>.plist (deployed / drift / perms / loaded),
#   - /usr/bin/stat -f (BSD stat),
#   - /usr/sbin/scutil --nc list (the App Store CONFLICT line).
# Where /Library/LaunchDaemons has no Tailscale plists (any non-mac host), the
# NOT DEPLOYED lines are asserted; otherwise the label loop is left alone.

repo=$(cd "$(dirname "$0")/../.." && pwd)
script=$repo/bin/check-tailscale
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0
pass=0

stubs=$tmp/stubs
root=$tmp/root
mkdir -p "$stubs" "$root/bin" "$root/system/launchd"

# tailscale: behaviour chosen by TS_STATE, TS_PREFS_HOST, TS_NAME.
cat > "$stubs/tailscale" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "status --json")
    [ -n "${TS_STATE:-}" ] || exit 1
    printf '{\n  "Version": "stub",\n  "BackendState": "%s",\n}\n' "$TS_STATE" ;;
  "debug prefs")
    [ -n "${TS_PREFS_HOST:-}" ] || { echo '{}'; exit 0; }
    printf '{\n  "Hostname": "%s",\n}\n' "$TS_PREFS_HOST" ;;
  "status --peers=false")
    [ -n "${TS_NAME:-}" ] || exit 1
    printf '100.64.0.1  %s  user@  macOS  -\n' "$TS_NAME" ;;
  *) echo "tailscale stub: unexpected: $*" >&2; exit 99 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$stubs/tailscaled"
cat > "$stubs/sysctl" <<'EOF'
#!/bin/sh
case "$2" in
  net.inet.ip.forwarding)    echo "${STUB_V4:-}" ;;
  net.inet6.ip6.forwarding)  echo "${STUB_V6:-}" ;;
  *) exit 1 ;;
esac
EOF
cat > "$stubs/scutil" <<'EOF'
#!/bin/sh
[ "$1 $2" = "--get LocalHostName" ] && [ -n "${STUB_LHN:-}" ] && echo "$STUB_LHN"
EOF
printf '#!/bin/sh\nexit 1\n' > "$stubs/launchctl"
# make: records its arguments, exits STUB_MAKE_RC.
cat > "$stubs/make" <<EOF
#!/bin/sh
echo "make-stub \$*" >> "$tmp/make.log"
exit \${STUB_MAKE_RC:-0}
EOF
# bin/termux-tailscale, relative to the repo root the script runs from.
cat > "$root/bin/termux-tailscale" <<'EOF'
echo "termux-stub $*"
exit "${STUB_TERMUX_RC:-0}"
EOF
chmod +x "$stubs"/*

plist=$root/system/launchd/com.tailscale.tailscaled.plist
printf '<plist>\n  <array>\n    <string>%s</string>\n  </array>\n</plist>\n' \
  "$stubs/tailscaled" > "$plist"
missing_plist=$root/system/launchd/missing.plist
printf '    <string>%s</string>\n' "$tmp/nonexistent/tailscaled" > "$missing_plist"

labels="com.tailscale.tailscaled com.tailscale.ip-forwarding"
not_deployed=yes
for label in $labels; do
  [ -f "/Library/LaunchDaemons/$label.plist" ] && not_deployed=no
done

# run VAR=value ... -- runs the script from $root with the default context,
# overridden by the arguments.  Output in $tmp/out, status in $status.
run() {
  : > "$tmp/make.log"
  (cd "$root" && env PATH="$stubs:/usr/bin:/bin" \
     OS=mac OS_MAC=mac FLAVOR=unknown FLAVOR_TERMUX=termux \
     MAKE="$stubs/make" TAILSCALED_PLIST_SRC="$plist" \
     TAILSCALE_LABELS="$labels" TAILSCALE_BIN="$stubs/tailscale" \
     TAILSCALE_FWD_LABEL=com.tailscale.ip-forwarding \
     "$@" "$script") > "$tmp/out" 2>&1
  status=$?
}

ok() { pass=$((pass + 1)); echo "ok $1"; }
bad() {
  fail=1; echo "FAIL $1" >&2; sed 's/^/    | /' "$tmp/out" >&2
}
# expect NAME STATUS LINE... -- status matches and every LINE is in the output.
expect() {
  name=$1; want=$2; shift 2
  if [ "$status" != "$want" ]; then bad "$name: exit $status, wanted $want"; return; fi
  for line in "$@"; do
    grep -qF -- "$line" "$tmp/out" || { bad "$name: missing line: $line"; return; }
  done
  ok "$name"
}
# absent NAME LINE... -- no LINE is in the output.
absent() {
  name=$1; shift
  for line in "$@"; do
    if grep -qF -- "$line" "$tmp/out"; then bad "$name: unexpected line: $line"; return; fi
  done
  ok "$name"
}

# 1. Missing context: each required variable, emptied, exits 64 with usage.
for var in OS OS_MAC FLAVOR FLAVOR_TERMUX MAKE TAILSCALED_PLIST_SRC \
           TAILSCALE_LABELS TAILSCALE_BIN TAILSCALE_FWD_LABEL; do
  run "$var="
  expect "missing $var exits 64" 64 "check-tailscale: $var is not set" "usage: OS=..."
done

# 2. Not mac, not termux (this host's branch).
run OS=linux
expect "linux: skipped" 0 "==> tailscaled system daemon" "    skipped: mac-only (detected linux)"
if [ "$(wc -l < "$tmp/out")" -eq 2 ]; then ok "linux: exactly two lines"; else bad "linux: exactly two lines"; fi

# 3. Termux, tailscale on PATH: no recursion, termux-tailscale's status wins.
run FLAVOR=termux OS=linux
expect "termux: runs termux-tailscale check" 0 "termux-stub check"
if [ -s "$tmp/make.log" ]; then bad "termux: make not called"; else ok "termux: make not called"; fi
absent "termux: no daemon header" "==> tailscaled system daemon"
run FLAVOR=termux STUB_TERMUX_RC=3
expect "termux: check status propagates" 3 "termux-stub check"

# 4. Termux, tailscale absent: $MAKE setup-tailscale first.
mv "$stubs/tailscale" "$stubs/tailscale.off"
run FLAVOR=termux
expect "termux no cli: setup then check" 0 "termux-stub check"
if grep -qx "make-stub setup-tailscale" "$tmp/make.log"; then
  ok "termux no cli: make setup-tailscale called"
else
  bad "termux no cli: make setup-tailscale called"
fi
run FLAVOR=termux STUB_MAKE_RC=2
expect "termux no cli: setup failure exits 1" 1
absent "termux no cli: check skipped after failed setup" "termux-stub check"
mv "$stubs/tailscale.off" "$stubs/tailscale"

# 5. mac, healthy daemon state.
run TS_STATE=Running TS_PREFS_HOST=minius TS_NAME=minius STUB_V4=1 STUB_V6=1
if [ "$not_deployed" = yes ]; then
  expect "mac healthy" 1 "==> tailscaled system daemon" \
    "    binary:  $stubs/tailscaled" \
    "    NOT DEPLOYED: /Library/LaunchDaemons/com.tailscale.tailscaled.plist -- run 'make setup-tailscale'" \
    "    NOT DEPLOYED: /Library/LaunchDaemons/com.tailscale.ip-forwarding.plist -- run 'make setup-tailscale'" \
    "    tailnet: Running" "    name:    minius" "    forward: ipv4=1 ipv6=1"
else
  expect "mac healthy (label loop not asserted)" "$status" "    binary:  $stubs/tailscaled" \
    "    tailnet: Running" "    name:    minius" "    forward: ipv4=1 ipv6=1"
fi
absent "mac healthy: no failure lines" "NO ANSWER" "BackendState=" "NAME DRIFT" "IP FORWARDING OFF" "MISSING:"

# 6. mac, daemon silent, LocalHostName fallback, forwarding off.
run STUB_LHN=MiniUs STUB_V4=0 STUB_V6=1
expect "mac daemon down" 1 \
  "    NO ANSWER from $stubs/tailscale (daemon down, or socket path mismatch)" \
  "    IP FORWARDING OFF: ipv4=0 ipv6=1" \
  "                com.tailscale.ip-forwarding exists.  Fix:"
absent "mac daemon down: no name line when unregistered" "    name:" "NAME DRIFT"

# 7. mac, logged out and renamed -N; want comes from LocalHostName, lowercased.
run TS_STATE=NeedsLogin TS_NAME=minius-1 STUB_LHN=MiniUs STUB_V4=1 STUB_V6=1
expect "mac name drift" 1 \
  "    BackendState=NeedsLogin -- try: sudo $stubs/tailscale up --advertise-exit-node" \
  "    NAME DRIFT: registered as 'minius-1', wanted 'minius'" \
  "                  sudo $stubs/tailscale set --hostname=minius" \
  "    forward: ipv4=1 ipv6=1"

# 8. mac, prefs Hostname wins over LocalHostName.
run TS_STATE=Running TS_PREFS_HOST=orb TS_NAME=orb STUB_LHN=MiniUs STUB_V4=1 STUB_V6=1
expect "mac prefs hostname wins" "$status" "    name:    orb"

# 9. mac, the plist names a binary that is not there.
run TAILSCALED_PLIST_SRC="$missing_plist" TS_STATE=Running STUB_V4=1 STUB_V6=1
expect "mac binary missing" 1 \
  "    MISSING: $tmp/nonexistent/tailscaled is not executable" \
  "              an Intel Mac puts it under /usr/local)"

echo "$pass passed"
[ "$fail" = 0 ]
