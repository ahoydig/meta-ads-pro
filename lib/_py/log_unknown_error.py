#!/usr/bin/env python3
"""log_unknown_error.py — appenda entry em unknown_errors.jsonl.

Lê response JSON da stdin (ou ignora se vazio).
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--code", required=True, type=int)
    p.add_argument("--subcode", default="")
    p.add_argument("--path", default="")
    p.add_argument("--output", required=True)
    args = p.parse_args()

    raw = sys.stdin.read().strip()
    try:
        response = json.loads(raw) if raw else None
    except json.JSONDecodeError:
        response = {"raw": raw[:2000]}  # trunca se não parseable

    entry = {
        "timestamp": datetime.now(timezone.utc).astimezone().isoformat(),
        "code": args.code,
        "subcode": args.subcode or None,
        "path": args.path,
        "response": response,
        "confirmed_by_human": False,
        "occurrences": 1,
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    # Dedup: se já existe entry com mesmo code+subcode+path, incrementa occurrences
    lines = []
    merged = False
    if out.exists():
        with open(out, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.strip()
                if not stripped:
                    continue  # ignora linhas vazias
                try:
                    e = json.loads(stripped)
                    if (e.get("code") == entry["code"]
                            and e.get("subcode") == entry["subcode"]
                            and e.get("path") == entry["path"]
                            and not e.get("confirmed_by_human")):
                        e["occurrences"] = e.get("occurrences", 1) + 1
                        e["timestamp"] = entry["timestamp"]
                        merged = True
                        lines.append(json.dumps(e, ensure_ascii=False))
                    else:
                        lines.append(stripped)
                except json.JSONDecodeError:
                    lines.append(stripped)

    if not merged:
        lines.append(json.dumps(entry, ensure_ascii=False))

    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
