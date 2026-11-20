#!/bin/sh
# Smoke test for bin/check-gpg: drives every branch of the script, including
# the macOS and Termux ones this host never takes, without touching the real
# keyring, agent or git config.
#
# Isolation (the whole point -- the real agent's cached passphrase must stay
# cached):
#   - env -i: the script sees only the variables set here
#   - HOME and GNUPGHOME are inside a mktemp -d, so $HOME/.gnupg is a fake
#   - GIT_CONFIG_GLOBAL is a private file, GIT_CONFIG_NOSYSTEM=1, and the cwd
#     is the temp dir with GIT_CEILING_DIRECTORIES, so no repo config applies
#   - PATH is a private directory: stub gpg, gpgconf and gpg-connect-agent,
#     plus symlinks to the few real tools the script needs.  The real gpg is
#     never on it, so nothing can sign, list a real key or start an agent.
#   - gpgconf and gpg-connect-agent stubs log any call; the test asserts none.
# The terminal branches (step 6) need stdin to be a tty; they run under
# util-linux script(1) when it is available and are reported as SKIP
# otherwise (a skip is not a pass).
#
# Usage: tests/gpg/check-gpg-smoke.sh   (exit 0 when every case passes)

here=$(cd "$(dirname "$0")" && pwd)
check_gpg="$here/../../bin/check-gpg"
fail=0
skipped=0

work_dir=$(mktemp -d) || exit 1
trap 'command rm -rf "$work_dir"' EXIT INT TERM

stub_bin="$work_dir/bin"
fake_home="$work_dir/home"
gnupg_dir="$fake_home/.gnupg"
git_config="$work_dir/gitconfig"
call_log="$work_dir/forbidden-calls.log"
mkdir -p "$stub_bin" "$gnupg_dir"
: >"$call_log"

# Real tools the script (and the stubs) call, linked onto the private PATH.
for tool_name in awk cat cut date find git grep head ls mktemp rm sed tail tr wc; do
  tool_path=$(command -v "$tool_name") || { echo "FAIL setup: $tool_name not found"; exit 1; }
  ln -s "$tool_path" "$stub_bin/$tool_name"
done

# Stub gpg: behaviour chosen by STUB_SECRET (none|never|<epoch>) and
# STUB_SIGN_RC (exit status of --sign).
cat >"$stub_bin/gpg" <<'EOF'
#!/bin/sh
case " $* " in
  *" --version "*) echo "gpg (GnuPG) 9.9.9-stub"; exit 0 ;;
  *" --list-secret-keys "*)
    case "${STUB_SECRET:-none}" in
      none) exit 2 ;;
      never) echo "sec:u:255:22:STUBKEY:1700000000::::::scESC:::+:::23::0:" ;;
      *) echo "sec:u:255:22:STUBKEY:1700000000:${STUB_SECRET}:::::scESC:::+:::23::0:" ;;
    esac
    exit 0 ;;
  *" --sign "*)
    cat >/dev/null
    if [ "${STUB_SIGN_RC:-0}" != 0 ]; then
      echo "gpg: signing failed: stub says no" >&2
      exit "$STUB_SIGN_RC"
    fi
    exit 0 ;;
esac
echo "stub gpg: unexpected arguments: $*" >&2
exit 99
EOF
for agent_tool in gpgconf gpg-connect-agent; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 99\n' "$agent_tool" "$call_log" >"$stub_bin/$agent_tool"
done
chmod +x "$stub_bin/gpg" "$stub_bin/gpgconf" "$stub_bin/gpg-connect-agent"

# A PATH with the real tools but no gpg at all, for the "not on PATH" branch.
no_gpg_bin="$work_dir/bin-no-gpg"
mkdir -p "$no_gpg_bin"
for tool_name in awk cat cut date find git grep head ls mktemp rm sed tail tr wc; do
  ln -s "$(command -v "$tool_name")" "$no_gpg_bin/$tool_name"
done

