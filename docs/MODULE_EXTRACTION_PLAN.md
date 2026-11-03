# Reusable job modules: implementation plan

**Status:** planning input for future branching-stage generation; no stage numbers
reserved, forecasts sealed, executors launched, or publication authorized by this
document. **Date:** 2026-09-27.

This is the implementation planning source of truth. The
[tmux review](TMUX_REVIEW_AND_MODULE_PLAN.md) supplies the measured findings R1–R6,
source locations, architectural rationale, and verification limitations. Follow
the existing [stage envelope](stages/README.md) when generating executable prompts.

## Goal and proposed execution charter

The user's destination is to separate distinct modules into actual Git submodules
that others can “mix-in.” Deliver two independently usable repositories:
`shell-jobs`, then `agent-jobs`, with `dot_files` consuming tested commits of both.
Names are provisional until the publication decision.

An unrelated user must be able to add the runner to their own dotfiles repository,
source one documented entry point, and run a logged tmux job without adopting
personal shell settings, private agent configuration, Guix, or a prescribed
checkout location. Agent wrappers are an optional second module.

Completion requires all of the following:

- R1–R6 are repaired with reproducible regression evidence.
- Runner identity, lifecycle, logs, notes/recaps, and promotion have documented
  compatibility contracts; display labels cannot change ownership.
- Both modules have their own entry points, documentation, dependency checks,
  tests, provenance, release version, and a license selected by the owner.
- Public clones and selected-submodule initialization work without private
  repository credentials. The superproject pins remotely available commits.
- A separate minimal consumer and the existing `dot_files` integration pass
  their applicable gates, including upgrade and rollback checks.
- Legacy sessions, persisted records, and login definitions have an explicit
  migration policy; no running personal session is migrated as a test.

These are proposed charter terms derived from the review, not verbatim user
answers to the branching-stages charter interview. Before the first forecast,
record the user's actual answers and any amendments in the forecast charter.
No timebox, token budget, or acceptable skip rate has been supplied.

## Scope and boundaries

| Component | Destination | Boundary |
| --- | --- | --- |
| `.jobs.zsh`, `bin/job-tee`, runner tests and docs | `shell-jobs` | One repository containing common logic and internally separated tmux, launchd, container, host, dashboard, and promotion code. |
| `.agent-jobs.zsh`, engine adapters, agent tests and docs | `agent-jobs` | Depends on a documented runner API; initially retains the current macOS/launchd recovery requirement. |
| Personal hosts, shell startup, permission choices, hooks, themes, machine deployment | `dot_files` | Composition and explicit configuration; modules do not import these to function. |
| Existing `claude` and `espanso/private` submodules | Existing locations | Remain separate; neither is a dependency of the public modules. |

Out of this milestone: Git-tool extraction, Espanso extraction, Guix feature
publication, new agent engines, Linux agent supervision, a plugin manager, and
one Git repository per runner backend. Preserve them as follow-up candidates in
the review, not implicit additions to this pipeline.

Keep the runner and agent modules as sibling submodules. Consumers select and pin
compatible versions; do not nest another copy of the runner inside the agent
module. Separate Git histories are the packaging mechanism, while the documented
API and standalone tests establish whether the separation actually works.

## Constraints to carry into every generated prompt

- Preserve unrelated working-tree edits. At planning time, `.agent-jobs.zsh`,
  `.aliases`, and `AGENTS.md` contain local changes, and `skills/` is untracked.
  Reinspect when execution starts; do not assume these edits were committed or
  included in an executor's base. Explicitly establish the intended source commit.
- All tmux tests and probes use `tests/jobs/private-tmux` or its extracted
  equivalent. Grant exact scratch paths and resources; never operate on the
  user's live sessions, profiles, private repositories, or login agents by default.
- Do not rewrite merged stage reports, personal notes, or the superproject's
  history. Perform history extraction in a disposable clone with provenance.
- Preserve public command names and log/record readability. Changes to lookup,
  rename semantics, or metadata need compatibility tests and release notes.
- Default public installs to local-only operation. Loading a module performs no
  network access, package installation, daemon startup, or login registration.
- Resolve local assets relative to the module. Remote paths, hosts, and project
  identity mappings must be explicit; they cannot depend on `~/dot_files`.
- A displayed success or read-only claim must match observable behavior. Missing
  dependencies, malformed input, and failed rendering must produce useful failures.
- Publishing repositories, selecting a license, refreshing existing login
  definitions, and applying live Guix/native configuration are separate actions.
  Prepare reviewable artifacts and use the authorization available at that time.

## Coarse route and dependencies

Work-package IDs below are stable planning labels, **not** pipeline stage numbers.
Stages currently exist through 16; recheck the global sequence when generating
prompts. Split or insert stages when evidence warrants, retaining traceability to
these IDs. One generated stage should deliver one reviewable behavior change.

