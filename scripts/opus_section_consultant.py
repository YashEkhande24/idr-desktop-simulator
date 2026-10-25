import requests
import json
import sys

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"
URL = "https://api.silvrai.net/v1/chat/completions"

def query_opus(section_name, prompt, output_file, max_tokens=3000):
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "model": "claude-opus-5-5",
        "max_tokens": max_tokens,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are Claude Opus 5.5, an elite principal robotics, INS, and aerospace guidance engineer.\n"
                    "We are building the genuine physics simulation engine for an ISRO SIH Dead-Reckoning browser simulator.\n"
                    "Provide mathematically exact, production-grade JavaScript code that runs inside a 60 FPS requestAnimationFrame loop (dt=0.01s).\n"
                    "Focus on physical fidelity, numerical stability, seamless looping, and realistic MEMS drift."
                )
            },
            {
                "role": "user",
                "content": f"### TASK: {section_name}\n\n{prompt}"
            }
        ]
    }
    
    print(f"\n[OPUS 5.5] Sending '{section_name}' to Claude Opus 5.5...")
    try:
        r = requests.post(URL, headers=headers, json=payload, timeout=90)
    except Exception as e:
        print(f"Request exception: {e}")
        return None
        
    if not r.ok:
        print(f"Error {r.status_code}: {r.text}")
        return None
        
    data = r.json()
    choices = data.get("choices", [])
    if not choices:
        print("No choices returned:", data)
        return None
        
    msg = choices[0].get("message", {})
    reply_text = msg.get("content", "")
    reasoning = msg.get("reasoning_content")
    
    usage = data.get("usage", {})
    in_tok = usage.get("prompt_tokens", 0)
    out_tok = usage.get("completion_tokens", 0)
    cost = (in_tok * 5.0 / 1e6) + (out_tok * 25.0 / 1e6)
    
    print(f"[OPUS 5.5] Completed. In: {in_tok} tok, Out: {out_tok} tok | Cost: ${cost:.4f}")
    if reasoning:
        print(f"[OPUS 5.5] Internal reasoning captured: {len(reasoning)} chars")
        
    with open(output_file, "w", encoding="utf-8") as f:
        if reasoning:
            f.write(f"<!-- REASONING TRACE:\n{reasoning}\n-->\n\n")
        f.write(reply_text)
        
    print(f"[OPUS 5.5] Saved solution to {output_file}")
    return reply_text

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "test":
        prompt = "Explain why double integration of accelerometer bias b leads to 0.5 * b * t^2 position error."
        query_opus("Test Verification", prompt, "scripts/test_opus_out.md", max_tokens=600)
