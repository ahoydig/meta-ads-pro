#!/usr/bin/env bash
# tests/cleanup.sh — apagador manual de objetos TEST_* esquecidos na conta.
#
# Uso:
#   META_ACCESS_TOKEN=... META_AD_ACCOUNT_ID=act_XXXXX bash tests/cleanup.sh
#   bash tests/cleanup.sh --yes        # pula confirm prompt (use com cuidado)
#   bash tests/cleanup.sh --dry-run    # só lista, não apaga
#
# Lógica:
#   1. Lista campaigns, adsets e ads cujo `name` começa com "TEST_"
#   2. Mostra o inventário e pede confirmação (a menos que --yes)
#   3. DELETE em ordem topológica: ads → adsets → campaigns
#      (a Graph API em tese aceita DELETE cascade no parent, mas fazer bottom-up
#      evita órfãos se algum DELETE individual falhar)
#
# Skip gracioso se META_ACCESS_TOKEN não setado (CI amigável).
# bash 3.2 portable. shellcheck clean.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── args ─────────────────────────────────────────────────────────────────────
ASSUME_YES=0
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run|-n) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "cleanup: flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

# ── guards ───────────────────────────────────────────────────────────────────
if [[ -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "⊘ cleanup: META_ACCESS_TOKEN não setado — skip"
  exit 0
fi

if [[ -z "${META_AD_ACCOUNT_ID:-}" ]]; then
  echo "✗ cleanup: META_AD_ACCOUNT_ID não setado (ex: act_763408067802379)" >&2
  exit 2
fi

if ! command -v jq &>/dev/null; then
  echo "✗ cleanup: jq é obrigatório" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$PLUGIN_ROOT/lib/graph_api.sh"
# graph_api.sh usa `set -euo pipefail` — restaura nossa intenção (sem -e,
# queremos detectar falhas por branch em vez de abortar silenciosamente).
set +e

ACCOUNT="$META_AD_ACCOUNT_ID"
LIST_LIMIT=500
TRUNCATED_WARN=()

# ── coleta ───────────────────────────────────────────────────────────────────
echo "→ Buscando objetos TEST_* em $ACCOUNT..."

# Filtering no servidor via `filtering` param: name CONTAIN "TEST_"
# Graph API não tem STARTS_WITH, então filtramos client-side depois.
list_prefixed() {
  local endpoint="$1"  # campaigns | adsets | ads
  local resp total
  if ! resp=$(graph_api GET "${ACCOUNT}/${endpoint}?fields=id,name,status&limit=${LIST_LIMIT}" 2>/dev/null); then
    echo "[]"
    return 0
  fi
  # aviso de truncamento: se a página veio cheia, provavelmente há mais
  total=$(echo "$resp" | jq '[.data[]?] | length')
  if [[ "$total" == "$LIST_LIMIT" ]]; then
    TRUNCATED_WARN+=("$endpoint")
  fi
  # só objetos cujo name começa com TEST_ (case-sensitive)
  echo "$resp" | jq -c '[.data[]? | select(.name | startswith("TEST_"))]'
}

CAMPAIGNS_JSON=$(list_prefixed campaigns)
ADSETS_JSON=$(list_prefixed adsets)
ADS_JSON=$(list_prefixed ads)

if (( ${#TRUNCATED_WARN[@]} > 0 )); then
  echo "⚠ Página cheia (limit=${LIST_LIMIT}) em: ${TRUNCATED_WARN[*]}"
  echo "  Pode haver mais TEST_* além dessa leva — rode cleanup novamente após apagar essa."
fi

n_campaigns=$(echo "$CAMPAIGNS_JSON" | jq 'length')
n_adsets=$(echo "$ADSETS_JSON" | jq 'length')
n_ads=$(echo "$ADS_JSON" | jq 'length')

total=$(( n_campaigns + n_adsets + n_ads ))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Inventário TEST_* em $ACCOUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf " Campaigns : %3d\n" "$n_campaigns"
printf " AdSets    : %3d\n" "$n_adsets"
printf " Ads       : %3d\n" "$n_ads"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if (( total == 0 )); then
  echo "✓ Nada pra apagar. Conta limpa."
  exit 0
fi

# ── preview detalhado ────────────────────────────────────────────────────────
show_block() {
  local label="$1" json="$2"
  local n
  n=$(echo "$json" | jq 'length')
  if (( n > 0 )); then
    echo ""
    echo "  $label:"
    echo "$json" | jq -r '.[] | "    • \(.id)  \(.name)  [\(.status // "?")]"'
  fi
}
show_block "Campaigns" "$CAMPAIGNS_JSON"
show_block "AdSets"    "$ADSETS_JSON"
show_block "Ads"       "$ADS_JSON"
echo ""

if (( DRY_RUN == 1 )); then
  echo "⊘ --dry-run: nada foi apagado."
  exit 0
fi

# ── confirm ──────────────────────────────────────────────────────────────────
if (( ASSUME_YES == 0 )); then
  printf "Apagar esses %d objeto(s)? Digite 'APAGAR' pra confirmar: " "$total"
  read -r answer
  if [[ "$answer" != "APAGAR" ]]; then
    echo "Abortado."
    exit 1
  fi
fi

# ── delete em ordem topológica (ads → adsets → campaigns) ────────────────────
DELETED=0
FAILED=0
FAILED_IDS=()

delete_batch() {
  local label="$1" json="$2"
  local n
  n=$(echo "$json" | jq 'length')
  (( n == 0 )) && return 0
  echo ""
  echo "→ Apagando $n $label..."
  # bash 3.2 friendly loop via jq -c
  local id name
  while IFS=$'\t' read -r id name; do
    [[ -z "$id" ]] && continue
    if graph_api DELETE "$id" >/dev/null 2>&1; then
      echo "  ✓ $id  $name"
      (( DELETED++ )) || true
    else
      echo "  ✗ $id  $name (falhou)"
      (( FAILED++ )) || true
      FAILED_IDS+=("$id")
    fi
  done < <(echo "$json" | jq -r '.[] | [.id, .name] | @tsv')
}

delete_batch "ads"       "$ADS_JSON"
delete_batch "adsets"    "$ADSETS_JSON"
delete_batch "campaigns" "$CAMPAIGNS_JSON"

# ── sumário ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf " ✓ Apagados : %3d\n" "$DELETED"
printf " ✗ Falhas   : %3d\n" "$FAILED"
if (( FAILED > 0 )); then
  echo ""
  echo " IDs que falharam (investigue manualmente):"
  for i in "${FAILED_IDS[@]}"; do echo "   • $i"; done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAILED" -eq 0 ]]
