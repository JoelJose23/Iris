from fastapi import FastAPI
from fastapi.responses import StreamingResponse, JSONResponse
from pydantic import BaseModel
from typing import List
import ollama
import os
import json
import hashlib
import logging
import threading
import time
from contextlib import asynccontextmanager


# =========================================================
# App & Directories
# =========================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global stop_event, background_memory_thread
    stop_event = threading.Event()
    update_global_memory_full_scan()
    background_memory_thread = threading.Thread(target=background_memory_update, daemon=True)
    background_memory_thread.start()
    yield
    # Shutdown
    stop_event.set()
    background_memory_thread.join()

app = FastAPI(lifespan=lifespan)

CONV_DIR = "conversations"
MEMORY_DIR = "memory"
GLOBAL_MEMORY_PATH = os.path.join(MEMORY_DIR, "global.json")
CONV_MEMORY_DIR = os.path.join(MEMORY_DIR, "per_conversation")

os.makedirs(CONV_DIR, exist_ok=True)
os.makedirs(CONV_MEMORY_DIR, exist_ok=True)

if not os.path.exists(GLOBAL_MEMORY_PATH):
    with open(GLOBAL_MEMORY_PATH, "w") as f:
        json.dump({"facts": [], "preferences": {}}, f, indent=2)

# =========================================================
# Logging
# =========================================================

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# =========================================================
# Threading and Locks
# =========================================================

memory_lock = threading.Lock()
stop_event = None
background_memory_thread = None

# =========================================================
# Models
# =========================================================

class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    prompt: str
    conversation: int
    context: str
    messages: List[ChatMessage]

class ConversationCreate(BaseModel):
    title: str

class MemoryUpdate(BaseModel):
    content: str

# =========================================================
# Utility Helpers
# =========================================================

def load_json(path: str, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)

