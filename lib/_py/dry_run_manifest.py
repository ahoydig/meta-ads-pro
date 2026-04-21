#!/usr/bin/env python3
"""dry_run_manifest.py — append ghost entry em dry-runs/.

Usado por lib/graph_api.sh quando META_ADS_DRY_RUN=1 e método != GET.
Grava JSONL (1 entry por linha) em ~/.claude/meta-ads-pro/dry-runs/YYYYMMDD-HHMMSS.jsonl
(ou em $DRY_RUN_DIR se setado — útil pra testes).

Uso:
  python3 dry_run_manifest.py --method POST --path act_X/campaigns \\
    --body '{"name":"test"}' --ghost-id DRY_RUN_1234_567

Exit codes:
  0 — sucesso
  1 — erro I/O
  2 — uso inválido
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def _default_dir() -> Path:
    return Path(
        os.environ.get(
            "DRY_RUN_DIR",
            os.path.expanduser("~/.claude/meta-ads-pro/dry-runs"),
        )
    )


def _parse_body(raw: str):
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        # body pode ser form-encoded ou string crua — guarda como string
        return raw


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--method", required=True)
    p.add_argument("--path", required=True)
    p.add_argument("--body", default="")
    p.add_argument("--ghost-id", required=True)
    args = p.parse_args()

    out_dir = _default_dir()
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        print(f"dry_run_manifest: mkdir fail — {e}", file=sys.stderr)
        return 1

    now = datetime.now(timezone.utc).astimezone()
    out_file = out_dir / f"{now.strftime('%Y%m%d-%H%M%S')}.jsonl"

    entry = {
        "ts": now.isoformat(),
        "ghost_id": args.ghost_id,
        "method": args.method,
        "path": args.path,
        "body": _parse_body(args.body),
    }

    try:
        with open(out_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"dry_run_manifest: write fail — {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
