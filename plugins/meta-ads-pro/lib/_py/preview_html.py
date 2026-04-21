#!/usr/bin/env python3
"""preview_html.py — renderiza HTML com mock fiel do Meta, via stdin JSON.

Input: JSON dict via stdin no formato {"level": "...", "payload": {...}, "extras": {...}}
Output: HTML escrito em stdout.

HTML é auto-contido (inline CSS, zero deps).
"""
import html
import json
import sys


_BASE_CSS = """
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Facebook Sans", "Segoe UI",
               Roboto, sans-serif;
  background: #f0f2f5;
  margin: 0;
  padding: 2em 1em;
  color: #1c1e21;
}
.container { max-width: 600px; margin: 0 auto; }
.card {
  background: #fff;
  border-radius: 8px;
  padding: 1.5em;
  margin-bottom: 1.5em;
  box-shadow: 0 1px 2px rgba(0,0,0,.1);
}
.ad-mock {
  width: 375px;
  max-width: 100%;
  border: 1px solid #dddfe2;
  border-radius: 8px;
  background: #fff;
  margin: 1em auto;
  overflow: hidden;
  font-size: 14px;
}
.ad-mock header {
  display: flex;
  align-items: center;
  padding: 10px;
  border-bottom: 1px solid #eef0f3;
}
.ad-mock .avatar {
  width: 40px; height: 40px;
  border-radius: 50%;
  background: #e4e6eb;
  margin-right: 10px;
}
.ad-mock .meta { font-size: 12px; color: #65676b; }
.ad-mock .brand { font-weight: 600; }
.ad-mock .primary { padding: 10px; white-space: pre-wrap; }
.ad-mock .media {
  width: 100%; aspect-ratio: 1/1; background: #000;
  display: flex; align-items: center; justify-content: center;
  color: #fff; font-size: 12px;
}
.ad-mock .footer {
  background: #f7f8fa; padding: 12px;
  display: flex; justify-content: space-between; align-items: center;
}
.ad-mock .headline { font-weight: 600; font-size: 14px; }
.ad-mock .desc { font-size: 12px; color: #65676b; margin-top: 2px; }
.ad-mock .cta {
  background: #e4e6eb; padding: 6px 12px;
  border-radius: 6px; font-weight: 600; font-size: 12px;
}
h1 { font-size: 20px; margin-top: 0; }
h2 { font-size: 16px; margin-top: 1em; }
code { background: #eef0f3; padding: 1px 5px; border-radius: 3px; }
""".strip()


def _esc(value):
    return html.escape(str(value if value is not None else ""), quote=True)


def _render_campaign(data):
    camp = data.get("payload", {}) or {}
    extras = data.get("extras", {}) or {}
    adset = extras.get("adset", {}) or {}
    ads = extras.get("ads", []) or []
    ads_html = []
    for ad in ads:
        creative = ad.get("creative", {}) or {}
        primary = _esc(creative.get("primary_text") or ad.get("primary_text", ""))
        headline = _esc(creative.get("headline") or ad.get("headline", "?"))
        description = _esc(creative.get("description") or ad.get("description", ""))
        cta = _esc(creative.get("call_to_action") or ad.get("cta", "Saiba mais"))
        media_label = _esc(ad.get("media_label", "[imagem/vídeo]"))
        ads_html.append(f"""
<div class="ad-mock">
  <header>
    <div class="avatar"></div>
    <div>
      <div class="brand">{_esc(camp.get('page_name', 'Página'))}</div>
      <div class="meta">Patrocinado · 🌐</div>
    </div>
  </header>
  <div class="primary">{primary}</div>
  <div class="media">{media_label}</div>
  <div class="footer">
    <div>
      <div class="headline">{headline}</div>
      <div class="desc">{description}</div>
    </div>
    <div class="cta">{cta}</div>
  </div>
</div>""")
    try:
        budget = int(adset.get("daily_budget", 0)) / 100
    except (TypeError, ValueError):
        budget = 0.0
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Preview Campanha</title>
<style>{_BASE_CSS}</style>
</head><body><div class="container">
  <h1>{_esc(camp.get('name', '?'))}</h1>
  <div class="card">
    <b>Objetivo:</b> {_esc(camp.get('objective', '?'))}<br>
    <b>Status:</b> {_esc(camp.get('status', 'PAUSED'))}<br>
    <b>Ad Set:</b> {_esc(adset.get('name', '?'))} · R$ {budget:.2f}/dia
  </div>
  <h2>Ads ({len(ads)})</h2>
  {''.join(ads_html)}
