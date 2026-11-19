# Agent Orientation Guide (AGENTS.md)

Welcome! This document is designed to help AI agents (like Claude, Gemini, or ChatGPT) quickly orient themselves in this `dot_files` repository. 

When you are asked to work on or understand a specific topic, you should **only load the files listed in the relevant section below** and skip the rest of the repository. This speeds up your reading time, saves context window, and prevents you from hallucinating cross-dependencies that don't exist.

## Reusable Skills and Workflows

When a reusable workflow is needed, first look for an existing global skill or workflow that fits. If none exists, write and validate one, then save it in your agent's standard global skill or workflow directory so other agents and later sessions can reuse it. Keep shared instructions accessible across model families, and add a pointer in this guide when relevant to this repository. Creating a workflow does not itself authorize performing the actions it describes.

### Starting a feature in a worktree (`worktree-start`)

For a multi-file change in this checkout, which other agents share, create the feature branch and worktree before the first edit: follow [the worktree-start skill](claude/skills/worktree-start/SKILL.md). It notes what a worktree cannot test here (`make apply`, the guix-dev entrypoint and live shells use `~/dot_files` itself) and hands off to `worktree-ship`.

### Committing through a worktree (`worktree-ship`)

To commit in a new worktree, then merge, push and clean up, follow [the worktree-ship skill](claude/skills/worktree-ship/SKILL.md). It moves only the task's own paths out of the shared checkout, so other agents' uncommitted edits stay where they are.

### Renaming anything people type (`language-changes`)

When a make target, command, alias, concept or any other word people say or
type changes, record it in [`docs/language.md`](docs/language.md) by following
[the language-changes skill](claude/skills/language-changes/SKILL.md): one row
per replacement, newest first, citing the commit that introduced the new name.
**The rename is committed first; the row cites that hash afterwards.**

This matters more here than in most repos because the house style is to
**remove** the old name rather than keep an alias (`setup-sshd` ->
`setup-sshd-for-ingress`, `check-ssh` -> `check-ssh-with-gpg-for-egress`,
`set_up_links` -> `setup-native-links`). Once the old spelling is gone from the
tree, that table is the only thing that still resolves it for someone reading
an older document, report or commit message -- so the row is what makes
removing the alias safe.

Do not rewrite old documents to the new name when they quote file content or
cite line numbers (a stage report, for instance): that turns a record of what
happened into something that never did. Add a note naming the new term, the
commit that renamed it, and the last hash that still had the old one.

`githooks/pre-commit` prints a NOTE when a commit removes a make target
without staging `docs/language.md`. It is a reminder, not a gate, and it only
sees make targets -- renaming an alias or a concept is on you to notice.

## 1. Tmux and Job Runner Commands (`tmux-*`, `job-*`, `docker-*`, `launchd-*`)
The repository contains a unified job runner abstraction for `tmux`, `launchd`, and `docker` to handle long-running local tasks. All three runners use the same verb convention (`-run`, `-ls`, `-status`, `-logs`).
*   **Core Implementation:** `.jobs.zsh`
*   **Logging utility:** `bin/job-tee`
*   **Testing:** `tests/jobs/smoke.zsh`, `tests/jobs/tee-smoke.zsh`, `tests/jobs/private-tmux` (`make check-jobs`); `tests/jobs/podman-live.zsh` needs a real container engine (`make check-jobs-live`)

**Agent Instruction:** If the user asks about `tmux-new`, `tmux-run`, `tmux-ls`, `job-recap`, etc., load `.jobs.zsh` and skip everything else.

### Closing a worktree without merging (`worktree-cleanup`)

When a worktree task ends with nothing to ship (research, an inquiry, a dropped experiment), follow [the worktree-cleanup skill](claude/skills/worktree-cleanup/SKILL.md). It asks before discarding uncommitted files or unmerged commits, closes the Herdr workspace that `worktree-start` opened, and removes the worktree and branch.

### Getting the user's attention (`herdr-notify`)

