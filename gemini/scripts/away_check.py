#!/usr/bin/env python3
import json
import os
import sys
import time

STATE_DIR = os.path.expanduser("~/.gemini/config/state")
os.makedirs(STATE_DIR, exist_ok=True)

# Parse hook input payload from stdin if present
payload = {}
try:
    if not sys.stdin.isatty():
        raw_input = sys.stdin.read()
        if raw_input.strip():
            payload = json.loads(raw_input)
except Exception:
    pass

conversation_id = payload.get("conversationId", "default")
safe_conv_id = "".join(c for c in conversation_id if c.isalnum() or c in ("-", "_")) or "default"
state_file = os.path.join(STATE_DIR, f"last_active_{safe_conv_id}.timestamp")

now = time.time()
away = False
threshold_seconds = 300  # 5 minutes idle threshold

if os.path.exists(state_file):
    try:
        with open(state_file, "r") as f:
            content = f.read().strip()
            if content:
                last_time = float(content)
                if (now - last_time) >= threshold_seconds:
                    away = True
    except Exception:
        pass

# Update last active timestamp
try:
    with open(state_file, "w") as f:
        f.write(str(now))
except Exception:
    pass

output = {}
if away:
    output["injectSteps"] = [
        {
            "ephemeralMessage": (
                "[AWAY SUMMARY] The user has returned after being away for over 5 minutes.\n"
                "Briefly begin your response with a quick catch-up recap before addressing the user prompt:\n"
                "- CWD: <current working directory>\n"
                "- Current Task: <high-level task in progress>\n"
                "- Current Subtask: <active subtask in progress, if applicable>\n"
                "- Brief 1-2 sentence recap of where things were left off and what was next."
            )
        }
    ]

print(json.dumps(output))
