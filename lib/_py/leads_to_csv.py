#!/usr/bin/env python3
"""leads_to_csv.py — converte a resposta de `GET /{form_id}/leads` pra CSV.

Usado por `/meta-ads-lead-forms --export {form_id}`. Recebe o JSON bruto do
Graph API (com ou sem paginação já concatenada) e produz CSV com:

    * colunas fixas iniciais: id, created_time
    * colunas dinâmicas: union de todos os `field_data[].name` encontrados
      (ordem de primeira aparição, determinística)

Uso:
    # JSON em arquivo
    python3 leads_to_csv.py --input leads.json --output leads.csv

    # JSON via stdin → CSV via stdout
    cat leads.json | python3 leads_to_csv.py > leads.csv

Formato de entrada aceito (qualquer um dos três):
    1. `{"data": [ {lead}, ... ]}`                     ← resposta direta do Graph
    2. `{"data": [...], "paging": {...}}` (idem)
    3. `[ {lead}, ... ]`                                ← lista crua já concatenada

Cada lead:
    {
      "id": "...",
      "created_time": "2026-04-21T10:30:00+0000",
      "field_data": [{"name": "email", "values": ["joao@x.com"]}, ...]
    }

Valores múltiplos em `values` são unidos com " | ". Campos ausentes ficam vazios.

Exit codes:
    0 — CSV gerado (≥0 linhas)
    1 — input inválido (JSON malformado ou estrutura inesperada)
    2 — erro de uso (argparse)
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Any, Iterable


FIXED_COLS = ("id", "created_time")
MULTI_VALUE_SEP = " | "


def _extract_leads(payload: Any) -> list[dict]:
    """Aceita 3 formatos (ver docstring do módulo). Nunca retorna None."""
    if isinstance(payload, list):
        return [x for x in payload if isinstance(x, dict)]
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            return [x for x in data if isinstance(x, dict)]
    raise ValueError("JSON não contém lista de leads em `data` nem array raiz")


def _collect_field_names(leads: Iterable[dict]) -> list[str]:
    """Ordem de primeira aparição, sem duplicatas (determinístico)."""
    seen: dict[str, None] = {}
    for lead in leads:
        for fd in lead.get("field_data", []) or []:
            name = fd.get("name")
            if isinstance(name, str) and name and name not in seen:
                seen[name] = None
    return list(seen.keys())


def _row_for_lead(lead: dict, field_names: list[str]) -> list[str]:
    row = [str(lead.get("id", "")), str(lead.get("created_time", ""))]
    # Indexa field_data por name pra lookup O(1)
    field_index: dict[str, list[str]] = {}
    for fd in lead.get("field_data", []) or []:
        name = fd.get("name")
        if not isinstance(name, str):
            continue
        values = fd.get("values") or []
        # values deve ser list[str]; normaliza com str() por segurança
        field_index[name] = [str(v) for v in values if v is not None]

    for name in field_names:
        values = field_index.get(name, [])
        row.append(MULTI_VALUE_SEP.join(values))
    return row


def leads_to_csv(leads: list[dict], out) -> int:
    """Escreve CSV em `out` (file-like). Retorna nº de linhas de dados."""
    field_names = _collect_field_names(leads)
    header = list(FIXED_COLS) + field_names
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(header)
    count = 0
    for lead in leads:
        writer.writerow(_row_for_lead(lead, field_names))
        count += 1
    return count


def _load_input(path: str | None) -> Any:
    if path and path != "-":
        text = Path(path).expanduser().read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()
    if not text.strip():
        raise ValueError("input vazio")
    return json.loads(text)


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="leads_to_csv.py",
        description="Converte resposta de GET /{form_id}/leads pra CSV.",
    )
    p.add_argument(
        "--input",
        "-i",
        default="-",
        help="Arquivo JSON de entrada (default: stdin com '-')",
    )
    p.add_argument(
        "--output",
        "-o",
        default="-",
        help="Arquivo CSV de saída (default: stdout com '-')",
    )
    return p


def main() -> int:
    args = build_arg_parser().parse_args()

    try:
        payload = _load_input(args.input)
    except FileNotFoundError as e:
        print(f"erro: arquivo não encontrado: {e.filename}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as e:
        print(f"erro: JSON inválido ({e})", file=sys.stderr)
        return 1

    try:
        leads = _extract_leads(payload)
    except ValueError as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1

    if args.output == "-":
        count = leads_to_csv(leads, sys.stdout)
    else:
        out_path = Path(args.output).expanduser()
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8", newline="") as f:
            count = leads_to_csv(leads, f)

    print(f"ok: {count} lead(s) → {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
