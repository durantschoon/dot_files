# Handoff to the geeeks session: highlight instead of A/B/C

From: Claude session `a74036d6` in orb-guix (minius), 2026-11-20(F).
For: `claude --resume 031f6229-b2d9-48b2-8f0a-e031748d5288` on geeeks
(stack `docs/problem-stack/geeeks.md` in media-announce, entry `[1]`).
Delete this file once `[1]` is rewritten.

## Decision (user's, recorded as `decided`)

media-announce `docs/DECISIONS.md`, entry "Problem stacks get a
user-only highlight, not importance levels" (commit `76ecbb7`). It
supersedes the A/B/C proposal in `[1]` and answers both of its open
design points.

- **No `[#A]/[#B]/[#C]` levels.** Priority stays in
  `docs/PRIORITY-TARGETS.org`; copying levels into the stack could drift
  from it.
- **An optional highlight field instead:**
  `- Highlighted: YYYY-MM-DD (by durant)`.
  A field line, not a mark on the `#### [N]` heading, so renumbering
  never disturbs it.
- **Only the user sets or clears it** ("highlight [N]", "unhighlight [N]").
  Agents never add or remove one on their own.
- **Sticky** until he removes it or the entry is popped. A popped entry
  keeps the line in `## Resolved` as history.
- **`prob-tree` opens with a Highlighted block**, gathered across every
  machine and session, and still shows each entry in its usual place.
- **Unhighlighted entries render exactly as today.** Nothing is hidden,
  so there is no default level to choose.

The case that motivated it: the `/data` switchover sat at `[10]` while it
was his top concern, because `[N]` is LIFO order.

## What to do

1. Rewrite stack `[1]` around the highlight. Set `Blocked on: nothing`.
2. In `claude/skills/prob-push/SKILL.md`:
   - add the optional `Highlighted:` line to the push template, with the
     user-only rule;
   - add highlight and unhighlight as operations (find the entry by `[N]`
     or title, add or remove the line, commit);
   - in `prob-tree`, render a **Highlighted** block first, across all
     `docs/problem-stack/*.md`, before the per-machine trees;
   - in `prob-pop`, keep the `Highlighted:` line in the resolved entry.
3. Update `docs/problem-stack/README.md` in media-announce to match.
4. Add a `docs/language.md` row if the vocabulary changes.
5. Pop `[1]` with the commit hashes, then delete this file.
