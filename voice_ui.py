import os
import requests
import json
import datetime
import gradio as gr
from google import genai
from google.genai import types

# Define the Tools
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

client = genai.Client()
chat_session = None

def init_chat():
    global chat_session
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

    chat_session = client.chats.create(
        model="gemini-3.6-flash",
        config=types.GenerateContentConfig(
            system_instruction=system_instruction,
            temperature=0.7,
            tools=[get_agent_status, unblock_agent],
        )
    )

def process_input(text, audio, history):
    global chat_session
    if chat_session is None:
        init_chat()

    message = []
    
    if audio:
        # Upload the recorded audio file to Gemini
        audio_file = client.files.upload(file=audio)
        message.append(audio_file)
        
    if text:
        message.append(text)

    if not message:
        return "", None, history

    # We append the user message to the UI history
    display_msg = text if text else "🎤 (Audio Message)"
    history.append({"role": "user", "content": display_msg})
    
    try:
        # Send to Gemini (which natively understands audio + text and can call tools)
        response = chat_session.send_message(message)
        history.append({"role": "assistant", "content": response.text})
    except Exception as e:
        history.append({"role": "assistant", "content": f"Error: {str(e)}"})

    return "", None, history # Clear text and audio inputs

# Build the Gradio UI
with gr.Blocks(title="Tmux-Dash Voice Assistant") as demo:
    gr.Markdown("# 🤖 Tmux-Dash Voice Assistant")
    
    chatbot = gr.Chatbot(height=500)
    
    with gr.Row():
        audio_in = gr.Audio(sources=["microphone"], type="filepath", label="Speak to Gemini")
    with gr.Row():
        text_in = gr.Textbox(placeholder="Or type your message here...", container=False, scale=4)
        submit_btn = gr.Button("Send", scale=1)

    # Bind actions
    submit_btn.click(process_input, inputs=[text_in, audio_in, chatbot], outputs=[text_in, audio_in, chatbot])
    text_in.submit(process_input, inputs=[text_in, audio_in, chatbot], outputs=[text_in, audio_in, chatbot])

if __name__ == "__main__":
    init_chat()
    print("Starting Gradio Voice UI...")
    # Launching with share=True creates a public URL you can instantly open on your phone!
    demo.launch(server_port=7860, share=True, theme=gr.themes.Soft())
