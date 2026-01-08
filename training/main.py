import ollama
import json
import requests

def response(prompt):
    with requests.post(
                "http://localhost:11434/api/generate",
                json={
                    "model": "mistral",
                    "prompt": prompt,
                    "stream": True},
                stream=True,       
            ) as response:
                for line in response.iter_lines():
                    if line:
                        try:
                            data = line.decode("utf-8")
                            if data.startswith("data: "):
                                data = data[6:]  # remove "data: "
                            if data.strip() == "[DONE]":
                                break
                            # Each chunk is JSON containing part of the response
                            json_data = json.loads(data)
                            if "response" in json_data:
                                yield json_data["response"]
                        except Exception as e:
                            print("Stream error:", e)

def save_conversation(conversation):
    with open("conversation.json", "w") as f:
        json.dump(conversation, f, indent=4)


