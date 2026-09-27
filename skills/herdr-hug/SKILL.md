---
name: herdr-hug
description: Reach out to a sibling agy process in another tmux session with a friendly hug message. Use when the user asks for herdr-hug or asks to greet or contact a sibling agent through tmux; prefer the sender's model family and working directory.
---

# Herdr Hug

Discover a sibling agent, identify its model family from its terminal UI, and send one friendly message. Defining or editing this workflow does not itself request a live hug.

## Workflow

1. **Discover sibling sessions.** Run:

   ```sh
   tmux ls
   ```

   Exclude your own session. When `TMUX_PANE` is available, identify it with:

   ```sh
   tmux display-message -p -t "$TMUX_PANE" '#{session_name}'
   ```

   If tmux has no running server or no sibling sessions, report that and stop.

2. **Inspect candidates and prefer your model family.** For each plausible sibling, substitute its actual name for `SESSION_NAME`:

   ```sh
   tmux capture-pane -p -t 'SESSION_NAME' -S -100
   ```

   Inspect the agent application's status bar or footer in the captured pane:

   - Codex commonly shows context information such as `Context 62% left`.
   - Gemini variants commonly show a model name such as `Gemini 3.1 Pro` at the bottom right.

   These are identification clues, not guaranteed strings. A session name alone is not enough to identify its model family. Prefer your own family: Codex to Codex, Gemini to Gemini, Claude to Claude. For other families, use visible model or application identification rather than guessing from a missing Codex or Gemini cue.

   Honor a recipient explicitly named by the user. Otherwise, prefer confirmed same-family siblings in your current working directory, then same-family siblings elsewhere. Compare `pwd` with the candidate pane's `pane_current_path` from the command below; a session name does not establish its directory. If no same-family sibling is available, choose another clearly identified agent that fits the request. Respect any directory or family restriction in the user's request. If no suitable agent can be identified, report that and stop.

3. **Confirm the recipient pane.** Ensure the selected pane contains the intended agent's input prompt before typing. If a session has multiple windows or panes, locate the agent with:

   ```sh
   tmux list-panes -s -t 'SESSION_NAME' -F '#{pane_id} #{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}'
   ```

   Capture the relevant pane using its `%N` pane ID as the target, then use that same ID for sending. Avoid submitting text into a shell, a confirmation dialog, or an existing unfinished draft. If the prompt is unavailable, stop and report that the hug has not been sent.

4. **Send the hug once.** Use the user's message when provided; otherwise send a short greeting identifying your actual model family and source session when known. For example, when the sender is Codex:

   ```sh
   tmux send-keys -t 'SESSION_NAME' 'Hey from your Codex sibling in another tmux session! Sending a herdr-hug. Hope your work is going well.' C-m
   ```

   `C-m` submits the message. Shell-quote the session name and message safely; substitute the verified pane ID when targeting a specific pane. Do not broadcast to every candidate.

   Capture the target again to check whether the message appears. Report the recipient and message sent, distinguishing visible submission from an actual reply. If delivery is uncertain, report that uncertainty instead of sending duplicates.
