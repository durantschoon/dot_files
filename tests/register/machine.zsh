#!/usr/bin/env zsh
# Checklist output with the network and live host stubbed out.
set -euo pipefail
root=${0:A:h:h:h}
script=$root/bin/register-machine
fail=0
base=(env REGISTER_SKIP_NET=1 REGISTER_SKIP_GPG=1 REGISTER_HOST=framepop)
run() {
    local name=$1 expect=$2
    shift 2
    local out rc=0
    out=$("${base[@]}" REGISTER_DF_AVAIL_K=$((20 * 1024 * 1024)) "$script" "$@" 2>&1) || rc=$?
    if [[ $rc != $expect ]]; then
        print -u2 "FAIL $name: exit $rc, wanted $expect"
        print -u2 "$out"
        fail=1
        return
    fi
    REPLY=$out
    print "ok $name"
}
run 'native names setup-native' 0 --role native
[[ $REPLY == *'Next: make setup-native'* && $REPLY == *'.zshrc.starship names framepop'* && $REPLY == *'mr-clone NAME'* ]] || {
    print -u2 'FAIL native body'
    print -u2 "$REPLY"
    fail=1
}
print 'ok native body'
small=$("${base[@]}" REGISTER_DF_AVAIL_K=1024 "$script" --role foreign 2>&1) || true
[[ $small == *'make setup-native'* && $small == *'Next: make apply'* ]] || {
    print -u2 'FAIL small-disk foreign still shows both facts'
    print -u2 "$small"
    fail=1
}
print 'ok small disk'
"${base[@]}" REGISTER_DF_AVAIL_K=$((20 * 1024 * 1024)) "$script" </dev/null >/dev/null 2>&1 && {
    print -u2 'FAIL missing role should exit'
    fail=1
} || print 'ok role required'
[[ $fail == 0 ]]
