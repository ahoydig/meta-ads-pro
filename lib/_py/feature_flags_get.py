#!/usr/bin/env python3
"""feature_flags_get.py — lê flag YAML via argv (nunca via heredoc).

Args: --file <path> --name <flag_name> [--default <value>]
Output: valor lowercase (bool normalizado) em stdout.

Se arquivo não existe → imprime default.
Se flag não existe no arquivo → imprime default.
Se YAML syntax error → imprime default + warning em stderr.
"""
import argparse
import sys
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--file", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--default", default="false")
    args = p.parse_args()

    path = Path(args.file)
    if not path.exists():
        print(str(args.default).lower())
        return

    try:
        import yaml  # type: ignore[import-untyped]
    except ImportError:
        print(
            "feature_flags_get: PyYAML não instalado, usando default",
            file=sys.stderr,
        )
        print(str(args.default).lower())
        return

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except (OSError, yaml.YAMLError) as exc:
        print(f"feature_flags_get: {exc}", file=sys.stderr)
        print(str(args.default).lower())
        return

    value = data.get(args.name, args.default)
    print(str(value).lower())


if __name__ == "__main__":
    main()
