---
description: "Diagnóstico completo do ambiente Meta Ads. Roda 10 checks (token, scopes, app mode, rate limit, ad account, page token, pixel, CLAUDE.md, learnings) e propõe fixes automáticos com --fix."
---

Invoque skill `meta-ads-pro/doctor` rodando os 10 checks de `lib/preflight.sh` em sequência.

Flags:
- `--fix` aplica fixes automáticos onde possível
- `--silent` só printa se tiver erro (usado como preflight interno)
- `--report` gera snapshot JSON em ~/.claude/meta-ads-pro/reports/
- `--release-lock` remove lockfile órfão
- `--review-learnings` fila de learnings não-confirmados pra revisão