</div></body></html>"""


def _render_ad(data):
    ad = data.get("payload", {}) or {}
    creative = ad.get("creative", {}) or {}
    primary = _esc(creative.get("primary_text") or ad.get("primary_text", ""))
    headline = _esc(creative.get("headline") or ad.get("headline", "?"))
    description = _esc(creative.get("description") or ad.get("description", ""))
    cta = _esc(creative.get("call_to_action") or ad.get("cta", "Saiba mais"))
    media_label = _esc(ad.get("media_label", "[imagem/vídeo]"))
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Preview Ad</title>
<style>{_BASE_CSS}</style>
</head><body><div class="container">
  <h1>{_esc(ad.get('name', '?'))}</h1>
  <div class="ad-mock">
    <header>
      <div class="avatar"></div>
      <div>
        <div class="brand">{_esc(ad.get('page_name', 'Página'))}</div>
        <div class="meta">Patrocinado · 🌐</div>
      </div>
    </header>
    <div class="primary">{primary}</div>
    <div class="media">{media_label}</div>
    <div class="footer">
      <div>
        <div class="headline">{headline}</div>
        <div class="desc">{description}</div>
      </div>
      <div class="cta">{cta}</div>
    </div>
  </div>
</div></body></html>"""


def _render_leadform(data):
    form = data.get("payload", {}) or {}
    intro = form.get("intro", {}) or {}
    questions = form.get("questions", []) or []
    questions_html = "".join(
        f"<li>{_esc(q.get('label', '?'))}</li>" for q in questions
    )
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Preview Lead Form</title>
<style>{_BASE_CSS}</style>
</head><body><div class="container">
  <h1>{_esc(form.get('name', '?'))}</h1>
  <div class="card">
    <h2>Intro</h2>
    <p><b>{_esc(intro.get('title', '?'))}</b></p>
    <p>{_esc(intro.get('description', ''))}</p>
  </div>
  <div class="card">
    <h2>Perguntas</h2>
    <ol>{questions_html}</ol>
  </div>
  <div class="card">
    <h2>Privacy Policy</h2>
    <code>{_esc(form.get('privacy_policy_url', '?'))}</code>
  </div>
</div></body></html>"""


def _render_generic(data):
    payload = data.get("payload", {}) or {}
    level = data.get("level", "preview")
    if isinstance(payload, dict):
        rows = "".join(
            f"<tr><td><b>{_esc(k)}</b></td><td><code>{_esc(v)}</code></td></tr>"
            for k, v in list(payload.items())[:20]
        )
        body = f"<table>{rows}</table>"
    else:
        body = f"<pre>{_esc(payload)}</pre>"
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>Preview {_esc(level)}</title>
<style>{_BASE_CSS}
table {{ width: 100%; border-collapse: collapse; }}
td {{ padding: 8px; border-bottom: 1px solid #eef0f3; vertical-align: top; }}
</style></head><body><div class="container">
  <h1>Preview: {_esc(level)}</h1>
  <div class="card">{body}</div>
</div></body></html>"""


RENDERERS = {
    "campaign": _render_campaign,
    "ad": _render_ad,
    "leadform": _render_leadform,
}


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("preview_html: stdin vazio", file=sys.stderr)
        sys.exit(2)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"preview_html: JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)
    level = (data.get("level") or "generic").lower()
    render = RENDERERS.get(level, _render_generic)
    sys.stdout.write(render(data))


if __name__ == "__main__":
    main()