now_epoch=$(date +%s)
expired_epoch=$((now_epoch - 86400))
soon_epoch=$((now_epoch + 10 * 86400))
later_epoch=$((now_epoch + 400 * 86400))

# reset_state: a healthy baseline -- key set, signing on, no agent conf, no locks.
reset_state() {
  printf '[user]\n\tsigningkey = STUBKEY\n[commit]\n\tgpgsign = true\n' >"$git_config"
  command rm -f "$gnupg_dir/gpg-agent.conf" "$gnupg_dir"/.#lk*
}

# run_check NAME WANT_RC NEEDLE [VAR=value ...]: run the script with a clean
# environment plus the given assignments, assert exit status and that NEEDLE
# appears in the combined output.
run_check() {
  case_name=$1 want_rc=$2 needle=$3
  shift 3
  case_out=$(cd "$work_dir" && env -i \
    PATH="$stub_bin" HOME="$fake_home" GNUPGHOME="$gnupg_dir" \
    GIT_CONFIG_GLOBAL="$git_config" GIT_CONFIG_NOSYSTEM=1 \
    GIT_CEILING_DIRECTORIES="$work_dir" TMPDIR="$work_dir" \
    OS=linux OS_MAC=mac FLAVOR=unknown FLAVOR_TERMUX=termux \
    "$@" "$check_gpg" </dev/null 2>&1)
  case_rc=$?
  report_case "$case_name" "$want_rc" "$needle"
}

# shell_quote ARG...: print the arguments as one single-quoted command line,
# for script(1), which only takes a command string.
shell_quote() {
  for quote_arg in "$@"; do
    printf "'%s' " "$(printf '%s' "$quote_arg" | sed "s/'/'\\\\''/g")"
  done
}

# run_check_tty: as run_check, but with stdin on a pseudo-terminal (step 6).
run_check_tty() {
  case_name=$1 want_rc=$2 needle=$3
  shift 3
  if [ -z "$have_script" ]; then
    echo "SKIP $case_name (no util-linux script(1) for a pty)"
    skipped=$((skipped + 1))
    return
  fi
  tty_cmd=$(shell_quote env -i \
    PATH="$stub_bin" HOME="$fake_home" GNUPGHOME="$gnupg_dir" \
    GIT_CONFIG_GLOBAL="$git_config" GIT_CONFIG_NOSYSTEM=1 \
    GIT_CEILING_DIRECTORIES="$work_dir" \
    OS=linux OS_MAC=mac FLAVOR=unknown FLAVOR_TERMUX=termux \
    "$@" "$check_gpg")
  # SHELL=/bin/sh: script(1) runs the command with $SHELL -c, and a login
  # zsh would source the real ~/.zshenv (which may talk to the agent).
  (cd "$work_dir" && SHELL=/bin/sh "$script_cmd" -qec "$tty_cmd" /dev/null </dev/null >"$work_dir/tty.out" 2>&1)
  case_rc=$?
  case_out=$(tr -d '\r' <"$work_dir/tty.out")
  report_case "$case_name" "$want_rc" "$needle"
}

report_case() {
  if [ "$case_rc" != "$2" ]; then
    echo "FAIL $1: exit $case_rc, wanted $2"
    printf '%s\n' "$case_out" | sed 's/^/     | /'
    fail=1
    return
  fi
  case "$case_out" in
    *"$3"*) echo "ok $1" ;;
    *)
      echo "FAIL $1: output lacks: $3"
      printf '%s\n' "$case_out" | sed 's/^/     | /'
      fail=1 ;;
  esac
}

# --- missing make context: exit 64 with a usage line -------------------------
for missing_var in OS OS_MAC FLAVOR FLAVOR_TERMUX; do
  reset_state
  case_out=$(cd "$work_dir" && env -i PATH="$stub_bin" HOME="$fake_home" \
    GIT_CONFIG_GLOBAL="$git_config" GIT_CONFIG_NOSYSTEM=1 \
    OS=linux OS_MAC=mac FLAVOR=unknown FLAVOR_TERMUX=termux \
    "$missing_var=" "$check_gpg" </dev/null 2>&1)
  case_rc=$?
  report_case "missing $missing_var exits 64 with usage" 64 "usage: OS="
