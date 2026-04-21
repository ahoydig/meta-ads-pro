#!/usr/bin/env python3
"""telemetry_log.py — append telemetry entry as JSON line.

Uso: python3 telemetry_log.py <event_name> [key=value]*
Env: TELEMETRY_FILE (default ~/.claude/meta-ads-pro/telemetry.jsonl)
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("usage: telemetry_log.py <event> [key=val]*", file=sys.stderr)
        sys.exit(2)
    event = sys.argv[1]
    kv = {}
    for arg in sys.argv[2:]:
        if "=" in arg:
            k, v = arg.split("=", 1)
            kv[k] = v
    entry = {
        "ts": datetime.now(timezone.utc).astimezone().isoformat(),
        "event": event,
        **kv,
    }
    out = os.environ.get(
        "TELEMETRY_FILE",
        os.path.expanduser("~/.claude/meta-ads-pro/telemetry.jsonl"),
    )
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    with open(out, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
