# Stage 20 REPORT — `.aliases` ordering and organisation audit (report only)

Branch `stage-20-aliases-audit`, base `7496eeead8b2b09e01f573c980e49ab168e7ccf0`
(tip of `overnight-1119`). Host: `orb-guix` guix-dev container, zsh 5.9.1,
bash 5.2.37, `/bin/sh -> dash`. The only file changed is this report.

Answers problem stack `[8]` (geeeks): "Is `.aliases` alphabetization and
organization messed up?" Short answer: **the file never claims to be
alphabetical; it claims only a section structure, and that structure is
partly wrong (mislabelled and empty sections, an override-order hazard for the
private files). Inside sections, alphabetical order is the evident intent in
about half the file and holds for 84% of the first section, 62% of the Git
section.** Of the three known data points, two are already gone on the base
(one `alias dot=`, no pasted output). The third (`pdot`) turned out to be
in order; `pp` next to it is not.

## Checklist echo

- [x] First action `git rev-parse HEAD`: `ae4857d…` (the harness branched from
      `origin/master`), tree clean, `git reset --hard 7496eee…`. Disclosed as
      Deviation 1.
- [x] Branch renamed to `stage-20-aliases-audit`.
- [x] Read COMMON, the stage 20 prompt, and the README Guardrails.
- [x] Q1–Q6 answered below, each with the command that produced it.
- [x] Blocking condition checked: `.aliases` parses on the base under every shell
      that sources it (Q4). Not blocked.
- [x] Only `docs/stages/stage-20-REPORT.md` changes.
- [x] G2 baseline and final.

## How the measurements were made

Five throwaway scripts in the session scratchpad, reproduced verbatim in the
Appendix so every number below can be re-run. All take the worktree path.

- `defs.py FILE [A-B] [--sections|--residue]` — static extractor. Prints one
  TSV row per `alias`, `alias -g`, function definition, `export`, and
  `unalias`/`unset -f`/`unfunction`: kind, name, line, section, enclosing
  top-level `if`/`case` (as `if@LINE`), enclosing function. It masks heredoc
  bodies and multi-line quoted strings; `500-516` masks the `tmstat` Babashka
  program by hand, which the quote counter cannot follow (it embeds `'\''`).
- `order.py` — per (section, kind), the definitions outside a longest
  non-decreasing subsequence of `name.lower()` in code-point order. That is the
  minimum set that must move for the group to be sorted. Run definitions inside
  other functions (`cleanup` in `ebn-lab-start`) are excluded.
- `dups.py` — names defined more than once in `.aliases`, and names it shares
  with `.shared.zshrc`, `.zshrc`, `.jobs.zsh`, `.agent-jobs.zsh` (static).
- `load.zsh` — runtime. Sources the file in `zsh -f` with `HOME` set to a
  `mktemp -d` that has `dot_files -> worktree` and `.aliases -> worktree/.aliases`.
  The order is the Guix Home one: `.aliases`, `.aliases` again, `.shared.zshrc`
  (with an `add_to_end_of_path` stub). It dumps the aliases and functions that
  win. `overlap.zsh` cross-checks job-file collisions at runtime.
- `blocks.py` — line count for the full-regroup proposal (Q6).

Sections used below are the banner titles found by
`python3 -I defs.py .aliases --sections`:

```
14	(Cross Platform) Bash Aliases
272	Docker Aliases
292	Guix Aliases
426	ssh to home machines
440	Emacs daemon over ssh  (see `make emacs-serve` on the host machine)
460	gpg-agent / ssh debugging  (see docs/GPG.md, "Troubleshooting")
480	OS Specific Aliases
548	Private aliases
561	Aliases at home
572	clean -- drop editor backup files (foo~) from here down
626	fastfetch -- one command name on every machine
642	Aliases for work (private repo to protect employer)
648	Cloud Services
766	Zsh Aliases
787	  Re-source a zsh config file.
1040	  PYTHON
1193	  global aliases
1291	Git Aliases (Oh-My-Zsh style)
1384	Remote Access (Lab / Web Shell)
1408	Long-running local work: tmux / launchd / Docker job helpers
```

Inventory (`defs.py … | cut -f1 | sort | uniq -c`): 192 `alias`, 44 `alias -g`,
61 function definitions, 3 `export`, 2 `unalias`, 1 `unset -f`, 1 `unfunction`,
in 1416 lines. At runtime (`load.zsh`) the file plus the two job files leave 177
regular aliases, 44 global aliases and 255 functions on this host. `.shared.zshrc`
raises the function count to 263.

## Q1 — What ordering or structure does the file claim?

**No ordering claim anywhere.** Searching for any wording about order:

```
$ rg -n -i 'alphabet|sort(ed)? |order|keep .* (above|below)|is above|section' .aliases
227:# stack.  Plain `dot' (cd) is above, for when you do not want a stack entry.
409:# docs/learning/wayland-tty-drm-seat.md section 2.  This alias used to say
467:# Triage order: make check-ssh-with-gpg-for-egress, then gpg-here, then make check-ssh-github.
651:# A standing section, not a scratchpad: several providers are in use at once and
682:#                  before cancelling, and do it in that order.
815:    # Re-source what zsh reads at startup, in the order zsh reads it.  The
851:    # Everything, in the order zsh itself reads it, skipping what is absent.
(plus `sort` inside command bodies at 32-34, 120, 154, 783, 1267, 1271, 1275)
```

None of these states a rule for how definitions are ordered. History does not
either: `git log --all -i --grep=alphabet` finds only `8ef141e` (add-pkg, about
Scheme package lists). The `pdot` commit `cd5a43d` explains where it put `pdot`
by meaning ("sitting next to `pp` … the pair it was always meant to be"), not by
any ordering rule.

**What the file does claim is a section structure**, through banner comments
(the list above). Banner styles:

- Top-level `#####…#####` rule / title / rule: lines 13–15 `(Cross Platform) Bash
  Aliases`, 647–649 `Cloud Services`, 765–767 `Zsh Aliases`.
- Top-level `# -----…` rule / title / rule: 271–273 Docker, 291–293 Guix,
  425–427 ssh, 439–441 Emacs daemon, 459–461 gpg, 479–481 OS Specific, 547–549
  Private, 560–562 at home, 571–573 clean, 625–627 fastfetch, 641–643 work,
  1290–1292 Git, 1383–1385 Remote Access, 1407–1409 Long-running.
- Indented subsections inside the zsh guard: `###…` + title at 786–787
  ("Re-source a zsh config file.", **no closing rule**); `# ----` + `# PYTHON`
  at 1039–1040, closed by a lone `# ----` at 1154; `###…` + `# global aliases`
  at 1192–1193 (**no closing rule**, runs to the `fi` at 1288). Informal markers
  that are not banners: `# spacemacs` 1156, `# -----` 1177, `# mac` 1190 (an
  orphan: nothing follows it before the next banner).

The one implicit, unstated convention is **alphabetical order inside the first
section**. 49 of its 58 aliases are already in order (Q2). The Git section's
title claims "Oh-My-Zsh style", which is grouping by git verb, not
alphabetical.

## Q2 — Where does the file violate what it claims?

### 2a. Violations of the claimed section structure (banner vs. content)

Measured from the `defs.py` TSV (kind, name, line, section, enclosing `if`):

