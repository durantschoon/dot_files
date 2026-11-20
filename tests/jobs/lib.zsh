# -*- mode: sh; -*-
#
# tests/jobs/lib.zsh -- the assertion plumbing shared by the job suites.
#
#   source "${0:A:h}/lib.zsh"      (from a suite's top level, so $0 is the suite)
#
# Sourced, never run: no shebang and no exec bit. Sourced by smoke.zsh,
# tee-smoke.zsh and podman-live.zsh. claude-smoke.zsh keeps its own pass /
# fail / skip: its lines are indented, its fail counts and carries on instead
# of exiting, and its counters are N and FAILS -- a different contract, not a
# copy of this one.
#
# One ok/FAIL line each, stop at the first failure. The first argument of
# every assertion is the message; the line format is shared so the suites'
# output is greppable together.
#
# Where two suites once gave one name two meanings, both meanings live here
# under distinct names and the suite that wanted the other one maps its name
# onto it locally (tee-smoke.zsh: eq -> eqlit, starts -> startslit). Nothing
# here picks a winner.

typeset -g N_OK=0
typeset -g N_SKIP=0
ok()   { (( N_OK++ )); print -r -- "ok   $1" }
note() { print -r -- "     note: $1" }
# A skipped assertion is counted and named, never silent and never an `ok':
# the closing line reports run and skipped separately, so "it passed here" and
# "it could not be asked here" stay two different facts. A skip is a MEASURED
# host limitation with the measurement in its reason -- never a way to make an
# unknown look like a pass.
skip() { (( N_SKIP++ )); print -r -- "SKIP $1  -- $2" }
skip_all() { local why=$1 m; for m in "${@:2}"; do skip "$m" "$why"; done }
fail() {
  print -r -- "FAIL $1"
  local l; for l in "${@:2}"; do print -r -- "     $l"; done
  exit 1
}

# eq's right-hand side is written unquoted, as a zsh PATTERN would be; eqlit
# quotes it, so it is literal whatever it holds (the record round trip's
# backslashes, image references, paths). Measured (zsh 5.9, smoke.zsh): a
# pattern that arrives through a parameter is matched literally unless it goes
# through ${~...}, so in practice the two agree -- they are kept apart anyway,
# because each call site was written against one of them.
eq()    { [[ $2 == $3   ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
eqlit() { [[ $2 == "$3" ]] && ok "$1" || fail "$1" "expected: [$3]" "actual:   [$2]" }
has()   { [[ $2 == *$3* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasnt() { [[ $2 != *$3* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
# The literal pair, for the same reason eqlit exists. A picker key is
# "host|name" and an fzf binding is "ctrl-r:reload(...)": `|' is alternation in
# a zsh pattern and `(' opens a group, so `*local|x*' and `*reload(*' do not
# mean what they read as. These two quote the needle instead.
haslit()   { [[ $2 == *"$3"* ]] && ok "$1" || fail "$1" "expected to contain: [$3]" "actual: [$2]" }
hasntlit() { [[ $2 != *"$3"* ]] && ok "$1" || fail "$1" "expected NOT to contain: [$3]" "actual: [$2]" }
# Two prefix tests, kept apart for the reason eq and eqlit are. starts is the
# anchored glob smoke.zsh wrote; startslit slices instead, as tee-smoke.zsh
# wrote it: zsh does not re-read the result of a parameter expansion as a
# pattern (no_glob_subst is the default), so a pattern arriving through "$3"
# is compared literally -- measured there, `[[ $a == $b ]]' with b='...at *'
# does NOT match.
starts()    { [[ $2 == $3* ]] && ok "$1" || fail "$1" "expected to start with: [$3]" "actual: [$2]" }
startslit() { [[ ${2[1,${#3}]} == "$3" ]] && ok "$1" || fail "$1" "expected to start with: [$3]" "actual: [$2]" }
# The other end, quoted: a row's status is appended to its label, so "ends
# with" is the whole claim, spelled as an anchored pattern with a LITERAL
# needle.
ends() { [[ $2 == *"$3" ]] && ok "$1" || fail "$1" "expected to end with: [$3]" "actual: [$2]" }
# Exit-status assertions carry the command's own output into the failure
# report: an engine that refused says why on stderr, and that sentence is the
# finding.
rc0()  { (( $2 == 0 )) && ok "$1" || fail "$1" "expected exit 0, got $2" "${@:3}" }
rceq() { [[ $2 == $3 ]] && ok "$1" || fail "$1" "expected exit $3, got $2" "${@:4}" }
# Non-zero exit, whatever the value: several paths only promise "not 0".
nonzero() { (( $2 != 0 )) && ok "$1 (rc=$2)" || fail "$1" "expected a non-zero exit, got 0" "${@:3}" }
# A closed interval, for assertions about a duration: an escalation that fired
# too early did not give the command its grace, and one that fired too late
# spent budget that belongs to the engine's stop timeout. Both bounds are
# therefore real failures, not slack.
within() {
  (( $2 >= $3 && $2 <= $4 )) && ok "$1" \
    || fail "$1" "expected: $(printf '%.2f <= x <= %.2f' $3 $4)" \
                 "actual:   $(printf '%.2f' $2)"
}
