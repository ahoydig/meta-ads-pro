# LEARNINGS — meta-ads-pro

Esse arquivo documenta decisões, bugs, fixes e trade-offs que emergiram durante o desenvolvimento. Atualizado a cada CP.

---

## CP1 — Foundation (2026-04-21)

### Bugs do plano detectados e corrigidos durante implementação

**1. `str(False)` → `"False"` em JSON payload (error-resolver.sh)**
- Plano tinha: `fix_args: [false]` e no bash `python3 -c "print(str(value))"` retornava `"False"` capitalized.
- Meta Graph API rejeita `"False"` — precisa ser `false` lowercase.
- Fix: bash-dev adicionou função `fmt_arg()` que normaliza bool→lowercase antes de embutir no payload.

**2. `declare -A` inline não funciona em bash 3.2 (macOS default)**
- Plano usava `declare -A ROLLBACK_PRIORITY=([ad]=1 ...)`.
- bash 3.2 (que é o default do macOS) não aceita inline values em associative arrays.
- Fix: removido `declare -A` do `lib/rollback.sh` — lógica de PRIORITY está no `lib/_py/manifest.py` (`PRIORITY` dict), shell só delega via subprocess.

**3. BSD sed incompatibilidade (nomenclatura.sh)**
- Plano usava `sed 's/_\{[a-z]*\}//g'` — sintaxe GNU sed.
- macOS usa BSD sed, trata `\{` como literal braces.
- Fix: `sed 's/_[{][a-zA-Z]*[}]//g'` — char classes `[{]`/`[}]` funcionam em BRE+ERE de ambos dialects. Portável.

**4. `mapfile` em `tests/01-lint.sh` (bash 4+, quebra em macOS bash 3.2)**
- `mapfile -t sh_files < <(find ...)` é bash 4+; macOS default é 3.2.57.
- shellcheck não flagga versioning, passou no review do bash-dev. Pego no cross-cutting review.
- Fix: substituir por `while IFS= read -r f; do arr+=("$f"); done < <(find ...)` — portable.
- Cascade: `run_all.sh` tem `|| exit 1` na camada 1 → quebra a camada 2 também.
- Commit fix: `f76e816`.

**4. Docstring inconsistente em detect_pattern.py (plano)**
- Docstring do plano dizia uma coisa, código fazia outra.
- python-dev detectou durante implementação e corrigiu a docstring pra bater com o comportamento.

---

### Follow-ups registrados pela review (CP2+)

**FU-1 — `visual-preview.sh` heredoc injection risk**
- `python3 - <<PYEOF ... json.loads('''$payload''')` é vulnerável se `$payload` contiver `'''` em campos user-controlled.
- CP1: risco baixo (payload construído pelo próprio código).
- CP2+: vira **Critical** quando lead form labels e ad text vierem do usuário.
- **Fix:** refatorar pra passar payload via `stdin` ou `argv` (pattern já usado em `lib/_py/log_unknown_error.py`).
- Scope: antes do CP2c (anúncios).

**FU-2 — `nomenclatura.sh` regex não cobre hífen**
- Regex `[a-zA-Z]*` não casa placeholders com hífen tipo `{nome-criativo}`.
- Placeholder não stripado se user não preencher.
- **Fix:** `[a-zA-Z-]*` ou `[a-zA-Z][a-zA-Z-]*`.
- Scope: CP2c (primeiro uso de `{nome-criativo}`).

**FU-3 — `feature_flags.sh` mesmo pattern heredoc**
- Mesma vulnerabilidade do FU-1, severidade menor (flag name é config interna, não user-controlled).
- **Fix:** junto com FU-1.

**FU-4 — `preview_and_confirm` perdeu parameterization**
- Plano tinha `preview_and_confirm <level> <preview_fn> <payload>` pra extensibilidade.
- bash-dev hardcodou `preview_html_campaign` — funciona pra CP1 (só campaign).
- **Fix:** re-introduzir `preview_fn` parameter quando adset/ad/leadform previews chegarem no CP2.
- Scope: CP2a (campanha concluída).

---

### Minor notes do cross-cutting review (CP2)

**M1 — `check_app_mode` branch inconclusive sem fail-safe**
- Quando a resposta da Graph API é ambígua (nem erro 1885183 nem creative_id), função retorna 1 mas deixa `FALLBACK_DARK_POST` unset.
- Edge case raro, mas pode bugar fluxos de CP2 que checam a flag.
- **Fix sugerido:** defaulting pra `FALLBACK_DARK_POST=true` (mais seguro — dark post sempre funciona).
- Scope: quick patch no início do CP2.

**M2 — curl direto em `check_token_expiration`/`check_scopes`**
- Bypassa o wrapper `lib/graph_api.sh` (perde retry em 5xx).
- Justificável: `debug_token` endpoint usa schema de auth diferente (`input_token=X&access_token=Y`).
- Aceitável. Se quiser normalizar, adicionar suporte a "two-token" no `graph_api`.

**M3 — `jq ... || echo 0` silencia erros de syntax**
- `check_learnings` usa fallback gentil pra contar entries em `unknown_errors.jsonl`.
- Se JSONL tiver syntax error, silencia com 0.
- Aceitável pra CP1; se CP2 precisar diagnóstico preciso, trocar pra validação explícita.

---

### Decisões arquiteturais validadas

- **lib/_py/ pra scripts Python standalone** — pagou dividendos: todos os scripts Python passaram review sem bug de escape/heredoc hell (zero issues de injection), diferente do pattern rejeitado no review round 1.
- **shellcheck zero warnings** — obrigatório; bash-dev manteve em todos os 10 scripts.
- **Testes granulares em `02-components.sh`** — 16 testes rodando em ~2s, catch de regressão imediato.
- **Topologia de rollback com priority dict no Python** — mais fácil testar + cross-platform.

### Performance do time

- 5 agents spawnados (bash-dev, python-dev, test-dev, docs-dev sonnet/haiku + reviewer opus)
- 21 tasks em ~40 minutos wall-time
- 7 commits no git
- 16 testes automatizados passando
- 1 bug real do plano fixado (str(False)), 4 bugs de compatibilidade macOS corrigidos (BSD sed, bash 3.2 `declare -A`, `mapfile`, inconsistências)
- Issues de coordenação: bash-dev marcou tasks como completed sem commitar inicialmente → corrigido via intervenção do team-lead

### Commits finais CP1

```
f76e816 fix(tests): 01-lint.sh usa while read em vez de mapfile (bash 3.2 compat)
5b27942 docs: LEARNINGS.md com bugs/fixes + 4 follow-ups do review CP1
bea7afc feat(lib): preflight.sh com 10 checks do doctor
78edd0d chore: scaffold inicial + todos os lib helpers CP1
72721c3 chore: scaffold inicial meta-ads-pro v1.0.0-alpha.1
52ccf5d feat(_py): 4 scripts standalone (telemetry_log, manifest, log_unknown_error, detect_pattern)
22b0700 feat(docs): skills setup + doctor com 11 passos + 10 checks
```

---

## CP2 — TBD

(A preencher quando CP2 iniciar)
