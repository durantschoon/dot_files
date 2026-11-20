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
| **Overnight batch, stages 17–31** | **All of stages 17–31 are on `main`; the macOS checks ran on `minius` on 2026-11-20 and every suite in them passes** (stage 31 reached `main` in `116de1f`). Thirteen stages ran on `orb-guix` on 2026-11-19/20, each merged into the integration branch after a mechanical review and a gate rerun on the union; `main` later fast-forwarded to `63316b7`, which carries stages 17–30. Several are proven only by stubs for their macOS and Termux branches. **Stage 30** (2026-11-20) merged `main` back in: `adc9f28`'s pinentry label and container key pin replaced stage 26's wrapper and pin; stage 26's `bin/gpg-key-owner` and container note stay. Stage 30 also fixed the label for key IDs written `0x…` (`05c70c3`, a separate commit) and added `tests/gpg/pinentry-label.sh`. **Stage 31** renamed the eight test-suite targets to `check-…-tests` (`b738e03`; `check-jobs` → `check-jobs-tests`, and so on); the old names resolve through [`docs/language.md`](language.md). | **Run on `minius` natively, 2026-11-20.** Three macOS-only test-harness bugs were fixed in `76c901f`: macOS `/bin/sh` (bash 3.2) keeps a `VAR=x func` assignment after the call, and BSD `chmod` rejects `--` after the mode. With them, `make check-gpg-enrollment-tests` is **0 FAIL**: stage 30's labelled prompt passes under macOS `awk`, as do `key-owner.sh` and `pinentry-label.sh` (82/82, sh, dash and bash). In `make check-jobs-tests`, `smoke.zsh` passes **433/433**, 4a included (it stopped at 4a on `orb-guix`), so stages 18, 21 and 31 are proven. `claude-smoke.zsh`, which had never run before, passes **167/167**. Its 6 `agent-stash-pop` FAILs were the test's fault, not the product's: the second `$HOME` it uses to fake another machine shares the Mac's launchd domain, so the original agents were still loaded under the same labels. It now boots them out first (`b9a9c00`). `4620adf` gave smoke's N12 signal child 40 s instead of 10 to report, since it takes ~8 s on minius and failed about one run in two. **Done; nothing remains for this row** except `podman-live.zsh` (`make check-jobs-live-tests`), which was not run. | [`docs/stages/README.md`](stages/README.md) ("Resumed 2026-11-19") · [`overnight-1119-COMMON.md`](stages/overnight-1119-COMMON.md) · the `stage-17`…`stage-31` PROMPT/REPORT pairs |
| **Makefile recipes into `bin/` scripts** | **Started.** `check-home-ownership`, `check-gpg`, `check-tailscale` and `check-orbstack` are extracted and wired (stages 22–25, 28); `make check-shell` and the pre-commit hook guard `bin/` (stage 17). The root `Makefile` went from 4203 to 3870 lines. | Next read-only giants: `check-guix-container`, `check-channels-sync`, `check-system-secrets`, `check-session-coupling`. Then decide whether the `mk/*.mk` split is still wanted. Never extract `apply*`, `setup-native-links`, `help`. | [`docs/stages/overnight-1119-EXTRACT.md`](stages/overnight-1119-EXTRACT.md) (rules, with a measured correction) · [`docs/MAKEFILE_STRUCTURE.md`](MAKEFILE_STRUCTURE.md) |
| **Reusable job modules (`shell-jobs`, `agent-jobs`)** | **Planned, not started.** Milestone M1 repairs R1–R6; only R3's parsing half has landed (`4ecacd6`). | Settle owner decisions (repo names/visibility, license, platform floor), then author the R1 repair stage. Stage numbers 17–30 were used by the overnight batch above and 31 is reserved for the test-target rename, so this sequence continues from **stage 32**. | [`docs/MODULE_EXTRACTION_PLAN.md`](MODULE_EXTRACTION_PLAN.md) · [review](TMUX_REVIEW_AND_MODULE_PLAN.md) |
| **EWM (Emacs Wayland Manager) trial** | **Built and launched.** Stages 0–2 done (runs on `geeeks`, TTY2, software rasteriser). Stage 1.5 (Guix session integration) unsolved. | Run the Stage 3 daily trial and answer its two questions (pinentry prompt; `wlr_data_control`). Stage 4 (Guix packaging) is deliberately last. | [`docs/EWM_TRIAL_PLAN.md`](EWM_TRIAL_PLAN.md) · [pre-switch checklist](EWM_PRE_SWITCH_EVALUATION.md) · [user guide](EWM_USER_GUIDE.md) |
| **Voice control for the job runner (`gemini-voice`)** | **In-flight on branch `gemini-voice`** (worktree `/Users/durant/dot_files_voice`); not yet on `main`. A phone/voice bridge to `tmux-dash`: `voice_server.py` (port 8642) + `gemini_agent.py` read live jobs and relay answers via each job's `extranotes`/`inbox`. | Test against a real job that writes a question to `extranotes`, then polish the CLI loop into a Gradio UI or the Gemini Live API (voice-to-voice). | `docs/voice-handoff.md` *(lives on the `gemini-voice` branch, not `main`)* |

## Open follow-ups from the job-runner close-out

These were recorded at the pipeline close-out (reports 14–16). None is blocking.

| Item | Kind | State |
| --- | --- | --- |
| Claude-side `/recap` skill | `claude` submodule edit, then `make claude-publish` | **Not done** — the one functional gap; stage 16's recap story is half-landed without it. |
| `tests/jobs/lib.zsh` consolidation | Executor stage (ran as **stage 18**) | **Done, on `main`, proven on macOS**: on `minius` (2026-11-20) `smoke.zsh` passed 433/433 and `tee-smoke.zsh` 48/48 through the shared helpers, after `76c901f` fixed a BSD `chmod` call in the 15g self-test. `podman-live.zsh` (`make check-jobs-live-tests`) was not run. `claude-smoke.zsh` keeps its own helpers by design; it passes 167/167 since `b9a9c00`. |
| `smoke.zsh` 4a fails on `orb-guix` (`server exited unexpectedly`) | Diagnosis, needs a granted tmux probe | **Open, `orb-guix` only**: a freshly started scratch tmux server dies there, so only 72 assertions run. 4a passes natively on `minius` (2026-11-20), so the cause is in the VM. Unconfirmed reading (stage 18): the aarch64 Guix tmux in an x86_64 Rosetta userland. |
| Stale macOS Login Items (`stage15probe-t1` + 10 old `job-tee` rows) | Manual admin (`sfltool resetbtm` / Settings) | **Pending** — needs admin; no code change. |

The deferred robustness questions from reports 14–16 were migrated into the module
plan's **M1 backlog** (its 2026-11-09 amendment), mapped to their work packages.

## Recently completed (for context)

| Project | Landed |
| --- | --- |
| Job-runner stage pipeline (stages 01–16) | `main` — all stages merged and green; close-out retro done. Follow-on work continues as the module extraction (stage 17+) above; non-blocking follow-ups below. |
| Register-a-machine checklist (`make register-machine`, role-aware `seed-linux`) | `main` (`7c58236`) |
| Disk floor — refuse `make apply` under 20 GiB on `/` | `main` (`e76c821`) |
