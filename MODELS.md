# Agent Orientation Guide (MODELS.md)

Welcome! This document is designed to help AI agents (like Claude, Gemini, or ChatGPT) quickly orient themselves in this `dot_files` repository. 

When you are asked to work on or understand a specific topic, you should **only load the files listed in the relevant section below** and skip the rest of the repository. This speeds up your reading time, saves context window, and prevents you from hallucinating cross-dependencies that don't exist.

## 1. Tmux and Job Runner Commands (`tmux-*`, `job-*`, `docker-*`, `launchd-*`)
The repository contains a unified job runner abstraction for `tmux`, `launchd`, and `docker` to handle long-running local tasks. All three runners use the same verb convention (`-run`, `-ls`, `-status`, `-logs`).
*   **Core Implementation:** `.jobs.zsh`
*   **Logging utility:** `bin/job-tee`
*   **Testing:** `tests/jobs/smoke.zsh`, `tests/jobs/private-tmux`

**Agent Instruction:** If the user asks about `tmux-new`, `tmux-run`, `tmux-ls`, `job-recap`, etc., load `.jobs.zsh` and skip everything else.

## 2. Guix Configuration (`guix home`, `guix system`)
The user is migrating to a declarative Guix setup with distinct "home" and "system" layers.
*   **Entry points:** `Makefile` (Look at targets like `apply`, `reconfigure`, `guix-config`)
*   **Home Layer (User prefs):** `home/base.scm`, `home/common.scm`, `home/wayland.scm`
*   **System Layer (Host configs):** `system/`, `system/README.md`
*   **Manifests & Channels:** `manifests/`, `channels.scm`, `system/channels-geeeks.scm`
*   **Documentation:** `docs/GUIX_MIGRATION_PLAN.md`

**Agent Instruction:** If asked to modify Guix package manifests, home configurations, or system configurations, stick to these files.

## 3. Claude & AI Agent Tooling (`claude-*`)
There are dedicated tools for running interactive AI sessions as background jobs.
*   **Core Implementation:** `.claude-jobs.zsh` (defines `claude-run`, `claude-status`, etc.)
*   **Claude Configs/Docs:** `claude/CLAUDE.md`, `claude/README.md`, `claude/agent-roles.conf`
*   **Testing:** `tests/jobs/claude-smoke.zsh`
*   **Gemini Configs:** `gemini/hooks.json`, `gemini/skills/`

**Agent Instruction:** When modifying AI workflows or CLI commands related to `claude-`, focus heavily on `.claude-jobs.zsh`.

## 4. Shell & Environment Baseline
For standard shell setup not related to the background job runners:
*   **Core Zsh:** `.zshrc`, `.zprofile`, `.aliases`, `.shared.zshenv`, `.shared.zshrc`
*   **OS-specific:** `.mac.zshenv`, `.linux.zshenv`
*   **Prompt configuration:** `.zshrc.starship`

## 5. Emacs Integration
*   **Installer script:** `install_emacs.zsh`
*   **Documentation:** `docs/mac-fzf-emacsclient.md`

## 6. Wayland and Keyboard Remapping (Keyd)
*   **Wayland Configs:** `home/wayland.scm`, `.wayland.zshenv`
*   **Keyd Setup:** `keyd.conf`, `keyd.service`

## 7. Text Expansion (Espanso)
*   **Configs:** `espanso/` directory (contains `match/`, `config/`, `private/`)
