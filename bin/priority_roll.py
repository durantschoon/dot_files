#!/usr/bin/env python3
from __future__ import annotations

import difflib
import os
from pathlib import Path
import re
import sys

ROOT = Path.cwd()
MD_GLOB = "*.md"

P1_PATTERN = re.compile(r"#P1\b")
SHIFT_PATTERN = re.compile(r"#P([234])\b")
PRIORITY_TAG_PATTERN = re.compile(r"#P(\d+)\b")

_ANSI_RESET = "\033[0m"


def _ansi_for_priority(level: int) -> str:
    if level == 1:
        return "\033[41;97;1m"
    if level == 2:
        return "\033[43;30;1m"
    if level == 3:
        return "\033[42;30;1m"
    if level == 4:
        return "\033[44;97;1m"
    return "\033[45;97;1m"


def _stdout_color_enabled() -> bool:
    if os.environ.get("NO_COLOR"):
        return False
    return sys.stdout.isatty()


def highlight_priority_tags(text: str) -> str:
    if not _stdout_color_enabled():
        return text

    def repl(m: re.Match[str]) -> str:
        level = int(m.group(1))
        return f"{_ansi_for_priority(level)}{m.group(0)}{_ANSI_RESET}"

    return PRIORITY_TAG_PATTERN.sub(repl, text)


def find_p1_hits(root: Path) -> list[tuple[Path, int, str]]:
    """
    Find occurrences of '#P1' in .md files under the given root directory.

    Parameters:
        root (Path): Path to search for Markdown files.

    Returns:
        list[tuple[Path, int, str]]:
            A list of tuples containing the file path, line number, and line content
            for each line that contains '#P1'.

    Example:
        If the directory 'my_docs' contains 'example.md' with these lines:
            1. This is a feature request
            2. #P1 Needs urgent attention
            3. #P2 Nice to have

        find_p1_hits(Path('my_docs')) will return:
            [
                (Path('my_docs/example.md'), 2, '#P1 Needs urgent attention')
            ]
    """
    hits: list[tuple[Path, int, str]] = []

    for path in root.rglob(MD_GLOB):
        try:
            text = path.read_text(encoding="utf-8")
        except Exception as e:
            print(f"Skipping unreadable file: {path} ({e})", file=sys.stderr)
            continue

        for lineno, line in enumerate[str](text.splitlines(), start=1):
            if P1_PATTERN.search(line):
                hits.append((path, lineno, line))

    return hits


def show_diff(path: Path, original: str, updated: str) -> None:
    diff = difflib.unified_diff(
        original.splitlines(keepends=True),
        updated.splitlines(keepends=True),
        fromfile=str(path),
        tofile=str(path),
        lineterm="",
    )
    for line in diff:
        if line.startswith("---") or line.startswith("+++"):
            continue
        print(highlight_priority_tags(line), end="")


def shift_priorities(root: Path) -> int:
    changed_files = 0

    for path in root.rglob(MD_GLOB):
        try:
            original = path.read_text(encoding="utf-8")
        except Exception as e:
            print(f"Skipping unreadable file: {path} ({e})", file=sys.stderr)
            continue

        updated = SHIFT_PATTERN.sub(lambda m: f"#P{int(m.group(1)) - 1}", original)

        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed_files += 1
            print(highlight_priority_tags(f"Updated: {path}"))
            show_diff(path, original, updated)

    return changed_files


def main() -> int:
    hits = find_p1_hits(ROOT)

    if hits:
        print(highlight_priority_tags(f"Found existing #P1 entries under {ROOT}. No changes made.\n"))
        for path, lineno, line in hits:
            print(highlight_priority_tags(f"{path}:{lineno}: {line}"))
        return 1

    changed_files = shift_priorities(ROOT)
    print(highlight_priority_tags(f"\nDone. Updated {changed_files} file(s) under {ROOT}."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