done

# --- step 1: gpg on PATH -----------------------------------------------------
reset_state
run_check "no gpg on PATH" 1 "[--] gpg      : not on PATH" PATH="$no_gpg_bin"

# --- healthy run, no terminal: everything ok, sign step skipped --------------
reset_state
run_check "healthy, never-expiring key, linux, no tty" 0 "[..] sign     : skipped" STUB_SECRET=never
case "$case_out" in
  *"[ok] gpg      : $stub_bin/gpg (9.9.9-stub)"*"[ok] key      : user.signingkey = STUBKEY"*"[ok] secret   : present, never expires"*"[ok] pinentry : gpg default"*"[ok] git      : commit.gpgsign = true"*"==> gpg signing OK"*)
    echo "ok healthy run prints every [ok] line in order" ;;
  *) echo "FAIL healthy run line order"; printf '%s\n' "$case_out" | sed 's/^/     | /'; fail=1 ;;
esac

# --- gpg.program pointing nowhere ---------------------------------------------
reset_state
printf '[gpg]\n\tprogram = %s/no-such-gpg\n' "$work_dir" >>"$git_config"
run_check "gpg.program does not exist" 1 "[--] gpg.program = $work_dir/no-such-gpg does not exist" STUB_SECRET=never

# --- step 2: signing key -------------------------------------------------------
reset_state
printf '[commit]\n\tgpgsign = true\n' >"$git_config"
run_check "user.signingkey unset" 1 "[--] key      : user.signingkey is not set"

# --- step 3: secret key and expiry -------------------------------------------
reset_state
run_check "no secret key" 1 "[--] secret   : no secret key for STUBKEY in $fake_home/.gnupg" STUB_SECRET=none
reset_state
run_check "secret expired" 1 "[--] secret   : present but EXPIRED on " STUB_SECRET="$expired_epoch"
reset_state
run_check "secret expires within 30 days" 0 "[!!] secret   : present, expires in " STUB_SECRET="$soon_epoch"
reset_state
run_check "secret expires later" 0 "[ok] secret   : present, expires $(date -d "@$later_epoch" +%Y-%m-%d 2>/dev/null || date -r "$later_epoch" +%Y-%m-%d)" STUB_SECRET="$later_epoch"

# --- step 4: pinentry ------------------------------------------------------------
reset_state
echo "pinentry-program $work_dir/no-such-pinentry" >"$gnupg_dir/gpg-agent.conf"
run_check "pinentry configured but missing" 1 "[--] pinentry : $work_dir/no-such-pinentry is missing" STUB_SECRET=never
reset_state
printf '#!/bin/sh\nexit 0\n' >"$work_dir/pinentry-stub"; chmod +x "$work_dir/pinentry-stub"
echo "pinentry-program $work_dir/pinentry-stub" >"$gnupg_dir/gpg-agent.conf"
run_check "pinentry configured and present" 0 "[ok] pinentry : $work_dir/pinentry-stub" STUB_SECRET=never
reset_state
run_check "mac with no pinentry configured" 1 "[--] pinentry : none configured" STUB_SECRET=never OS=mac
reset_state
run_check "linux with no pinentry configured" 0 "[ok] pinentry : gpg default" STUB_SECRET=never OS=linux

# --- step 5: commit.gpgsign ---------------------------------------------------------
reset_state
printf '[user]\n\tsigningkey = STUBKEY\n' >"$git_config"
run_check "commit.gpgsign unset" 1 "[--] git      : commit.gpgsign = <unset>" STUB_SECRET=never
reset_state
printf '[user]\n\tsigningkey = STUBKEY\n[commit]\n\tgpgsign = false\n' >"$git_config"
run_check "commit.gpgsign false" 1 "[--] git      : commit.gpgsign = false" STUB_SECRET=never
case "$case_out" in
  *"==> gpg signing: fix the [--] lines above"*) echo "ok failures end with the fix summary" ;;
  *) echo "FAIL failures end with the fix summary"; fail=1 ;;
