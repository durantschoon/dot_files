# Project status index

An at-a-glance map of the large, multi-stage projects described across `docs/`.
This file is **derived**: the authoritative status for each project stays in the
`**Status:**` and per-stage lines of the linked doc. When those change, update the
one-liner here too.

**How status is tracked in this repo** — so this index is read for what it is:

- **Branches are in-flight only.** A task gets a branch and worktree at its first
  edit (`worktree-start`) and loses them on merge (`worktree-ship`). The branch
  list therefore shows what is *being worked right now*, never the backlog or what
  is finished. There is **not** a standing branch per remaining task.
- **Durable per-task status is in the docs** — the stage PROMPT/REPORT pairs and
  the `**Status:**` lines in each plan. This index summarises those.

## Large projects still in flight

| Project | State | Next action | Source of truth |
| --- | --- | --- | --- |
| **Job-runner stage pipeline** | **Paused, complete at stage 16.** All 16 stages merged and green; close-out retro done. | Optional follow-ups below; resume as the module extraction (stage 17+) if desired. | [`docs/stages/README.md`](stages/README.md) |
| **Reusable job modules (`shell-jobs`, `agent-jobs`)** | **Planned, not started.** Milestone M1 repairs R1–R6; only R3's parsing half has landed (`4ecacd6`). | Settle owner decisions (repo names/visibility, license, platform floor), then author stage 17 for the R1 repair. | [`docs/MODULE_EXTRACTION_PLAN.md`](MODULE_EXTRACTION_PLAN.md) · [review](TMUX_REVIEW_AND_MODULE_PLAN.md) |
| **EWM (Emacs Wayland Manager) trial** | **Built and launched.** Stages 0–2 done (runs on `geeeks`, TTY2, software rasteriser). Stage 1.5 (Guix session integration) unsolved. | Run the Stage 3 daily trial and answer its two questions (pinentry prompt; `wlr_data_control`). Stage 4 (Guix packaging) is deliberately last. | [`docs/EWM_TRIAL_PLAN.md`](EWM_TRIAL_PLAN.md) · [pre-switch checklist](EWM_PRE_SWITCH_EVALUATION.md) · [user guide](EWM_USER_GUIDE.md) |

## Open follow-ups from the job-runner close-out

These were recorded at the pipeline close-out (reports 14–16). None is blocking.

| Item | Kind | State |
| --- | --- | --- |
| Claude-side `/recap` skill | `claude` submodule edit, then `make claude-publish` | **Not done** — the one functional gap; stage 16's recap story is half-landed without it. |
| `tests/jobs/lib.zsh` consolidation | Executor stage (would be **stage 17**) | **Owed** — five suites now carry near-duplicate helpers. |
| Stale macOS Login Items (`stage15probe-t1` + 10 old `job-tee` rows) | Manual admin (`sfltool resetbtm` / Settings) | **Pending** — needs admin; no code change. |

The deferred robustness questions from reports 14–16 were migrated into the module
plan's **M1 backlog** (its 2026-11-09 amendment), mapped to their work packages.

## Recently completed (for context)

| Project | Landed |
| --- | --- |
| Register-a-machine checklist (`make register-machine`, role-aware `seed-linux`) | `main` (`7c58236`) |
| Disk floor — refuse `make apply` under 20 GiB on `/` | `main` (`e76c821`) |
