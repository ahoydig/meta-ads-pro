#!/usr/bin/env python3
"""media_hash.py — SHA256 de arquivo de mídia.

Uso:
  python3 media_hash.py <file>

Exit codes:
  0 — sucesso (hash impresso em stdout)
  1 — erro de I/O (arquivo não existe, sem permissão, etc.)
  2 — uso inválido (argumentos)
"""
import hashlib
import sys
from pathlib import Path


CHUNK_SIZE = 65536  # 64 KiB — bom trade-off entre syscalls e memória


def hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(CHUNK_SIZE), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: media_hash.py <file>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"media_hash.py: not a file: {path}", file=sys.stderr)
        return 1

    try:
        print(hash_file(path))
    except OSError as e:
        print(f"media_hash.py: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
