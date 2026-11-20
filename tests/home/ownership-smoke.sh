#!/bin/sh
# tests/home/ownership-smoke.sh -- smoke test for bin/check-home-ownership.
#
# Drives the script down every branch by building a fake $HOME, a fake repo
# root (DOTFILES_HOME) and a fake home/common.scm inside one `mktemp -d', and
# passing FLAVOR / PREFLIGHT explicitly.  The branches are file-system state
# (is ~/.guix-home there, what does each path point at), not commands, so the
# only external commands are find/sed/grep/readlink/sort and no stub PATH is
# needed.  Never touches the real $HOME, ~/.ssh, ~/.gnupg or the network, and
# removes its temp dir on exit.
#
# Run from anywhere: ./tests/home/ownership-smoke.sh

script_dir=$(cd "$(dirname "$0")" && pwd -P)
script="$script_dir/../../bin/check-home-ownership"
tmp=$(mktemp -d) || exit 1
trap 'command rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

# expect_status NAME WANT GOT
expect_status() {
  if [ "$3" -eq "$2" ]; then ok "$1 (exit $3)"; else bad "$1 (exit $3, wanted $2)"; fi
}
# expect_line NAME FIXED-STRING FILE
expect_line() {
  if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1: no line containing: $2"; sed 's/^/      | /' "$3"; fi
}
# expect_no_line NAME FIXED-STRING FILE
expect_no_line() {
  if grep -qF -- "$2" "$3"; then bad "$1: unexpected line containing: $2"; else ok "$1"; fi
}

owned=".zshenv .config/zsh/.zshenv .config/zsh/.zshrc .config/zsh/.zprofile"

# fresh_fixture: a new fake home, repo and common.scm under $tmp/case.
fresh_fixture() {
  command rm -rf "$tmp/case"
  mkdir -p "$tmp/case/home" "$tmp/case/repo" "$tmp/case/cwd/home"
  fake_home="$tmp/case/home"
  fake_repo="$tmp/case/repo"
  cwd="$tmp/case/cwd"
  cat > "$cwd/home/common.scm" <<'EOF'
(home-files-service-type
 (list `(".aliases" ,(local-file "../.aliases"))
       `(".config/espanso/match/base.yml" ,(local-file "x"))))
EOF
  : > "$fake_repo/.aliases"
}

# run_check OUTFILE [VAR=VALUE ...] -- runs the script from the fixture cwd.
run_check() {
  out="$1"; shift
  (cd "$cwd" && env HOME="$fake_home" NO_COLOR=1 "$@" "$script") > "$out" 2>&1
}

# --- 1. missing context: exit 64 with a usage line ------------------------
fresh_fixture
for missing in GUIX_ZSH_OWNED DOTFILES_HOME FLAVOR; do
  # env sets all three, then -u removes the one under test.
  (cd "$cwd" && env GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack \
     env -u "$missing" HOME="$fake_home" \
     "$script") > "$tmp/out" 2>&1
  expect_status "missing $missing exits 64" 64 $?
  expect_line "missing $missing prints usage" "usage: " "$tmp/out"
  expect_line "missing $missing names it" "$missing is not set" "$tmp/out"
done

# --- 2. no ~/.guix-home: native ownership expected, exit 0 ----------------
fresh_fixture
ln -s "$fake_repo/.aliases" "$fake_home/.aliases"
: > "$fake_home/.zshenv"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack
expect_status "no generation: exit 0" 0 $?
expect_line "no generation: header" "==> \$HOME dotfiles: Guix Home vs native symlinks" "$tmp/out"
expect_line "no generation: native link" "native" "$tmp/out"
expect_line "no generation: real file is not a conflict" "real file" "$tmp/out"
expect_no_line "no generation: no CONFLICT" "CONFLICT" "$tmp/out"
expect_line "no generation: note line" "(no ~/.guix-home: no home generation active" "$tmp/out"

