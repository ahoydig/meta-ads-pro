---
name: meta-ads-doctor
description: "Diagnóstico completo do ambiente Meta Ads. Roda 14 checks (token, scopes, app mode, rate limit, ad account, page token, pixel, CLAUDE.md, learnings, GHL/FluxiHub, receiver de leadgen, subscrição leadgen, dataset CAPI) e propõe fixes automáticos com --fix."
---

# meta-ads-doctor

Diagnóstico completo do ambiente Meta Ads antes de criar campanhas. Valida configuração, permissões, conta, recursos e detecta problemas.

## Quando usar

- Após rodar `/meta-ads-setup`
- Antes de criar sua primeira campanha
- Quando receber erro não esperado ("rodar doctor pra diagnóstico")
- Após renovar token

## 14 checks executados

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

### 11. GHL/FluxiHub conectável
Testa `GHL_PIT_TOKEN`/`GHL_LOCATION_ID` (Private Integration da subconta) contra `GET locations/{id}` na API do GHL/FluxiHub (`services.leadconnectorhq.com`).
- ✓ OK: mostra nome da subconta
- ⚠ Aviso: GHL não configurado (ok se não usa CRM — rode `/meta-ads-crm` pra configurar)
- ✗ Bloqueador: token/location inválidos — regenerar Private Integration

### 12. Receiver de leadgen no ar
Faz `GET` em `RECEIVER_HEALTH_URL` e espera um campo `received_total` no JSON de resposta.
- ✓ OK: receiver up (mostra total de leads recebidos)
- ⚠ Aviso: `RECEIVER_HEALTH_URL` não configurado (webhook de atribuição off)
- ✗ Bloqueador: receiver fora do ar/URL não responde JSON válido — leads seguem só pela nativa GHL

### 13. Página subscrita em leadgen
Deriva o **page token** internamente (`GET {page_id}?fields=access_token`, nunca ecoado) e confere `{page_id}/subscribed_apps?fields=subscribed_fields` — esse endpoint exige page token, não o `META_ACCESS_TOKEN` normal (confirmado ao vivo, ver `docs/spikes/2026-07-webhook-leadgen.md`).
- ✓ OK: página subscrita em leadgen
- ⚠ Aviso: sem page token pra checar, OU página sem subscrição leadgen (webhook não recebe — ver runbook Task 10)

### 14. Dataset CAPI ativo
Verifica `PIXEL_ID` e lê `last_fired_time` via `GET {pixel_id}?fields=name,last_fired_time`.
- ✓ OK: mostra timestamp do último evento
- ⚠ Aviso: sem `PIXEL_ID` (CAPI do funil inativa), OU pixel sem eventos ainda (rodar `/meta-ads-crm capi-testar`)

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

Meta Ads Doctor — 14 checks

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
⚠ GHL não configurado (ok se não usa CRM) — /meta-ads-crm
⚠ Receiver não configurado (webhook de atribuição off)
✓ Página subscrita em leadgen
✓ CAPI/pixel: último evento em 2026-07-08T14:18:22+0000

Resultado: TUDO OK ✓ (avisos não bloqueiam — GHL e receiver são opcionais)
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
- **GHL token/location inválidos (check 11):** regenere o Private Integration Token direto na subconta (Configurações → Private Integrations) — token de agência/API key global não serve
- **Receiver fora do ar (check 12):** confira se o processo está de pé na VPS e se `RECEIVER_HEALTH_URL` aponta pro domínio certo (default `https://webhooks.ahoy.digital/meta-leads/health`)
- **Sem subscrição leadgen (check 13):** siga o runbook da Task 10 pra subscrever a Página em `subscribed_apps` com `subscribed_fields=leadgen`
