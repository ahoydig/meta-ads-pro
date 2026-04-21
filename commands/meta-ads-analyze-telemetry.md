---
description: "Relatório sobre uso local do plugin — top 5 erros, sub-skills mais usadas, taxa de sucesso, duração média. Agrega ~/.claude/meta-ads-pro/telemetry.jsonl. 100% local, nunca envia nada pra fora."
---

Uso:

```
/meta-ads-analyze-telemetry [--days N] [--file PATH]
```

## Fluxo

1. **Valida opt-out.** Se `META_ADS_NO_TELEMETRY=1`, avisa que telemetria
   nunca foi coletada e sai com mensagem didática:

   ```
   ⚠ META_ADS_NO_TELEMETRY=1 ativo — nenhum dado pra analisar.
     Remova a flag em CLAUDE.md ou no env pra começar a coletar.
   ```

2. **Delega pro Python.** Este command é só wrapper fino:

   ```bash
   python3 "$CLAUDE_PLUGIN_ROOT/lib/_py/analyze_telemetry.py" "$@"
   ```

   Passa `$@` direto pra expor `--days` e `--file` do script.

3. **Imprime relatório no stdout.** O script gera markdown com:

   - Top 5 pares `code/subcode` em eventos `error_encountered`
   - Ranking de `sub_skill`
   - Taxa de sucesso (`run_completed` vs `run_failed`)
   - Duração média (em segundos) pra eventos com `duration_ms`

## Exemplo de saída

```
📊 Telemetria — últimos 30 dias (142 eventos)

Top erros:
  2635/1487390: 12x
  190/463: 4x
  613/-: 2x

Sub-skills:
  anuncios: 48x
  conjuntos: 32x
  campanha: 28x

Taxa sucesso: 38/41 (92.7%)
Duração média: 47.3s (n=38)
```

## Privacidade

- 100% local. Nenhum dado sai da máquina do usuário.
- Log JSONL: `~/.claude/meta-ads-pro/telemetry.jsonl`.
- Opt-out por `META_ADS_NO_TELEMETRY=1` (honrado por `lib/telemetry.sh`).
- Pra zerar: `rm ~/.claude/meta-ads-pro/telemetry.jsonl`.

## Libs

- `lib/_py/analyze_telemetry.py` — toda lógica de agregação (spec §5.6)
