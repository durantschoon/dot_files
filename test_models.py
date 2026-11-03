import os
from google import genai
client = genai.Client()
for m in client.models.list():
    print(m.name, getattr(m, "supported_generation_methods", []))
