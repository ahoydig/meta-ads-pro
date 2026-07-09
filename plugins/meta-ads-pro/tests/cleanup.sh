#!/usr/bin/env bash
# tests/cleanup.sh — apagador manual de objetos TEST_* esquecidos na conta.
#
# Uso:
#   META_ACCESS_TOKEN=... META_AD_ACCOUNT_ID=act_XXXXX bash tests/cleanup.sh
#   bash tests/cleanup.sh --yes        # pula confirm prompt (use com cuidado)
#   bash tests/cleanup.sh --dry-run    # só lista, não apaga
#   (PAGE_ID opcional no env — necessário só pra varrer/arquivar leadgen_forms)
#
# Lógica:
#   1. Lista campaigns, adsets, ads, adcreatives e customaudiences (edge da
#      ad account) + leadgen_forms (edge da PAGE_ID, se setada) cujo `name`
#      começa com "TEST_"
#   2. Mostra o inventário e pede confirmação (a menos que --yes)
#   3. DELETE em ordem topológica: ads → adsets → campaigns → adcreatives →
#      customaudiences (a Graph API em tese aceita DELETE cascade no parent,
#      mas fazer bottom-up evita órfãos se algum DELETE individual falhar)
#   4. leadgen_forms NÃO suportam DELETE via Graph API (confirmado ao vivo,
#      code 100/33 "Unsupported delete request") — arquiva via
#      POST {form_id}?status=ARCHIVED com o PAGE TOKEN (não o token de
#      usuário/system-user do .env), mesmo padrão de tests/08-lead-forms.sh
#      (_cleanup_forms) e lib/rollback.sh:80. Forms já ARCHIVED não entram
#      na varredura (não há nada pra fazer com eles).
#
# NÃO toca: adspixels (sem DELETE na Graph API, pixel de teste é permanente
# por design — ver tests/09-publicos.sh) e qualquer objeto sem prefixo TEST_.
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
      sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
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

# Aceita META_AD_ACCOUNT_ID (nome documentado acima) OU AD_ACCOUNT_ID (nome
# usado pelo resto da suíte/.env) — o que vier primeiro.
META_AD_ACCOUNT_ID="${META_AD_ACCOUNT_ID:-${AD_ACCOUNT_ID:-}}"
if [[ -z "${META_AD_ACCOUNT_ID:-}" ]]; then
  echo "✗ cleanup: META_AD_ACCOUNT_ID (ou AD_ACCOUNT_ID) não setado (ex: act_763408067802379)" >&2
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
PAGE_ID="${PAGE_ID:-}"
LIST_LIMIT=500
TRUNCATED_WARN=()

# ── coleta ───────────────────────────────────────────────────────────────────
echo "→ Buscando objetos TEST_* em $ACCOUNT..."

