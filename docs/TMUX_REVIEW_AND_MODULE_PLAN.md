# Tmux review and reusable module extraction plan

Reviewed 2026-09-27 against `6bec5f9`, including the current working tree.
This is a review and proposed migration; no runner implementation, submodule,
remote repository, or existing local edit was changed.

The [stage-ready implementation plan](MODULE_EXTRACTION_PLAN.md) is the source of
truth for generating future branching stages. This document retains the original
review evidence and architectural recommendations.

## Recommendation

Extract **shell-jobs** first and **agent-jobs** second. Keep the shared job model,
logging, tmux dashboard, SSH transport, launchd, and container backends in one
runner repository initially, with internal source modules and lazy dependency
checks. The agent package should depend on a documented runner API. The
`dot_files` repository remains the composition layer for personal choices,
machine configuration, and deployment.

A useful mix-in has its own entry point, dependencies, tests, documentation, and
release lifecycle. Moving files behind a Git submodule without removing their
assumptions about `~/dot_files`, the user's hosts, and other dotfiles does not
provide that interface.

Names and public URLs below are proposals, not existing repositories.

## Review findings

### R1 — P1: repository filtering can select and kill another repo's sessions

Location: [`.jobs.zsh:799`](../.jobs.zsh#L799), consumed by
[`tmux-rm --all`](../.jobs.zsh#L1608). This predates the recent UI additions.

The filter `^$(job-repo)(-|$)` treats a repository named `foo-bar` as a task of
`foo`. In a guarded private tmux server, a session named `foo-bar` rooted in a
separate `foo-bar/` directory appeared in `foo`'s rows and was killed by
`tmux-rm --all` from `foo/`. Repositories with identical basenames also share
the current identity.

Fix before public extraction: distinguish display names from stable repository
and task identity. Record explicit metadata, compare canonical roots for local
ownership, and give remote checkouts a configured shared project identity when
their paths differ. Bulk deletion must only include positively identified owned
sessions. Treat legacy or foreign sessions conservatively; listing them in the
all-session dashboard must not grant ownership.

### R2 — P1: the new rename action breaks task lookup and notes

Location: [`_tmux_pick_rename`](../.jobs.zsh#L1230).

The action changes only the tmux session name. After renaming `foo-build` to
`review-renamed`, the private-server probe observed:

```text
tmux-status build: no session 'foo-build'; exit 1
picker-inferred task: review-renamed
session environment: JOB_TASK=build
```

The dashboard now looks for a different notes/recap filename while task
commands still construct the old session name. An agent's relaunch definition
also retains the old name, allowing recovery to recreate a session beside the
renamed one.

Recommended behavior: make rename change a display label while preserving
identity. If actual task renaming is desired later, make it an explicit operation
that updates metadata, lookups, logs/notes references, and relaunch definitions
together. Do not silently rename the user's notes files through a UI label edit.

### R3 — P2: Markdown status parsing drops existing notes

Location: [`.jobs.zsh:915`](../.jobs.zsh#L915), changed in `c5df622`.

The row reader now accepts Markdown headings only. A notes file containing
`> waiting on review` produces an empty status, or loses priority to a recap.
That format remains the documented contract in [README](../README.md#L458)
and is asserted by [the smoke suite](../tests/jobs/smoke.zsh#L1391).

Support the previous marker during migration and define precedence when both
headings and explicit status lines exist. Keep rich Markdown rendering separate
from status extraction. Update the template, documentation, and compatibility
tests together; do not rewrite existing personal notes automatically.

### R4 — P2: missing option values cause an infinite parse loop

Locations: [`_tmux_args`](../.jobs.zsh#L998),
[`_job_parse_run`](../.jobs.zsh#L292), and
[`tmux-pick`](../.jobs.zsh#L1306). These predate the recent additions.

Each of these probes exceeded a 0.5-second process timeout:

```text
_tmux_args --on
_job_parse_run tmux-run build --on
tmux-pick --poll
```

The parser reads `$2` and attempts `shift 2` when one argument remains; the
failed shift leaves the same option in the loop. Validate arity before shifting
and return usage status 64. Cover the equivalent value-taking options in all
runner parsers.

### R5 — P2: nested polite attach does not provide read-only access

Location: [`_job_tmux_attach`](../.jobs.zsh#L748). Existing behavior.

For a local target with `$TMUX` set, the implementation ignores the requested
`ro` mode and issues `tmux switch-client -t ...`. A command-dispatch probe
confirmed that branch. The caller still announces READ-ONLY, although it has
not changed the client's access mode. This was a dispatch test, not an
interactive two-client test.

Define and test nested-client behavior explicitly. Either provide a true
read-only interaction with a clear way back, or refuse that mode with an
accurate explanation. The help text also needs to describe `tmux-peek`'s
attached-session behavior.

### R6 — P2: the new rendering pipeline masks context errors

Location: [`job-note-context`](../.jobs.zsh#L525), changed in `c5df622`.

`job-note-context bad/name` prints the invalid-task diagnostic but returns 0.
Validation now occurs inside the producer side of a rendering pipeline, followed
by an unconditional success return. Validate inputs before the pipeline and
preserve producer and renderer failures explicitly.

### Other extraction concerns

- `JOB_HOSTS` defaults to the personal host `minius` at
  [line 582](../.jobs.zsh#L582). Public defaults should be local-only, with no
  Tailscale probe or warning unless remote discovery was requested.
- [`_job_tee`](../.jobs.zsh#L133) falls back to `~/dot_files/bin/job-tee`;
  remote notes [source `~/dot_files/.jobs.zsh`](../.jobs.zsh#L1146).
  Resolve bundled assets relative to the module and configure remote entry
  points independently of the superproject location.
- [`tmux-logs`](../.jobs.zsh#L1581) always reads local logs, even when
  `tmux-run` selected a remote host. Define remote log retrieval or clearly
  report the host instead of presenting a potentially stale local log.
- [`job-note`](../.jobs.zsh#L439) uses macOS-style `script` arguments for
  emacsclient. Validate the editor path separately on Linux and Termux.
- `.agent-jobs.zsh` is explicitly macOS-only and calls private runner helpers.
  Keep that platform boundary explicit in its first standalone release; Linux
  supervision is additional work, not a property gained by moving the file.
- `AGENTS.md` still routes agent work to the removed `.claude-jobs.zsh`.
  Correct that routing during migration.

## Proposed repository boundaries

| Module | Initial contents | Dependency and ownership boundary | Order |
| --- | --- | --- | --- |
| `shell-jobs` | `.jobs.zsh`, `bin/job-tee`, runner tests, job documentation | Zsh core; tmux for tmux commands; optional fzf/glow, SSH/Tailscale, launchd, container engine. Owns task identity, records, notes/recap contracts, and runner lifecycle. | First |
| `agent-jobs` | `.agent-jobs.zsh`, agent smoke tests, engine adapter documentation | Requires the supported `shell-jobs` API and chosen agent CLI; launchd support remains macOS-only initially. Does not require personal Claude/Gemini/Codex settings. | Second |
| `git-tools` | `bin/submodule-publish`, selected `bin/git-*` tools, `tests/submodule/`, associated Make targets | Git and each tool's documented shell/runtime; no shell startup or home deployment dependency. Audit individual tools before declaring this package complete. | Third candidate |
| `espanso-shared` | Public `espanso/match/` content and suitable config examples | Public snippets can be installed alone. Machine keyboard/backend choices and private snippets are separate overlays. | Later |
| `guix-home-features` | Reusable service/layer constructors from `home/common.scm` | Explicit session facts and asset paths as inputs. Leave personal package selections, channel pins, and host records in `dot_files`. | Later, after path decoupling |

Keep `.zshrc`, `.aliases`, OS-specific shell files, the top-level deployment
Makefile, `system/`, and machine-specific configs in the composition repository
for now. Extract cohesive features from them when an independent consumer exists;
do not make one repository per dotfile.

`home/base.scm` and `home/wayland.scm` are intentionally thin selectors for one
shared implementation. Preserve that structure instead of creating two forks.

The existing `claude` and `espanso/private` entries are already real submodules.
README describes Claude setup as requiring private access. Neither private
repository should become a prerequisite for a public job-runner install. Editor
integration is another possible later package, but `install_emacs.zsh` currently
installs personal Spacemacs choices and sources the shared shell configuration;
it is not yet a standalone reusable installer.

## First package layout and public contract

Proposed `shell-jobs` layout:

```text
jobs.plugin.zsh
lib/core.zsh
lib/records.zsh
lib/notes.zsh
lib/hosts.zsh
lib/dashboard.zsh
lib/promotion.zsh
runners/tmux.zsh
runners/launchd.zsh
runners/container.zsh
bin/job-tee
tests/
README.md
LICENSE
```

These are internal source files within one Git repository, not nested Git
submodules. Keep promotion and common record semantics together. Start with one
entry point that defines commands without starting services, contacting hosts,
installing packages, or modifying unrelated shell settings. Runtime dependencies
are checked when the corresponding command runs.

Preserve the existing user-facing verbs. Document a small supported integration
API for `agent-jobs`, including root/task identity, session creation/environment,
ownership metadata, and launchd registration. Replace ad hoc calls to private
helpers at that boundary. Publish a compatibility range for the pair and test it.

Configuration should be supplied before sourcing the module; repeated sourcing
must be safe. Use module-relative paths and honor explicit overrides. Test caller
aliases/options, including the current local `glow='glow -p'` alias, so a user's
shell does not change the module's noninteractive rendering behavior.

## What a consumer should do

Illustrative commands after a public release exists; replace `OWNER` and the
version with the actual published values:

```sh
# In the consumer's own dotfiles repository:
git submodule add https://github.com/OWNER/shell-jobs.git modules/shell-jobs
git -C modules/shell-jobs checkout v0.1.0
git add .gitmodules modules/shell-jobs
git commit -m "Add shell-jobs mix-in"
```

Then add an explicit source line to that consumer's Zsh setup:

```zsh
# Example consumer root; there is no required checkout name.
typeset -ga JOB_HOSTS=()
source "$HOME/my-dotfiles/modules/shell-jobs/jobs.plugin.zsh"
```

Optional agent support is a second sibling submodule sourced after the runner.
The consumer pins both commits. Avoid a nested runner submodule inside
`agent-jobs`, which would introduce duplicate copies and competing versions.
Direct clones should work through the same entry point too.

For a fresh checkout, initialize selected public modules by path:

```sh
git submodule update --init -- modules/shell-jobs
```

Git records the selected submodule commit in a gitlink; normal initialization
checks out that recorded version. Do not put `--remote` updates into shell
startup or bootstrap. Keep release upgrades explicit and reviewable.
[Git submodule model](https://git-scm.com/docs/gitsubmodules),
[initialization and update commands](https://git-scm.com/docs/git-submodule).

## Migration sequence and acceptance gates

1. **Repair the runner behavior in place.** Address R1–R6 and add focused tests
   for cross-repository isolation, renamed task identity, old/new notes formats,
   malformed options, read-only attach, and failure propagation. Preserve
   existing working-tree changes; do not sweep unrelated edits into extraction.
   Gate: focused cases and the existing applicable suites pass.

2. **Make the package relocatable inside this repository.** Introduce the
   internal files and entry point while retaining a thin `.jobs.zsh` compatibility
   loader. Resolve local assets from the module location; replace the hardcoded
   remote source path with an explicit remote installation contract. Move the
   `minius` default to personal configuration. Keep terminal styling and personal
   `.tmux.conf` optional. Gate: a fresh `zsh -f` can source a copy under an arbitrary
   directory and run a logged task without `.aliases`, Oh My Zsh, Guix, or `~/bin`.

3. **Extract `shell-jobs` history and establish its own tests.** Use a disposable
   clone to produce the standalone history and record source commit provenance;
   do not rewrite the working superproject. Carry the private-tmux guard and
   tests with the code. Replace test dependencies on the parent Makefile with
   package-level checks. Choose license, public repository name, and initial
   release version before publishing. Gate: standalone checkout tests pass with
   no access to private submodules or personal config.

4. **Consume the published commit as a real submodule.** Add it at
   `modules/shell-jobs`, record `.gitmodules` and the gitlink, and wire compatibility
   loaders and `bin/job-tee` through relative paths. Adapt native links, Guix
   `local-file` inputs, README, and AGENTS routing. Initialize only requested
   modules; an omitted optional module must not make unrelated shell startup
   fail. Gate: an unrelated user's minimal dotfiles repo and this repo both work.

5. **Extract `agent-jobs` through the supported API.** Move engine wrappers and
   ownership/recovery tests after the runner boundary stabilizes. Keep personal
   permissions, hooks, notifications, and login choices outside the package.
   Publish a compatibility table and smoke-test the chosen pair. Gate: an agent
   job can launch, resume, report status, and be removed without the private
   `claude` config repository.

6. **Extract further modules only after proving independent consumption.** Start
   with Git utilities if useful. For Guix, parameterize assets and optional layer
   initialization first; changing a checkout path must not break service inputs.
   For Espanso, prove a public-only install while leaving private snippets absent.

Each release gate should cover macOS and Linux for portable runner behavior,
with a Termux check for remote dashboard use. Split tests by capability:
core/logging, private tmux, mocked SSH, launchd integration, and live containers.
Keep the latter two opt-in. Preserve the private-tmux guard for all tmux probes.
Use a real two-client terminal test for R5 and a PTY test for rename/kill prompts.

Add clean-consumer tests for missing optional dependencies, repeated sourcing,
paths containing spaces and shell metacharacters, absent private modules, custom
remote roots, and module upgrades. Verify that log and record formats remain
readable across a release boundary.

## Submodule maintenance

Publish a module commit before updating the superproject gitlink. The existing
`bin/submodule-publish` already checks remote default-branch reachability and can
serve this purpose for newly added paths. Its policy is stronger than merely
having a release tag; document that distinction. Treat `make submodule-pull` as
an explicit upgrade operation, not as installation of pinned dependencies.

Use public HTTPS fetch URLs for public modules, with maintainers configuring
their own push URLs. Keep private modules explicitly opt-in. A normal public
bootstrap should not depend on the current recursive-all `submodule-update`
target, which also tries to initialize the private entries.

Keep the superproject compatibility loaders through the first migration release.
Document how to restore a previous superproject commit and its recorded module
versions without discarding dirty module checkouts. Existing tmux sessions and
launchd definitions need an explicit transition policy: new code must recognize
legacy metadata, and login definitions that embed executable paths need an
intentional refresh. Rollback must account for persisted records, not only Git.

## Verification performed for this review

- `zsh -n .jobs.zsh` passed.
- Guarded private tmux probes reproduced R1 and R2 using scratch sessions only;
  the probe stopped its private server afterwards.
- Focused function probes reproduced R3 and R6.
- Three malformed-option probes reproduced R4 under bounded process timeouts.
- A stubbed command-dispatch probe confirmed R5's missing read-only handling.
- Inspected the existing smoke assertions and recent tmux changes. The full
  `make check-jobs` suite and cross-platform/interactive checks were not run.

The immediate next implementation slice is R1–R4 plus their regression tests,
followed by R5–R6 and the relocation gate. Repository creation and public release
are later steps after those behaviors and the public API are settled.
