# Agent Orientation Guide (AGENTS.md)

Welcome! This document is designed to help AI agents (like Claude, Gemini, or ChatGPT) quickly orient themselves in this `dot_files` repository. 

When you are asked to work on or understand a specific topic, you should **only load the files listed in the relevant section below** and skip the rest of the repository. This speeds up your reading time, saves context window, and prevents you from hallucinating cross-dependencies that don't exist.

## Reusable Skills and Workflows

When a reusable workflow is needed, first look for an existing global skill or workflow that fits. If none exists, write and validate one, then save it in your agent's standard global skill or workflow directory so other agents and later sessions can reuse it. Keep shared instructions accessible across model families, and add a pointer in this guide when relevant to this repository. Creating a workflow does not itself authorize performing the actions it describes.

### Starting a feature in a worktree (`worktree-start`)

For a multi-file change in this checkout, which other agents share, create the feature branch and worktree before the first edit: follow [the worktree-start skill](claude/skills/worktree-start/SKILL.md). It notes what a worktree cannot test here (`make apply`, the guix-dev entrypoint and live shells use `~/dot_files` itself) and hands off to `worktree-ship`.

### Committing through a worktree (`worktree-ship`)

To commit in a new worktree, then merge, push and clean up, follow [the worktree-ship skill](claude/skills/worktree-ship/SKILL.md). It moves only the task's own paths out of the shared checkout, so other agents' uncommitted edits stay where they are.

## 1. Tmux and Job Runner Commands (`tmux-*`, `job-*`, `docker-*`, `launchd-*`)
The repository contains a unified job runner abstraction for `tmux`, `launchd`, and `docker` to handle long-running local tasks. All three runners use the same verb convention (`-run`, `-ls`, `-status`, `-logs`).
*   **Core Implementation:** `.jobs.zsh`
*   **Logging utility:** `bin/job-tee`
*   **Testing:** `tests/jobs/smoke.zsh`, `tests/jobs/tee-smoke.zsh`, `tests/jobs/private-tmux` (`make check-jobs`); `tests/jobs/podman-live.zsh` needs a real container engine (`make check-jobs-live`)

**Agent Instruction:** If the user asks about `tmux-new`, `tmux-run`, `tmux-ls`, `job-recap`, etc., load `.jobs.zsh` and skip everything else.

### Getting the user's attention (`herdr-notify`)

When you are stuck, blocked (a merge conflict, a question only the user can answer) or have finished a long-running task, do not just print it to the terminal: read [the herdr-notify skill](skills/herdr-notify/SKILL.md) and push a notification to the Herdr UI with `herdr notification show "<Title>" --body "<what you need>"` (`--sound request` when you need the user to proceed, `--sound done` when only reporting completion). This applies to every model family and needs no relay through another agent.

## 2. Guix Configuration (`guix home`, `guix system`)
The user is migrating to a declarative Guix setup with distinct "home" and "system" layers.
*   **Entry points:** `Makefile` (Look at targets like `apply`, `reconfigure`, `guix-config`)
*   **Home Layer (User prefs):** `home/base.scm`, `home/common.scm`, `home/wayland.scm`, `home/ewm.scm` (EWM trial, `make apply-ewm`)
*   **System Layer (Host configs):** `system/`, `system/README.md`
*   **Manifests & Channels:** `manifests/`, `channels.scm`, `system/channels-geeeks.scm`
*   **Per-directory environments:** `direnv/direnvrc` (deployed by `home/common.scm`)
*   **System timezone (foreign distros, e.g. orb-guix):** `setup-timezone` / `check-timezone` in `Makefile` (`/etc/localtime`); on Guix System it is `(timezone ...)` in `system/geeeks.scm`
*   **System locale (foreign distros, e.g. orb-guix, WSL):** `setup-locale` / `check-locale` in `Makefile` (generates `LOCALE` for the distro glibc; fixes the `setlocale: LC_ALL` warning)
*   **Known-warning filter:** `bin/expected-warnings` (hides and counts the warnings `apply`/`apply-wayland` are known to print; add new ones to its `%EXPECTED` table)
*   **Documentation:** `docs/GUIX_MIGRATION_PLAN.md`, `docs/GENERATIONS_AND_ROLLBACK.md`, `docs/EWM_TRIAL_PLAN.md`