When you are stuck, blocked (a merge conflict, a question only the user can answer) or have finished a long-running task, do not just print it to the terminal: read [the herdr-notify skill](skills/herdr-notify/SKILL.md) and push a notification to the Herdr UI with `herdr notification show "<Title>" --body "<what you need>"` (`--sound request` when you need the user to proceed, `--sound done` when only reporting completion). This applies to every model family and needs no relay through another agent.

## 2. Guix Configuration (`guix home`, `guix system`)

* **First-machine seed:** `bin/seed-linux`, `docs/LINUX_SEED.md` cover prerequisites, Guix installation, SSH/GitHub access, cloning and `make apply`. Reusable agent instructions: `~/.codex/skills/linux-dotfiles-seed/SKILL.md`. `make register-machine` (`bin/register-machine`, `docs/REGISTER_MACHINE.md`) is the checklist that chooses native, foreign Guix, or Guix System before those commands.
*   **Disk floor:** `bin/check-disk-floor` (`make check-disk-floor`) refuses `apply`, `apply-wayland`, and `apply-ewm` when `/` has under 20 GiB free. `FORCE_APPLY=1` overrides. Tests: `make check-disk-floor-tests`.
The user is migrating to a declarative Guix setup with distinct "home" and "system" layers.
*   **Foreign-distro installer / AppArmor:** `guix-install.sh`, `bin/seed-linux`, `tests/guix/apparmor.py` and its fixtures (`make check-guix-installer`). The decision is the 2026-11-09 entry in `docs/LEARNINGS.md`.
*   **Entry points:** `Makefile` (Look at targets like `apply`, `reconfigure`, `guix-config`)
*   **Home Layer (User prefs):** `home/base.scm`, `home/common.scm`, `home/wayland.scm`, `home/ewm.scm` (EWM trial, `make apply-ewm`)
*   **System Layer (Host configs):** `system/`, `system/README.md`
*   **Manifests & Channels:** `manifests/`, `channels.scm`, `system/channels-geeeks.scm`
*   **Per-directory environments:** `direnv/direnvrc` (deployed by `home/common.scm`)
*   **System timezone (foreign distros, e.g. orb-guix):** `setup-timezone` / `check-timezone` in `Makefile` (`/etc/localtime`); on Guix System it is `(timezone ...)` in `system/geeeks.scm`
*   **Incoming SSH:** `bin/sshd-setup`, `setup-sshd-for-ingress` / `check-sshd-for-ingress` in `Makefile` (automatic on apply/setup-native), `system/keys/minius.pub`; Guix System declares sshd in `system/geeeks.scm`. Tests: `tests/ssh/bootstrap.py` (`make check-sshd-for-ingress-tests`).
*   **System locale (foreign distros, e.g. orb-guix, WSL):** `setup-locale` / `check-locale` in `Makefile` (generates `LOCALE` for the distro glibc; fixes the `setlocale: LC_ALL` warning)
*   **Known-warning filter:** `bin/expected-warnings` (hides and counts the warnings `apply`/`apply-wayland` are known to print; add new ones to its `%EXPECTED` table)
*   **Documentation:** `docs/GENERATIONS_AND_ROLLBACK.md`, `docs/EWM_TRIAL_PLAN.md`, `docs/archive/README.md` (how to recover removed notes)

**Agent Instruction:** If asked to modify Guix package manifests, home configurations, or system configurations, stick to these files.

## 3. Claude & AI Agent Tooling (`agent-*`, `claude-*`, `agy-*`, `codex-*`)
There are dedicated tools for running interactive AI sessions as background jobs.
*   **Core Implementation:** `.agent-jobs.zsh` (built on `.jobs.zsh`; defines `agent-run ENGINE TASK`, `agent-status`, `agent-relaunch`, `agent-rm`, `agent-help`, plus the `claude-*`, `agy-*` and `codex-*` wrappers that supply ENGINE)
*   **Claude Configs/Docs:** `claude/CLAUDE.md`, `claude/README.md`, `claude/agent-roles.conf` (`claude/` is a git submodule; empty until `git submodule update --init claude`)
*   **Testing:** `tests/jobs/claude-smoke.zsh`
*   **Gemini Configs:** `gemini/hooks.json`, `gemini/scripts/`, `gemini/skills/`

