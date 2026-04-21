#!/usr/bin/env python3
"""privacy_check.py — valida URL de privacy policy em 3 camadas bilíngue (PT+EN).

Usage:
    python3 privacy_check.py <url>

Exit codes:
    0 → URL passa em todas as 3 camadas (prints "OK" em stdout)
    1 → URL rejeitada (motivo em stderr no formato "REJECT: ...")
    2 → erro de uso

Camadas:
    1. Blacklist de host/path (Instagram, linktr.ee, beacons.ai, facebook.com/*/posts)
    2. Estrutural: HEAD retorna 200 (fallback GET se servidor responder 405/Method Not Allowed)
    3. Conteúdo: texto ≥ 300 chars + heading (h1/h2/title) mencionando "privacid"/"privacy"
       + pelo menos 1 keyword de privacy em PT ou EN.

Fix do bug #7 do caso Filipe (Instagram URL aceita como privacy policy).
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.parse
import urllib.request


# ── Camada 1: blacklist ───────────────────────────────────────────────────────
BLACKLIST_HOSTS = (
    "instagram.com",
    "linktr.ee",
    "beacons.ai",
)

# Paths especificamente bloqueados em hosts permitidos (ex.: facebook.com/foo/posts)
BLACKLIST_PATH_PATTERNS = (
    re.compile(r"facebook\.com/[^/]+/posts", re.IGNORECASE),
)

# ── Camada 3: keywords bilíngue ──────────────────────────────────────────────
KEYWORDS_PT = (
    "privacidade",
    "política de privacidade",
    "politica de privacidade",  # sem acento
    "dados pessoais",
    "lgpd",
    "lei 13.709",
    "lei nº 13.709",
)

KEYWORDS_EN = (
    "privacy policy",
    "personal data",
    "gdpr",
    "data protection",
    "ccpa",
)

MIN_CHARS = 300
HEAD_TIMEOUT = 10
GET_TIMEOUT = 15
USER_AGENT = "Mozilla/5.0 (compatible; meta-ads-pro/1.0; privacy-validator)"


def _reject(msg: str) -> None:
    """Print REJECT reason to stderr and exit 1."""
    print(f"REJECT: {msg}", file=sys.stderr)
    sys.exit(1)


def _host_of(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    return (parsed.netloc or "").lower()


def check_blacklist(url: str) -> None:
    """Camada 1 — rejeita se host ou path bate com blacklist."""
    host = _host_of(url)
    for blocked in BLACKLIST_HOSTS:
        # bate host exato ou subdomain (ex: www.instagram.com)
        if host == blocked or host.endswith("." + blocked):
            _reject(f"URL blacklisted (host={blocked})")

    for pat in BLACKLIST_PATH_PATTERNS:
        if pat.search(url):
            _reject(f"path blacklisted ({pat.pattern})")


def _open(url: str, method: str, timeout: int):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT})
    return urllib.request.urlopen(req, timeout=timeout)  # noqa: S310 (validated URL)


def check_structural(url: str) -> None:
    """Camada 2 — HEAD 200. Se servidor retorna 405/Method Not Allowed, tenta GET."""
    try:
        with _open(url, "HEAD", HEAD_TIMEOUT) as r:
            status = getattr(r, "status", None) or r.getcode()
            if status != 200:
                _reject(f"HTTP {status}")
            return
    except urllib.error.HTTPError as e:
        # 405 = Method Not Allowed → tenta GET
        if e.code == 405:
            pass
        else:
            _reject(f"HTTP {e.code}")
    except Exception as e:  # noqa: BLE001
        # Algumas redes bloqueiam HEAD. Tenta GET como fallback universal.
        # Só rejeita se o GET também falhar (na Camada 3).
        pass

    # Fallback GET pra confirmar 200
    try:
        with _open(url, "GET", GET_TIMEOUT) as r:
            status = getattr(r, "status", None) or r.getcode()
            if status != 200:
                _reject(f"HTTP {status}")
    except urllib.error.HTTPError as e:
        _reject(f"HTTP {e.code}")
    except Exception as e:  # noqa: BLE001
        _reject(f"fetch failed ({e.__class__.__name__}: {e})")


def _fetch_html(url: str) -> str:
    try:
        with _open(url, "GET", GET_TIMEOUT) as r:
            data = r.read()
            # tenta charset do header, cai pra utf-8
            charset = "utf-8"
            try:
                ctype = r.headers.get("Content-Type", "")
                m = re.search(r"charset=([\w-]+)", ctype, re.IGNORECASE)
                if m:
                    charset = m.group(1)
            except Exception:  # noqa: BLE001
                pass
            return data.decode(charset, errors="ignore")
    except Exception as e:  # noqa: BLE001
        _reject(f"GET failed ({e.__class__.__name__}: {e})")
        return ""  # unreachable


HEADING_RE = re.compile(
    r"<(h1|h2|title)\b[^>]*>\s*(?P<text>[^<]+)\s*</\1>",
    re.IGNORECASE | re.DOTALL,
)
TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")


def check_content(url: str) -> None:
    """Camada 3 — verifica heading mencionando privacidade + texto longo + keyword."""
    html = _fetch_html(url)

    # Heading em h1/h2/title deve mencionar "privacid" (PT) ou "privacy" (EN)
    has_heading = False
    for m in HEADING_RE.finditer(html):
        text = m.group("text").lower()
        if "privacid" in text or "privacy" in text:
            has_heading = True
            break

    if not has_heading:
        _reject("sem heading (h1/h2/title) mencionando privacidade/privacy")

    # Remove tags e normaliza whitespace
    plain = TAG_RE.sub(" ", html)
    plain = WS_RE.sub(" ", plain).strip()

    if len(plain) < MIN_CHARS:
        _reject(f"texto muito curto ({len(plain)} < {MIN_CHARS} chars)")

    plain_lower = plain.lower()
    has_pt = any(kw in plain_lower for kw in KEYWORDS_PT)
    has_en = any(kw in plain_lower for kw in KEYWORDS_EN)

    if not (has_pt or has_en):
        _reject("sem keyword de privacy (PT ou EN)")


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: privacy_check.py <url>", file=sys.stderr)
        sys.exit(2)

    url = sys.argv[1].strip()
    if not url:
        print("usage: privacy_check.py <url>", file=sys.stderr)
        sys.exit(2)

    # Valida que é URL http(s)
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        _reject(f"scheme inválido ({parsed.scheme or 'vazio'}) — use http:// ou https://")
    if not parsed.netloc:
        _reject("URL sem host")

    check_blacklist(url)
    check_structural(url)
    check_content(url)

    print("OK")


if __name__ == "__main__":
    main()
