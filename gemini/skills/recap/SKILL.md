---
name: recap
description: Summarize the current session, showing the current working directory (CWD), current task, subtask, touched files, and next steps. Use when the user asks for a recap, status update, session catch-up, or runs /recap.
---

# Session Recap

Provide a structured, Claude-style status recap of the current session.

## Instructions

When this skill is invoked (e.g., via `/recap` or when the user asks for a recap, status update, or catch-up):

1. **Inspect Session State:**
   - **Current Working Directory (CWD):** Identify the active working directory (`pwd` or workspace root).
   - **Task & Subtask:** Review the conversation turns, goals, and active work to identify:
     - **Current Task:** The primary overarching goal, problem, or feature being worked on.
     - **Current Subtask:** The immediate active subtask, function, test, or subagent currently running or being edited (or "Ready for next instruction" if none).
   - **Repository & Workspace Status:** Check `git status -s` (if inside a git repository) or review recent file edits/creations in this session.
   - **Recent Accomplishments:** Review actions completed in recent turns.

2. **Output Format:**
   Output the recap using the following clean Markdown format:

   ### 📍 Session Context
   - **CWD:** `<current_working_directory>`
   - **Current Task:** <High-level goal or problem being solved>
   - **Current Subtask:** <Active subtask/step in progress, or "Ready for next instruction">

   ---

   ### 📋 Progress & Status
   - **✅ What Was Done:**
     - <Key completed item 1>
     - <Key completed item 2>
   - **📁 Files Touched:**
     - [<relative_path>](file://<absolute_path>) — <brief summary of change>
   - **🚧 In Progress / Pending:**
     - <Any uncommitted changes, failing tests, or pending decisions, or "None">
   - **👉 Next Steps:**
     1. <Immediate next action 1>
     2. <Next action 2>

3. **Style Guidelines:**
   - Keep it concise, high-signal, and easy to scan.
   - Always include clickable markdown links for touched files (`file:///absolute/path`).
   - If no files were touched or no active subtask exists, explicitly state "None".
