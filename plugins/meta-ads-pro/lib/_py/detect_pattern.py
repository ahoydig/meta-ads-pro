#!/usr/bin/env python3
"""detect_pattern.py — extrai template a partir de amostra de nomenclatura.

Casos suportados:
  "[FORMULARIO][PACIENTE-MODELO][AUTO]" → "[{TOKEN1}][{TOKEN2}][{TOKEN3}]"
  "ahoy_20260319_curso_vendas_lp" → "{TOKEN1}_{DATE}_{TOKEN2}_{TOKEN3}_{TOKEN4}"
  "AD 01 - IMG" → "AD {NN} - {TOKEN1}"
"""
import re
import sys


def detect(sample: str) -> str:
    # Caso 1: tokens em brackets [XXX] (caso Filipe)
    bracket_tokens = re.findall(r"\[([A-Z0-9\-_]+)\]", sample)
    if bracket_tokens:
        template = sample
        for i, _tok in enumerate(bracket_tokens, 1):
            template = re.sub(r"\[[A-Z0-9\-_]+\]", f"[{{TOKEN{i}}}]", template, count=1)
        return template

    # Caso 2: separadores _ ou - (caso ahoy-style)
    sep = "_" if "_" in sample else ("-" if "-" in sample else None)
    if sep is None:
        # single word, retorna como está
        return sample

    parts = sample.split(sep)
    marks = []
    token_idx = 0
    for p in parts:
        if p.isdigit() and len(p) == 8:
            marks.append("{DATE}")
        elif p.isdigit() and len(p) <= 3:
            marks.append("{NN}")
        elif re.match(r"^[A-Za-z][A-Za-z\-]*$", p):
            token_idx += 1
            marks.append(f"{{TOKEN{token_idx}}}")
        else:
            marks.append(p)
    return sep.join(marks)


def main():
    if len(sys.argv) != 2:
        print("usage: detect_pattern.py <sample>", file=sys.stderr)
        sys.exit(2)
    print(detect(sys.argv[1]))


if __name__ == "__main__":
    main()
