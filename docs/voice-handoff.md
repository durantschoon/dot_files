# Voice Integration Handoff

## Current State
We are building a Voice Integration for the `tmux-dash` job runner system, allowing the user to interact with their background agents using Gemini over the phone.

- **Worktree**: `/Users/durant/dot_files_voice`
- **Branch**: `gemini-voice` (synced with `main` to get the latest `.jobs.zsh` paths).

## Architecture
We've successfully moved past the mock stage and are wired into the real system:
1. **`voice_server.py`**: A Python server running on **port 8642** (`VOIC`).
   - `GET /status`: Executes `_tmux_pick_lines --all` to get the live list of background jobs. It extracts the absolute path for each job, then checks those paths for an `extranotes` file (which indicates a blocker/question) and a `logs/<job>.outbox` file (for status updates).
   - `POST /inbox/<job_name>`: Receives JSON `{"answer": "..."}` and writes it directly to the real job directory as `inbox`.
2. **`gemini_agent.py`**: A CLI tool that acts as the Gemini brain using `google-genai` and `gemini-3.6-flash`. It has native tool calling equipped with `get_agent_status` and `unblock_agent` to orchestrate the conversation.

## Next Steps
The system is ready to be tested against real jobs!
- When you run a real job, have it write a question to its local `extranotes` file.
- Start `voice_server.py` (if not already running).
- Run `python3 gemini_agent.py` and ask for an update. Gemini should natively detect the `extranotes`, read the question, and wait for your answer.
- **Future Polish**: Upgrade `gemini_agent.py` from a CLI text loop to either a Gradio Web UI or the Gemini Multimodal Live API (WebSockets) for true voice-to-voice streaming.

## Context for Next Agent
The user is restarting the session with the `agy --dangerously-skip-permissions` flag so you can execute commands freely. Start by checking if `voice_server.py` is running on `8642`, and ask the user if they'd like to test the live integration or build the voice UI!