def save_json(path: str, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def conv_path(conv_id: int) -> str:
    return os.path.join(CONV_DIR, f"conv_{conv_id}.json")

def conv_memory_path(conv_id: int) -> str:
    return os.path.join(CONV_MEMORY_DIR, f"conv_{conv_id}.json")

# =========================================================
# Memory Helpers
# =========================================================

def load_global_memory():
    return load_json(GLOBAL_MEMORY_PATH, {
        "facts": [],
        "preferences": {}
    })

import requests

OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

def ollama_generate(prompt, model="llama3"):
    res = requests.post(
        OLLAMA_URL,
        json={
            "model": model,
            "prompt": prompt,
            "stream": False
        },
        timeout=30
    )
    res.raise_for_status()
    return res.json()["response"].strip()


def load_conv_memory(conv_id: int):
    return load_json(conv_memory_path(conv_id), {
        "summary": "",
        "notes": []
    })

def update_conv_memory(conv_id: int, messages: List[ChatMessage], conv_memory_data: dict = None):
    logging.info(f"Updating conversation memory for conv_{conv_id}")
    prompt = [
        {
            "role": "system",
            "content": "Summarize the key facts, user goals, and important decisions from the entire conversation. The summary should be a single, concise paragraph."
        },
        {
            "role": "user",
            "content": json.dumps([m.dict() for m in messages])
        }
    ]

    result = ollama.chat(
        model="mistral",
        messages=prompt
    )

    memory = conv_memory_data if conv_memory_data is not None else load_conv_memory(conv_id)
    memory["summary"] = result["message"]["content"]

    with memory_lock:
        save_json(conv_memory_path(conv_id), memory)
    logging.info(f"Finished updating conversation memory for conv_{conv_id}")


def update_global_memory_full_scan():
    logging.info("Rebuilding global memory from all conversations.")

    all_facts = set()
    all_preferences = {}

    for conv_file in os.listdir(CONV_DIR):
        if not conv_file.startswith("conv_") or not conv_file.endswith(".json"):
            continue

        conv_data = load_json(os.path.join(CONV_DIR, conv_file), None)
        if not conv_data or not conv_data.get("messages"):
            continue

        prompt = [
            {
                "role": "system",
                "content": """
Analyze the conversation and extract user facts and preferences.
Return JSON ONLY:
{
  "facts": [string],
  "preferences": { key: value }
}
If none, return empty structures.
"""
            },
            {
                "role": "user",
                "content": json.dumps(conv_data["messages"])
            }
        ]

        try:
            result = ollama.chat(
                model="mistral",
                messages=prompt,
                format="json"
            )

            extracted = json.loads(result["message"]["content"])

            for fact in extracted.get("facts", []):
                all_facts.add(fact)

            for k, v in extracted.get("preferences", {}).items():
                all_preferences[k] = v

        except Exception as e:
            logging.error(f"Memory extraction failed for {conv_file}: {e}")

    with memory_lock:
        save_json(GLOBAL_MEMORY_PATH, {
            "facts": sorted(all_facts),
            "preferences": all_preferences
        })

    logging.info("Global memory rebuild complete.")

def background_memory_update():
    logging.info("Background memory updater started.")
    last_snapshot = snapshot_directory()
    while not stop_event.is_set():
        try:
            if not memory_lock.locked():
                current_snapshot = snapshot_directory()
                diff = diff_snapshots(last_snapshot, current_snapshot)

                changed_conv_files = []
                # Combine added and modified files for global memory update
                changed_conv_files.extend(diff["added"])
                changed_conv_files.extend(diff["modified"])
                
                if changed_conv_files:
                    logging.info(f"Detected changes in conversations: {changed_conv_files}")
                    # Update global memory only with changed conversations
                    
                    # Update per-conversation summaries for modified/added conversations
                    for conv_file in changed_conv_files:
                        if stop_event.is_set():
                            break # Exit if stop event is set during processing
                        
                        try:
                            conv_id = int(conv_file.split("_")[1].split(".")[0])
                            conv_data = load_json(os.path.join(CONV_DIR, conv_file), {})
                            if conv_data.get("messages"):
                                conv_memory_data = load_json(conv_memory_path(conv_id), {
                                    "summary": "",
                                    "notes": []
                                })
                                update_conv_memory(conv_id, [ChatMessage(**msg) for msg in conv_data["messages"]], conv_memory_data)
                                time.sleep(1) # Small delay to distribute workload
                        except (ValueError, IndexError) as e:
                            logging.error(f"Could not process {conv_file}: {e}")
                        except Exception as e:
                            logging.error(f"An unexpected error occurred while processing {conv_file}: {e}")

                last_snapshot = current_snapshot

        except Exception as e:
            logging.error(f"Error in background memory update loop: {e}")
        
        # Wait for a while before the next run, or until the stop event is set
        stop_event.wait(60) # Check for changes every 60 seconds
    logging.info("Background memory updater stopped.")

# =========================================================
# Filesystem Tracking
# =========================================================

def file_hash(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.md5(f.read()).hexdigest()

def snapshot_directory() -> dict:
    snap = {}
    for f in os.listdir(CONV_DIR):
        path = os.path.join(CONV_DIR, f)
        if os.path.isfile(path):
            snap[f] = {
                "hash": file_hash(path),
                "size": os.path.getsize(path)
            }
    return snap

def diff_snapshots(old: dict, new: dict) -> dict:
    return {
        "added": list(new.keys() - old.keys()),
        "removed": list(old.keys() - new.keys()),
        "modified": [
            k for k in old.keys() & new.keys()
            if old[k]["hash"] != new[k]["hash"]
        ]
    }

# =========================================================
# Ollama Streaming
# =========================================================

def ollama_stream(messages: List[dict]):
    response = ollama.chat(
        model="mistral",
        messages=messages,
        stream=True
    )
    for chunk in response:
        if "message" in chunk and "content" in chunk["message"]:
            yield chunk["message"]["content"]

# =========================================================
# Core Helpers
# =========================================================

def next_conversation_id() -> int:
    ids = []
    for f in os.listdir(CONV_DIR):
        if f.startswith("conv_"):
            try:
                ids.append(int(f.split("_")[1].split(".")[0]))
            except:
                pass
    return max(ids) + 1 if ids else 0

def save_conversation(data: ChatRequest):
    path = conv_path(data.conversation)
    old_data = load_json(path, {})
    old_dir = old_data.get("directory", {})

    new_dir = snapshot_directory()

    save_json(path, {
        "conversation": data.conversation,
        "context": data.context,
        "messages": [m.dict() for m in data.messages],
        "directory": new_dir,
        "directory_diff": diff_snapshots(old_dir, new_dir)
    })
def generate_title_and_summary(messages: list[dict]):
    prompt = [
        {
            "role": "system",
            "content": """
You are an assistant that creates conversation metadata.

Return STRICT JSON with:
- title: 3–6 words, no punctuation
- summary: one concise paragraph summarizing user goals, facts, and decisions

Do NOT add explanations.
"""
        },
        {
            "role": "user",
            "content": json.dumps(messages)
        }
    ]

    result = ollama.chat(
        model="mistral",
        messages=prompt,
        format="json"
    )

    data = json.loads(result["message"]["content"])

    return {
        "title": data.get("title", "New Conversation"),
        "summary": data.get("summary", "")
    }




# =========================================================
# Endpoints
# =========================================================

from fastapi import BackgroundTasks

@app.post("/chat")
async def chat(data: ChatRequest, background_tasks: BackgroundTasks):
    # Load memory safely
    with memory_lock:
        global_mem = load_global_memory()
        conv_mem = load_conv_memory(data.conversation)

    system_prompt = {
        "role": "system",
        "content": f"""
You are Iris.

Global memory:
{json.dumps(global_mem, indent=2)}

Conversation memory:
{json.dumps(conv_mem, indent=2)}

You have access to past conversation context internally.
Use it to guide your responses, but do NOT repeat it verbatim to the user.
"""
    }

    messages = [system_prompt] + [m.dict() for m in data.messages] + [{"role": "user", "content": data.prompt}]

    full_response = ""

    # After streaming finishes, memory update happens here
    def update_memory_later():
        # Append assistant reply
        data.messages.append(ChatMessage(role="assistant", content=full_response))

        path = conv_path(data.conversation)
        conv_data = load_json(path, {})

        try:
            meta = generate_title_and_summary(
                [m.dict() for m in data.messages]
            )
        except Exception as e:
            logging.error(f"Metadata generation failed: {e}")
            meta = {
                "title": conv_data.get("title", "New Conversation"),
                "summary": ""
            }

        # Save conversation
        save_json(path, {
            "conversation": data.conversation,
            "title": meta["title"],
            "context": data.context,
            "messages": [m.dict() for m in data.messages],
            "directory": conv_data.get("directory", {}),
            "directory_diff": conv_data.get("directory_diff", {})
        })

        # Save conversation memory
        with memory_lock:
            save_json(conv_memory_path(data.conversation), {
                "summary": meta["summary"],
                "notes": []
            })

    def stream_gen():
        nonlocal full_response
        for chunk in ollama_stream(messages):
            full_response += chunk
            yield chunk

    # Schedule memory update **after streaming finishes**
    background_tasks.add_task(update_memory_later)

    return StreamingResponse(stream_gen(), media_type="text/plain")

# ---------------- Conversation CRUD ----------------

@app.post("/conversation", status_code=201)
async def create_conversation(payload: ConversationCreate):
    conv_id = next_conversation_id()

    save_json(conv_path(conv_id), {
        "conversation": conv_id,
        "title": payload.title,
        "context": "default",
        "messages": [{
            "role": "assistant",
            "content": f"Hi, I am Iris. This is '{payload.title}'. What are we building today?"
        }],
        "directory": {},
        "directory_diff": {}
    })

    save_json(conv_memory_path(conv_id), {
        "summary": "",
        "notes": []
    })

    return {"id": conv_id, "title": payload.title}

@app.get("/conversations")
async def list_conversations():
    items = []
    for f in sorted(os.listdir(CONV_DIR)):
        with open(os.path.join(CONV_DIR, f)) as fh:
            data = json.load(fh)
        items.append({
            "id": data["conversation"],
            "title": data.get("title", "New Conversation")
        })
    return {"conversations": items}

@app.get("/conversation/{conv_id}")
async def get_conversation(conv_id: int):
    path = conv_path(conv_id)
    if not os.path.exists(path):
        return JSONResponse(status_code=404, content={"error": "Not found"})
    return load_json(path, {})

@app.delete("/conversation/{conv_id}", status_code=204)
async def delete_conversation(conv_id: int):
    with memory_lock:
        for p in [conv_path(conv_id), conv_memory_path(conv_id)]:
            if os.path.exists(p):
                os.remove(p)
    return {}

# ---------------- Memory API ----------------

@app.post("/memory/global")
async def add_global_memory(payload: MemoryUpdate):
    with memory_lock:
        mem = load_global_memory()
        mem["facts"].append(payload.content)
        save_json(GLOBAL_MEMORY_PATH, mem)
    return {"status": "saved"}

@app.post("/memory/conversation/{conv_id}")
async def add_conversation_memory(conv_id: int, payload: MemoryUpdate):
    with memory_lock:
        mem = load_conv_memory(conv_id)
        mem["notes"].append(payload.content)
        save_json(conv_memory_path(conv_id), mem)
    return {"status": "saved"}
