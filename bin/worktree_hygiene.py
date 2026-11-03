"""Abandoned-worktree report for mr-hygiene.

Classifies linked worktrees and prints paste-ready cleanup commands.
It never deletes a worktree, a branch, or a remote-tracking ref.

A worktree is reported only when its tip is at least IDLE_DAYS old, or
when its directory is already gone.  Envelope checkouts under
~/Repos/enveloped/e* and each repo's main worktree are skipped.
"""

from __future__ import annotations

import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess

IDLE_DAYS = 3
STAMP_HOURS = 24

CLASSES_READY = ("prune", "remove", "remove-force")


def git(cwd: Path, *args: str, timeout: int = 15) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", str(cwd), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(["git", *args], 1, "", "timed out")


def stamp_due(stamp: Path, hours: int = STAMP_HOURS, now: datetime.datetime | None = None) -> bool:
    if not stamp.exists():
        return True
    moment = now or datetime.datetime.now(datetime.timezone.utc)
    age = moment.timestamp() - stamp.stat().st_mtime
    return age >= hours * 3600


def is_envelope_worktree(path: Path, envelope_root: Path) -> bool:
    """True for a live envelope checkout: ~/Repos/enveloped/e<branch>."""
    try:
        resolved = path.resolve()
        root = envelope_root.resolve()
    except OSError:
        return False
    return resolved.parent == root and resolved.name.startswith("e") and len(resolved.name) > 1


def git_common_dir(path: Path) -> str | None:
    res = git(path, "rev-parse", "--git-common-dir")
    if res.returncode != 0:
        return None
    raw = res.stdout.strip()
    if not raw:
        return None
    common = Path(raw)
    if not common.is_absolute():
        common = path / common
    try:
        return str(common.resolve())
    except OSError:
        return str(common)


def submodule_paths(repo: Path) -> list[Path]:
    res = git(repo, "submodule", "foreach", "--recursive", "--quiet", 'echo "$toplevel/$sm_path"')
    if res.returncode != 0:
        return []
    return [Path(line.strip()) for line in res.stdout.splitlines() if line.strip()]


def repo_units(paths: list[str]) -> list[Path]:
    """mr repos plus their submodules, one path per git common dir."""
    seen: set[str] = set()
    units: list[Path] = []

    def add(path: Path) -> None:
        if not path.exists():
            return
        key = git_common_dir(path)
        if not key or key in seen:
            return
        seen.add(key)
        units.append(path)

    for raw in paths:
        repo = Path(raw)
        add(repo)
        for child in submodule_paths(repo):
            add(child)
    return units


def parse_worktrees(text: str) -> list[dict]:
    items: list[dict] = []
    current: dict | None = None
    for line in text.splitlines():
        if line.startswith("worktree "):
            if current is not None:
                items.append(current)
            current = {
                "path": line[len("worktree "):],
                "head": "",
                "branch": "",
                "detached": False,
                "prunable": False,
                "locked": False,
            }
            continue
        if current is None:
            continue
        if line.startswith("HEAD "):
            current["head"] = line[len("HEAD "):]
        elif line.startswith("branch "):
            ref = line[len("branch "):]
            prefix = "refs/heads/"
            current["branch"] = ref[len(prefix):] if ref.startswith(prefix) else ref
        elif line == "detached":
            current["detached"] = True
        elif line.startswith("prunable"):
            current["prunable"] = True
        elif line.startswith("locked"):
            current["locked"] = True
    if current is not None:
        items.append(current)
    return items


def idle_days(day: str, today: datetime.date) -> int | None:
    if not day:
        return None
    try:
        committed = datetime.date.fromisoformat(day)
    except ValueError:
        return None
    return max(0, (today - committed).days)


def classify(prunable: bool, missing: bool, locked: bool, idle: int | None,
             dirty: int, stashes: int, how: str | None) -> str:
    if prunable or missing:
        return "prune"
    if idle is not None and idle < IDLE_DAYS:
        return "active"
    if locked:
        return "review"
    clean = dirty == 0 and stashes == 0
    if clean and how == "ancestor":
        return "remove"
    if clean and how in ("patch", "contained"):
        return "remove-force"
    return "review"


def _ref_exists(repo: Path, ref: str) -> bool:
    return git(repo, "rev-parse", "--verify", "--quiet", ref).returncode == 0


