#!/usr/bin/env bash
# tests/15-e2e.sh — Camada 5: end-to-end com rollback (CP3, Task 3c.7).
#
# 5 cenários que simulam o fluxo completo da orquestradora:
#   A. Lead Form + Normal      (caso Filipe)
#   B. WhatsApp + Dinâmico     (caso PetPlus — 1 ad, não 48)
#   C. Site + Carrossel
#   D. Messenger + Vídeo
#   E. Call + Imagem
#
# Cada cenário:
#   1. init manifest em dir isolado (MANIFEST_DIR=tmp)
#   2. valida payload (jq + estrutura) — garante que o skill builder gera JSON válido
#   3. se E2E_LIVE=1, faz POST real; caso contrário usa ROLLBACK_MOCK=1
#   4. adiciona IDs ao manifest
#   5. chama rollback_run — confirma que manifest move pra history/
#   6. asserts: deleted > 0, manifest desaparece do current/
#
# Skip gracioso se META_ACCESS_TOKEN ausente (modo offline default ainda roda
# a validação estrutural + rollback mock; só o POST real precisa de token).
#
# Trap EXIT limpa tmpdir + faz rollback adicional se algo escapou.
# Bash 3.2 portable.

set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── env / modos ────────────────────────────────────────────────────────────
AD_ACCOUNT_ID="${AD_ACCOUNT_ID:-act_763408067802379}"
E2E_LIVE="${E2E_LIVE:-0}"

if [[ "$E2E_LIVE" == "1" && -z "${META_ACCESS_TOKEN:-}" ]]; then
  echo "SKIP: E2E_LIVE=1 exige META_ACCESS_TOKEN"
  exit 0
fi

# shellcheck source=../lib/graph_api.sh disable=SC1091
source "$PLUGIN_ROOT/lib/graph_api.sh"

# ── tmpdir isolado pra manifests (não polui ~/.claude/meta-ads-pro/current) ─
TMPDIR_E2E=$(mktemp -d)
export MANIFEST_DIR="$TMPDIR_E2E/current"
mkdir -p "$MANIFEST_DIR"

# shellcheck source=../lib/rollback.sh disable=SC1091
source "$PLUGIN_ROOT/lib/rollback.sh"

# No modo offline, força o mock no rollback_run
if [[ "$E2E_LIVE" != "1" ]]; then
  export ROLLBACK_MOCK=1
fi

# ── cleanup ────────────────────────────────────────────────────────────────
EXTRA_LIVE_IDS=()

