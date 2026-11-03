import json
import requests
import asyncio
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from google import genai
from google.genai import types

app = FastAPI()
client = genai.Client()

def get_agent_status() -> str:
    try:
        response = requests.get("http://localhost:8642/status")
        return response.text
    except Exception as e:
        return json.dumps({"error": str(e)})

def unblock_agent(job_name: str, answer: str) -> str:
    try:
        response = requests.post(f"http://localhost:8642/inbox/{job_name}", json={"answer": answer})
        return response.text
    except Exception as e:
        return json.dumps({"error": str(e)})

@app.get("/")
async def get():
    with open("driving_index.html", "r") as f:
        return HTMLResponse(f.read())

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    
    config = types.LiveConnectConfig(
        system_instruction=types.Content(parts=[types.Part.from_text(text="""
        You are a voice-optimized assistant managing autonomous background developer agents.
        You are currently talking to the user while they are driving. 
        Keep responses concise, conversational, and completely hands-free.
        IMPORTANT: The first thing you hear will be a system ping. You MUST immediately reply with an audio greeting (e.g. "I'm online and listening, ready when you are").
        1. When asked for an update, call `get_agent_status`.
        2. If the status shows a `blocked_question`, alert the user and read it. Wait for their answer.
        3. When they answer, call `unblock_agent`.
        """)]),
        response_modalities=["AUDIO"],
        tools=[get_agent_status, unblock_agent]
    )
    
    try:
        async with client.aio.live.connect(model="gemini-3.8-live", config=config) as gemini_session:
            print("Connected to Gemini Live API!")
            
            # Send an initial ping to wake up the assistant before starting the audio stream
            await gemini_session.send(input="Hello! I'm in the car now. Can you confirm you are listening?", end_of_turn=True)
            print("Sent wake-up ping to Gemini...")
            
            async def receive_from_browser():
                try:
                    while True:
                        data = await websocket.receive_bytes()
                        print(f"Received {len(data)} bytes from Mic")
                        await gemini_session.send(input={"data": data, "mime_type": "audio/pcm;rate=16000"})
                except WebSocketDisconnect:
                    print("Browser disconnected")

            async def receive_from_gemini():
                print("Waiting for messages from Gemini...")
                async for msg in gemini_session.receive():
                    if msg.server_content and msg.server_content.model_turn:
                        for part in msg.server_content.model_turn.parts:
                            if part.inline_data:
                                print(f"Received {len(part.inline_data.data)} bytes of audio from Gemini!")
                                await websocket.send_bytes(part.inline_data.data)
                            if part.text:
                                print(f"Gemini text: {part.text}")
                    elif msg.tool_call:
                        print("Gemini requested a tool call:", msg.tool_call)
                        responses = []
                        for call in msg.tool_call.function_calls:
                            if call.name == "get_agent_status":
                                res = get_agent_status()
                                responses.append(types.FunctionResponse(name=call.name, id=call.id, response={"result": res}))
                            elif call.name == "unblock_agent":
                                args = call.args
                                res = unblock_agent(args.get("job_name", ""), args.get("answer", ""))
                                responses.append(types.FunctionResponse(name=call.name, id=call.id, response={"result": res}))
                        
                        if responses:
                            print("Sending tool response back to Gemini...")
                            await gemini_session.send(input={"tool_responses": responses})
                    else:
                        print("Received other message type from Gemini:", msg)

            await asyncio.gather(receive_from_browser(), receive_from_gemini())
            
    except Exception as e:
        print("Session Error:", e)
        try:
            await websocket.close()
        except:
            pass
