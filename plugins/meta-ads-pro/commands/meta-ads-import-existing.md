---
description: "Importa campanhas/adsets/ads/leadgen_forms da conta Meta pra ~/.claude/meta-ads-pro/history/. 100% leitura, zero escrita. Paginação cursor-based, token redacted, idempotente. Útil quando a conta já tem estrutura pre-plugin."
---

Invoque a skill `meta-ads-pro/import-existing` seguindo o fluxo de 5 passos
em `flows/import-existing/SKILL.md`.

**Pré-condições:**

- `META_ACCESS_TOKEN` setado (vem do `.env` via setup)
- `AD_ACCOUNT_ID` no CLAUDE.md (ex: `act_763408067802379`)
- `PAGE_ID` no CLAUDE.md (opcional — sem ele, leadgen_forms são pulados)
- `python3` e `jq` disponíveis no PATH

**Fluxo resumido:**

1. Pre-flight (libs + ferramentas)
2. Ler config (env > .env > CLAUDE.md)
3. Delegar pra `lib/_py/import_existing.py` → gera
   `history/{account}/imported-YYYYMMDD-HHMMSS.json`
4. Mostrar sumário (#campanhas/adsets/ads/forms + top 5 recentes)
5. Oferecer export CSV opcional

**Regras invioláveis:**

- Nunca POST/DELETE. Só GET na Graph API.
- Token nunca ecoado no stdout/stderr (redact built-in).
- Re-run NÃO sobrescreve — gera novo arquivo timestamped.
- Respeita `META_ADS_NO_TELEMETRY=1` (lib/telemetry.sh).

**Libs:**

- `lib/_py/import_existing.py` — paginação cursor-based, redact, schema
- `lib/telemetry.sh` — wrapper de telemetry_log
