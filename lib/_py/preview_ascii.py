#!/usr/bin/env python3
"""preview_ascii.py — renderiza preview ASCII a partir de payloads JSON via stdin.

Input: JSON dict via stdin no formato {"level": "...", "payload": {...}, "extras": {...}}
Output: árvore ASCII em stdout.

Nível-específico:
  - campaign: renderiza com camp/adset/ads via extras["adset"] e extras["ads"]
  - adset:    renderiza ad set standalone
  - ad:       renderiza single ad
  - leadform: renderiza form
  - generic:  fallback — lista primeiros 8 campos

Heredoc-safe: tudo vem via stdin, zero interpolação de shell variables.
"""
import json
import sys


def _render_campaign(data):
    camp = data.get("payload", {}) or {}
    extras = data.get("extras", {}) or {}
    adset = extras.get("adset", {}) or {}
    ads = extras.get("ads", []) or []
    lines = []
    lines.append("┌─ PREVIEW: Campanha ──────────────────────────────────────┐")
    lines.append(f"│ 📊 {camp.get('name','?')}")
    lines.append(f"│    Objetivo: {camp.get('objective','?')}  ·  Status: {camp.get('status','PAUSED')}")
    lines.append("│")
    lines.append(f"│ 🎯 Ad Set: {adset.get('name','?')}")
    budget_cents = adset.get("daily_budget", 0)
    try:
        budget_reais = int(budget_cents) / 100
    except (TypeError, ValueError):
        budget_reais = 0.0
    lines.append(f"│    Budget: R$ {budget_reais:.2f}/dia")
    lines.append(f"│    Target: {adset.get('targeting_summary','?')}")
    lines.append("│")
    lines.append(f"│ 📺 Ads ({len(ads)}):")
    for i, ad in enumerate(ads, 1):
        lines.append(f"│    {i}. {ad.get('name','?')}")
    lines.append("└──────────────────────────────────────────────────────────┘")
    return "\n".join(lines)


def _render_ad(data):
    ad = data.get("payload", {}) or {}
    lines = []
    lines.append("┌─ PREVIEW: Ad ────────────────────────────────────────────┐")
    lines.append(f"│ Nome: {ad.get('name','?')}")
    lines.append(f"│ Formato: {ad.get('format','?')}")
    creative = ad.get("creative", {}) or {}
    headline = creative.get("headline") or ad.get("headline") or "?"
    primary = creative.get("primary_text") or ad.get("primary_text") or "?"
    description = creative.get("description") or ad.get("description") or "?"
    cta = creative.get("call_to_action") or ad.get("cta") or "?"
    dest = ad.get("destination", "?")
    lines.append(f"│ Headline: {str(headline)[:60]}")
    lines.append(f"│ Primary:  {str(primary)[:60]}")
    lines.append(f"│ Desc:     {str(description)[:60]}")
    lines.append(f"│ CTA: {cta}")
    lines.append(f"│ Destino: {dest}")
    lines.append("└──────────────────────────────────────────────────────────┘")
    return "\n".join(lines)


def _render_adset(data):
    adset = data.get("payload", {}) or {}
    lines = []
    lines.append("┌─ PREVIEW: Ad Set ────────────────────────────────────────┐")
    lines.append(f"│ Nome: {adset.get('name','?')}")
    try:
        budget = int(adset.get("daily_budget", 0)) / 100
    except (TypeError, ValueError):
        budget = 0.0
    lines.append(f"│ Budget: R$ {budget:.2f}/dia")
    lines.append(f"│ Destination: {adset.get('destination_type','?')}")
    lines.append(f"│ Optimization goal: {adset.get('optimization_goal','?')}")
    lines.append(f"│ Bid strategy: {adset.get('bid_strategy','?')}")
    lines.append("└──────────────────────────────────────────────────────────┘")
    return "\n".join(lines)


def _render_leadform(data):
    form = data.get("payload", {}) or {}
    lines = []
    lines.append("┌─ PREVIEW: Lead Form ─────────────────────────────────────┐")
    lines.append(f"│ Nome: {form.get('name','?')}")
    intro = form.get("intro", {}) or {}
    lines.append(f"│ Intro: {intro.get('title','?')}")
    questions = form.get("questions", []) or []
    lines.append(f"│ Perguntas ({len(questions)}):")
    for i, q in enumerate(questions, 1):
        lines.append(f"│   {i}. {q.get('label','?')}")
    lines.append(f"│ Privacy: {form.get('privacy_policy_url','?')}")
    lines.append("└──────────────────────────────────────────────────────────┘")
    return "\n".join(lines)


def _render_generic(data):
    payload = data.get("payload", {}) or {}
    level = data.get("level", "preview")
    lines = []
    lines.append(f"┌─ PREVIEW: {level} ────────────────────────────────────────┐")
    if isinstance(payload, dict):
        for k, v in list(payload.items())[:8]:
            lines.append(f"│  {k}: {str(v)[:50]}")
    else:
        lines.append(f"│  {str(payload)[:200]}")
    lines.append("└──────────────────────────────────────────────────────────┘")
    return "\n".join(lines)


RENDERERS = {
    "campaign": _render_campaign,
    "ad": _render_ad,
    "adset": _render_adset,
    "leadform": _render_leadform,
}


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("preview_ascii: stdin vazio", file=sys.stderr)
        sys.exit(2)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"preview_ascii: JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)
    level = (data.get("level") or "generic").lower()
    render = RENDERERS.get(level, _render_generic)
    print(render(data))


if __name__ == "__main__":
    main()