| Package | Depends on | Deliverable | Observable acceptance |
| --- | --- | --- | --- |
| W01 | Baseline readiness | Repository/task ownership contract and R1 repair | `foo`, `foo-bar`, same-basename repos, and foreign/legacy sessions cannot be confused by lookup or bulk removal; remote project identity is explicit. |
| W02 | W01 | Stable display labels and R2 repair | Changing a label preserves status lookup, notes/recaps, task environment, and agent recovery identity; no duplicate relaunch session appears. |
| W03 | Baseline readiness | R3, R4, R6 repairs | Old/new notes formats obey documented precedence; missing option values terminate with status 64; validation/renderer errors remain nonzero. |
| W04 | W01, W02, W03 | R5 repair and compatible interactive behavior | Real two-client tests prove read-only claims; PTY tests cover rename/kill confirmation; help matches behavior. |
| W05 | Milestone M1 | Internal runner modules and relocatable entry point | A moved copy works in `zsh -f` without `.aliases`, `~/bin`, personal tmux config, or `~/dot_files`; repeated sourcing is safe. |
| W06 | W05 | Explicit remote and optional-dependency contracts | Custom remote roots work; local-only operations avoid host probes; remote logs are correctly retrieved or explicitly refused; optional renderer/editor paths are portable. |
| W07 | W05, W06 | Supported runner API and agent adaptation | Engine wrappers consume documented APIs; ownership, start/resume/status/remove tests pass without private agent settings. |
| W08 | W05, W06, W07 | Standalone package test harnesses and independent consumer | Package checks no longer require the parent's Makefile; bare-shell and separate-consumer tests pass with only declared dependencies. |
| W09 | Milestone M2, release decisions | Standalone runner history and first published release | Provenance and license are recorded; selected commit is fetchable from the chosen public remote; independent clone passes package gates. |
| W10 | W09 | Runner consumed as a real superproject submodule | `.gitmodules` and gitlink pin the release; compatibility loaders, native paths, Guix inputs, tests, and documentation work with the new location. |
| W11 | W07, W08, W10, release decisions | Standalone agent release and sibling submodule integration | Compatible runner/agent versions are pinned; launch, recovery, status, and removal work without private config dependencies. |
| W12 | W10, W11 | Release verification and migration/rollback guide | Public-only fresh checkout, upgrade, rollback, and legacy-state handling pass the platform matrix; remaining limitations are explicit. |

W03 is independent in logic but shares `.jobs.zsh` and runner tests with W01/W02:
serialize those implementations. W10/W11 also share `.gitmodules`, Makefile,
loaders, and deployment wiring. Do not launch overlapping allow-lists in parallel.

### M1 — trustworthy behavior, W01–W04

Done when all six findings are closed, required runner/agent regression suites are
green on their designated hosts, and interactive claims have real terminal
evidence. No extraction or public release is needed to reach this milestone.

Capture the current baseline before generating the first repair prompt. The
previous review did not run the complete suite, and notes/menu assertions may
already fail. If a mandatory gate fails, insert a narrow prerequisite repair or
order W03 first when it owns the failure. Do not merge a red required gate, remove
assertions merely to obtain green, or treat an old report's pass as a fresh result.

### M2 — independent consumption, W05–W08

Done when both prospective packages work from arbitrary locations in an unrelated
minimal consumer, the supported API is documented and tested, and all dependencies
are declared. This milestone can be demonstrated locally without public remotes.

### M3 — released and integrated modules, W09–W12

Done when the two public releases are consumed by actual gitlinks, their commits
are retrievable, and both clean adoption and stateful upgrade/rollback are verified.
Repository publication choices must be resolved before W09/W11. If publication is
deferred, report M2 complete and M3 pending; do not call the overall goal finished.

## Verification contracts

Existing commands, to be rechecked against the execution base:

| Gate | Exact current command | Scope |
| --- | --- | --- |
| Repository integrity | `make check` | Superproject integrity; record platform-dependent skips. |
| Runner syntax | `zsh -n .jobs.zsh` | Also check each modified/new Zsh source individually. |
| Agent syntax | `zsh -n .agent-jobs.zsh` | Applies when agent integration changes. |
| Logger | `./tests/jobs/tee-smoke.zsh` | Logging and signals; inspect capability requirements and skips. |
| Runner integration | `./tests/jobs/smoke.zsh` | Private tmux and host/runner tests; some integration uses launchd. |
| Agent integration | `./tests/jobs/claude-smoke.zsh` | Historical filename; current engine wrappers and macOS recovery. |
| Aggregate jobs | `make check-jobs` | Runs the three suites above. |
| Live container behavior | `make check-jobs-live` | Explicitly granted disposable containers and an available engine. |
| Submodule publishing | `make check-submodule-publish` | Disposable Git repositories; relevant to release/integration changes. |
| Patch hygiene | `git diff --check` | Every implementation stage. |

The stage envelope's original “no test suite” description is historical. Before
generating prompts, reconcile its gate section with the current Makefile and
actual harnesses. Do not inherit historical assertion counts or platform passes.

W08 must introduce package-local equivalents for portable checks, macOS launchd
integration, live containers, and clean-consumer acceptance. Those commands do not
exist yet: the W08 report must establish their exact spellings for W09 onward.
Do not leave future prompts referring to deleted superproject paths.

