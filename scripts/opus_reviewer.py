import requests
import json
import sys

API_KEY = "sk-silvr-7b3d7fea700d2f9fe30d837408a2a2592b828dd26db4d1665ec990122d6600d4"
URL = "https://api.silvrai.net/v1/chat/completions"

def review_section(section_name, code_snippet, context_and_task, max_tokens=1500):
    system_prompt = (
        "You are Claude Opus 5.5, an elite principal engineer and robotics/INS specialist.\n"
        "Review the provided simulation code section for our ISRO SIH dead reckoning web simulator.\n"
        "Be concise, highly concrete, and provide exact math equations and JavaScript fixes.\n"
        "Focus on: physics stability, continuous geometry, realistic MEMS bias drift, and robust numerical integration."
    )
    
    user_prompt = (
        f"### SECTION TO REVIEW: {section_name}\n\n"
        f"**Context & Issues to Solve:**\n{context_and_task}\n\n"
        f"**Current Code:**\n```javascript\n{code_snippet}\n```\n\n"
        "Please provide:\n"
        "1. Concrete critique of the mathematical/physics flaws.\n"
        "2. Exact corrected JavaScript code snippet for this section."
    )
    
    payload = {
        "model": "claude-opus-5-5",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "max_tokens": max_tokens
    }
    
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    print(f"\n[OPUS 5.5] Sending {section_name} to Claude Opus 5.5...")
    r = requests.post(URL, headers=headers, json=payload, timeout=60)
    if not r.ok:
        print(f"Error {r.status_code}: {r.text}")
        return None
        
    data = r.json()
    reply = data["choices"][0]["message"]["content"]
    usage = data.get("usage", {})
    in_tok = usage.get("prompt_tokens", 0)
    out_tok = usage.get("completion_tokens", 0)
    cost = (in_tok * 4.0 / 1e6) + (out_tok * 20.0 / 1e6)
    
    print(f"[OPUS 5.5] Completed. In: {in_tok} tok, Out: {out_tok} tok | Cost: ${cost:.5f}")
    return reply

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print("Opus Reviewer ready.")
