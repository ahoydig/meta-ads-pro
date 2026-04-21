#!/usr/bin/env python3
"""import_existing.py — importa campanhas/adsets/ads/forms da conta Meta pra history/.

Uso:
  python3 import_existing.py \\
    --account act_XXX \\
    --token TOKEN \\
    --out DIR \\
    [--page PAGE_ID] \\
    [--api-version v25.0]

Idempotente: re-run gera novo arquivo timestamped, não sobrescreve nem duplica.
Nunca altera nada na conta Meta — só lê.

Saída: 1 arquivo JSON por run em <out>/<account>/imported-YYYYMMDD-HHMMSS.json
com schema:
  {
    "imported_at": ISO8601,
    "ad_account_id": "act_X",
    "source": "pre-plugin",
    "campaigns": [{..., "adsets": [{..., "ads": [...]}]}, ...],
    "leadgen_forms": [...],
    "summary": {"campaigns": N, "adsets": M, "ads": K, "forms": L}
  }

Exit codes:
  0 — sucesso
  1 — erro HTTP / I/O
  2 — uso inválido
"""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_API_VERSION = "v25.0"
API_TIMEOUT = 30  # segundos
PAGE_LIMIT = 100


def _build_url(api_base: str, path: str, token: str, fields: str) -> str:
    qs = urllib.parse.urlencode(
        {
            "fields": fields,
            "limit": PAGE_LIMIT,
            "access_token": token,
        }
    )
    return f"{api_base}/{path}?{qs}"


def _fetch_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=API_TIMEOUT) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        # Lê body pra contexto, mas redact token
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:500]
        except Exception:  # noqa: BLE001
            pass
        safe_url = _redact_token(url)
        raise RuntimeError(
            f"HTTP {e.code} em {safe_url}: {body}"
        ) from None
    except urllib.error.URLError as e:
        raise RuntimeError(f"URLError: {e.reason}") from None


def _redact_token(url: str) -> str:
    return urllib.parse.urlunparse(
        _replace_qs(urllib.parse.urlparse(url))
    )


def _replace_qs(parsed):
    qs = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    qs = [(k, "***" if k == "access_token" else v) for k, v in qs]
    return parsed._replace(query=urllib.parse.urlencode(qs))


def fetch_all_pages(api_base: str, path: str, token: str, fields: str) -> list:
    """Segue paginação cursor-based do Graph API."""
    results: list = []
    url = _build_url(api_base, path, token, fields)
    while url:
        page = _fetch_json(url)
        results.extend(page.get("data", []))
        url = page.get("paging", {}).get("next") or None
    return results


def import_account(
    api_base: str,
    account: str,
    token: str,
    page_id: str = "",
) -> dict:
    print(f"→ fetching campanhas de {account}...", file=sys.stderr)
    campaigns = fetch_all_pages(
        api_base,
        f"{account}/campaigns",
        token,
        "id,name,status,objective,created_time,daily_budget,lifetime_budget",
    )
    print(f"  {len(campaigns)} campanhas", file=sys.stderr)

    for camp in campaigns:
        print(f"  → ad sets de {camp['id']}...", file=sys.stderr)
        adsets = fetch_all_pages(
            api_base,
            f"{camp['id']}/adsets",
            token,
            "id,name,status,optimization_goal,daily_budget,created_time",
        )
        camp["adsets"] = adsets
        for adset in adsets:
            ads = fetch_all_pages(
                api_base,
                f"{adset['id']}/ads",
                token,
                "id,name,status,creative{id,name},created_time",
            )
            adset["ads"] = ads

    forms: list = []
    if page_id:
        print(f"→ fetching lead forms de {page_id}...", file=sys.stderr)
        forms = fetch_all_pages(
            api_base,
            f"{page_id}/leadgen_forms",
            token,
            "id,name,status,created_time,leads_count",
        )
        print(f"  {len(forms)} forms", file=sys.stderr)

    summary = {
        "campaigns": len(campaigns),
        "adsets": sum(len(c.get("adsets", [])) for c in campaigns),
        "ads": sum(
            len(a.get("ads", []))
            for c in campaigns
            for a in c.get("adsets", [])
        ),
        "forms": len(forms),
    }

    return {
        "imported_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "ad_account_id": account,
        "source": "pre-plugin",
        "campaigns": campaigns,
        "leadgen_forms": forms,
        "summary": summary,
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--account", required=True, help="ad account ID (act_XXX)")
    p.add_argument("--token", required=True, help="META_ACCESS_TOKEN")
    p.add_argument("--out", required=True, help="diretório raiz pra gravar JSON")
    p.add_argument("--page", default="", help="page ID (pra importar leadgen forms)")
    p.add_argument(
        "--api-version",
        default=DEFAULT_API_VERSION,
        help=f"default {DEFAULT_API_VERSION}",
    )
    args = p.parse_args()

    api_base = f"https://graph.facebook.com/{args.api_version}"

    out_dir = Path(args.out) / args.account
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        print(f"import_existing: mkdir fail — {e}", file=sys.stderr)
        return 1

    try:
        manifest = import_account(
            api_base=api_base,
            account=args.account,
            token=args.token,
            page_id=args.page,
        )
    except RuntimeError as e:
        print(f"import_existing: {e}", file=sys.stderr)
        return 1

    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_file = out_dir / f"imported-{ts}.json"
    try:
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
    except OSError as e:
        print(f"import_existing: write fail — {e}", file=sys.stderr)
        return 1

    print(f"\n✓ Importado pra {out_file}", file=sys.stderr)
    print(f"  {manifest['summary']}", file=sys.stderr)
    # stdout = path do arquivo, pra permitir piping
    print(str(out_file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