| Lines | Banner | What is actually there |
| --- | --- | --- |
| 13–269 | `(Cross Platform) Bash Aliases` | Nothing sources this file in bash (Q4). The section holds zsh-only code: `(( $+functions[mr-brief-deluxe] )) && unfunction` (196) and `"${mr_dirs[1]}"` (76), which takes the FIRST element only under zsh's 1-based arrays and would take the second in bash. It also holds 7 functions (the myrepos block 44–196 and `watchf` 259) that sit between `git_personal_ignore` (43) and `h` (202). |
| 271–290 | `Docker Aliases` | **Zero definitions.** Comments only (XQuartz/nyxt notes, a Pop!_OS example). |
| 291–423 | `Guix Aliases` | Guix container functions (314, 344) and font aliases (380–385), then console keymap and VT helpers that are not Guix-specific (`swap-caps` 388, `vt` 398, `vt-*`/`vt1..8` 405–420). `restart-gnome` 423 uses `herd`, so it is Guix System only. |
| 479–545 | `OS Specific Aliases` | The `if uname` chain ends at `fi` 541. **`orb-guix` (545) sits under this banner but is unconditional.** Its comment says it covers macOS and WSL. |
| 571–623 / 625–639 | `clean` / `fastfetch` | One-function sections, between the private and work loaders. |
| 647–763 | `Cloud Services` | **Zero definitions**, 117 comment lines. It says so itself at 761: "No aliases yet". |
| 765–1288 | `Zsh Aliases` (`if [ -n "$ZSH_VERSION" ]` 769) | This is the only explicitly guarded block. Lines 1–768 and 1289–1416 are zsh-only in practice too: `${ref:t}` (1304) is a zsh modifier, and 1411/1413 test `$ZSH_VERSION` themselves. The `# elif [ -n "$BASH_VERSION" ]` at 1286 is a commented-out dead branch. |
| 786–1038 | `Re-source a zsh config file.` | The banner has no closing rule. Its real scope is `_source_if`/`_source_shell_files`/`s.z*` (806–852), but `dfmake`, `dot-apply*`, `lth`, `ztheme`, `rg`, `pd`, `killport`, … (854–1037) run on under it with no banner of their own. |
| 1290–1381 | `Git Aliases (Oh-My-Zsh style)` | Outside the zsh guard, so `alias g='git'` (1311) overrides `alias g=grep` (38) (Q3). |
| 1383–1405 | `Remote Access (Lab / Web Shell)` | One function, which defines a **global** `cleanup` function and `trap cleanup INT TERM EXIT` in the calling interactive shell at run time (1395–1400). Line 1393 `local ttyd_pid=$!` is not indented. |

### 2b. Out-of-order definitions inside each section

Kinds are kept apart, as the prompt asks. The order key is `name.lower()`, in
code-point order. Sections where alphabetical order is plainly not the intent
are listed for completeness. Command:
`python3 -I order.py < aliases2.tsv`. `aliases2.tsv` is the `defs.py` TSV with
the zsh guard split at its two real boundaries: 769–1038 (including the
unterminated Re-source banner) and 1155–1191 (after the PYTHON closing rule).
Groups with 0 out of order are omitted. Total: **96 out-of-order definitions.**

**Aliases (`alias`)**

```
## (Cross Platform) Bash Aliases / alias: 58 defs, 9 out of order
  line 23: c2n  -> belongs after agy-auto (line 19)
  line 39: glow  -> belongs after git_personal_ignore (line 43)
  line 40: gv  -> belongs after git_personal_ignore (line 43)
  line 204: ipy  -> belongs after ipn (line 205)
  line 222: nrun  -> belongs after nrt (line 223)
  line 224: labels  -> belongs after ipn (line 205)
  line 229: pp  -> belongs after port_scan (line 230)
  line 252: ,  -> belongs before a (line 17)
  line 253: ,.  -> belongs before a (line 17)
## Guix Aliases / alias: 18 defs, 4 out of order
  line 380: guix-shell-zsh  -> belongs after guix-powerline-bold (line 384)
  line 381: guix-shell-bash  -> belongs after guix-powerline-bold (line 384)
  line 405: vt-gnome  -> belongs after vt-ewm (line 412)
  line 423: restart-gnome  -> belongs after guix-spleen (line 385)
## ssh to home machines / alias: 4 defs, 2 out of order
  line 434: minius  -> belongs after framepop (line 436)
  line 435: geeeks  -> belongs after framepop (line 436)
## OS Specific Aliases / alias: 16 defs, 7 out of order
  line 490: mcs  -> belongs after mcd (line 492)
  line 496: backup  -> belongs before claude (line 485)
  line 532: cmake  -> belongs after claude (line 485)
  line 537: llhome  -> belongs after ip_addr (line 489)
  line 538: llhomea  -> belongs after ip_addr (line 489)
  line 539: cdhome  -> belongs before claude (line 485)
  line 545: orb-guix  -> belongs after oemacs (line 493)
## Aliases at home / alias: 4 defs, 2 out of order
  line 565: proj  -> belongs after clerk (line 568)
  line 566: dox  -> belongs after clerk (line 568)
## Zsh Aliases (769-1038, incl. unterminated Re-source banner) / alias: 25 defs, 14 out of order
  line 782: ollama_update  -> belongs after ollama_library_list (line 784)
  line 783: ollama_list  -> belongs after ollama_library_list (line 784)
  line 841: s.zp  -> belongs after s.zh (line 847)
  line 844: s.zs  -> belongs after s.zh (line 847)
  line 846: s.zps  -> belongs after s.zh (line 847)
  line 852: s.zall  -> belongs after s.z (line 837)
  line 874: da  -> belongs after ctags (line 772)
  line 880: daw  -> belongs after ctags (line 772)
  line 887: dae  -> belongs after ctags (line 772)
  line 889: lth  -> belongs after fng (line 779)
  line 890: lthd  -> belongs after fng (line 779)
  line 931: llrm  -> belongs after fng (line 779)
  line 937: python3  -> belongs after ollama_library_list (line 784)
  line 939: heroku_logs  -> belongs after fng (line 779)
## Git Aliases (Oh-My-Zsh style) / alias: 68 defs, 26 out of order
  line 1324: gcb  -> belongs after gcans! (line 1333)
  line 1325: gcd  -> belongs after gcans! (line 1333)
  line 1326: gcm  -> belongs after gcans! (line 1333)
  line 1329: gcn!  -> belongs after gcmsg (line 1335)
  line 1334: gcam  -> belongs after gca! (line 1331)
  line 1336: gcs  -> belongs after gcor (line 1338)
  line 1339: gcl  -> belongs after gcans! (line 1333)
  line 1340: gclean  -> belongs after gcans! (line 1333)
  line 1358: gstp  -> belongs after gstd (line 1360)
  line 1359: gstl  -> belongs after gstd (line 1360)
  line 1362: gst  -> belongs after gs (line 1356)
  line 1363: gss  -> belongs after gs (line 1356)
  line 1364: gsb  -> belongs after gs (line 1356)
  line 1365: glum  -> belongs after gl (line 1348)
  line 1367: gpristine  -> belongs after gpf! (line 1350)
  line 1368: ggpull  -> belongs after gfo (line 1347)
  line 1369: ggpush  -> belongs after gfo (line 1347)
  line 1370: gpsup  -> belongs after gpf! (line 1350)
  line 1372: glog  -> belongs after gl (line 1348)
  line 1373: gloga  -> belongs after gl (line 1348)
  line 1374: glg  -> belongs after gl (line 1348)
  line 1375: glgp  -> belongs after gl (line 1348)
  line 1376: glo  -> belongs after gl (line 1348)
  line 1379: dglo  -> belongs before g (line 1311)
  line 1380: dglog  -> belongs before g (line 1311)
  line 1381: dgloga  -> belongs before g (line 1311)
```

