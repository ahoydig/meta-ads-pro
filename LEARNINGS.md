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

### Decisões arquiteturais validadas

- **lib/_py/ pra scripts Python standalone** — pagou dividendos: todos os scripts Python passaram review sem bug de escape/heredoc hell (zero issues de injection), diferente do pattern rejeitado no review round 1.
- **shellcheck zero warnings** — obrigatório; bash-dev manteve em todos os 10 scripts.
- **Testes granulares em `02-components.sh`** — 16 testes rodando em ~2s, catch de regressão imediato.
- **Topologia de rollback com priority dict no Python** — mais fácil testar + cross-platform.

### Performance do time

- 5 agents spawnados (bash-dev, python-dev, test-dev, docs-dev sonnet/haiku + reviewer opus)
- 21 tasks em ~40 minutos wall-time
- 5 commits no git
- 16 testes automatizados passando
- 1 bug real do plano fixado (str(False)), 3 bugs de compatibilidade macOS corrigidos (BSD sed, bash 3.2, `declare -A`)
- Issues de coordenação: bash-dev marcou tasks como completed sem commitar inicialmente → corrigido via intervenção do team-lead

---

## CP2 — TBD

(A preencher quando CP2 iniciar)
