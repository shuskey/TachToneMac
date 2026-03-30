#!/usr/bin/env python3
"""
token_coins.py — Claude Code Stop hook
Reads the session transcript, computes cost for the most recent turn,
maps it to 1–10 coins, and sends "coins:N" to TachTone on UDP 9876.

Installed to ~/.claude/token_coins.py by install.sh.
"""
import json
import sys
import socket

# ---------------------------------------------------------------------------
# Pricing (per million tokens, USD)
# ---------------------------------------------------------------------------
PRICING = {
    "sonnet": {"input": 3.00,  "output": 15.00},
    "opus":   {"input": 15.00, "output": 75.00},
    "haiku":  {"input": 0.80,  "output":  4.00},
}

# ---------------------------------------------------------------------------
# Cost → coin count thresholds (1 = cheapest, 10 = most expensive)
# ---------------------------------------------------------------------------
THRESHOLDS = [0.010, 0.025, 0.050, 0.080, 0.120, 0.180, 0.270, 0.400, 0.600]
#             1→2    2→3    3→4    4→5    5→6    6→7    7→8    8→9    9→10


def model_rates(model_id: str) -> tuple[float, float]:
    m = (model_id or "").lower()
    if "opus"   in m: key = "opus"
    elif "haiku" in m: key = "haiku"
    else:              key = "sonnet"   # default / sonnet[1m]
    p = PRICING[key]
    return p["input"], p["output"]


def cost_to_coins(cost_usd: float) -> int:
    for i, threshold in enumerate(THRESHOLDS):
        if cost_usd < threshold:
            return i + 1
    return 10


def parse_turn_usage(transcript_path: str) -> tuple[int, int]:
    """
    Walk the transcript JSONL from the bottom up, summing usage from all
    assistant entries until we cross a human/user turn boundary.
    Returns (total_input_tokens, total_output_tokens) for the current turn.
    """
    try:
        with open(transcript_path, "r") as f:
            lines = f.readlines()
    except (OSError, IOError):
        return 0, 0

    input_tokens     = 0
    output_tokens    = 0
    passed_assistant = False

    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        role = entry.get("role") or entry.get("type") or ""
        if "message" in entry and isinstance(entry["message"], dict):
            msg   = entry["message"]
            role  = role or msg.get("role", "")
            usage = msg.get("usage", {})
        else:
            usage = entry.get("usage", {})

        if role == "assistant":
            inp = usage.get("input_tokens", 0)
            out = usage.get("output_tokens", 0)
            if inp or out:
                input_tokens  += inp
                output_tokens += out
                passed_assistant = True
        elif role in ("user", "human") and passed_assistant:
            break

    return input_tokens, output_tokens


def send_udp(message: str, host: str = "127.0.0.1", port: int = 9876) -> None:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.sendto(message.encode(), (host, port))
    s.close()


def main() -> None:
    try:
        payload = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, EOFError):
        payload = {}

    transcript_path = payload.get("transcript_path", "")
    model_id        = payload.get("model", "")

    input_tok, output_tok = parse_turn_usage(transcript_path)

    if input_tok == 0 and output_tok == 0:
        coins = 1
    else:
        in_rate, out_rate = model_rates(model_id)
        cost  = (input_tok * in_rate + output_tok * out_rate) / 1_000_000
        coins = cost_to_coins(cost)

    send_udp(f"coins:{coins}")


if __name__ == "__main__":
    main()
