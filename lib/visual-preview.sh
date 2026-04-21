#!/usr/bin/env bash
# visual-preview.sh — gera ASCII tree ou HTML com mock do Meta

set -euo pipefail

preview_ascii_campaign() {
  # uso: preview_ascii_campaign <campaign_json> <adset_json> <ads_json_array>
  local camp_json="$1" adset_json="$2" ads_json="$3"
  python3 - <<PYEOF
import json, sys
try:
    camp = json.loads('''$camp_json''')
    adset = json.loads('''$adset_json''')
    ads = json.loads('''$ads_json''')
except json.JSONDecodeError as e:
    print(f"preview error: {e}", file=sys.stderr)
    sys.exit(1)
print("┌─ PREVIEW: Campanha ──────────────────────────────────────┐")
print(f"│ 📊 {camp.get('name','?')}")
print(f"│    Objetivo: {camp.get('objective','?')}  ·  Status: {camp.get('status','PAUSED')}")
print("│")
print(f"│ 🎯 Ad Set: {adset.get('name','?')}")
print(f"│    Budget: R\$ {int(adset.get('daily_budget', 0))/100:.2f}/dia")
print(f"│    Target: {adset.get('targeting_summary','?')}")
print("│")
print(f"│ 📺 Ads ({len(ads)}):")
for i, ad in enumerate(ads, 1):
    print(f"│    {i}. {ad.get('name','?')}")
print("└──────────────────────────────────────────────────────────┘")
PYEOF
}

preview_html_campaign() {
  # gera arquivo HTML, retorna path
  local camp_json="$1"
  local out_file
  out_file=$(mktemp -t meta-ads-preview.XXXXXX.html)
  python3 - <<PYEOF > "$out_file"
import json
try:
    camp = json.loads('''$camp_json''')
except Exception:
    camp = {}
print(f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Preview Campanha</title>
<style>
body{{font-family:-apple-system,sans-serif;max-width:600px;margin:2em auto;padding:1em}}
.card{{border:1px solid #ddd;border-radius:8px;padding:1em;margin:1em 0;background:#fff}}
.ad-mock{{width:375px;border:1px solid #ddd;border-radius:12px;margin:1em 0;padding:.5em}}
</style></head><body>
<h1>{camp.get('name','?')}</h1>
<div class="card"><b>Objetivo:</b> {camp.get('objective','?')}</div>
</body></html>""")
PYEOF
  echo "$out_file"
}

# Confirmação obrigatória antes de POST
preview_and_confirm() {
  local level="$1"  # campaign|adset|ad|leadform
  local payload="$2"

  # Renderiza preview ASCII simples
  python3 - <<PYEOF
import json
try:
    d = json.loads('''$payload''')
    print("┌─ PREVIEW: $level ───────────────────────────────┐")
    for k, v in list(d.items())[:8]:
        print(f"│  {k}: {str(v)[:50]}")
    print("└────────────────────────────────────────────────────┘")
except Exception:
    print("$payload")
PYEOF

  echo ""
  read -rp "Confirma criação? [s/N/p=preview HTML no browser] " ans
  case "$ans" in
    s|S) return 0 ;;
    p|P)
      local html
      html=$(preview_html_campaign "$payload")
      open "$html" 2>/dev/null || xdg-open "$html" 2>/dev/null || true
      read -rp "Confirma após ver o preview? [s/N] " ans2
      [[ "$ans2" == "s" || "$ans2" == "S" ]]
      ;;
    *) return 1 ;;
  esac
}