The Git section's own claim is "Oh-My-Zsh style", that is, grouped by git
verb. Measured against that claim (verb = the first word after `git`,
`log-compact` counted as `log`), it breaks contiguity in only six places:

```
$ sed -n '1311,1381p' .aliases | awk -F"'" '/^alias/{…verb…}' | awk '{…report a verb run that reopens…}'
REOPEN: verb branch resumes at line 1322 (gbnm), last run ended line 1320
REOPEN: verb checkout resumes at line 1337 (gco), last run ended line 1326
REOPEN: verb pull resumes at line 1365 (glum), last run ended line 1348
REOPEN: verb reset resumes at line 1367 (gpristine), last run ended line 1353
REOPEN: verb pull resumes at line 1368 (ggpull), last run ended line 1366
REOPEN: verb push resumes at line 1369 (ggpush), last run ended line 1350
```

(the branch run is broken by `gbl` = `git blame` at 1321). The full awk is in
the Appendix.

On the known data points: `pdot` (228) **is** in alphabetical order (`path` 225 <
`pdot` 228 < `port_scan` 230). The violator is `pp` (229), which belongs after
`port_scan`. Leaving `pdot` next to `pp` is a sound choice by meaning, but it
does not fix `pp`. There is one `alias dot=` (`rg -n '^\s*alias dot=' .aliases`
→ `29:alias dot='cd ~/dot_files/'`), so the 197-line duplicate is gone.

**Global aliases (`alias -g`)**

```
## global aliases / global-alias: 42 defs, 11 out of order
  line 1205: CA  -> belongs after C (line 1206)
  line 1223: err→out  -> belongs after ELS (line 1253)
  line 1239: LOGT  -> belongs after L (line 1262)
  line 1245: LOGP  -> belongs after L (line 1262)
  line 1254: ETL  -> belongs after ET (line 1255)
  line 1260: Sk  -> belongs after S (line 1272)
  line 1261: LL  -> belongs after L (line 1262)
  line 1264: MM  -> belongs after M (line 1265)
  line 1273: TL  -> belongs after T (line 1274)
  line 1277: X0G  -> belongs after X0 (line 1278)
  line 1284: X  -> belongs after VM (line 1276)
```

The 1247–1284 run follows a "first letter, longer spelling first" pattern
(`ETL` before `ET`, `MM` before `M`, `X0G` before `X0`). Under that weaker key,
the only violator in the run is **`Sk` (1260)**, which sits among `H`/`L`. The
documented `err→out` (1208–1223) and `LOG`/`LOGT`/`LOGP` (1225–1245) blocks sit
before `D` with their long comments. `latestd`/`latestf` (928–929) are two global
aliases defined outside the global-aliases subsection.

**Functions**

```
## (Cross Platform) Bash Aliases / function: 7 defs, 2 out of order
  line 89: mr-register  -> belongs after mr-push-ahead (line 162)
  line 165: mr-brief  -> belongs after mr-all (line 96)
## Zsh Aliases (769-1038, incl. unterminated Re-source banner) / function: 25 defs, 13 out of order
  line 776: funcs  -> belongs after epoch_date2 (line 963)
  line 876: dot-apply-wayland  -> belongs after dot-apply-ewm (line 883)
  line 901: spacemacs_force_clean  -> belongs after pdfsearch (line 1004)
  line 912: clojars-lookup-lein  -> belongs after _source_shell_files (line 824)
  line 915: clojars-lookup-deps  -> belongs after _source_shell_files (line 824)
  line 921: branches  -> belongs after _source_shell_files (line 824)
  line 965: rm  -> belongs after pdfsearch (line 1004)
  line 969: rg  -> belongs after pdfsearch (line 1004)
  line 974: rg_with_git  -> belongs after pdfsearch (line 1004)
  line 976: psg  -> belongs after pdfsearch (line 1004)
  line 988: pd  -> belongs after p (line 1000)
  line 1008: get_pids_from_port  -> belongs after epoch_date2 (line 963)
  line 1033: grep_git_branches  -> belongs after epoch_date2 (line 963)
## PYTHON / function: 9 defs, 4 out of order
  line 1052: m2f  -> belongs after half (line 1053)
  line 1066: uv_mkvirtualenv  -> belongs after uv_lsvirtualenv (line 1143)
  line 1080: uv_set_venv_dir  -> belongs after uv_rmvirtualenv (line 1149)
  line 1104: uv_workon  -> belongs after uv_rmvirtualenv (line 1149)
## Zsh Aliases tail (1155-1191, after PYTHON closing rule) / function: 5 defs, 1 out of order
  line 1158: switch_spacemacs  -> belongs after stt_title (line 1188)
## global aliases / function: 2 defs, 1 out of order
  line 1229: LOG  -> belongs after F0 (line 1282)
```

Function order follows narrative or dependency order, not the alphabet. Each
helper comes before its users (`_source_if` → `_source_shell_files` → `dfmake` →
`dot-apply*`; `guix-container-heal` → `guix-container-shell`), and the uv block
follows virtualenvwrapper's command order (mk, set, workon, deactivate, ls, rm).
**I would not treat these as violations.** The zsh-guard function list, though,
has no structure at all (`spacemacs_force_clean` 901 and `switch_spacemacs`
1158 are 257 lines apart).

**Exports**: only 3 `export`s. `XDG_CONFIG_HOME` (521) is the only load-time
one, in the Darwin branch. `GPG_TTY` and `PINENTRY_USER_DATA` (469, 471/473)
are set inside `gpg-here` at run time. Nothing to order. The non-exported
load-time assignment `MVP=` (1041) is noted under Q4.

## Q3 — Duplicates and shadowing

### Within `.aliases`

Static, then the runtime winner:

```
$ python3 -I dups.py WORKTREE
# within .aliases (alias / global-alias / function)
g | alias@38 ctx=- in=-; alias@1311 ctx=- in=-
ll | alias@214 ctx=if@213 in=-; alias@216 ctx=if@213 in=-
s.a | alias@233 ctx=- in=-; alias@552 ctx=if@551 in=-; alias@556 ctx=if@555 in=-
ssh_fingerprint | alias@494 ctx=if@483 in=-; alias@525 ctx=if@483 in=-
```

```
$ zsh -f load.zsh WORKTREE OUT; cat OUT/s.a OUT/alias-and-function
s.a=source ~/.aliases
g=git
(alias-and-function: empty -- no name is both an alias and a function)
```

| Name | Lines | Kind | Winner at load time |
| --- | --- | --- | --- |
| `g` | 38 `g=grep`, 1311 `g='git'` | alias vs alias, both unconditional | **1311 (`git`)**, measured. Line 38 is dead code, and the neighbouring `eg`/`gv` (35/40) still assume the grep meaning. |
| `s.a` | 233, 552 (if `~/.private_aliases`), 556 (if `~/.aliases.private`) | alias ×3 | 233 here, measured (no private files in the fake HOME). With one private file, its block wins. **With both present, 556 wins, and `s.a` stops re-sourcing `~/.private_aliases`**, which 553 did source at startup. Host-limited: no private files were read (Guardrail 5 spirit; they live outside the worktree). |
| `ll` | 214 / 216 | alias, `if`/`else` of one probe (213) | Mutually exclusive, so not a real duplicate. 214 here (GNU ls). The Guix-generated zshrc also sets `ll="ls -lah --color=always"` (`home/common.scm:1103`) just before sourcing `.aliases`, and `.aliases` wins by design (comment at `home/common.scm:1099–1102`). |
| `ssh_fingerprint` | 494 (Darwin) / 525 (Linux) | alias, two `elif` branches of 483 | Mutually exclusive. 525 here (`ssh-keygen -E md5 -l`). |
| `cmake` | `unalias` 528 (Linux) / `alias` 532 (MINGW) | branches of 483 | Mutually exclusive. |
| `funcs` | `unalias` 775, then `function funcs` 776 | alias → function | Re-source guard. The function wins. |
| `f2m`/`m2f`/`half` | `unalias` 1043, functions 1051–1053 / `unset -f` 1056 | guarded by `-x $MVP` (1042) | Absent here (no `money_value.py`). |
| `mr-brief-deluxe` | `unfunction` 196 | retired-name guard | Not defined. |
| `cleanup` | 1395, inside `ebn-lab-start` | function created at run time | Not defined at load. Running `ebn-lab-start` defines a global `cleanup` and an EXIT trap in the interactive shell. |

