---
name: meta-ads-doctor
description: "Diagnóstico completo do ambiente Meta Ads. Roda 10 checks (token, scopes, app mode, rate limit, ad account, page token, pixel, CLAUDE.md, learnings) e propõe fixes automáticos com --fix."
---

# meta-ads-doctor

Diagnóstico completo do ambiente Meta Ads antes de criar campanhas. Valida configuração, permissões, conta, recursos e detecta problemas.

## Quando usar

- Após rodar `/meta-ads-setup`
- Antes de criar sua primeira campanha
- Quando receber erro não esperado ("rodar doctor pra diagnóstico")
- Após renovar token

## 10 checks executados

### 1. Token válido
Testa se `META_ACCESS_TOKEN` é válido via `graph_api GET me?fields=id,name`.
- ✓ OK: mostra nome do usuário
- ✗ Bloqueador: "Token inválido — rode /meta-ads-setup"

### 2. Expiração do token
Lê `debug_token` para dias até expiração.
- ✓ OK: não expira (token never-expire)
- ⚠ Aviso: < 7 dias até expiração
- ✗ Bloqueador: Se expirado

### 3. Scopes obrigatórios
Valida 5 scopes: `ads_management`, `ads_read`, `business_management`, `leads_retrieval`, `pages_manage_ads`.
- ✓ OK: 5/5 presentes
- ✗ Bloqueador: Faltam scopes — especifica quais

### 4. App mode (dev vs live)
Cria adcreative de teste. Se erro `1885183` → app em dev mode.
- ✓ OK: app em LIVE mode (criativos diretos liberados)
- ⚠ Aviso: app em dev mode (fallback dark post ativado)
- ✗ Bloqueador: inconclusivo (algo errado no payload)

### 5. Rate limit (BUC)
Lê header `X-Business-Use-Case-Usage` para verificar if bloqueado.
- ✓ OK: rate limit baixo
- ✗ Bloqueador: rate limit bloqueado — mostra minutos de espera

### 6. Ad account ativo
Verifica `account_status == 1`.
- ✓ OK: ACTIVE (mostra currency + timezone)
- ✗ Bloqueador: account não ativo (desativado, em review, ou falha pagamento)

### 7. Page token disponível
Verifica se consegue puxar `page_id` com access_token.
- ✓ OK: página configurada (mostra nome)
- ⚠ Aviso: page token não disponível (ok se só usar WhatsApp/Lead Form)

### 8. Pixels encontrados
Lista pixels na conta.
- ✓ OK: N pixels encontrados
- ⚠ Aviso: sem pixels (ok se só usar Lead Form/WhatsApp/Messenger)

### 9. CLAUDE.md válido
Verifica se arquivo existe e tem campos obrigatórios: `ad_account_id`, `page_id`, `nomenclatura_style`.
- ✓ OK: config válido
- ✗ Bloqueador: CLAUDE.md não encontrado ou campos faltando

### 10. Learnings pendentes
Verifica se há erros desconhecidos aguardando revisão humana.
- ✓ OK: sem learnings pendentes
- ⚠ Aviso: N learnings pendentes — rode com `--review-learnings`

## Flags

- `--fix` → aplica fixes automáticos onde possível (ex: atualizar CLAUDE.md se página mudou)
- `--silent` → só output se tiver erro (usado como preflight interno)
- `--report` → gera snapshot JSON em `~/.claude/meta-ads-pro/reports/doctor-{timestamp}.json`
- `--release-lock` → remove lockfile órfão (ex: se processo crashed)
- `--review-learnings` → fila de learnings não-confirmados pra revisão humana

## Exemplos

```bash
# Full diagnostic
/meta-ads-doctor

# Com fixes automáticos
/meta-ads-doctor --fix

# Silent check (útil em pipelines)
/meta-ads-doctor --silent && echo "ok" || echo "erro detectado"

# Gerar relatório
/meta-ads-doctor --report

# Revisar erros desconhecidos aprendidos
/meta-ads-doctor --review-learnings
```

## Output esperado

Saída bem-formatada com ✓ (ok), ⚠ (aviso), ✗ (bloqueador).

Exemplo:
```
$ /meta-ads-doctor

Meta Ads Doctor — 10 checks

✓ Token válido (Flávio Sistema)
✓ Token expira em 365 dias
✓ Scopes: 5/5 necessários
✓ App em LIVE mode (criativos diretos liberados)
✓ Rate limit: ok
✓ Ad account ACTIVE (BRL, America/Recife)
✓ Page token: 200+ chars (Ahoy Digital)
✓ Pixels: 2 encontrados
✓ CLAUDE.md config válido
✓ Sem learnings pendentes

Resultado: TUDO OK ✓
Pode criar campanhas com confiança.
```

## Troubleshooting

Veja `lib/error-catalog.yaml` pra detalhes de cada erro retornado pela Meta.

Erros mais comuns no doctor:
- **Erro 190:** token inválido → rode `/meta-ads-setup` de novo
- **Erro 200:** scope faltando → gere novo token no Business Manager
- **Erro 270:** app sem acesso avançado → ativa na App Review
- **Erro 803:** account_id errado → verifica se digitou certo
- **Erro 1885183:** app em dev mode → doctor ativa fallback automático