def landing_targets(repo: Path, own: str, candidates: set[str]) -> list[str]:
    """Default branch, its upstream, and local branches that are not candidates."""
    refs: list[str] = []

    def add(ref: str) -> None:
        ref = ref.strip()
        if ref and ref not in refs and ref != own:
            refs.append(ref)

    origin_head = git(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if origin_head.returncode == 0:
        add(origin_head.stdout)
    for name in ("main", "master"):
        if _ref_exists(repo, name):
            add(name)
            break
    if own:
        upstream = git(repo, "rev-parse", "--abbrev-ref", f"{own}@{{upstream}}")
        if upstream.returncode == 0:
            add(upstream.stdout)
    local = git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads")
    if local.returncode == 0:
        for name in local.stdout.splitlines():
            if name.strip() and name.strip() not in candidates:
                add(name)
    return refs


def _is_ancestor(repo: Path, rev: str, target: str) -> bool:
    if not rev or not target or rev == target:
        return False
    return git(repo, "merge-base", "--is-ancestor", rev, target).returncode == 0


def _is_patch_equivalent(repo: Path, branch: str, target: str) -> bool:
    if not branch or not target or branch == target:
        return False
    res = git(repo, "cherry", target, branch)
    if res.returncode != 0:
        return False
    return not any(line.startswith("+") for line in res.stdout.splitlines())


def _contained_in(repo: Path, head: str, own: str, candidates: set[str]) -> str | None:
    res = git(repo, "branch", "-a", "--contains", head)
    if res.returncode == 0:
        for line in res.stdout.splitlines():
            # "* " is the current branch, "+ " is checked out in another worktree.
            if line.startswith("* ") or line.startswith("+ "):
                name = line[2:].strip()
            else:
                name = line.strip()
            if " -> " in name:
                name = name.split(" -> ", 1)[0].strip()
            if name.startswith("remotes/"):
                name = name[len("remotes/"):]
            local = name.split("/", 1)[-1] if name.startswith("origin/") else name
            if not name or name == own or local == own:
                continue
            if local in candidates and not name.startswith("origin/"):
                continue
            return name
    subject = git(repo, "log", "-1", "--format=%s", head).stdout.strip()
    # Short subjects ("fix", "wip") match unrelated commits.
    if len(subject) < 20:
        return None
    log = git(repo, "log", "--all", "--format=%H%x09%s")
    if log.returncode != 0:
        return None
    for line in log.stdout.splitlines():
        if "\t" not in line:
            continue
        sha, text = line.split("\t", 1)
        if text == subject and sha != head:
            return sha[:8]
    return None


def landed(repo: Path, entry: dict, candidates: set[str]) -> tuple[str | None, str | None]:
    own = entry["branch"]
    rev = own or entry["head"]
    targets = landing_targets(repo, own, candidates)
    for target in targets:
        if _is_ancestor(repo, rev, target):
            return "ancestor", target
    if own:
        for target in targets:
            if _is_patch_equivalent(repo, own, target):
                return "patch", target
    if entry["detached"] or entry["prunable"] or not own:
        hit = _contained_in(repo, entry["head"], own, candidates)
        if hit:
            return "contained", hit
    return None, None


def _commit_day(repo: Path, rev: str) -> str:
    res = git(repo, "log", "-1", "--format=%cs", rev)
    return res.stdout.strip() if res.returncode == 0 else ""


def _dirty_count(path: Path) -> int:
    res = git(path, "status", "--porcelain")
    if res.returncode != 0:
        return 0
    return sum(1 for line in res.stdout.splitlines() if line.strip())


def _stash_count(path: Path) -> int:
    res = git(path, "stash", "list")
    if res.returncode != 0:
        return 0
    return sum(1 for line in res.stdout.splitlines() if line.strip())


def _unlanded(repo: Path, branch: str, head: str, default: str | None) -> tuple[int, list[str]]:
    if not branch:
        subject = git(repo, "log", "-1", "--format=%s", head or "HEAD").stdout.strip()
        return (1, [subject]) if subject else (0, [])
    if not default:
        res = git(repo, "log", "-5", "--format=%s", branch)
        lines = [line for line in res.stdout.splitlines() if line]
        return len(lines), lines
    count = git(repo, "rev-list", "--count", f"{default}..{branch}")
    try:
        total = int(count.stdout.strip() or "0") if count.returncode == 0 else 0
    except ValueError:
        total = 0
    subjects = git(repo, "log", "-5", "--format=%s", f"{default}..{branch}")
    lines = [line for line in subjects.stdout.splitlines() if line]
    return total, lines


def _default_branch(repo: Path) -> str | None:
    for name in ("main", "master"):
        if _ref_exists(repo, name):
            return name
    return None


def try_fetch(repo: Path) -> str | None:
    """Fetch remotes without pruning.  Return an error string, or None."""
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    try:
        res = subprocess.run(
            ["git", "-C", str(repo), "-c", "fetch.prune=false", "fetch", "--all", "--quiet"],
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return "timed out"
    if res.returncode == 0:
        return None
    err = (res.stderr or res.stdout or "fetch failed").strip().splitlines()
    return (err[0] if err else "fetch failed")[:120]


def _tilde(path: str) -> str:
    home = str(Path.home())
    if path == home:
        return "~"
    prefix = home + "/"
    if path.startswith(prefix):
        return "~/" + path[len(prefix):]
    return path


def scan_unit(unit: Path, today: datetime.date, envelope_root: Path, fetch: bool) -> tuple[list[dict], str | None]:
    listed = git(unit, "worktree", "list", "--porcelain")
    if listed.returncode != 0:
        return [], None
    entries = parse_worktrees(listed.stdout)
    if len(entries) < 2:
        return [], None
    main = entries[0]
    rest = entries[1:]
    failure = try_fetch(unit) if fetch else None
    try:
        main_path = str(Path(main["path"]).resolve())
    except OSError:
        main_path = main["path"]
    candidates = {entry["branch"] for entry in rest if entry["branch"]}
    default = _default_branch(unit)
    findings: list[dict] = []
    for entry in rest:
        raw = entry["path"]
        path = Path(raw)
        if is_envelope_worktree(path, envelope_root):
            continue
        try:
            if str(path.resolve()) == main_path:
                continue
        except OSError:
            pass
        missing = bool(entry["prunable"]) or not path.is_dir()
        where = path if path.is_dir() else unit
        day = ""
        if entry["head"] and not missing:
            day = _commit_day(where, entry["head"])
        idle = idle_days(day, today)
        dirty = 0 if missing else _dirty_count(path)
        stashes = 0 if missing else _stash_count(where)
        recent = idle is not None and idle < IDLE_DAYS and not missing
        how, onto = (None, None)
        if not recent:
            how, onto = landed(unit, entry, candidates)
        kind = classify(bool(entry["prunable"]), missing, bool(entry["locked"]), idle, dirty, stashes, how)
        if kind == "active":
            continue
        count, subjects = (0, [])
        if kind == "review":
            count, subjects = _unlanded(unit, entry["branch"], entry["head"], default)
        findings.append({
            "class": kind,
            "repo": str(unit),
            "path": raw,
            "branch": entry["branch"],
            "detached": bool(entry["detached"]),
            "idle": idle,
            "dirty": dirty,
            "stashes": stashes,
            "locked": bool(entry["locked"]),
            "landed": how,
            "landed_on": onto,
            "unlanded": count,
            "subjects": subjects,
        })
    return findings, failure


def scan(paths: list[str], *, today: datetime.date | None = None, fetch: bool = True,
         envelope_root: Path | None = None) -> dict:
    day = today or datetime.date.today()
    root = envelope_root or (Path.home() / "Repos" / "enveloped")
    findings: list[dict] = []
    failures: list[dict] = []
    for unit in repo_units(paths):
        found, failure = scan_unit(unit, day, root, fetch)
        findings.extend(found)
        if failure:
            failures.append({"repo": _tilde(str(unit)), "error": failure})
    return {"today": day.isoformat(), "findings": findings, "fetch_failures": failures}


def summary_line(findings: list[dict]) -> str | None:
    ready = sum(1 for item in findings if item["class"] in CLASSES_READY)
    review = sum(1 for item in findings if item["class"] == "review")
    if ready == 0 and review == 0:
        return None
    trees = "worktree" if ready == 1 else "worktrees"
    look = "needs" if review == 1 else "need"
    return f"{ready} {trees} ready to clean, {review} {look} a look"


def cleanup_commands(findings: list[dict]) -> list[str]:
    live = {
        (item["repo"], item["branch"])
        for item in findings
        if item["class"] != "prune" and item["branch"]
    }
    lines: list[str] = []
    pruned: set[str] = set()
    for item in findings:
        repo = shlex.quote(item["repo"])
        if item["class"] == "prune":
            if item["repo"] not in pruned:
                lines.append(f"cd {repo} && git worktree prune -v")
                pruned.add(item["repo"])
            branch = item["branch"]
            if not branch or (item["repo"], branch) in live:
                continue
            flag = "-d" if item["landed"] == "ancestor" else "-D" if item["landed"] else ""
            if flag:
                lines.append(f"cd {repo} && git branch {flag} {shlex.quote(branch)}")
        elif item["class"] == "remove" and item["branch"]:
            lines.append(
                f"cd {repo} && git worktree remove {shlex.quote(item['path'])} "
                f"&& git branch -d {shlex.quote(item['branch'])}"
            )
        elif item["class"] == "remove-force":
            removal = f"cd {repo} && git worktree remove {shlex.quote(item['path'])}"
            if item["branch"]:
                removal += f" && git branch -D {shlex.quote(item['branch'])}"
            lines.append(removal)
    return lines


def _bullet(item: dict) -> str:
    label = item["branch"] or "detached"
    place = f"{_tilde(item['path'])} [{label}]"
    if item["class"] == "prune":
        return f"- {place} directory missing"
    if item["class"] == "remove":
        idle = item["idle"] if item["idle"] is not None else "?"
        return f"- {place} clean, idle {idle}d"
    if item["class"] == "remove-force":
        onto = item["landed_on"] or "another branch"
        return f"- {place} -> landed on {onto}"
    bits = []
    if item["locked"]:
        bits.append("locked")
    if item["dirty"]:
        bits.append(f"{item['dirty']} dirty file" + ("s" if item["dirty"] != 1 else ""))
    if item["stashes"]:
        bits.append(f"{item['stashes']} stash" + ("es" if item["stashes"] != 1 else ""))
    if item["unlanded"]:
        bits.append(f"{item['unlanded']} unlanded commit" + ("s" if item["unlanded"] != 1 else ""))
    idle = item["idle"] if item["idle"] is not None else "?"
    bits.append(f"idle {idle}d")
    line = f"- {place} " + ", ".join(bits)
    for subject in item["subjects"]:
        line += f"\n  - {subject}"
    return line


def render(report: dict, *, fetched: bool = True) -> str:
    findings = report["findings"]
    today = report["today"]
    groups = {
        "remove": [item for item in findings if item["class"] == "remove"],
        "remove-force": [item for item in findings if item["class"] == "remove-force"],
        "prune": [item for item in findings if item["class"] == "prune"],
        "review": [item for item in findings if item["class"] == "review"],
    }
    if report["fetch_failures"]:
        failed = "; ".join(
            f"{item['repo']} ({item['error']})" for item in report["fetch_failures"]
        )
        remote = f"Remote refs as of last fetch; fetch failed for: {failed}."
    elif fetched:
        remote = "Remote refs as of last fetch."
    else:
        remote = "Remote refs as of last fetch (fetch not run)."
    lines = [
        f"## Worktrees to review — {today}",
        "",
        remote,
        "",
        "This report does not delete anything.",
        "",
    ]
    sections = (
        ("remove", "Safe (ancestor-merged)"),
        ("remove-force", "Patch-equivalent (needs -D)"),
        ("prune", "Directory gone"),
        ("review", "Needs a look"),
    )
    for key, title in sections:
        rows = groups[key]
        if not rows:
            continue
        lines.append(f"### {title} — {len(rows)}")
        lines.append("")
        lines.extend(_bullet(item) for item in rows)
        lines.append("")
    if not any(groups.values()):
        lines.append("No abandoned worktrees.")
        lines.append("")
    commands = cleanup_commands(findings)
    if commands:
        lines.append("<details><summary>Paste to clean up the safe and patch-equivalent ones</summary>")
        lines.append("")
        lines.append("```sh")
        lines.extend(commands)
        lines.append("```")
        lines.append("")
        lines.append("</details>")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def loose_ends_item(findings: list[dict]) -> str | None:
    line = summary_line(findings)
    if line is None:
        return None
    return f"**Repo Hygiene (Worktrees):** {line}"


def read_cache(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict) or "markdown" not in data:
        return None
    return data


def write_cache(cache: Path, stamp: Path, report: dict, *, fetched: bool) -> dict:
    markdown = render(report, fetched=fetched)
    item = loose_ends_item(report["findings"])
    payload = {
        "scanned": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "today": report["today"],
        "summary": summary_line(report["findings"]),
        "item": item,
        "ready": sum(1 for item in report["findings"] if item["class"] in CLASSES_READY),
        "review": sum(1 for item in report["findings"] if item["class"] == "review"),
        "markdown": markdown,
    }
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = cache.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(cache)
    stamp.write_text(payload["scanned"] + "\n", encoding="utf-8")
    return payload
