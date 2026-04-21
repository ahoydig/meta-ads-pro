#!/usr/bin/env python3
"""manifest.py — gerencia manifest transacional de runs meta-ads-pro.

Uso:
  python3 manifest.py init --file X.json --run-id RID --account ACCT
  python3 manifest.py add --file X.json --type campaign --id 123
  python3 manifest.py list --file X.json      # TSV priority\ttype\tid
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

PRIORITY = {
    "ad": 1,
    "adcreative": 2,
    "dark_post": 2,
    "adimage": 3,
    "adset": 4,
    "campaign": 5,
    "leadgen_form": 6,
}


def cmd_init(args):
    m = {
        "run_id": args.run_id,
        "ad_account_id": args.account,
        "started_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "created": [],
        "status": "in_progress",
        "failed_step": None,
    }
    Path(args.file).parent.mkdir(parents=True, exist_ok=True)
    with open(args.file, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2, ensure_ascii=False)


def cmd_add(args):
    with open(args.file, "r", encoding="utf-8") as f:
        m = json.load(f)
    m["created"].append({
        "type": args.type,
        "id": args.id,
        "created_at": datetime.now(timezone.utc).astimezone().isoformat(),
    })
    with open(args.file, "w", encoding="utf-8") as f:
        json.dump(m, f, indent=2, ensure_ascii=False)


def cmd_list(args):
    with open(args.file, "r", encoding="utf-8") as f:
        m = json.load(f)
    objs = m.get("created", [])
    with_p = [(PRIORITY.get(o["type"], 99), o["type"], o["id"]) for o in objs]
    with_p.sort(key=lambda x: x[0])
    for p, t, i in with_p:
        print(f"{p}\t{t}\t{i}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init")
    p_init.add_argument("--file", required=True)
    p_init.add_argument("--run-id", required=True)
    p_init.add_argument("--account", required=True)
    p_init.set_defaults(func=cmd_init)

    p_add = sub.add_parser("add")
    p_add.add_argument("--file", required=True)
    p_add.add_argument("--type", required=True)
    p_add.add_argument("--id", required=True)
    p_add.set_defaults(func=cmd_add)

    p_list = sub.add_parser("list")
    p_list.add_argument("--file", required=True)
    p_list.set_defaults(func=cmd_list)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