*   **Homebase hygiene jobs:** `bin/homebase` (`on`/`off`/`status`/`tick`; gates `bin/mr-hygiene` + `bin/tmux-hygiene` and media-announce autosave to one machine), the `homebase` layer in `home/common.scm` (shepherd timer), and the homebase handoff in `agent-stash-all`/`agent-stash-pop`. Once a day `mr-hygiene` also reports abandoned worktrees (`bin/worktree_hygiene.py`); it never deletes them.
*   **Worktree-cleanup grants:** `bin/agent-permissions` merges `git branch -D`, `git worktree remove`, and `git worktree prune` into Claude Code `permissions.allow`, Codex `~/.codex/rules/dot_files.rules`, and the Cursor CLI `~/.cursor/cli-config.json`. `setup-native-links` and the Guix dotfiles-layer activation run it. `make check-agent-permissions` (part of `make check`) only reads. agy has no per-command allowlist.

**Agent Instruction:** When modifying AI workflows or CLI commands related to `agent-`, `claude-`, `agy-` or `codex-`, focus heavily on `.agent-jobs.zsh`.

## 4. Shell & Environment Baseline
* **Bitbucket SSH migration:** `.gitconfig` (SSH URL rewrites), `bin/setup-bitbucket-ssh` (host trust and legacy Host blocks), `docs/BITBUCKET_SSH.md`; native `setup-native-links` and the Guix `%dotfiles-layer` activation deploy it. Container key setup: `build-aux/setup-guix-github-key.sh`. Check with `make check-bitbucket-ssh`.
**`rg` in your own shell; POSIX `grep` in committed code.** These are two
different rules and conflating them breaks the installer.

*In an agent's own Bash calls, prefer `rg` and `fd`.* Not a style preference,
and **not a bug anyone can fix here.** Claude Code injects `grep` and `find`
shell functions that re-route through its bundled `ugrep`/`bfs` by dispatching
on **argv0** (busybox style). On this machine `claude` is a `#!/bin/sh`
launcher wrapper (`bin/install-claude.sh` writes it, because Guix has no FHS
loader and patchelf corrupts Bun binaries), and **argv0 cannot cross a shebang
boundary**: the interpreter sets `$0` to the script path, so neither
`exec -a ugrep` nor zsh's `ARGV0=ugrep` reaches the wrapper. Measured, both
arrive as `$0=<script path>` with `$ARGV0` unset. The binary therefore runs as
`claude` and answers `error: unknown option '-G'`.

Passing `--argv0 "${ARGV0:-...}"` through the wrapper was tried and reverted:
there is nothing for it to read. Making it work would need the wrapper to be a
real executable rather than a script. So plain `grep` and `find` are *broken*,
not merely slow, in agent shells here, and that is permanent: use `rg`/`fd`,
or `command grep` / `command find` to bypass the function layer.

*In committed scripts, the Makefile and githooks, use POSIX `grep`.* `ripgrep`
is in `%base-packages`, so it is on every machine guix home manages -- but
NOT on the Guix ISO or on a machine before its first `make apply`, which is
exactly where `guix-platform-install`'s bootstrap runs. Converting the 60
`grep` calls in the Makefile and the 15 in `bin/` would buy nothing and break
the one path that cannot afford it. Where `rg` genuinely helps, guard it and
fall back, as `bin/remindme` does:

```sh
if command -v rg >/dev/null 2>&1; then ...   # rg path
else ...                                      # grep path
fi
```

