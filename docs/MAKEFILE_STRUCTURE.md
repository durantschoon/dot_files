# Makefile structure decision

## Decision

Keep one root `Makefile` as the command interface, and gradually move related
rules into included `mk/*.mk` files. Do not create separately invoked Makefiles
for individual tasks. A user should still run `make apply`, `make check`, or
`make setup-radicle` from the repository root.

This is a structural recommendation, not authorization to move every rule at
once. Each extraction should be a mechanical change with its own verification.

## Evidence

- The root Makefile has 3,901 lines and 119 distinct targets other than
  `.PHONY` (measured at commit `169c317`). It has no includes today.
- The first roughly 140 lines detect the OS, architecture, environment, package
  manager, and login shell. Targets throughout the file use these values.
- `help-text` is a central catalog. `apply`, `setup-native`, `update`, and
  `check` combine targets from several domains. Keeping one make invocation
  preserves those dependencies and the existing user-facing commands.
- `SUBMODULE_PUBLISH` derives the root path from the first entry in
  `MAKEFILE_LIST`. Include order must preserve that assumption. Many recipes
  use `CURDIR` or paths relative to the invocation directory; moving the rules
  must not change their working directory.
- Tests call both `make` from the repository root and `make -f` with an
  absolute path to the root Makefile from scratch repositories, notably the
  submodule smoke test. Includes must resolve relative to the root Makefile,
  not the caller's current directory.

## Layout to work toward

Keep `.DEFAULT_GOAL := apply`, common host detection, the include list, and
the aggregate `help`, `apply`, `update`, and `check` targets in the root file.
Keep the help catalog in one place so commands remain discoverable. Put
substantial, cohesive groups in `mk/` (for example Guix Home, native setup,
security, containers/network, and system checks). A small target that merely
calls a script does not need its own include file.

Use explicit, ordered includes based on the root Makefile's path, for example:

```make
MAKEFILE_ROOT := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
include $(MAKEFILE_ROOT)mk/guix.mk
```

GNU Make reads included files in place, so variables and conditionals still
obey parse order. Keep each `ifeq`/`endif` pair inside one file. Put shared
variables before the includes that consume them, or move them into a clearly
named common section. Use `include`, not `-include`, so a missing tracked
fragment fails visibly. Keep the root file first in `MAKEFILE_LIST`.

## Migration and acceptance checks

1. Extract one cohesive group at a time, preserving recipe text and target
   names. Start with a group that has few shared variables; leave the long
   native setup recipe and aggregate targets until the pattern is proven.
2. Compare `make help-text` output, `.DEFAULT_GOAL`, and the target list from
   `make -qp` before and after each move. Compare stderr too; the current
   `help-text` already emits a `HOMEBASE: command not found` warning, which is
   a separate issue and must not be attributed to extraction.
3. Run the group's smoke tests and the scratch-repository submodule smoke test
   when path handling or `MAKEFILE_LIST` changes. Run `make check` once the
   grouped moves are complete. `make apply` deploys from `~/dot_files` and
   cannot validate a worktree copy before merge.

The result should reduce the size of the root file while leaving the same
commands, prerequisites, help output, and supported `make -f` behavior.