**Agent Instruction:** If asked to modify Guix package manifests, home configurations, or system configurations, stick to these files.

## 3. Claude & AI Agent Tooling (`agent-*`, `claude-*`, `agy-*`, `codex-*`)
There are dedicated tools for running interactive AI sessions as background jobs.
*   **Core Implementation:** `.agent-jobs.zsh` (built on `.jobs.zsh`; defines `agent-run ENGINE TASK`, `agent-status`, `agent-relaunch`, `agent-rm`, `agent-help`, plus the `claude-*`, `agy-*` and `codex-*` wrappers that supply ENGINE)
*   **Claude Configs/Docs:** `claude/CLAUDE.md`, `claude/README.md`, `claude/agent-roles.conf` (`claude/` is a git submodule; empty until `git submodule update --init claude`)
*   **Testing:** `tests/jobs/claude-smoke.zsh`
*   **Gemini Configs:** `gemini/hooks.json`, `gemini/scripts/`, `gemini/skills/`

*   **Homebase hygiene jobs:** `bin/homebase` (`on`/`off`/`status`/`tick`; gates `bin/mr-hygiene` + `bin/tmux-hygiene` and media-announce autosave to one machine), the `homebase` layer in `home/common.scm` (shepherd timer), and the homebase handoff in `agent-stash-all`/`agent-stash-pop`

**Agent Instruction:** When modifying AI workflows or CLI commands related to `agent-`, `claude-`, `agy-` or `codex-`, focus heavily on `.agent-jobs.zsh`.

## 4. Shell & Environment Baseline
For standard shell setup not related to the background job runners:
*   **Core Zsh:** `.zshrc`, `.zprofile`, `.aliases`, `.shared.zshenv`, `.shared.zshrc`
*   **OS-specific:** `.mac.zshenv`, `.linux.zshenv`
*   **Prompt configuration:** `.zshrc.starship`, `starship/starship.toml`
*   **Herdr config & tool:** `herdr/config.toml` (linked by `make set_up_links`; binary installed by `bin/install-herdr.sh` via `make install-herdr`, `apply`, or `setup-native`)
*   **macOS Packages (Homebrew):** `set_up_links` and `setup-native` install the Ghostty cask and Yazi (+ media-handling stack) on macOS; also available via `make install-ghostty` and `make install-yazi`
*   **Multi-repo sync (myrepos / `mr`):** `.mrconfig`, `docs/MYREPOS.md`, the `mr-register` helper in `.aliases`, `bin/mr-clone` (clone a configured repo by name anywhere)
*   **GPG / signed commits:** `docs/GPG.md`, `gnupg/` (tracked gpg.conf, dirmngr.conf, mac gpg-agent template), the `[user] signingkey` and `[commit] gpgsign` in `.gitconfig`, the `install-gnupg` / `check-gpg` targets in `Makefile`, and `bin/gpg-new-machine` (`make gpg-new-machine`: interactive first-time key transfer). The Linux agent config is the `%gpg-ssh-agent-layer` in `home/common.scm`.

**Agent Instruction:** Note that Guix environments (like Linux or `orb-guix`) construct `.zshrc` dynamically by concatenating configs, while native environments (like Mac without Guix) rely on `make set_up_links` to symlink `.zshrc.starship` and source `.shared.zshrc` manually. If asked to add a command, alias, or shell feature "everywhere" or "on all platforms," make sure it is added to the shared configs or updated in both the Guix `home/*.scm` files and the native Zsh files so it isn't lost on one platform.

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

## 9. Submodules (`claude`, `espanso/private`, `private`)
*   **Publishing a bump:** `bin/submodule-publish` (`make claude-publish`, `make submodule-publish SUBMODULE=...`); also `submodule-update`, `submodule-pull`, `submodule-push` in `Makefile`
*   **Testing:** `tests/submodule/publish-smoke.zsh` (`make check-submodule-publish`)
