import os
import requests
import json
import datetime
from google import genai
from google.genai import types

# Ensure you have your API key set: export GEMINI_API_KEY="your-key"
# Install SDK: pip install google-genai requests

# ==========================================
# 1. Define the Tools Gemini can use
# ==========================================
def get_agent_status() -> str:
    """Fetches the current status of all background agents, including live sessions and blocked questions."""
    try:
        response = requests.get("http://localhost:8642/status")
        return response.text
    except Exception as e:
        return json.dumps({"error": str(e)})

def unblock_agent(job_name: str, answer: str) -> str:
    """Submits the user's answer to unblock a specific job that has a blocked_question."""
    try:
        response = requests.post(
            f"http://localhost:8642/inbox/{job_name}",
            json={"answer": answer}
        )
        return response.text
    except Exception as e:
        return json.dumps({"error": str(e)})

# ==========================================
# 2. Setup the Gemini Agent
# ==========================================
def main():
    if "GEMINI_API_KEY" not in os.environ:
        print("Error: GEMINI_API_KEY environment variable not set.")
        return

    client = genai.Client()
    
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %I:%M %p")

    system_instruction = f"""
    You are a voice-optimized assistant managing autonomous background developer agents.
    The current time is {current_time}.
    
    RULES:
    1. Keep responses conversational and concise (as if speaking out loud).
    2. When the user asks for an update, call `get_agent_status`.
    3. PRIORITY: If the status shows any `blocked_question`, immediately tell the user which job is blocked and read the question. Ask them what to do.
    4. If there are no blockers, summarize the top 3 most important updates from the job `outbox`es, numbering them 1, 2, 3.
    5. When the user provides an answer to a blocker, call `unblock_agent` with the job name and their answer. Then confirm to the user that the job has been resumed.
    """

    # We use Gemini 3.6 Flash as it's the fastest and best for conversational/tool-calling loops
    chat = client.chats.create(
        model="gemini-3.6-flash",
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
            temperature=0.7,
            tools=[get_agent_status, unblock_agent],
        )
    )

    print("🤖 Gemini Agent Ready! (Type 'quit' to exit)")
    print("Try asking: 'Can I get a status update on the agents?'")
    print("-" * 50)

    # 3. Simple CLI Loop (Can be swapped with a voice capture UI later)
    while True:
        user_input = input("\nYou: ")
        if user_input.lower() in ['quit', 'exit']:
            break
            
        print("Gemini is thinking (and potentially checking tools)...")
        response = chat.send_message(user_input)
        print(f"\n🗣️ Gemini: {response.text}")

if __name__ == "__main__":
    main()
