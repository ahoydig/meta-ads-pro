#!/usr/bin/env python3
"""claude_invoke_api.py — fallback pra gerar copy via Anthropic SDK direto.

Uso pretendido: CI / testes rodando fora do Claude Code, sem acesso ao Task tool.
Requer ANTHROPIC_API_KEY no ambiente e o pacote `anthropic` instalado.

Uso:
  ANTHROPIC_API_KEY=sk-... python3 claude_invoke_api.py "<prompt>"

Saída:
  JSON array em stdout (ex.: ["var 1","var 2","var 3","var 4"])

Exit codes:
  0 — sucesso
  1 — erro (SDK ausente, API key ausente, parse fail, API error)
  2 — uso inválido
"""
import json
import os
import re
import sys


def _strip_markdown_fence(text: str) -> str:
    """Remove ```json ... ``` ou ``` ... ``` do começo/fim."""
    text = text.strip()
    if text.startswith("```"):
        # remove linha de abertura (```json ou ```)
        lines = text.split("\n", 1)
        text = lines[1] if len(lines) > 1 else ""
        # remove ``` final
        if text.rstrip().endswith("```"):
            text = text.rstrip()[:-3].rstrip()
    return text


def _extract_json_array(text: str):
    """Tenta parsear JSON array; se falhar, tenta extrair o primeiro bloco
    delimitado por colchetes balanceados."""
    cleaned = _strip_markdown_fence(text)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass

    # fallback: regex pro primeiro array top-level (non-greedy seria unsafe
    # com strings aninhadas; usamos greedy e validamos)
    m = re.search(r"\[.*\]", cleaned, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError:
            return None
    return None


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: claude_invoke_api.py <prompt>", file=sys.stderr)
        print("[]")
        return 2

    prompt = sys.argv[1]

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("claude_invoke_api: ANTHROPIC_API_KEY não setado", file=sys.stderr)
        print("[]")
        return 1

    try:
        from anthropic import Anthropic  # import só quando precisa
    except ImportError:
        print(
            "claude_invoke_api: pacote `anthropic` não instalado "
            "(pip install anthropic)",
            file=sys.stderr,
        )
        print("[]")
        return 1

    model = os.environ.get("META_ADS_COPY_MODEL", "claude-sonnet-4-5")
    max_tokens = int(os.environ.get("META_ADS_COPY_MAX_TOKENS", "1024"))

    try:
        client = Anthropic(api_key=api_key)
        message = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}],
        )
    except Exception as e:  # noqa: BLE001 — anthropic.* tem hierarquia grande
        # Nunca printa o API key em erro
        safe_msg = str(e).replace(api_key, "***")
        print(f"claude_invoke_api: API error — {safe_msg}", file=sys.stderr)
        print("[]")
        return 1

    if not message.content:
        print("claude_invoke_api: response sem content", file=sys.stderr)
        print("[]")
        return 1

    # Primeira content block do tipo text
    text = ""
    for block in message.content:
        if getattr(block, "type", None) == "text":
            text = block.text
            break
    if not text:
        print("claude_invoke_api: nenhum text block no response", file=sys.stderr)
        print("[]")
        return 1

    arr = _extract_json_array(text)
    if not isinstance(arr, list):
        preview = text[:200].replace("\n", " ")
        print(
            f"claude_invoke_api: parse fail — {preview}",
            file=sys.stderr,
        )
        print("[]")
        return 1

    print(json.dumps(arr, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
