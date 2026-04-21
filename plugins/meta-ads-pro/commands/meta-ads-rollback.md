---
description: "Rollback manual de um run específico — deleta em ordem topológica (ads → creatives → images → adsets → campaigns → forms) todos os objetos registrados no manifest do run_id fornecido. Idempotente (404 = já deletado)."
---

Uso:

```
/meta-ads-rollback {run_id}
```

Onde `{run_id}` é o ID do run salvo em `~/.claude/meta-ads-pro/current/{run_id}.json`
(ou em `history/`/`failures/` se já rodou antes).

## Fluxo

1. **Valida formato do argumento.** `run_id` deve ser alfanumérico com `-`/`_`
   (ex: `20260421-183012`, `cp3-smoke-abc`). Rejeita vazio ou com caracteres
   suspeitos (previne path traversal).

2. **Localiza o manifest.** Procura em ordem:
   - `$HOME/.claude/meta-ads-pro/current/{run_id}.json`
   - `$HOME/.claude/meta-ads-pro/failures/{run_id}.json`

   Se não encontrar, erro claro com lista dos run_ids disponíveis.

3. **Mostra resumo antes de deletar.** Preview de quantos objetos e em que
   ordem serão deletados (usa `manifest_list_for_rollback`). Pede confirmação:

   ```
   Rollback {run_id} vai deletar:
     - 3 ads
     - 2 adcreatives
     - 1 adset
     - 1 campaign

   Ordem topológica respeita dependências (ads primeiro, campaigns por último).
   Continuar? [y/N]
   ```

4. **Executa via `rollback_run`.** Carrega `lib/rollback.sh` e chama a função:

   ```bash
   source "$CLAUDE_PLUGIN_ROOT/lib/rollback.sh"
   rollback_run "$run_id"
   ```

   Retries automáticos pra erros 613/80004 (rate limit). 404 = idempotente
   (conta como "deletado"). Qualquer outro erro preserva o objeto e loga.

5. **Finaliza.** Manifest é movido pra `history/` (rollback limpo) ou
   `failures/` (se algum objeto foi preservado). Reporta contagem final:

   ```
   rollback {run_id}: 7 deletados, 0 preservados
   ```

## Regras

- **Nunca rollback automático** — este comando é sempre manual.
- Orquestradora já roda rollback automaticamente quando detecta falha mid-run;
  este comando é pra casos onde o rollback automático falhou ou o user quer
  desfazer um run bem-sucedido.
- `ROLLBACK_MOCK=1` no env pula a Graph API real (útil pra testes).

## Libs

- `lib/rollback.sh` — `manifest_list_for_rollback`, `rollback_run`
- `lib/graph_api.sh` — sourced por rollback.sh pro DELETE real
- `lib/_py/manifest.py` — serializer/ordenação topológica