### Shared with `.shared.zshrc`, `.zshrc`, `.jobs.zsh`, `.agent-jobs.zsh`

**None.** The static pass (`dups.py`, "# shared with other files" section)
printed no rows. Every top-level definition in `.shared.zshrc`
(`source_virtualenvwrapper_safe`, `mktemp` (inside a subshell), `chpwd`,
`glowtmux`, `remindme`, `_remindme`, `env-cd`, `_env-cd`) and `.zshrc`
(`venv_prompt_info`, `prompt_context`, `precmd`) has a name `.aliases` does not use:

```
$ rg -n '^\s*(alias |function |[A-Za-z_][\w.-]*\s*\(\))' .zshrc .shared.zshrc
.zshrc:119:    function venv_prompt_info() {
.zshrc:140:prompt_context() {
.zshrc:204:    precmd() {
.shared.zshrc:121:            source_virtualenvwrapper_safe() {
.shared.zshrc:123:                    function mktemp() {
.shared.zshrc:183:function chpwd() {
.shared.zshrc:202:glowtmux() {
.shared.zshrc:207:remindme() {
.shared.zshrc:215:_remindme() {
.shared.zshrc:238:env-cd() {
.shared.zshrc:253:_env-cd() {
```

The runtime cross-check for the job files agrees:

```
$ zsh -f overlap.zsh WORKTREE
.aliases alone: 273 names; job files alone: 205 names
overlap:
run-help
which-command
```

`run-help` and `which-command` are aliases zsh itself defines, even under
`zsh -f`, so they are not collisions. The `load.zsh` diff of aliases before and
after `.shared.zshrc` shows only sort-order changes (its `LC_ALL=en_US.UTF-8`
changes collation). No value changed.

Cross-file **couplings** (not duplicates), worth knowing before a reorder:

- `.agent-jobs.zsh:1773–1795` reads `$aliases[agy-auto]` and `$aliases[codex-auto]`,
  so `.aliases` 19/21 must be defined before those functions run. They are,
  since the job files are sourced last (1411/1413).
- `alias tu='tmux-up'` (1414) and `.jobs.zsh:1747 alias tdu=tmux-dash-universal`
  depend on `.jobs.zsh`. `tu` is defined even when `.jobs.zsh` is absent.
- `,=pd` (252) points at a function defined 736 lines later, inside the zsh guard
  (988).

### Load order, which decides every "winner" above

`git grep -n -e 'aliases' -- home/ .shared.zshrc .shared.zshenv .zprofile .zshrc.starship`
and `rg -n 'link-dotfile' Makefile` give:

- **Guix Home**: the generated zshrc runs `[[ -f ~/.aliases ]] && source ~/.aliases`
  (`home/common.scm:1104`), then concatenates `.zshrc.starship`, which sources it
  **again** (`.zshrc.starship:66`), then `.shared.zshrc`. So `.aliases` loads
  **twice** per shell. Measured: the second source exits 0 and prints nothing
  (`load.zsh` stderr: `first source exit=0`, `second source exit=0`).
- **Native (macOS)**: `~/.zshrc -> .zshrc.starship` (Makefile:742), which sources
  `~/.aliases` once (66) and then `~/.shared.zshrc` (68).
- The oh-my-zsh `.zshrc` also sources it (177), but no target links it: Makefile
  742 links `.zshrc.starship` to `~/.zshrc`. It is legacy.

**Override hazard:** the private files (553, 557) and the work file (645) are
sourced **before** the zsh block (769–1288), the Git block (1311–1381) and the
job files. Any private definition of a name those later blocks define is
silently overridden. The usual intent of a "private overrides" file is the
opposite. Host-limited: whether any private name actually collides cannot be
measured without reading the private files.

### Shadowing commands on PATH (this host only)

```
$ cat OUT/shadows-path
ctags shadows /root/.guix-home/profile/bin/ctags
glow shadows /root/.guix-home/profile/bin/glow
mr shadows /root/.guix-home/profile/bin/mr
remindme shadows /root/bin/remindme
rg shadows /root/.guix-home/profile/bin/rg
rm shadows /usr/bin/rm
sg shadows /usr/bin/sg
```

`mr`, `glow`, `ctags`, `rg`, `rm` wrap their binary on purpose
(`command mr`, `=rg`, `=rm`, `=ctags`). `remindme` comes from `.shared.zshrc`.
**`sg` (236, `set | grep`) shadows `/usr/bin/sg`** (shadow-utils
switch-group), which looks accidental. The `rg` function (969) adds
`--hidden -g '!.git/*'` and an echo to every interactive `rg`. Host-limited: on
macOS and geeeks the PATH differs, and `gs` (git switch, 1356) would shadow
Ghostscript wherever it is installed. It is not installed here.

## Q4 — Residue, and which shells parse and source the file

### Parse checks

```
$ zsh -n .aliases; echo "exit=$?"
exit=0
$ bash -n .aliases; echo "exit=$?"
exit=0
$ sh -n .aliases; echo "exit=$?"         # /bin/sh -> dash
.aliases: 61: Syntax error: "(" unexpected (expecting "}")
exit=2
$ bash --posix -n .aliases; echo "exit=$?"
exit=0
```

### Who sources it

Only **zsh**, on three paths: `home/common.scm:1104` (Guix Home generated zshrc),
`.zshrc.starship:66` (Guix Home concatenation and native `~/.zshrc`), and the
unlinked legacy `.zshrc:177`. **No bash or sh startup file sources it.** The repo
deploys no `.bashrc`/`.profile`. `git grep -e '\.bashrc'` finds only
`.aliases:234 alias s.b='source ~/.bashrc'` and `guix-install.sh:883`, and the
latter does not source `.aliases`. So the dash failure at line 61 (the zsh/bash
array `mr_dirs=("$1")` inside `mr()`) is not a parse failure of any sourcing
shell. bash still parses the file cleanly, which the comment at 1044–1050 says
is deliberate. **Not a Blocked condition** (Deviation 2).

### Residue

Every top-level line that is not a definition, comment, blank, `}` or control
keyword (`defs.py .aliases 500-516 --residue`):

```
553	source ~/.private_aliases
557	source ~/.aliases.private
645	[[ -f ~/dot_aliases/dot_aliases ]] && source ~/dot_aliases/dot_aliases # bitbucket
1041	MVP="$HOME/.ipython/profile_default/startup/money_value.py"
1057	unset MVP
1074	touch "$HOME/.venv_map"
1075	echo "# Virtual Environment to Project Directory Mapping" > "$HOME/.venv_map"
1076	echo "Created ~/.venv_map file."
1411	[[ -n "$ZSH_VERSION" && -f ~/dot_files/.jobs.zsh ]] && source ~/dot_files/.jobs.zsh
1413	[[ -n "$ZSH_VERSION" && -f ~/dot_files/.agent-jobs.zsh ]] && source ~/dot_files/.agent-jobs.zsh
```