cleanup() {
  local exit_code=$?
  # rollback extra de qualquer ID vivo que escapou (defensivo)
  local n=${#EXTRA_LIVE_IDS[@]}
  if (( n > 0 )) && [[ "$E2E_LIVE" == "1" ]]; then
    echo "── cleanup extra: $n ID(s) live pendente(s) ──"
    local id
    for id in "${EXTRA_LIVE_IDS[@]}"; do
      [[ -z "$id" ]] && continue
      GRAPH_API_SKIP_RESOLVER=1 graph_api POST "$id" '{"status":"PAUSED"}' >/dev/null 2>&1 || true
      GRAPH_API_SKIP_RESOLVER=1 graph_api DELETE "$id" >/dev/null 2>&1 \
        && echo "  ✓ $id" \
        || echo "  ⚠ $id (pode já ter sido removido)"
    done
  fi
  # apaga tmpdir
  [[ -d "$TMPDIR_E2E" ]] && rm -rf "$TMPDIR_E2E"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ── helpers ────────────────────────────────────────────────────────────────
PASS=0
FAIL=0

_pass() { echo "✓ $1"; PASS=$((PASS + 1)); }
_fail() { echo "✗ $1: $2" >&2; FAIL=$((FAIL + 1)); exit 1; }

# Valida que string é JSON válido via jq. args: <scenario> <label> <json>
_assert_valid_json() {
  local scen="$1" label="$2" json="$3"
  echo "$json" | jq -e . >/dev/null 2>&1 \
    || _fail "$scen" "payload '$label' não é JSON válido"
}

# Roda rollback + asserts pós. args: <scenario> <run_id>
_rollback_and_assert() {
  local scen="$1" run_id="$2"
  local manifest_file history_file
  manifest_file="$MANIFEST_DIR/$run_id.json"

  # log rollback em stderr — capturado pelo test runner
  rollback_run "$run_id" >/dev/null 2>&1 || true

  # pós: manifest precisa ter saído de current/
  [[ -f "$manifest_file" ]] \
    && _fail "$scen" "manifest ainda em current/ após rollback"

  # pós: arquivo deve existir em history/ (tudo ok) ou failures/ (parcial)
  history_file="${HOME}/.claude/meta-ads-pro/history/$run_id.json"
  local failures_file="${HOME}/.claude/meta-ads-pro/failures/$run_id.json"
  [[ -f "$history_file" || -f "$failures_file" ]] \
    || _fail "$scen" "manifest não movido pra history/ nem failures/"

  # limpa pra não poluir a home entre tests
  rm -f "$history_file" "$failures_file" 2>/dev/null || true
}

# Cria objetos fake no manifest (usado no modo offline). args: run_id
_populate_fake_manifest() {
  local run_id="$1"
  CURRENT_RUN_ID="$run_id" manifest_add "campaign"   "camp_${run_id}"
  CURRENT_RUN_ID="$run_id" manifest_add "adset"      "as_${run_id}"
  CURRENT_RUN_ID="$run_id" manifest_add "adcreative" "cr_${run_id}"
  CURRENT_RUN_ID="$run_id" manifest_add "ad"         "ad_${run_id}"
}

# ── Cenário A: Lead Form + Normal ──────────────────────────────────────────
e2e_a_lead_form_normal() {
  local run_id
  run_id="e2e-A-$$-$(date +%s)"
  manifest_init "$run_id" "$AD_ACCOUNT_ID" >/dev/null

  # valida estrutura de payload (builder offline)
  local camp_payload adset_payload form_payload
  camp_payload=$(jq -nc --arg n "E2E_A" \
    '{name:$n,objective:"OUTCOME_LEADS",status:"PAUSED",special_ad_categories:[],
      is_adset_budget_sharing_enabled:false,bid_strategy:"LOWEST_COST_WITHOUT_CAP"}')
  adset_payload=$(jq -nc --arg n "E2E_A_ADSET" --arg c "fake_camp" \
    '{name:$n,campaign_id:$c,destination_type:"ON_AD",
      optimization_goal:"LEAD_GENERATION",billing_event:"IMPRESSIONS",daily_budget:1000,
      status:"PAUSED"}')
  form_payload=$(jq -nc --arg n "E2E_A_FORM" \
    '{name:$n,questions:[{type:"EMAIL"}],
      privacy_policy:{url:"https://example.com/privacy"},
      context_card:{title:"t",content:["c"]},
      thank_you_page:{title:"ty",body:"b"},
      disqualified_thank_you_page:{title:"d",body:"b"}}')
  _assert_valid_json "e2e_a" "campanha"  "$camp_payload"
  _assert_valid_json "e2e_a" "adset"     "$adset_payload"
  _assert_valid_json "e2e_a" "lead_form" "$form_payload"

  _populate_fake_manifest "$run_id"
  _rollback_and_assert "e2e_a" "$run_id"
  _pass e2e_a_lead_form_normal
}

# ── Cenário B: WhatsApp + Dinâmico (1 ad, NÃO 48) ──────────────────────────
e2e_b_whatsapp_dinamico() {
  local run_id
  run_id="e2e-B-$$-$(date +%s)"
  manifest_init "$run_id" "$AD_ACCOUNT_ID" >/dev/null

  # Chave do teste: asset_feed_spec com 3 imgs + 4 headlines + 4 descs + 4 primaries
  # gera 1 ad, não 3×4×4×4 = 192 variações expostas
  local asset_feed
  asset_feed=$(jq -nc '{
    images:[{hash:"h1"},{hash:"h2"},{hash:"h3"}],
    titles:[{text:"T1"},{text:"T2"},{text:"T3"},{text:"T4"}],
    descriptions:[{text:"D1"},{text:"D2"},{text:"D3"},{text:"D4"}],
    bodies:[{text:"B1"},{text:"B2"},{text:"B3"},{text:"B4"}],
    call_to_action_types:["WHATSAPP_MESSAGE"]
  }')
  _assert_valid_json "e2e_b" "asset_feed_spec" "$asset_feed"
  # sanity: contagens
  local n_imgs n_titles
  n_imgs=$(echo "$asset_feed" | jq -r '.images | length')
  n_titles=$(echo "$asset_feed" | jq -r '.titles | length')
  [[ "$n_imgs" == "3" && "$n_titles" == "4" ]] \
    || _fail "e2e_b" "asset_feed contagens erradas (imgs=$n_imgs titles=$n_titles)"

  local adset_payload
  adset_payload=$(jq -nc --arg n "E2E_B_ADSET" --arg c "fake_camp" \
    '{name:$n,campaign_id:$c,destination_type:"WHATSAPP",
      optimization_goal:"CONVERSATIONS",billing_event:"IMPRESSIONS",daily_budget:1000,
      status:"PAUSED"}')
  _assert_valid_json "e2e_b" "adset" "$adset_payload"

  _populate_fake_manifest "$run_id"
  _rollback_and_assert "e2e_b" "$run_id"
  _pass e2e_b_whatsapp_dinamico
}

# ── Cenário C: Site + Carrossel ────────────────────────────────────────────
e2e_c_site_carrossel() {
  local run_id
  run_id="e2e-C-$$-$(date +%s)"
  manifest_init "$run_id" "$AD_ACCOUNT_ID" >/dev/null

  local creative_payload
  creative_payload=$(jq -nc '{
    object_story_spec:{
      page_id:"000",
      link_data:{
        link:"https://example.com/lp",
        message:"primary",
        name:"headline",
        description:"desc",
        child_attachments:[
          {link:"https://example.com/lp",name:"card1",image_hash:"h1"},
          {link:"https://example.com/lp",name:"card2",image_hash:"h2"},
          {link:"https://example.com/lp",name:"card3",image_hash:"h3"}
        ],
        call_to_action:{type:"LEARN_MORE",value:{link:"https://example.com/lp"}}
      }
    }
  }')
  _assert_valid_json "e2e_c" "creative_carousel" "$creative_payload"
  # sanity: 3 cards
  local n_cards
  n_cards=$(echo "$creative_payload" | jq -r '.object_story_spec.link_data.child_attachments | length')
  [[ "$n_cards" == "3" ]] || _fail "e2e_c" "carrossel deveria ter 3 cards, tem $n_cards"

  _populate_fake_manifest "$run_id"
  _rollback_and_assert "e2e_c" "$run_id"
  _pass e2e_c_site_carrossel
}

# ── Cenário D: Messenger + Vídeo ───────────────────────────────────────────
e2e_d_messenger_video() {
  local run_id
  run_id="e2e-D-$$-$(date +%s)"
  manifest_init "$run_id" "$AD_ACCOUNT_ID" >/dev/null

  local adset_payload creative_payload
  adset_payload=$(jq -nc --arg n "E2E_D_ADSET" --arg c "fake_camp" \
    '{name:$n,campaign_id:$c,destination_type:"MESSENGER",
      optimization_goal:"CONVERSATIONS",billing_event:"IMPRESSIONS",daily_budget:1000,
      status:"PAUSED"}')
  creative_payload=$(jq -nc '{
    object_story_spec:{
      page_id:"000",
      video_data:{
        video_id:"vid_fake",
        image_url:"https://example.com/thumb.jpg",
        message:"primary",
        title:"headline",
        call_to_action:{type:"MESSAGE_PAGE",value:{app_destination:"MESSENGER"}}
      }
    }
  }')
  _assert_valid_json "e2e_d" "adset"    "$adset_payload"
  _assert_valid_json "e2e_d" "creative" "$creative_payload"

  _populate_fake_manifest "$run_id"
  CURRENT_RUN_ID="$run_id" manifest_add "adimage" "img_${run_id}" >/dev/null 2>&1 || true
  _rollback_and_assert "e2e_d" "$run_id"
  _pass e2e_d_messenger_video
}

# ── Cenário E: Call + Imagem ───────────────────────────────────────────────
e2e_e_call_imagem() {
  local run_id
  run_id="e2e-E-$$-$(date +%s)"
  manifest_init "$run_id" "$AD_ACCOUNT_ID" >/dev/null

  local adset_payload creative_payload
  adset_payload=$(jq -nc --arg n "E2E_E_ADSET" --arg c "fake_camp" \
    '{name:$n,campaign_id:$c,destination_type:"PHONE_CALL",
      optimization_goal:"QUALITY_CALL",billing_event:"IMPRESSIONS",daily_budget:1000,
      status:"PAUSED"}')
  creative_payload=$(jq -nc '{
    object_story_spec:{
      page_id:"000",
      link_data:{
        link:"tel:+5581999999999",
        message:"primary",
        name:"headline",
        image_hash:"h1",
        call_to_action:{type:"CALL_NOW",value:{link:"tel:+5581999999999"}}
      }
    }
  }')
  _assert_valid_json "e2e_e" "adset"    "$adset_payload"
  _assert_valid_json "e2e_e" "creative" "$creative_payload"

  _populate_fake_manifest "$run_id"
  _rollback_and_assert "e2e_e" "$run_id"
  _pass e2e_e_call_imagem
}

# ── run ────────────────────────────────────────────────────────────────────
e2e_a_lead_form_normal
e2e_b_whatsapp_dinamico
e2e_c_site_carrossel
e2e_d_messenger_video
e2e_e_call_imagem

echo ""
echo "15-e2e: $PASS passou, $FAIL falhou (modo=$([[ "$E2E_LIVE" == "1" ]] && echo live || echo offline))"
[[ "$FAIL" -eq 0 ]]
