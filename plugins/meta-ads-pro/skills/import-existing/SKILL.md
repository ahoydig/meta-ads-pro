---
name: meta-ads-import-existing
description: Importa campanhas/adsets/ads/leadgen_forms existentes da conta Meta pra history/ local — útil quando o usuário já tinha estrutura antes de instalar o plugin. 100% leitura, zero escrita na Meta. Paginação cursor-based, token redacted nos logs, idempotente (re-run gera novo arquivo timestamped).
---

# meta-ads-import-existing

Sub-skill de "onboarding reverso". Quando alguém instala o plugin mas a conta
Meta já tem histórico de campanhas antigas (pre-plugin), este fluxo importa
tudo pra `~/.claude/meta-ads-pro/history/{account}/imported-YYYYMMDD-HHMMSS.json`.

Serve pra:
- Alimentar analytics locais (`/meta-ads-analyze-telemetry` não cobre pre-plugin).
- Backup rápido antes de mexer em estrutura antiga.
- Input pra export CSV consumido em planilhas/Data Studio.

**Nunca escreve na Meta.** Só GETs — toda a leitura usa `import_existing.py`
que não conhece POST/DELETE.

## Quando usar

- `/meta-ads-import-existing` — invocação direta
- Sugerido pela orquestradora no primeiro `/meta-ads-menu` depois do setup
  (se `~/.claude/meta-ads-pro/history/` está vazio)

## Fluxo de execução (5 passos)

### Passo 1 — Pre-flight

```bash
# Plugin root + libs mínimas
[[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/lib/telemetry.sh"

telemetry_log run_started sub_skill=import-existing
```

Valida que `python3` está disponível (`import_existing.py` usa só stdlib —
sem pip install). Valida que `jq` existe (usado na exibição de sumário).

### Passo 2 — Ler config do CLAUDE.md

Lê em ordem de prioridade:

1. **Env vars** (se setadas): `META_ACCESS_TOKEN`, `AD_ACCOUNT_ID`, `PAGE_ID`
2. **.env** do projeto: `grep ^META_ACCESS_TOKEN= .env | cut -d= -f2-`
3. **CLAUDE.md "Meta Ads Config"**: extrai `ad_account_id`, `page_id`

Se faltar qualquer um:

```
✗ import-existing precisa de:
  - META_ACCESS_TOKEN  (seu System User token)
  - AD_ACCOUNT_ID      (ex: act_XXX)
  - PAGE_ID            (opcional — sem ele, leadgen_forms são pulados)

Rode /meta-ads-setup primeiro.
```

Oferece override:

```
Detectei:
  ad_account: act_763408067802379
  page:       108356564252733
  api_version: v25.0

[enter] pra usar esses. Ou cole um ad_account_id diferente.
```

### Passo 3 — Invocar `lib/_py/import_existing.py`

Este script já existe desde CP2 (commit `dd9b492`) e faz todo o trabalho
pesado. A skill só delega:

```bash
OUT_DIR="${HOME}/.claude/meta-ads-pro/history"
mkdir -p "$OUT_DIR"

imported_file=$(python3 "$CLAUDE_PLUGIN_ROOT/lib/_py/import_existing.py" \
  --account "$AD_ACCOUNT_ID" \
  --token   "$META_ACCESS_TOKEN" \
  --out     "$OUT_DIR" \
  ${PAGE_ID:+--page "$PAGE_ID"} \
  --api-version "${META_API_VERSION:-v25.0}")

[[ -n "$imported_file" && -f "$imported_file" ]] || {
  echo "✗ import_existing não gerou arquivo — ver stderr acima"
  telemetry_log run_failed sub_skill=import-existing
  return 1
}
```

O script segue paginação cursor-based (`page.paging.next`) automaticamente,
redact tokens em mensagens de erro, e gera schema:

```json
{
  "imported_at": "2026-04-21T12:34:56-03:00",
  "ad_account_id": "act_XXX",
  "source": "pre-plugin",
  "campaigns": [{..., "adsets": [{..., "ads": [...]}]}],
  "leadgen_forms": [...],
  "summary": {"campaigns": N, "adsets": M, "ads": K, "forms": L}
}
```

### Passo 4 — Mostrar sumário

```bash
echo ""
echo "✓ Importado pra: $imported_file"
echo ""
jq -r '
  "📊 Sumário:",
  "  \(.summary.campaigns) campanhas",
  "  \(.summary.adsets) ad sets",
  "  \(.summary.ads) anúncios",
  "  \(.summary.forms) leadgen forms"
' "$imported_file"

# Top 5 campanhas mais recentes
echo ""
echo "🔝 Campanhas mais recentes:"
jq -r '.campaigns | sort_by(.created_time) | reverse | .[:5]
  | .[] | "  [\(.status)] \(.name) (\(.objective)) — \(.id)"' "$imported_file"
```

### Passo 5 — Oferecer export CSV

```
Quer gerar CSV pra abrir em planilha? [y/N]
```

Se `y`:

```bash
csv_file="${imported_file%.json}.csv"
jq -r '
  ["campaign_id","campaign_name","campaign_status","objective",
   "adset_id","adset_name","adset_status","ad_id","ad_name","ad_status"],
  (.campaigns[] | . as $c
    | ($c.adsets // [])[] | . as $a
    | ($a.ads // [{}])[]
    | [$c.id, $c.name, $c.status, $c.objective,
       $a.id, $a.name, $a.status,
       (.id // ""), (.name // ""), (.status // "")])
  | @csv
' "$imported_file" > "$csv_file"

echo "✓ CSV: $csv_file"
```

Se `N`: pula. O JSON por si já é consumível por qualquer tool.

Emite telemetria final:

```bash
telemetry_log run_completed sub_skill=import-existing \
  campaigns="$(jq '.summary.campaigns' "$imported_file")" \
  ads="$(jq '.summary.ads' "$imported_file")"
```

## Regras

- **100% leitura.** Nunca POST/DELETE na Meta. O script `import_existing.py`
  não tem paths pra mutação (garantia de código).
- **Token nunca ecoado.** `import_existing.py` tem `_redact_token()` em
  todos os logs de erro — masca `access_token=***`.
- **Idempotente.** Re-run gera **novo** arquivo com timestamp diferente,
  nunca sobrescreve.
- **Sem pip.** Só stdlib Python — roda em ambiente vanilla.
- **Opt-in pelo user.** Nunca importa automaticamente; orquestradora só
  *sugere* quando history/ está vazio.

## Libs

- `lib/_py/import_existing.py` — todo o trabalho pesado (paginação, redact,
  schema, exit codes)
- `lib/telemetry.sh` — wrapper do telemetry_log (respeita opt-out)

## Erros comuns

| Código | Significado | Ação |
|--------|-------------|------|
| 190 | token inválido/expirado | `/meta-ads-setup` pra renovar |
| 200 | scope faltando (`ads_read`) | adicione no System User |
| 803 | `AD_ACCOUNT_ID` não existe ou sem permissão | check CLAUDE.md |
| 613 | rate limit | aguarde 1h, `import_existing.py` não retenta sozinho |