**No pasted output and no stray text.** Every line here is a deliberate
statement. The `c0cfacb` eshell residue is gone. The only load-time side effect
outside the shell is **1073–1077: it creates `~/.venv_map` on first load and
echoes "Created ~/.venv_map file."** into the startup output. Measured in the
fake HOME: `Created ~/.venv_map file.` / `venv_map created: yes`.

Near-residue that a human reader could take for junk:

- 496–497 `alias backup='cd …; \⏎        # echo "if compaudit errors, …"'`: the
  value carries a commented-out echo across a backslash-newline. Measured:
  `print -r -- "value=[${aliases[backup]}]"` shows both lines, and
  `eval backup` runs only the `cd` (the comment is inert).
- 941–959: a commented-out `_heroku_logs_completions` with blank lines inside,
  and commented `XDG_CACHE_HOME`/`zstyle` lines.
- 1286–1287: commented-out `# elif [ -n "$BASH_VERSION" ]` / `# assume Bash`
  just before the guard's `fi`.
- 1190 `# mac` and 1177 `# -----`: orphan markers with nothing under them.
- 1416 `#  LocalWords:  popd`: an Emacs ispell file-local word list. Intentional,
  and belongs at the end.

## Q5 — Conditional blocks a reorder must move as a unit

From the `ctx` column of the `defs.py` TSV (top-level conditionals only; the
`if`s inside function bodies move with their function):

