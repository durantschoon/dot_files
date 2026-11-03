---
name: herdr-notify
description: Notifies the user via the Herdr UI when you are stuck, need attention, or finish a long-running task.
---

# Herdr Notifications

When you need to alert the user, ask for their attention, report a blocker (like a merge conflict), or notify them that a long-running background task has completed, do not just print it to the terminal. Instead, proactively push a notification to the Herdr UI.

## Command

Use the `herdr` CLI to trigger a notification:

```bash
herdr notification show "<Short Title>" --body "<Detailed message explaining what you need>"
```

**Examples:**
*   `herdr notification show "Merge Conflict" --body "I hit a conflict in main.py. Please review."`
*   `herdr notification show "Task Complete" --body "The model training loop has finished."`

**Flags available:**
*   `--position <top-left|top-right|bottom-left|bottom-right>`
*   `--sound <none|done|request>` (Use `request` if you need the user's attention to proceed, use `done` if you are just reporting completion).

Do not wait for another agent to relay this for you. You have direct access to the `herdr` CLI.
