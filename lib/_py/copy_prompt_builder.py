#!/usr/bin/env python3
"""copy_prompt_builder.py — constrói prompt pro Claude gerar copy de anúncio.

Saída: prompt em stdout (texto puro), pronto pra passar pro Task tool ou
pro fallback claude_invoke_api.py.

Campos suportados:
  headline      — título do anúncio (27-40 caracteres)
  description   — descrição curta (até 27 caracteres)
  primary_text  — legenda principal (125+ caracteres, pode ser longa)

Uso:
  python3 copy_prompt_builder.py \\
    --field headline --count 4 \\
    --objective OUTCOME_LEADS \\
    --product "curso X" \\
    [--audience "dentistas"] \\
    [--image-path /path/to/img.jpg] \\
    [--voice-file /path/to/voice-profile.md]

Exit codes:
  0 — sucesso
  2 — uso inválido
"""
import argparse
import sys
from pathlib import Path


FIELD_SPECS = {
    "headline": {
        "name": "Headline (título do anúncio)",
        "chars": "27-40 caracteres",
    },
    "description": {
        "name": "Description",
        "chars": "até 27 caracteres",
    },
    "primary_text": {
        "name": "Legenda principal",
        "chars": "125+ caracteres, pode ser longa",
    },
}

MAX_VOICE_CHARS = 2000  # trunca voice profile pra não estourar context


def build_prompt(
    field: str,
    count: int,
    image_path: str,
    objective: str,
    audience: str,
    voice_file: str,
    product: str,
) -> str:
    spec = FIELD_SPECS[field]

    voice_guidance = ""
    if voice_file:
        try:
            content = Path(voice_file).read_text(encoding="utf-8")
            if len(content) > MAX_VOICE_CHARS:
                print(
                    f"copy_prompt_builder: voice-file truncado a "
                    f"{MAX_VOICE_CHARS}c (original {len(content)}c)",
                    file=sys.stderr,
                )
            voice_guidance = (
                f"\n\n## Voz da marca\n\n{content[:MAX_VOICE_CHARS]}"
            )
        except (FileNotFoundError, OSError) as e:
            # Voice é opcional mas se foi solicitado, avisa que não foi aplicado.
            print(
                f"copy_prompt_builder: voice-file não aplicado ({voice_file}): {e}",
                file=sys.stderr,
            )

    image_line = "- Imagem de referência anexada\n" if image_path else ""

    prompt = (
        f"Gere {count} variações de {spec['name']} ({spec['chars']}) "
        f"pra anúncio Meta Ads.\n"
        f"\n"
        f"## Contexto\n"
        f"- Produto/serviço: {product}\n"
        f"- Objetivo: {objective}\n"
        f"- Público: {audience or 'não especificado'}\n"
        f"{image_line}"
        f"{voice_guidance}\n"
        f"\n"
        f"## Regras\n"
        f"- Cada variação num ângulo diferente "
        f"(acolhimento, benefício, urgência, social proof)\n"
        f"- Português brasileiro\n"
        f"- Zero emojis genéricos de IA (🚀 ✨ 💯 🎯)\n"
        f"- Zero clichês (\"em um mundo onde\", \"não apenas... mas também\")\n"
        f"- Claro, direto, humano\n"
        f"\n"
        f"## Formato de resposta\n"
        f"Retorne APENAS um JSON array de {count} strings. Nada mais.\n"
        f"Exemplo: [\"variação 1\", \"variação 2\", ...]\n"
    )
    return prompt


def main() -> int:
    p = argparse.ArgumentParser(
        description="Constrói prompt pra gerar copy de anúncio Meta Ads."
    )
    p.add_argument("--field", required=True, choices=list(FIELD_SPECS.keys()))
    p.add_argument("--count", type=int, default=4)
    p.add_argument("--image-path", default="")
    p.add_argument("--objective", required=True)
    p.add_argument("--audience", default="")
    p.add_argument("--voice-file", default="")
    p.add_argument("--product", default="")
    args = p.parse_args()

    if args.count < 1:
        print("copy_prompt_builder: --count precisa ser >= 1", file=sys.stderr)
        return 2

    prompt = build_prompt(
        field=args.field,
        count=args.count,
        image_path=args.image_path,
        objective=args.objective,
        audience=args.audience,
        voice_file=args.voice_file,
        product=args.product,
    )
    print(prompt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