| Block | Lines | Condition | Definitions inside |
| --- | --- | --- | --- |
| ls probe | 213–217 | `if ls --color=always …` | `ll` ×2 (if/else) |
| OS chain | 483–541 | `if Darwin / elif Linux / elif MINGW / elif WSL-cmake` | Darwin: `claude fix_spotlight gitk ip_addr mcs mca mcd oemacs ssh_fingerprint backup`, fn `tmstat`, `export XDG_CONFIG_HOME`. Linux: `ssh_fingerprint`, `unalias cmake`. MINGW: `cmake`. WSL: nested `if whoami == root` (536–540) with `llhome llhomea cdhome` |
| private (1) | 551–554 | `-e ~/.private_aliases` | `s.a`, source |
| private (2) | 555–558 | `-e ~/.aliases.private` | `s.a`, source |
| home | 564–569 | `-e ~/.HOME` | `proj dox blog clerk` |
| fastfetch shim | 634–639 | no fastfetch and neofetch present | fn `fastfetch` |
| **zsh guard** | 769–1288 | `-n "$ZSH_VERSION"` | 25 aliases, 44 global aliases (42 in the global subsection plus `latestd`/`latestf`), 41 functions (all of Q2's zsh-guard groups), nested blocks below |
|  nested | 911–918 | `command -v clojars-lookup` | fns `clojars-lookup-lein`, `clojars-lookup-deps` |
|  nested | 1042–1058 | `-x "$MVP"` | `unalias f2m m2f half`, fns `f2m m2f half` / else `unset -f …`, `unset MVP` |
|  nested | 1073–1077 | `! -f ~/.venv_map` | side effect only (no definitions) |

One-line conditionals that must keep their guard: 196 (`unfunction` if
defined), 645 (work file), 937 (`python3` if a pyenv shim exists), 1411 and 1413
(job files, zsh and file test).

**Order-sensitive units**, beyond the `if`s:

- `funcs`: the `unalias` (775) must stay before `function funcs` (776).
- `guix-container-heal` (314) before `guix-container-shell` (344). Not strictly
  needed at define time, but documented as a pair.
- `_source_if` → `_source_shell_files` → `s.z*` → `dfmake` → `dot-apply*` → `da/daw/dae`.
- Private loaders after `s.a` (233). They redefine it.
- The job-file sources (1411/1413) before `tu` (1414). They should stay last.

## Q6 — Proposed layout, with lines moved (NOT applied)

### Option 1 — minimal: fix the violations in place

Keep every banner and every block where it is. Fix only what breaks each
section's own evident convention:

1. First section, alphabetical: move the 9 single-line aliases from Q2
   (`c2n glow gv ipy nrun labels pp , ,.`). → **9 lines.**
2. Git section, verb grouping ("Oh-My-Zsh style"): `gbl` after `gbr`, `gco`/`gcor`
   up beside `gcb`, `glum`/`gupaom`/`ggpull` beside `gl`, `gpristine` beside
   `grhh`, `ggpush`/`gpsup` beside `gpf!`. → **9 lines.**
3. Global aliases, first-letter run: move `Sk` (1260) into the `S` group.
   → **1 line.**
4. Not moves, but part of "fix in place": delete the dead `alias g=grep` (38).
   Retitle `(Cross Platform) Bash Aliases` and `Docker Aliases` to what they
   hold. Add a closing rule after 852 for the Re-source subsection.

**Total moved: 19 lines** (of 1416), plus 1 deletion and 3 comment edits. No
load-order change, so it is behaviour-neutral, except that deleting line 38
changes nothing either, because 1311 already wins.

### Option 2 — full: regroup by topic, then sort inside each group

Target layout (a header rule states the convention: "aliases alphabetical
within a section; functions in dependency order; loaders last"):

```
A  header + the ordering rule                         1-12
B  general aliases, a-z                               13-43, 197-253
C  myrepos (mr*)                                      44-196
D  general functions (watchf, clean, fastfetch shim)  254-269, 570-639
E  Guix and containers (+ Docker notes, orb-guix)     270-385, 542-545
F  console / VT                                       386-423
G  remote hosts (ssh aliases, eam, ebn-lab)           424-457, 1382-1405
H  gpg                                                458-477
J  OS specific (the uname chain)                      478-541
J2 cloud services notes (comment only)                646-763
K  zsh-only (guard) + Git (Git may join the guard)    764-1381
M  late loaders: private, ~/.HOME, work               546-569, 640-645
N  job files + tu (must stay last)                    1406-1414
O  LocalWords                                         1415-1416
```

Lines moved at the block level (`python3 -I blocks.py`, which keeps the
largest-weight set of blocks already in target order and moves the rest):

```
MOVE   197-253  ( 57 lines) -> B general aliases
MOVE   542-545  (  4 lines) -> E Guix and containers
MOVE   546-558  ( 13 lines) -> M late: private
MOVE   559-569  ( 11 lines) -> M late: home
MOVE   570-623  ( 54 lines) -> D general functions
MOVE   624-639  ( 16 lines) -> D general functions
MOVE   640-645  (  6 lines) -> M late: work
MOVE  1382-1405 ( 24 lines) -> G remote hosts
total lines 1416, moved 185
```

On top of the 185 block-level lines come the in-section sorts. Use Option 1's
19 lines if functions keep dependency order. If the zsh-guard aliases are also
alphabetized, add the 14 aliases from Q2's zsh group, plus their attached
comments.

**Option 2 is not behaviour-neutral.** Moving M (private, home, work) after the
zsh and Git blocks makes private definitions win over public ones where today
they lose (Q3, override hazard). That is probably the intent, but it changes
the behaviour of any private name that collides, which cannot be checked from
this worktree. `s.a` should be fixed at the same time, so that one alias
re-sources both private files.

## Gates

| Gate | Baseline (unmodified `7496eee`) | Final (committed tree) | Result |
| --- | --- | --- | --- |
| G2 `git diff --check 7496eee…` | no output, exit 0 | see below | pass |
| G1 `make -k check` | not run: not required, nothing executable changes (prompt DoD) | not run | n/a |
| G3/G4 | not applicable: no script changed | — | n/a |

Baseline, verbatim:

```
$ git diff --check 7496eeead8b2b09e01f573c980e49ab168e7ccf0; echo "G2 baseline exit=$?"
G2 baseline exit=0
```

Final, on the committed tree (folded in by the report-only amend):

```
$ git diff --check 7496eeead8b2b09e01f573c980e49ab168e7ccf0; echo "G2 final exit=$?"
G2 final exit=0
(measured on commit 615bf75, the tree before this report-only amend)
```

## `git diff 7496eee --stat`

```
$ git diff 7496eeead8b2b09e01f573c980e49ab168e7ccf0 --stat     # on 615bf75, before the amend
 docs/stages/stage-20-REPORT.md | 1133 ++++++++++++++++++++++++++++++++++++++++
 1 file changed, 1133 insertions(+)
(the amend adds 4 lines to this same file; still exactly one file)
```

## Host-limited evidence

- Private files (`~/.private_aliases`, `~/.aliases.private`,
  `~/dot_aliases/dot_aliases`) were not read. The `s.a` winner when they exist
  and the override hazard are therefore derived from the code, not observed.
- The Darwin, MINGW and WSL branches of the OS chain were not executed. Their
  winners (`ssh_fingerprint` 494, `cmake` 532, `llhome*`) come from reading the
  code.
- PATH shadowing was measured only on this host's PATH.
- Interactive-shell behaviour (prompt hooks, compinit) was not exercised:
  `load.zsh` is non-interactive (`zsh -f`), which also skips `.shared.zshrc`'s
  `$- == *i*` block and makes `compdef` absent (`.shared.zshrc:258: command not
  found: compdef` on stderr, harmless here).

## Deviations

1. The worktree started at `ae4857d` (harness branched from `origin/master`), not
   the base. The tree was clean, so I ran `git reset --hard
   7496eeead8b2b09e01f573c980e49ab168e7ccf0` as COMMON instructs.
2. Blocking condition read narrowly. The prompt says to block "if `.aliases`
   fails to parse on the base". `sh -n` (dash) fails at line 61, but no `sh`
   sources the file. zsh (the only sourcing shell) and bash both parse it, so I
   treated it as a finding, not a block. If the coordinator reads the condition
   literally, this stage should be re-filed as BLOCKED with that output, which
   is quoted in Q4.
3. Q2 has no claimed order to measure violations against (Q1). I measured
   against (a) the claimed banners and (b) per-section alphabetical order as
   the implicit convention. For the Git section I also measured its own
   "Oh-My-Zsh style" verb-grouping claim. The numbers depend on that choice
   and on the key (`lower()`, code-point order).
4. The zsh guard's subsections were re-bounded by hand for Q2: the Re-source
   banner has no closer, and the PYTHON block closes at 1154. `aliases2.tsv` is
   the `defs.py` TSV with those two ranges relabelled. The awk that did it is in
   the Appendix.
5. Lines 500–516 (the `tmstat` Babashka program) are masked by hand. The
   extractor's quote counter cannot follow `'\''` there. Without the mask, every
   later line is misattributed to `tmstat`. That was observed on the first run
   and fixed before any number in this report was taken.
6. The scratchpad scripts are reproduced in the Appendix rather than committed
   as files, because the allow-list is this report alone.
7. G1 was not run. The prompt's Definition of Done says it is not required.

## Open questions

1. Should `sg` (236) keep shadowing `/usr/bin/sg`? Should the `rg` wrapper
   function (969) stay, given that AGENTS.md §4 tells agents to use `rg` in their
   shells, where they get the wrapper's `--hidden` and echo too?
2. `ebn-lab-start` (1387) installs a global `cleanup` function and `trap … EXIT`
   in the interactive shell that runs it, so the trap fires when that terminal
   exits. That is a behaviour fix, outside this stage's scope.
3. `.aliases` is sourced twice per Guix Home shell (`home/common.scm:1104` and
   `.zshrc.starship:66`). It is harmless today (measured), but every load-time
   side effect runs twice, and a reorder stage should know it.
4. `s.a` with both private files present re-sources only one of them (Q3).
5. Whether to run Option 1 or Option 2 is the user's call. Option 2 changes
   which definition wins for private names. No Makefile, AGENTS.md or
   `docs/language.md` lines are needed for either option: no target or
   user-typed name changes. Deleting `alias g=grep` (38) removes a spelling
   nobody can reach today, because 1311 already overrides it.

## Appendix — the measurement scripts (verbatim)

Run from the worktree as `python3 -I SCRATCH/<script> …` or `zsh -f SCRATCH/<script> …`.

### `defs.py`

```python
"""Extract definitions from a zsh config file: kind, name, line, section, enclosing
top-level conditional, enclosing function.  Usage: defs.py FILE [--sections]"""
import re, sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")

RULE = re.compile(r'^\s*#\s*(-{20,}|#{20,})\s*$|^\s*#{20,}\s*$')
FUNC = re.compile(r'^\s*(?:function\s+)?([A-Za-z_][\w.:+-]*)\s*\(\)\s*\{|^\s*function\s+([A-Za-z_][\w.:+-]*)\s*\{')
ALIAS = re.compile(r"""^\s*(?:\[\[.*\]\]\s*&&\s*)?alias\s+(-g\s+)?(?:'([^']+)'|"([^"]+)"|([^=\s]+))=""")
EXPORT = re.compile(r'^\s*export\s+([A-Za-z_]\w*)=')
UNDEF = re.compile(r'^\s*(?:\(\(.*\)\)\s*&&\s*)?(unalias|unset -f|unfunction)\s+(.*?)(\s+2>/dev/null)?\s*$')


def open_quote(s):
    """Return the quote char left open at end of line s, else None."""
    q = None
    k = 0
    while k < len(s):
        c = s[k]
        if q is None:
            if c == '\\':
                k += 2
                continue
            if c == '#' and (k == 0 or s[k - 1] in ' \t'):
                break
            if c in "'\"":
                q = c
        elif q == "'" and c == "'":
            q = None
        elif q == '"':
            if c == '\\':
                k += 2
                continue
            if c == '"':
                q = None
        k += 1
    return q


# mask heredoc bodies and multi-line quoted strings
masked = [False] * len(lines)
# --mask A-B: hand-verified string bodies the quote counter cannot follow
# (e.g. a single-quoted program that embeds '\'' escapes)
manual = [a for a in sys.argv[2:] if re.match(r'^\d+-\d+$', a)]
manual_lines = set()
for spec in manual:
    a, b = map(int, spec.split('-'))
    manual_lines.update(range(a, b + 1))
i = 0
while i < len(lines):
    l = lines[i]
    if i + 1 in manual_lines:
        masked[i] = True
        i += 1
        continue
    if l.lstrip().startswith('#'):
        i += 1
        continue
    m = re.search(r"<<-?\s*'?(\w+)'?", l)
    if m and '<<<' not in l:
        tag = m.group(1)
        j = i + 1
        while j < len(lines) and lines[j].strip() != tag:
            masked[j] = True
            j += 1
        i = j + 1
        continue
    q = open_quote(l)
    if q:
        j = i + 1
        while j < len(lines):
            masked[j] = True
            if lines[j].count(q) % 2 == 1:
                break
            j += 1
        i = j + 1
        continue
    i += 1

# section banners: a comment line right after a rule line
sections = []
for n, l in enumerate(lines):
    if RULE.match(l) and n + 1 < len(lines):
        nxt = lines[n + 1]
        if nxt.strip().startswith('#') and not RULE.match(nxt) and nxt.strip() != '#':
            closing_rule = n >= 2 and RULE.match(lines[n - 2]) and not RULE.match(lines[n - 1])
            if not closing_rule:
                sections.append((n + 2, nxt.strip('# ').strip(), len(l) - len(l.lstrip())))


def section_of(ln):
    cur = '(preamble)'
    for s_ln, title, _ in sections:
        if s_ln <= ln:
            cur = title
    return cur


func_stack = []
cond_stack = []
residue = []
out = []
for n, l in enumerate(lines):
    ln = n + 1
    if masked[n]:
        continue
    s = l.strip()
    ind = len(l) - len(l.lstrip())
    if s.startswith('#') or not s:
        continue
    infunc = func_stack[-1][0] if func_stack else ''
    ctx = ' > '.join(f"{k}@{c_ln}" for k, c_ln, _, f in cond_stack if not f)
    fm = FUNC.match(l)
    if fm:
        name = fm.group(1) or fm.group(2)
        out.append(('function', name, ln, section_of(ln), ctx, infunc))
        if not re.search(r'\}\s*(#.*)?$', s):
            func_stack.append((name, ind))
        continue
    if func_stack and s == '}' and ind == func_stack[-1][1]:
        func_stack.pop()
        continue
    am = ALIAS.match(l)
    if am:
        name = am.group(2) or am.group(3) or am.group(4)
        out.append(('global-alias' if am.group(1) else 'alias', name, ln, section_of(ln), ctx, infunc))
    em = EXPORT.match(l)
    if em:
        out.append(('export', em.group(1), ln, section_of(ln), ctx, infunc))
    um = UNDEF.match(l)
    if um:
        out.append((um.group(1).replace(' ', ''), um.group(2), ln, section_of(ln), ctx, infunc))
    if not func_stack and not (fm or am or em or um) and '--residue' in sys.argv:
        if not re.match(r'(if|elif|else|fi|case|esac|then)\b|\}$', s):
            residue.append(f"{ln}\t{s}")
    w = re.match(r'(if|case|elif|else|fi|esac)\b', s)
    if w:
        k = w.group(1)
        if k in ('if', 'case') and not re.search(r'\b(fi|esac)\s*(#.*)?$', s):
            cond_stack.append((k, ln, ind, bool(func_stack)))
        elif k in ('fi', 'esac') and cond_stack:
            cond_stack.pop()

if '--residue' in sys.argv:
    print('\n'.join(residue))
elif '--sections' in sys.argv:
    for s_ln, title, lvl in sections:
        print(f"{s_ln}\t{'  ' if lvl else ''}{title}")
else:
    for row in out:
        print('\t'.join(str(x) for x in row))
```

### `order.py`

```python
"""Per section and per kind, find definitions that break ascending order.

Reads the TSV from defs.py on stdin.  Order key: name.lower(), plain code-point
comparison (so '-' < '.' < digits < '_' < letters, and ',' sorts first).
A definition is "out of order" when it is not in a longest non-decreasing
subsequence of its (section, kind) group: the minimum set of lines that would
have to move for the group to be sorted.  For each, prints the in-order
neighbour it belongs after (or before, if it sorts first).
Usage: order.py [--kinds alias,function,...] < defs.tsv
"""
import sys
from bisect import bisect_right
from collections import OrderedDict

kinds = None
for a in sys.argv[1:]:
    if a.startswith('--kinds='):
        kinds = set(a.split('=', 1)[1].split(','))

groups = OrderedDict()
for row in sys.stdin:
    kind, name, ln, section, ctx, infunc = row.rstrip('\n').split('\t')
    if infunc:
        continue  # defined at run time by another function, not at load time
    if kinds and kind not in kinds:
        continue
    groups.setdefault((section, kind), []).append((name, int(ln)))


def lnds(keys):
    """Indices of one longest non-decreasing subsequence."""
    tails, tails_idx, prev = [], [], [-1] * len(keys)
    for i, k in enumerate(keys):
        p = bisect_right(tails, k)
        if p == len(tails):
            tails.append(k); tails_idx.append(i)
        else:
            tails[p] = k; tails_idx[p] = i
        prev[i] = tails_idx[p - 1] if p else -1
    out, i = [], tails_idx[-1] if tails_idx else -1
    while i != -1:
        out.append(i); i = prev[i]
    return set(out)


total = 0
for (section, kind), items in groups.items():
    keys = [n.lower() for n, _ in items]
    keep = lnds(keys)
    bad = [i for i in range(len(items)) if i not in keep]
    print(f"## {section} / {kind}: {len(items)} defs, {len(bad)} out of order")
    total += len(bad)
    kept = sorted(((keys[i], items[i]) for i in keep))
    for i in bad:
        name, ln = items[i]
        before = [it for k, it in kept if k <= keys[i]]
        after = [it for k, it in kept if k > keys[i]]
        if before:
            where = f"after {before[-1][0]} (line {before[-1][1]})"
        else:
            where = f"before {after[0][0]} (line {after[0][1]})"
        print(f"  line {ln}: {name}  -> belongs {where}")
print(f"TOTAL out of order: {total}")
```

### `dups.py`

```python
"""Names defined more than once in .aliases, and names .aliases shares with
other shell files.  Usage: dups.py WORKTREE"""
import subprocess, sys
from collections import defaultdict

wt = sys.argv[1]
here = __file__.rsplit('/', 1)[0]


def defs(path, extra=()):
    out = subprocess.run([sys.executable, '-I', f'{here}/defs.py', f'{wt}/{path}', *extra],
                         capture_output=True, text=True, check=True).stdout
    rows = []
    for r in out.splitlines():
        kind, name, ln, section, ctx, infunc = r.split('\t')
        if kind.startswith('un'):
            continue
        for n in name.split():
            rows.append((kind, n, int(ln), ctx, infunc))
    return rows


mine = defs('.aliases', ['500-516'])
by = defaultdict(list)
for kind, n, ln, ctx, infunc in mine:
    if kind == 'export':
        continue
    by[n].append((kind, ln, ctx or '-', infunc or '-'))
print('# within .aliases (alias / global-alias / function)')
for n, v in sorted(by.items(), key=lambda kv: kv[1][0][1]):
    if len(v) > 1:
        print(n, '|', '; '.join(f'{k}@{ln} ctx={c} in={f}' for k, ln, c, f in v))

print('\n# shared with other files')
for other in ['.shared.zshrc', '.zshrc', '.jobs.zsh', '.agent-jobs.zsh']:
    for kind, n, ln, ctx, infunc in defs(other):
        if kind == 'export':
            continue
        if n in by:
            print(f'{other}:{ln} {kind} {n} (in={infunc or "-"}) <-> .aliases',
                  '; '.join(f'{k}@{l}' for k, l, _, _ in by[n]))
```

### `load.zsh`

```zsh
# Load .aliases the way the shells do, in a throwaway HOME, and dump what wins.
# Usage: zsh -f load.zsh WORKTREE OUTDIR
# Order simulated (Guix Home): source ~/.aliases (generated line), source
# ~/.aliases again (.zshrc.starship:66), then .shared.zshrc.  ~/dot_files is a
# symlink to the worktree so .jobs.zsh/.agent-jobs.zsh are sourced too.
wt=$1 out=$2
fakehome=$(mktemp -d)
ln -s "$wt" "$fakehome/dot_files"
ln -s "$wt/.aliases" "$fakehome/.aliases"
export HOME=$fakehome
typeset -A before_f; for n in ${(k)functions}; do before_f[$n]=1; done

print -r -- "== first source ==" >&2
source ~/.aliases; print -r -- "first source exit=$?" >&2
print -l ${(ok)aliases} > $out/aliases.after1
print -l ${(ok)galiases} > $out/galiases.after1
print -l ${(ok)functions} > $out/functions.after1
for n in ${(ok)aliases}; do print -r -- "$n=${aliases[$n]}"; done > $out/alias-values.after1

print -r -- "== second source (Guix Home double source) ==" >&2
source ~/.aliases; print -r -- "second source exit=$?" >&2

print -r -- "== .shared.zshrc ==" >&2
add_to_end_of_path() { : }
source "$wt/.shared.zshrc" >/dev/null; print -r -- "shared exit=$?" >&2
print -l ${(ok)aliases} > $out/aliases.final
print -l ${(ok)galiases} > $out/galiases.final
print -l ${(ok)functions} > $out/functions.final
for n in ${(ok)aliases}; do print -r -- "$n=${aliases[$n]}"; done > $out/alias-values.final

# names that are both an alias and a function
for n in ${(ok)aliases}; do (( $+functions[$n] )) && print -r -- "alias+function: $n  whence: $(whence -w $n)"; done > $out/alias-and-function
# names that shadow a command on PATH (only meaningful for this host)
for n in ${(ok)aliases} ${(ok)functions}; do
  [[ $n == _* ]] && continue
  p=${commands[$n]}; [[ -n $p ]] && print -r -- "$n shadows $p"
done | sort -u > $out/shadows-path
print -r -- "s.a=${aliases[s.a]}" > $out/s.a
print -r -- "g=${aliases[g]}" >> $out/s.a
print -r -- "venv_map created: $([[ -f $HOME/.venv_map ]] && print yes || print no)" >&2
command rm -rf -- "$fakehome"
```

### `overlap.zsh`

```zsh
# Runtime overlap: names .aliases defines by itself vs names .jobs.zsh +
# .agent-jobs.zsh define by themselves.  Usage: zsh -f overlap.zsh WORKTREE
wt=$1
fakehome=$(mktemp -d)
export HOME=$fakehome
base=( ${(k)functions} ${(k)aliases} )
# .aliases alone: no ~/dot_files, so its two job-file sources are skipped
own=( $(zsh -f -c 'source "$1" >/dev/null 2>&1; print -l ${(k)functions} ${(k)aliases} ${(k)galiases}' _ "$wt/.aliases") )
jobs=( $(zsh -f -c 'source "$1" >/dev/null 2>&1; source "$2" >/dev/null 2>&1; print -l ${(k)functions} ${(k)aliases}' _ "$wt/.jobs.zsh" "$wt/.agent-jobs.zsh") )
print -r -- ".aliases alone: ${#own} names; job files alone: ${#jobs} names"
print -r -- "overlap:"
print -l ${own:*jobs}
# zsh -f defines no functions itself; anything in both is a real collision
command rm -rf -- "$fakehome"
```

### `blocks.py`

```python
"""Lines that move under the full regroup: blocks of .aliases (current line
ranges) mapped to a target section rank.  Blocks in a longest non-decreasing
run of ranks stay; every other block moves.  Prints the moved blocks and
the total moved lines."""
from bisect import bisect_right

# (first, last, target rank, target section)
BLOCKS = [
    (1, 12, 0, 'A header'),
    (13, 43, 1, 'B general aliases'),
    (44, 196, 2, 'C myrepos'),
    (197, 253, 1, 'B general aliases'),
    (254, 269, 3, 'D general functions'),
    (270, 290, 4, 'E Guix and containers'),
    (291, 385, 4, 'E Guix and containers'),
    (386, 423, 5, 'F console / VT'),
    (424, 437, 6, 'G remote hosts'),
    (438, 457, 6, 'G remote hosts'),
    (458, 477, 7, 'H gpg'),
    (478, 541, 9, 'J OS specific'),
    (542, 545, 4, 'E Guix and containers'),
    (546, 558, 12, 'M late: private'),
    (559, 569, 12, 'M late: home'),
    (570, 623, 3, 'D general functions'),
    (624, 639, 3, 'D general functions'),
    (640, 645, 12, 'M late: work'),
    (646, 763, 9, 'J2 cloud notes (comment only)'),
    (764, 1288, 10, 'K zsh-only'),
    (1289, 1381, 10, 'K2 git (after zsh-only)'),
    (1382, 1405, 6, 'G remote hosts'),
    (1406, 1414, 13, 'N job files (last)'),
    (1415, 1416, 14, 'O LocalWords'),
]

ranks = [b[2] for b in BLOCKS]
tails, tails_idx, prev = [], [], [-1] * len(ranks)
for i, r in enumerate(ranks):
    p = bisect_right(tails, r)
    if p == len(tails):
        tails.append(r); tails_idx.append(i)
    else:
        tails[p] = r; tails_idx[p] = i
    prev[i] = tails_idx[p - 1] if p else -1
keep, i = set(), tails_idx[-1]
while i != -1:
    keep.add(i); i = prev[i]
# the LIS is not unique; prefer keeping the larger blocks, so report the one
# that maximises kept lines via a simple weighted DP instead
n = len(BLOCKS)
w = [b[1] - b[0] + 1 for b in BLOCKS]
best = w[:]
par = [-1] * n
for j in range(n):
    for k in range(j):
        if ranks[k] <= ranks[j] and best[k] + w[j] > best[j]:
            best[j] = best[k] + w[j]; par[j] = k
j = max(range(n), key=lambda x: best[x])
keep = set()
while j != -1:
    keep.add(j); j = par[j]
moved = 0
for idx, (a, b, r, name) in enumerate(BLOCKS):
    mark = 'stay' if idx in keep else 'MOVE'
    if idx not in keep:
        moved += b - a + 1
    print(f"{mark}  {a:4}-{b:<4} ({b - a + 1:3} lines) -> {name}")
print(f"total lines {BLOCKS[-1][1]}, moved {moved}")
```

### One-liners

```sh
# TSV used by Q2/Q5 (tmstat program masked by hand)
python3 -I defs.py WORKTREE/.aliases 500-516 > aliases.tsv
# re-bound the zsh guard's subsections (Deviation 4)
awk -F'\t' 'BEGIN{OFS="\t"} $3>=769 && $3<=1038 {$4="Zsh Aliases (769-1038, incl. unterminated Re-source banner)"} $3>=1155 && $3<=1191 {$4="Zsh Aliases tail (1155-1191, after PYTHON closing rule)"} {print}' aliases.tsv > aliases2.tsv
python3 -I order.py < aliases2.tsv
# Git verb contiguity (Q2)
sed -n '1311,1381p' .aliases | awk -F"'" '/^alias/{split($1,a,"[ =]"); split($2,w," "); v=w[2]; if(w[1]!="git")v=w[1]; if(v=="log-compact")v="log"; print NR+1310, a[2], v}' | awk '{ if($3!=last){ if(seen[$3]) print "REOPEN: verb " $3 " resumes at line " $1 " (" $2 "), last run ended line " endl[$3]; seen[$3]=1; last=$3} endl[$3]=$1 }'
# zsh-guard counts (Q5)
awk -F'\t' '$3>=769 && $3<=1288 && $6=="" {c[$1]++} END{for(k in c) print k, c[k]}' aliases.tsv
# backup alias value (Q4): lines 496-497 plus a probe, run with zsh -f
sed -n 496,497p .aliases > backup-alias.zsh
echo 'print -r -- "value=[${aliases[backup]}]"; eval backup; print -r -- "exit=$?"' >> backup-alias.zsh
zsh -f -c 'setopt no_interactive_comments; source "$1"' _ backup-alias.zsh
```