# --- 3. no generation, real directory: hazard; PREFLIGHT fails, normal passes
fresh_fixture
mkdir -p "$fake_home/.aliases"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack
expect_status "real directory, no generation, no PREFLIGHT: exit 0" 0 $?
expect_line "real directory: HAZARD row" "HAZARD: real directory where guix wants a symlink" "$tmp/out"
expect_line "real directory: HAZARD legend" "HAZARD = \`guix home reconfigure' will do damage" "$tmp/out"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack PREFLIGHT=1
expect_status "real directory, PREFLIGHT=1: exit 1" 1 $?

# --- 4. symlinked ancestor hazard -----------------------------------------
fresh_fixture
mkdir -p "$fake_repo/.config"
ln -s "$fake_repo/.config" "$fake_home/.config"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack PREFLIGHT=1
expect_status "symlinked ancestor, PREFLIGHT=1: exit 1" 1 $?
expect_line "symlinked ancestor: HAZARD row" "HAZARD: ~/.config is a symlink -> $fake_repo/.config" "$tmp/out"

# --- 5. generation active: conflict, leftover, inactive layer, other ------
fresh_fixture
mkdir -p "$fake_home/.guix-home/files"
: > "$fake_home/.guix-home/files/.aliases"
: > "$fake_home/.guix-home/files/.zshenv"
ln -s "$fake_repo/.aliases" "$fake_home/.aliases"      # native -> CONFLICT
: > "$fake_repo/.leftover"
ln -s "$fake_repo/.leftover" "$fake_home/.leftover"    # unclaimed -> LEFTOVER
: > "$tmp/case/elsewhere"
ln -s "$tmp/case/elsewhere" "$fake_home/.zshenv"       # other -> ...
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack
expect_status "generation active, conflict+leftover: exit 1" 1 $?
expect_line "generation: CONFLICT row" "CONFLICT: native, but Guix Home is active" "$tmp/out"
expect_line "generation: CONFLICT legend" "CONFLICT = claimed by Guix Home" "$tmp/out"
expect_line "generation: LEFTOVER row" "LEFTOVER: native link -> $fake_repo/.leftover" "$tmp/out"
expect_line "generation: LEFTOVER legend" "LEFTOVER = a native-setup link" "$tmp/out"
expect_line "generation: other row" "other -> $tmp/case/elsewhere" "$tmp/out"
expect_line "generation: inactive layer row" "absent -- OK: not part of this session" "$tmp/out"
expect_line "generation: inactive legend" '"absent -- OK" = home/common.scm declares the path' "$tmp/out"
expect_no_line "generation, FLAVOR=orbstack: no WSL espanso note" "this is guix inside WSL" "$tmp/out"
expect_no_line "generation: no no-generation note" "(no ~/.guix-home" "$tmp/out"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=wsl
expect_line "generation, FLAVOR=wsl: WSL espanso note" "espanso in particular: this is guix inside WSL" "$tmp/out"
run_check "$tmp/out" GUIX_ZSH_OWNED="$owned" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack PREFLIGHT=1
expect_status "generation, conflicts only, PREFLIGHT=1: exit 0" 0 $?

# --- 6. generation active, everything clean: exit 0 -----------------------
fresh_fixture
mkdir -p "$fake_home/.guix-home/files"
: > "$fake_home/.guix-home/files/.aliases"
run_check "$tmp/out" GUIX_ZSH_OWNED=".aliases" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack
# .aliases is absent but deployed -> plain "absent"; espanso entry is inactive.
expect_status "generation active, nothing wrong: exit 0" 0 $?
if [ -d /gnu/store ] && store_item=$(command find /gnu/store -maxdepth 1 -mindepth 1 -name '*-home' -print 2>/dev/null | head -n 1) && [ -n "$store_item" ]; then
  ln -s "$store_item" "$fake_home/.aliases"
  run_check "$tmp/out" GUIX_ZSH_OWNED=".aliases" DOTFILES_HOME="$fake_repo" FLAVOR=orbstack
  expect_line "store link reads as guix" "guix" "$tmp/out"
else
  echo "skip store link reads as guix (no /gnu/store on this host)"
fi

echo "$pass ok, $fail failed"
[ "$fail" -eq 0 ]