esac

# --- stale lock files (informational) ------------------------------------------------
reset_state
: >"$gnupg_dir/.#lk0x1.host.1"; : >"$gnupg_dir/.#lk0x2.host.2"
run_check "stale locks are counted" 0 "[..] locks    : 2 stale .#lk* lock files" STUB_SECRET=never

# --- step 6: terminal branches (stdin on a pty) ---------------------------------------
have_script=
if script_cmd=$(command -v script) && "$script_cmd" --version 2>/dev/null | grep -q util-linux; then
  have_script=1
fi
fake_tty="$work_dir/fake-tty"
: >"$fake_tty"

reset_state
run_check_tty "ssh without PINENTRY_USER_DATA" 1 "[--] ssh      : PINENTRY_USER_DATA is not set" \
  STUB_SECRET=never SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" GPG_TTY="$fake_tty" TMPDIR="$work_dir"
reset_state
run_check_tty "ssh with USE_TTY=1" 0 "[ok] ssh      : PINENTRY_USER_DATA=USE_TTY=1" \
  STUB_SECRET=never SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" PINENTRY_USER_DATA=USE_TTY=1 GPG_TTY="$fake_tty" TMPDIR="$work_dir"
reset_state
run_check_tty "GPG_TTY unset" 1 "[--] tty      : GPG_TTY is not set" STUB_SECRET=never TMPDIR="$work_dir"
reset_state
run_check_tty "GPG_TTY not openable" 1 "so the pinentry cannot open it" \
  STUB_SECRET=never GPG_TTY="$work_dir/no-such-tty" TMPDIR="$work_dir"
reset_state
run_check_tty "sign works (stub gpg)" 0 "[ok] sign     : works" STUB_SECRET=never GPG_TTY="$fake_tty" TMPDIR="$work_dir"
reset_state
run_check_tty "sign fails (stub gpg)" 1 "[--] sign     : gpg: signing failed: stub says no" \
  STUB_SECRET=never STUB_SIGN_RC=2 GPG_TTY="$fake_tty" TMPDIR="$work_dir"
reset_state
mkdir -p "$work_dir/termux-prefix/tmp"
run_check_tty "termux uses PREFIX/tmp when TMPDIR is unset" 0 "[ok] sign     : works" \
  STUB_SECRET=never GPG_TTY="$fake_tty" FLAVOR=termux PREFIX="$work_dir/termux-prefix"
reset_state
run_check_tty "termux reports an unusable PREFIX/tmp" 1 "[--] sign     : cannot create a temporary file in $work_dir/missing-prefix/tmp" \
  STUB_SECRET=never GPG_TTY="$fake_tty" FLAVOR=termux PREFIX="$work_dir/missing-prefix"
reset_state
run_check_tty "non-termux ignores PREFIX" 1 "[--] sign     : cannot create a temporary file in $work_dir/no-such-tmpdir" \
  STUB_SECRET=never GPG_TTY="$fake_tty" FLAVOR=unknown PREFIX="$work_dir/termux-prefix" TMPDIR="$work_dir/no-such-tmpdir"

# --- isolation: the agent tools were never called; errfiles were cleaned up ------------
if [ -s "$call_log" ]; then
  echo "FAIL agent tools were called:"; sed 's/^/     | /' "$call_log"; fail=1
else
  echo "ok gpgconf / gpg-connect-agent never called"
fi
leftover=$(command find "$work_dir" "$work_dir/termux-prefix/tmp" -maxdepth 1 -name 'check-gpg.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$leftover" != 0 ]; then
  echo "FAIL $leftover check-gpg.* temp files left behind"; fail=1
else
  echo "ok no check-gpg.* temp files left behind"
fi

[ "$skipped" = 0 ] || echo "NOTE $skipped case(s) skipped; a skip is not a pass"
exit "$fail"
