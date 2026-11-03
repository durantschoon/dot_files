#!/usr/bin/env bash
# TEMPORARY. Delete this file after both Pop!_OS machines have run it.
# From a dot_files checkout: bash tmp-pop-os-apparmor-steps.sh
set -euo pipefail

if [[ $(uname -s) == Darwin ]]; then
    echo 'These steps are for Pop!_OS, not macOS.' >&2
    exit 1
fi
if [[ $(uname -s) != Linux ]]; then
    echo "These steps are for Pop!_OS. This machine is $(uname -s)." >&2
    exit 1
fi

repo=$HOME/dot_files
cd "$repo"

confirm() {
    local answer
    read -r -p "$1 [y/N] " answer
    case $answer in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

echo "=== 1. Update the checkout ==="
git pull --ff-only

echo "=== 2. Read-only checks ==="
bash -n guix-install.sh bin/seed-linux
make check-guix-installer
apparmor_parser --version
guix --version
echo -n 'AppArmor enabled: '
cat /sys/module/apparmor/parameters/enabled
echo '--- installed builder profile ---'
grep -n -A18 'profile guix-builder' /etc/apparmor.d/guix-daemon
echo '--- Guix source builder profile ---'
grep -n -A18 'profile guix-builder' /var/guix/profiles/per-user/root/current-guix/etc/apparmor.d/guix-daemon

echo "=== 3. Validate the adjustment without loading policy ==="
candidate=$(mktemp)
bash -c 'source ./guix-install.sh; apparmor_adjust_builder /etc/apparmor.d/guix-daemon "$1"' check "$candidate"
apparmor_parser --skip-kernel-load --skip-cache --warn=all -b /etc/apparmor.d "$candidate"
rm -f "$candidate"
echo 'Candidate parsed without loading it.'

echo "=== 4. Optional real-parser fixture compile ==="
APPARMOR_TEST_PARSER=$(command -v apparmor_parser) \
APPARMOR_TEST_BASE=/etc/apparmor.d make check-guix-installer
if command -v shellcheck >/dev/null; then
    shellcheck guix-install.sh bin/seed-linux
else
    echo 'shellcheck is not installed; skipping it.'
fi

echo "=== 5. Install and validate the live Guix profiles ==="
echo 'This changes /etc/apparmor.d Guix policy and reloads those profiles.'
echo 'Do not continue while a Guix build is running.'
if confirm 'Run sudo bash ./guix-install.sh --setup-apparmor now?'; then
    sudo bash ./guix-install.sh --setup-apparmor
else
    echo 'Skipped live policy setup.'
fi

echo "=== 6. Verify the installed text and loaded profile ==="
grep -n -A18 'profile guix-builder' /etc/apparmor.d/guix-daemon
sudo grep -F 'guix-daemon//guix-builder' /sys/kernel/security/apparmor/profiles
apparmor_parser --skip-kernel-load --skip-cache --warn=all /etc/apparmor.d/guix-daemon

echo "=== 7. Reload only if the installed file is ahead of the running profile ==="
echo 'The kernel listing shows names and mode, not the permission rules.'
if confirm 'Reload /etc/apparmor.d/guix-daemon into the kernel?'; then
    sudo apparmor_parser --skip-cache --warn=all -r /etc/apparmor.d/guix-daemon
else
    echo 'Skipped reload.'
fi

echo "=== 8. Repeat the build that AppArmor was denying ==="
if confirm 'Run guix home reconfigure --keep-failed home/base.scm now?'; then
    guix home reconfigure --keep-failed home/base.scm
    echo '--- recent guix AppArmor denials ---'
    sudo journalctl -k --since '10 minutes ago' --no-pager | grep -E 'apparmor="DENIED".*guix' || echo 'No guix AppArmor denials in the last 10 minutes.'
else
    echo 'Skipped the home reconfigure.'
fi

echo 'Done. After both machines have run this file, delete tmp-pop-os-apparmor-steps.sh.'
