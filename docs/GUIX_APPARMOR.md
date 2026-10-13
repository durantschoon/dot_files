# Guix builder AppArmor compatibility on Pop!_OS

## Cause and scope

Guix builders run generated scripts (including ZFS `configure`) and newly
compiled executables inside `/tmp/guix-build-*.drv-*/`. Unix execute bits and a
valid Bash shebang are insufficient when the enforcing
`guix-daemon//guix-builder` AppArmor profile grants only `owner /tmp/** rw,`.
The result is `In execvp of ./configure: Permission denied`, accompanied by
`apparmor="DENIED" operation="exec" requested_mask="x" denied_mask="x"`.

This is a bundled-policy defect, not a ZFS version or filesystem `noexec`
problem. Upstream Guix fixed it in commit
[8ead7a983706](https://codeberg.org/guix/guix/commit/8ead7a983706bc9ac7647a7b017d08b7bc1aadaa)
on March 8, 2026 ([issue 6501](https://codeberg.org/guix/guix/issues/6501)).
That change uses `owner /tmp/** rwklmux,`. The observed Guix 1.5.0 version
string does not establish which profile was copied onto the host: inspect
both the root profile's source and `/etc/apparmor.d/guix-daemon`. `guix pull`
does not itself replace the installed `/etc/apparmor.d` policy.

The defect matters on foreign distros with enforcing AppArmor (including
Pop!_OS). ABI/parser compatibility is a separate concern: Guix's supplied
policies use ABI 4.0 and modern flags/userns syntax. An older parser may reject
them; this installer stops before overwriting installed policy. Update using
the distro's supported packages rather than removing ABI declarations or
turning off confinement. The Pop!_OS/AppArmor version of the failing machine
was not supplied, so no specific distro-version incompatibility is inferred.

## Repository installer

Previously `bin/seed-linux` downloaded the upstream installer at runtime; no
installer was tracked here. `guix-install.sh` now vendors upstream's installer
from commit `1cb4b105d75c7bbe7d884602bded12d20032fa2f` (retrieved 2026-10-13),
with the local compatibility/transaction changes below. Its GPLv3+ header is
retained. Update this source deliberately and rerun `make check-guix-installer`.
The source profiles still come from
`/var/guix/profiles/per-user/root/current-guix/etc/apparmor.d/`.

The recognized old builder policy receives two lines, inside that child
profile only:

```text
# dot_files: execute generated build scripts without leaving confinement.
owner /tmp/guix-build-*/** klmix,
```

The original `owner /tmp/** rw,` rule remains. `k` permits locking, `l` hard
links, and `m` executable mappings (needed by compiled executables/shared
objects). `ix` permits execution while inheriting the builder profile. The
addition is owner-qualified and limited to Guix build directories rather than
all of `/tmp`. It leaves other profiles and unrelated rules intact.

[AppArmor's policy manual](https://manpages.ubuntu.com/manpages/noble/man5/apparmor.d.5.html)
distinguishes `ix` from `ux`: `ux` executes unconfined and preserves potentially
dangerous environment variables; `Ux` scrubs the environment but still drops
confinement. `px`/`cx` require a suitable separate target profile; they do not
solve dynamically generated executable discovery by themselves. This adjustment
uses `ix`. Ubuntu AppArmor 4.0.1 parser checks confirm `rwux`, `rwix`, and
`klmix` are valid combined permission tokens; `rw ux` is invalid syntax.

This is not a complete sandbox redesign. The upstream builder profile already
uses `ux` for store executables, and this patch preserves it. An inherited
script can subsequently execute a store interpreter/tool under that upstream
rule and leave AppArmor confinement. Guix's build container, namespaces, and
build-user isolation remain essential. Full runtime equivalence of this
narrower `ix` variant to upstream's `ux` needs a real Pop!_OS build test.

Installation behavior:

- Only recognized older policies are adjusted. Recognized upstream execution
  rules or an existing scoped execution rule are kept unchanged. Unknown,
  conflicting, or missing policy inputs stop the operation.
- Existing installed policies/tunables are the starting point on reruns, so
  local edits are preserved; missing files come from Guix's source directory.
- Both candidate profiles are compiled with `--skip-kernel-load --skip-cache`
  against staged includes/tunables before installation. Validation never loads
  kernel profiles or writes the AppArmor cache.
- Unchanged installed files are neither rewritten nor reloaded. A first
  installation of a correct upstream policy still validates and loads it.
- A lock prevents concurrent installer transactions. Changed files are backed
  up; installation/load failures restore them and reload the previous profiles,
  or remove newly loaded profiles when there were no previous files.
- Rollback errors are loud and retain the backup plus lock for inspection.
  Resolve the error and recover the policies before removing that lock. SIGKILL
  or power loss cannot be caught: the retained transaction directory provides
  the backup, but recovery is not automatic.
- Disabled/absent AppArmor is explicitly skipped. Enabled AppArmor with a
  missing parser fails and recommends installing the distro `apparmor` package.
  Declining the interactive policy prompt is explicitly reported.
- Successful transactions remove their staging/backup files. Upstream uninstall
  removes only the Guix profiles/tunable; it needs no extra compatibility file.

`bin/seed-linux` uses this repository installer, including when downloaded
before cloning. On an existing Guix installation with AppArmor enabled, it
also offers the installer's policy check before proceeding to `make apply`.

## The separate `--keep-failed` denials

Execution permission does not automatically fix preservation of failed builds.
`open` needs the requested read/write permissions; renaming requires permissions
on both source and destination paths. The daemon's parent profile currently
uses owner-qualified `/tmp` and `/var/tmp` rules. A root daemon handling a tree
owned by a build user can fail that owner check. `attach_disconnected` path
naming, alternate build directories, and the destination can also matter.

No audit paths, masks, or ownership for those additional failures were provided.
This adjustment does **not** broaden parent-daemon access or promise to fix
`--keep-failed`. Collect the exact audit records (including profile, path,
`fsuid`, `ouid`, requested/denied masks) and source/destination ownership before
adding a narrow rule for that case. A builder execution denial and a parent
cleanup denial should not be combined into a blanket `/tmp/** rwux` grant.

## Deploy and verify on Pop!_OS

The change is on the `guix-apparmor-compat` branch in its worktree.
Copy the reviewed `guix-install.sh` and `bin/seed-linux` from that worktree to
the test checkout. Do not expect `git pull main` to fetch this change yet.

Read-only checks (kernel logs and loaded-profile listings may require sudo):

```sh
cd ~/dot_files
bash -n guix-install.sh bin/seed-linux
make check-guix-installer
apparmor_parser --version
guix --version
cat /sys/module/apparmor/parameters/enabled
grep -n -A18 'profile guix-builder' /etc/apparmor.d/guix-daemon
grep -n -A18 'profile guix-builder' /var/guix/profiles/per-user/root/current-guix/etc/apparmor.d/guix-daemon
```

Validate a proposed adjustment without root or loading policy:

```sh
cd ~/dot_files
candidate=$(mktemp)
bash -c 'source ./guix-install.sh; apparmor_adjust_builder /etc/apparmor.d/guix-daemon "$1"' check "$candidate"
apparmor_parser --skip-kernel-load --skip-cache --warn=all -b /etc/apparmor.d "$candidate"
rm -f "$candidate"
```

Explicit deployment on an existing installation (changes live Guix policies;
never run it while builds are active):

```sh
cd ~/dot_files
sudo bash ./guix-install.sh --setup-apparmor
```

This mode validates and installs profiles only; it does not reinstall Guix or
restart services. Fresh machines use `bash bin/seed-linux`, which invokes the
same setup function during Guix installation. If `apparmor_parser` is missing,
install it first with `sudo apt-get install apparmor`.

Verify the installed text and loaded profile names:

```sh
grep -n -A18 'profile guix-builder' /etc/apparmor.d/guix-daemon
sudo grep -F 'guix-daemon//guix-builder' /sys/kernel/security/apparmor/profiles
apparmor_parser --skip-kernel-load --skip-cache --warn=all /etc/apparmor.d/guix-daemon
```

The kernel profile listing shows names/mode, not individual permission rules.
If files were already correct but the active policy is stale, explicitly reload
only the Guix daemon profile after parser validation:

```sh
sudo apparmor_parser --skip-cache --warn=all -r /etc/apparmor.d/guix-daemon
```

Finally repeat the original failing build; this is the runtime verification:

```sh
guix home reconfigure --keep-failed home/base.scm
sudo journalctl -k --since '10 minutes ago' --no-pager | grep -E 'apparmor="DENIED".*guix'
```

For future denials also record `ls -ln`/`stat` for the reported path and its
parent, the process's `/proc/PID/attr/current`, `findmnt -T PATH`, the parser
version, and both policy files. Keep the full build log. If configure succeeds
but preservation fails, investigate the separate cleanup case above.

## Tests

`make check-guix-installer` runs Bash syntax checks and rootless fixture tests.
Fixtures are upstream policy snapshots before/after commit `8ead7a983706`;
`guix` and the tunable are from the locally installed current Guix profile.
The source and installed trees, parser, failures and rollback are isolated in
temporary directories; tests never load live profiles.

Optional real-parser compilation (requires readable AppArmor includes and a
Guix tunable in the include tree):

```sh
APPARMOR_TEST_PARSER=$(command -v apparmor_parser) \
APPARMOR_TEST_BASE=/etc/apparmor.d make check-guix-installer
shellcheck guix-install.sh bin/seed-linux
```

The optional tests use ABI 4.0 as a synthetic kernel feature set for offline
syntax compilation. They do not demonstrate the host kernel's enforcement.