# Filtering no servidor via `filtering` param: name CONTAIN "TEST_"
# Graph API não tem STARTS_WITH, então filtramos client-side depois.
# args: endpoint [fields] — fields default "id,name,status" (adcreatives e
# customaudiences não têm um campo `status` comparável, então passam "id,name").
list_prefixed() {
  local endpoint="$1"
  local fields="${2:-id,name,status}"
  local resp total
  if ! resp=$(graph_api GET "${ACCOUNT}/${endpoint}?fields=${fields}&limit=${LIST_LIMIT}" 2>/dev/null); then
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

# leadgen_forms são edge da PAGE (não da ad account) — varredura separada,
# só se PAGE_ID setado. Forms já ARCHIVED ficam de fora (nada a fazer com
# eles; "evidência final" documentada no report é justamente forms ARCHIVED
# sobrando, não ACTIVE).
list_forms_prefixed() {
  [[ -n "$PAGE_ID" ]] || { echo "[]"; return 0; }
  local resp total
  if ! resp=$(graph_api GET "${PAGE_ID}/leadgen_forms?fields=id,name,status&limit=${LIST_LIMIT}" 2>/dev/null); then
    echo "[]"
    return 0
  fi
  total=$(echo "$resp" | jq '[.data[]?] | length')
  if [[ "$total" == "$LIST_LIMIT" ]]; then
    TRUNCATED_WARN+=("leadgen_forms")
  fi
  echo "$resp" | jq -c '[.data[]? | select(.name | startswith("TEST_")) | select(.status != "ARCHIVED")]'
}

CAMPAIGNS_JSON=$(list_prefixed campaigns)
ADSETS_JSON=$(list_prefixed adsets)
ADS_JSON=$(list_prefixed ads)
CREATIVES_JSON=$(list_prefixed adcreatives "id,name")
AUDIENCES_JSON=$(list_prefixed customaudiences "id,name")
FORMS_JSON=$(list_forms_prefixed)

if (( ${#TRUNCATED_WARN[@]} > 0 )); then
  echo "⚠ Página cheia (limit=${LIST_LIMIT}) em: ${TRUNCATED_WARN[*]}"
  echo "  Pode haver mais TEST_* além dessa leva — rode cleanup novamente após apagar essa."
fi

n_campaigns=$(echo "$CAMPAIGNS_JSON" | jq 'length')
n_adsets=$(echo "$ADSETS_JSON" | jq 'length')
n_ads=$(echo "$ADS_JSON" | jq 'length')
n_creatives=$(echo "$CREATIVES_JSON" | jq 'length')
n_audiences=$(echo "$AUDIENCES_JSON" | jq 'length')
n_forms=$(echo "$FORMS_JSON" | jq 'length')

total=$(( n_campaigns + n_adsets + n_ads + n_creatives + n_audiences ))
total_all=$(( total + n_forms ))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Inventário TEST_* em $ACCOUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf " Campaigns      : %3d\n" "$n_campaigns"
printf " AdSets         : %3d\n" "$n_adsets"
printf " Ads            : %3d\n" "$n_ads"
printf " AdCreatives    : %3d\n" "$n_creatives"
printf " CustomAudiences: %3d\n" "$n_audiences"
if [[ -n "$PAGE_ID" ]]; then
  printf " LeadgenForms   : %3d (ACTIVE — serão ARQUIVADOS, não deletados)\n" "$n_forms"
else
  echo " LeadgenForms   :   ? (PAGE_ID não setado — varredura de forms pulada)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if (( total_all == 0 )); then
  echo "✓ Nada pra apagar/arquivar. Conta limpa."
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
show_block "Campaigns"       "$CAMPAIGNS_JSON"
show_block "AdSets"          "$ADSETS_JSON"
show_block "Ads"             "$ADS_JSON"
show_block "AdCreatives"     "$CREATIVES_JSON"
show_block "CustomAudiences" "$AUDIENCES_JSON"
show_block "LeadgenForms (serão ARQUIVADOS)" "$FORMS_JSON"
echo ""

if (( DRY_RUN == 1 )); then
  echo "⊘ --dry-run: nada foi apagado/arquivado."
  exit 0
fi

# ── confirm ──────────────────────────────────────────────────────────────────
if (( ASSUME_YES == 0 )); then
  printf "Apagar %d objeto(s) + arquivar %d form(s)? Digite 'APAGAR' pra confirmar: " "$total" "$n_forms"
  read -r answer
  if [[ "$answer" != "APAGAR" ]]; then
    echo "Abortado."
    exit 1
  fi
fi

# ── delete em ordem topológica (ads → adsets → campaigns → creatives → audiences) ──
DELETED=0
FAILED=0
ARCHIVED=0
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

delete_batch "ads"              "$ADS_JSON"
delete_batch "adsets"           "$ADSETS_JSON"
delete_batch "campaigns"        "$CAMPAIGNS_JSON"
delete_batch "adcreatives"      "$CREATIVES_JSON"
delete_batch "customaudiences"  "$AUDIENCES_JSON"

# ── arquiva leadgen_forms (sem DELETE na Graph API — mesmo padrão de
# tests/08-lead-forms.sh _cleanup_forms / lib/rollback.sh:80) ─────────────────
archive_forms() {
  local json="$1"
  local n
  n=$(echo "$json" | jq 'length')
  (( n == 0 )) && return 0

  if [[ -z "$PAGE_ID" ]]; then
    echo ""
    echo "⚠ $n leadgen_form(s) TEST_* encontrado(s), mas PAGE_ID não setado — não dá pra arquivar." >&2
    return 0
  fi

  echo ""
  echo "→ Arquivando $n leadgen_form(s)..."

  local page_token
  # `|| page_token=""` — mesmo guard de tests/08-lead-forms.sh: sob
  # `set -o pipefail` (herdado do graph_api.sh, mesmo com set +e no resto
  # deste script), um stdout não-JSON quebraria o jq; degrada pro check de
  # vazio abaixo em vez de propagar erro.
  page_token=$(GRAPH_API_SKIP_RESOLVER=1 graph_api GET "${PAGE_ID}?fields=access_token" 2>/dev/null \
    | jq -r '.access_token // empty') || page_token=""
  if [[ -z "$page_token" ]]; then
    echo "  ⚠ sem page token — forms de teste ficam ACTIVE (arquive manualmente)" >&2
    local skip_id skip_name
    while IFS=$'\t' read -r skip_id skip_name; do
      [[ -z "$skip_id" ]] && continue
      echo "  ✗ $skip_id  $skip_name (sem page token)"
      (( FAILED++ )) || true
      FAILED_IDS+=("$skip_id")
    done < <(echo "$json" | jq -r '.[] | [.id, .name] | @tsv')
    return 0
  fi

  local id name
  while IFS=$'\t' read -r id name; do
    [[ -z "$id" ]] && continue
    if curl -sS -X POST "https://graph.facebook.com/${META_API_VERSION:-v25.0}/${id}" \
      -d "status=ARCHIVED" -d "access_token=${page_token}" 2>/dev/null \
      | jq -e '.success == true' >/dev/null 2>&1; then
      echo "  ✓ $id  $name (ARCHIVED)"
      (( ARCHIVED++ )) || true
    else
      echo "  ✗ $id  $name (falhou arquivar)"
      (( FAILED++ )) || true
      FAILED_IDS+=("$id")
    fi
  done < <(echo "$json" | jq -r '.[] | [.id, .name] | @tsv')
}

archive_forms "$FORMS_JSON"

# ── sumário ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf " ✓ Apagados  : %3d\n" "$DELETED"
printf " ✓ Arquivados: %3d\n" "$ARCHIVED"
printf " ✗ Falhas    : %3d\n" "$FAILED"
if (( FAILED > 0 )); then
  echo ""
  echo " IDs que falharam (investigue manualmente):"
  for i in "${FAILED_IDS[@]}"; do echo "   • $i"; done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAILED" -eq 0 ]]