For standard shell setup not related to the background job runners:
*   **Core Zsh:** `.zshrc`, `.zprofile`, `.aliases`, `.shared.zshenv`, `.shared.zshrc`
*   **OS-specific:** `.mac.zshenv`, `.linux.zshenv`
*   **Prompt configuration:** `.zshrc.starship`, `starship/starship.toml`
*   **Herdr config & tool:** `herdr/config.toml` (linked by `make setup-native-links`; binary installed by `bin/install-herdr.sh` via `make install-herdr`, `apply`, or `setup-native`)
*   **Julia (`juliaup`):** `bin/install-julia.sh` (`make install-julia`, run by `apply`, `apply-wayland`, `update`, `setup-native-links`, and `setup-native`; updates via `juliaup update` or `bin/install-julia.sh --force`)
*   **Termux setup & font:** `bin/termux-setup`, `termux/termux.properties` (extra-keys toolbar & navigation cluster, synced to `~/.termux/termux.properties`), `system/fonts/CascadiaMonoNF-Regular-patched.ttf` (Cascadia Mono NF + ⏴⏵⏶⏷ from Noto Sans Symbols 2; synced to `~/.termux/font.ttf`), rebuilt with `bin/patch-font-glyphs.py`
*   **macOS Packages (Homebrew):** `setup-native-links` and `setup-native` install the Ghostty cask and Yazi (+ media-handling stack) on macOS; also available via `make install-ghostty` and `make install-yazi`
*   **Multi-repo sync (myrepos / `mr`):** `.mrconfig`, `docs/MYREPOS.md`, the `mr-register` helper in `.aliases`, `bin/mr-clone` (clone a configured repo by name anywhere)
*   **Radicle (`rad://` remotes):** `%radicle-layer` in `home/common.scm` (package + `radicle-node` Shepherd service), `install-radicle` / `setup-radicle` / `check-radicle` in `Makefile` (LaunchAgent template `system/launchd/com.durantschoon.radicle-node.plist` on mac), the login warning in `.shared.zshrc`; see `docs/MYREPOS.md`
*   **GPG / signed commits:** `docs/GPG.md`, `gnupg/` (tracked gpg.conf, dirmngr.conf, mac gpg-agent template), the `[user] signingkey` and `[commit] gpgsign` in `.gitconfig`, the `install-gnupg` / `check-gpg` / `check-ssh-with-gpg-for-egress` targets in `Makefile`, and `machines.toml` / `bin/gpg-hub` (`make gpg-hub-create`, `make gpg-spoke-copy`: inventory-backed subkey enrollment). The Linux agent config is the `%gpg-ssh-agent-layer` in `home/common.scm`.

**Agent Instruction:** Note that Guix environments (like Linux or `orb-guix`) construct `.zshrc` dynamically by concatenating configs, while native environments (like Mac without Guix) rely on `make setup-native-links` to symlink `.zshrc.starship` and source `.shared.zshrc` manually. If asked to add a command, alias, or shell feature "everywhere" or "on all platforms," make sure it is added to the shared configs or updated in both the Guix `home/*.scm` files and the native Zsh files so it isn't lost on one platform.

## 5. Emacs Integration
*   **Installer script:** `install_emacs.zsh`
*   **Documentation:** `docs/mac-fzf-emacsclient.md`

## 6. Wayland and Keyboard Remapping (Keyd)
*   **Wayland Configs:** `home/wayland.scm`, `.wayland.zshenv`
*   **Keyd Setup:** `keyd.conf`, `keyd.service`

## 7. Text Expansion (Espanso)
*   **Configs:** `espanso/` directory (contains `match/`, `config/`, `private/`)

## 8. Cloud-Backed Directories (Proton Drive)
*   **Scripts:** `bin/cloud-dirs.sh`, `bin/cloud-sync.sh` (Linux only), `bin/cloud-creds.sh`
*   **Make targets:** `setup-cloud-dirs`, `check-cloud-dirs`, `cloud-sync`, `check-cloud-creds`, `cloud-creds-login`, `cloud-creds-strip`
*   **Testing:** `tests/cloud/dirs-smoke.zsh`, `tests/cloud/creds-smoke.zsh` (`make check-cloud`)

## 9. Submodules (`claude`, `espanso/private`, `private`, `remindme/private`)
*   **Publishing a bump:** `bin/submodule-publish` (`make claude-publish`, `make remindme-publish`, `make submodule-publish SUBMODULE=...`); also `submodule-update`, `submodule-pull`, `submodule-push` in `Makefile`
*   **Personal Markdown Reminders (`remindme`):** `bin/remindme`, Zsh completion `_remindme` in `.shared.zshrc`, private sheets in `remindme/private/*.md` (`git@github.com:durantschoon/remindme-private.git`), tests in `tests/remindme/smoke.zsh` (`make check-remindme`)
*   **Testing:** `tests/submodule/publish-smoke.zsh` (`make check-submodule-publish`)