| Environment | Required evidence before release |
| --- | --- |
| macOS | Portable runner checks, private tmux, two-client/PTY behavior, launchd, and agent recovery. |
| Linux | Portable runner checks, private tmux, renderer/editor fallbacks, and supported container behavior. |
| Termux | Module loading and the SSH/dashboard interaction advertised for phone use. |
| Clean consumer | Public-only initialization, optional dependencies absent, repeated sourcing, alternate paths, pinned upgrades, and rollback. |

Skipped tests are not passes. If a required host is unavailable, record the
specific missing evidence and keep the corresponding release gate pending.
Separate mocked remote tests from actual SSH/terminal compatibility claims.
Source paths containing spaces and shell metacharacters must be part of the
relocation test fixtures.

## Decision points for the future forecast author

This section is unsealed coordinator planning input. It lists uncertainties to
investigate; it is not a forecast, contains no probabilities, and should not be
copied wholesale into executor prompts. R1–R6 are measured facts, not prediction
candidates.

| Decision | Evidence and resolution point | Consequence |
| --- | --- | --- |
| Baseline has failures beyond the reviewed regressions | Fresh gate output before W01 | Insert a bounded prerequisite repair; revise the stage map before launch. |
| Legacy sessions lack enough ownership evidence | Session metadata/root fixtures at W01 review | Choose a documented explicit-adoption path if conservative automatic recognition is insufficient. No name-only destructive fallback. |
| Display-only rename cannot satisfy an existing supported consumer | Caller inventory and recovery tests at W02 review | Keep label editing as the safe default; specify a separate task-migration operation only if justified. |
| Nested read-only behavior needs a different interaction | Real client tests at W04 review | Implement a supported read-only route or explicitly refuse it; update the UX contract. |
| Agent code needs more than the proposed runner API | Private-helper inventory and tests at W07 review | Extend a bounded public API or revise the package boundary before extracting history. |
| Remote relocation exposes shell/path or version coupling | Mocked and actual remote evidence through W06/W08 | Add explicit remote configuration or a bounded compatibility layer; move remote-only fixes ahead of release. |
| Guix/native deployment cannot consume module paths as proposed | Evaluation/link checks at W10 review | Adapt the composition layer; avoid putting machine deployment back inside the runner. |
| Publication choices or a required platform remain unresolved | Release decision record and matrix at W09/W12 | Complete independent local packaging, keep publication/release pending, and do not quietly reduce the charter. |

Ask the owner before the first affected stage to settle: repository names and
visibility, license, whether history preservation is required, the supported
platform/version floor, any deadline or effort limit, and consent to the proposed
display-label rename behavior. Record actual answers verbatim in the charter;
do not present recommendations here as already approved answers.

## Instructions for generating branching stages from this plan

1. Reinspect repository state, existing stage numbers, and the current skill
   instructions. Verify the exact base and reconcile the baseline gates. Update
   agent routing documentation to the real `.agent-jobs.zsh` implementation.
2. Complete the goal-charter interview for unresolved terms. Establish the
   forecast envelope and pipeline-agent configuration while preserving existing
   files. Keep concrete model names in the machine-local routing registry, not
   this repository. Resolve frontier author/reviewer routing before those roles run.
3. Establish or preserve the append-only directory-scoped known-problem registry.
   Import only verified problems and tested remedies with their evidence. The
   review's proposed fixes are not tested remedies. Include the established
   private-tmux containment practice in applicable prompts.
4. Generate executable prompts for the next resolvable milestone, initially M1.
   Preserve the coarse M2/M3 route; author their detailed prompts after upstream
   decisions resolve. Each prompt names its work-package ID, exact base, allowed
   files, scratch grants, observable behavior, tests, exact gates, report format,
   success/blocked commit messages, and blocked protocol.
5. Run calibration before assigning probabilities. Use a milestone-aligned horizon
   of roughly three to five stages, adjusted to the observed work. Select only
   material, falsifiable uncertainties; keep detailed probabilities and branch
   plans out of executor prompts. If the milestone expands beyond roughly ten
   working days, roll the horizon rather than forecasting an unresolved tail.
6. Commit each canonical prompt with its sealed forecast and hash before launching
   that stage. Do not unseal before the merge/abandon verdict. Use isolated
   worktrees, independent review, and disjoint file ownership; model routing and
   command labels follow the pipeline skills.
7. Resolve predictions from committed evidence after the verdict, record every
   unmodeled pivot and why it was missed, and preserve charter amendments. Run
   retrospectives according to the global stage number, not this plan's W labels.
8. At each milestone, reconcile the downstream map with observed coupling and
   unresolved decisions. Append dated plan amendments; do not rewrite historical
   reports or relabel deferred publication as completed delivery.

The next action is to generate the charter and first milestone's stage contracts
from this plan when requested. Implementation and forecast sealing have not begun.

## Amendments

- **2026-09-29.** R3's parsing half already landed in `4ecacd6`, just before the
  review was committed: notes headlines take the first non-empty `#` heading or
  `> ` line. W03 still owns R3's regression tests (both forms, precedence) and
  R4/R6. No other R-finding has changed; `.jobs.zsh` has had only the editor
  default change (`60ee8aa`) since the review commit (`cc93b8e`).
