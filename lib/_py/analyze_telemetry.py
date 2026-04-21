#!/usr/bin/env python3
"""analyze_telemetry.py — agrega eventos de ~/.claude/meta-ads-pro/telemetry.jsonl.

Spec §5.6 / Plan Task 3c.4.1. Lê o log JSONL escrito por telemetry_log.py e
reporta em markdown no stdout:

    * Top 5 pares code/subcode em eventos `error_encountered`
    * Ranking de `sub_skill` (eventos com campo `sub_skill`)
    * Taxa de sucesso (`run_completed` vs `run_failed`)
    * Duração média dos eventos com `duration_ms`

Uso:
    python3 analyze_telemetry.py [--days N] [--file PATH]

Exit codes:
    0 — análise gerada (ou arquivo inexistente com mensagem amigável)
    2 — erro de uso (argparse)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEFAULT_LOG = "~/.claude/meta-ads-pro/telemetry.jsonl"


def _parse_ts(raw: str) -> datetime:
    """Tolera ISO8601 com ou sem sufixo 'Z' (Python <3.11 não aceita 'Z')."""
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    dt = datetime.fromisoformat(raw)
    if dt.tzinfo is None:
        # Assume UTC se sem tz — defensivo, não deveria acontecer com telemetry_log.py
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def load_events(path: Path, cutoff: datetime) -> list[dict]:
    """Retorna eventos com `ts >= cutoff`. Linhas inválidas são ignoradas."""
    events: list[dict] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            ts_raw = entry.get("ts")
            if not ts_raw:
                continue
            try:
                ts = _parse_ts(str(ts_raw))
            except ValueError:
                continue
            if ts >= cutoff:
                events.append(entry)
    return events


def render_report(events: list[dict], days: int) -> str:
    """Gera relatório markdown. Pure function — facilita teste."""
    out: list[str] = []
    out.append(f"\n📊 Telemetria — últimos {days} dias ({len(events)} eventos)\n")

    # Top 5 erros (code/subcode)
    err_events = [e for e in events if e.get("event") == "error_encountered"]
    err_counter: Counter[str] = Counter(
        f"{e.get('code', '?')}/{e.get('subcode', '?')}" for e in err_events
    )
    out.append("Top erros:")
    if err_counter:
        for code, count in err_counter.most_common(5):
            out.append(f"  {code}: {count}x")
    else:
        out.append("  (sem erros registrados)")

    # Sub-skills mais usadas
    skill_counter: Counter[str] = Counter(
        e.get("sub_skill", "?") for e in events if e.get("sub_skill")
    )
    out.append("")
    out.append("Sub-skills:")
    if skill_counter:
        for skill, count in skill_counter.most_common():
            out.append(f"  {skill}: {count}x")
    else:
        out.append("  (nenhuma sub-skill reportada)")

    # Taxa de sucesso
    completed = sum(1 for e in events if e.get("event") == "run_completed")
    failed = sum(1 for e in events if e.get("event") == "run_failed")
    total = completed + failed
    out.append("")
    if total > 0:
        rate = 100.0 * completed / total
        out.append(f"Taxa sucesso: {completed}/{total} ({rate:.1f}%)")
    else:
        out.append("Taxa sucesso: sem runs concluídos/falhos no período")

    # Duração média (duration_ms)
    durations: list[int] = []
    for e in events:
        raw = e.get("duration_ms")
        if raw is None or raw == "":
            continue
        try:
            durations.append(int(raw))
        except (TypeError, ValueError):
            continue
    if durations:
        avg_s = sum(durations) / len(durations) / 1000.0
        out.append(f"Duração média: {avg_s:.1f}s (n={len(durations)})")

    return "\n".join(out) + "\n"


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="analyze_telemetry.py",
        description=(
            "Agrega telemetria local do meta-ads-pro: top erros, sub-skills, "
            "taxa de sucesso e duração média."
        ),
    )
    p.add_argument(
        "--days",
        type=int,
        default=30,
        help="Janela de análise em dias (default: 30)",
    )
    p.add_argument(
        "--file",
        default=os.path.expanduser(DEFAULT_LOG),
        help=f"Caminho do log JSONL (default: {DEFAULT_LOG})",
    )
    return p


def main() -> int:
    args = build_arg_parser().parse_args()

    if args.days <= 0:
        print("erro: --days precisa ser > 0", file=sys.stderr)
        return 2

    path = Path(args.file).expanduser()
    if not path.exists():
        print("Sem telemetria registrada.")
        return 0

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    events = load_events(path, cutoff)
    sys.stdout.write(render_report(events, args.days))
    return 0


if __name__ == "__main__":
    sys.exit(main())
