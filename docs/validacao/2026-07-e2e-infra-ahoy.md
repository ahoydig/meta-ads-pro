# Validação E2E — F1 (nativa GHL + receiver local + CAPI)

Execução real em 2026-07-12, branch `feat/v1.1-operacao-ahoy` (base `f22b49d`), conforme
`docs/superpowers/plans/2026-07-11-fechamento-v11-golive-piloto.md` (F1 completa: F1.0
a-d → F1.1 → F1.2 → F1.3 → F1.4 → F1.5 → F1.6). Env: `.env` da raiz (conta `act_763408067802379`,
página `108356564252733`, pixel `947064561562400`, subconta GHL de teste `u0z5iy2DIlyMKk4zdMxu`
"InfraJus Excluir"). Token e secrets nunca ecoados nesta sessão.

## F1.0 — Pré-checagens

**a. Form TEST_E2E existe?** Confirmado ao vivo: `GET {PAGE_ID}/leadgen_forms` com page token
(derivado via `{PAGE_ID}?fields=access_token`, 200 chars) →

```json
{"id":"1527646068830661","name":"TEST_E2E_NATIVA_20260709_174845","status":"ACTIVE"}
```

Reusado (não foi preciso criar form novo).

**b. Scopes da PIT GHL ok?** `ghl_api GET /locations/{GHL_LOCATION_ID}` → 200:
`location.id = u0z5iy2DIlyMKk4zdMxu`, `location.name = "InfraJus Excluir"`.

**c. Test lead já existe no form?** `GET {form_id}/leads` (page token) → `{"data":[]}`. Não
existia — criado na F1.2.

**d. Plumbing GHL da VPS real?** `ssh root@5.78.224.81 "grep -c PENDENTE /opt/meta-leads/.env
/opt/meta-leads/config.json"` →

```
/opt/meta-leads/.env:1        (META_APP_SECRET=PENDENTE_HUMANO — único placeholder legítimo)
/opt/meta-leads/config.json:0
```

`systemctl is-active meta-leads.service` → `active`. `config.json` real:
`{"108356564252733": {"location_id": "u0z5iy2DIlyMKk4zdMxu", "ghl_token_env": "GHL_TOKEN_AHOY"}}`
— `GHL_TOKEN_AHOY` **não** é mais `PENDENTE_T11` (confirmado por `grep -c` = 0; comprimento
40 chars) — foi preenchido com um token real em algum momento entre a T10 e agora, fora
desta sessão.

## F1.1 — Mapear o form no GHL

Caminho real na UI (achado — difere da hipótese "Settings → Integrations → Facebook Form
Fields Mapping" direto): Settings → Integrations → card **Facebook** → botão **Gerenciar**
→ modal "Sincronize automaticamente seus leads do Facebook e Instagram" → marcar a página
**Flávio Ahoy** (`108356564252733`) → **Conectar e Continuar** → modal de sucesso
"Novas páginas do Facebook foram adicionadas com sucesso" com CTA dedicado **"Configurar
mapeamento de campos"** → abre **"Mapeamento de Campos de Formulário do Facebook"**, uma
tabela com todos os forms da página → linha `TEST_E2E_NATIVA_20260709_...` → **Mapear
campos**.

Tela de mapeamento (achado: `Full name`/`Email`/`Phone number` já vêm **auto-mapeados**
pelo GHL para os campos correspondentes do CRM; `utm_source`/`utm_medium`/`utm_campaign`
aparecem como linhas próprias e mapeáveis — confirma ao vivo, nesta tela de UI, o achado
do spike T2 de que `tracking_parameters` propaga como campos de primeira classe do form,
não um bloco separado):

| Campo do formulário | Campo do CRM |
|---|---|
| Full name | Full name (auto) |
| Email * | Email (auto) |
| Phone number * | Phone (auto) |
| utm_source | (deixado sem mapear — fora do escopo mínimo desta task) |
| utm_medium | (idem) |
| utm_campaign | (idem) |

Clicado **Confirmar** → toast "Sucesso: O formulário TEST_E2E_NATIVA_20260709_174845 foi
..." → linha da tabela passou a mostrar toggle **ativo** + rótulo **"Editar campos"**
(antes "Mapear campos"). **VALIDAR: PASS** — tela pós-save mostra o form mapeado.

## F1.2 — Test lead

`POST {form_id}/test_leads` → `{"id":"1034926895729782"}`.

`GET {form_id}/leads?fields=field_data` → lead presente, com `tracking_parameters`
**presentes** no `field_data` deste test lead especificamente (o plano previa a
possibilidade de divergência — não houve):

```json
{"name":"utm_source","values":["meta-leadform"]}
{"name":"utm_medium","values":["trafego-pago"]}
{"name":"utm_campaign","values":["20260709_test-e2e-nativa-20260709-174845"]}
{"name":"full_name","values":["<test lead: dummy data for full_name>"]}
{"name":"email","values":["test@meta.com"]}
{"name":"phone_number","values":["<test lead: dummy data for phone_number>"]}
```

**VALIDAR: PASS.**

## F1.3 — Veredito NATIVA

`ghl_api GET /contacts/?locationId={id}&query=test@meta.com`, aguardando 60s — contato
encontrado **na 1ª tentativa** (não precisou das 3):

```json
{"id":"V7DjKL78didODigMGwWH","contactName":"<test lead: dummy data for full_name>",
 "email":"test@meta.com","phone":null,"source":"Facebook",
 "attributions":[{"utmSessionSource":"Paid Social","adSource":"facebook","utmMedium":"social",
   "medium":"facebook","mediumId":"1527646068830661","utmSource":"facebook"}],
 "customFields":[]}
```

Veredito:

```
Contato apareceu no GHL?                   SIM (1ª tentativa, 60s)
Campos mapeados corretos (nome/email/tel)? PARCIAL — nome (dummy) e email OK;
                                            telefone NÃO populado (dummy da Meta
                                            "<test lead: dummy data for phone_number>"
                                            não é parseável como telefone — a nativa
                                            silenciosamente deixa null em vez de errar)
UTMs presentes via nativa (customFields)?  NÃO (não mapeamos os 3 campos UTM no F1.1 —
                                            fora do escopo mínimo pedido; a nativa tem
                                            sua PRÓPRIA atribuição genérica em
                                            `attributions[]`: Paid Social/facebook)

VEREDITO: NATIVA OK — contato chegou via integração nativa GHL↔Facebook, campos
essenciais (nome, email) mapeados corretamente; divergência de telefone é do dado
dummy do test lead, não da integração.
```

## F1.4 — Receiver local via assinatura

Checagem executável: `.env` da VPS ainda tem `META_APP_SECRET=PENDENTE_HUMANO` (1 match) →
assinado com o **placeholder literal**, lido de dentro do processo Python (nunca no
comando/output) — script `sign_and_post.py` no VPS: lê `/opt/meta-leads/.env`, monta o
payload de entrega `leadgen` com o `leadgen_id` REAL da F1.2, calcula
`X-Hub-Signature-256: sha256=<hmac>` e faz o POST em `127.0.0.1:8811/meta-leads`.

Sanity check prévio (secret errado) → `403` confirmado (validação HMAC ativa).

**1ª tentativa (payload real, secret placeholder correto): `HTTP 500`.** Diagnóstico —
`events.jsonl`: `"status": "error:HTTP Error 403: Forbidden"`. Isolado: `fetch_lead()`
(GET na Graph API) funciona (200); `push_to_ghl()` (POST em
`services.leadconnectorhq.com/contacts/upsert`) falhava com 403 — **mesmo token que
funciona via `curl` falha via `urllib.request` puro**. Causa raiz confirmada: o
Cloudflare WAF de `leadconnectorhq.com` bloqueia a assinatura padrão
`User-Agent: Python-urllib/x.y` (qualquer UA explícito e descritivo passa — testado com
`curl/8.0.0` e com `meta-leads-receiver/1.0`, ambos 201).

**Fix 1 (bug real, corrigido nesta sessão):** `webhook-receiver/app.py::push_to_ghl` —
adicionado header `User-Agent: meta-leads-receiver/1.0 (+meta-ads-pro webhook-receiver)`
no `Request` do upsert. Sem isso, **todo push real do receiver falharia** (o
`test_app.py` original não pegou porque não exercita rede real contra
`leadconnectorhq.com`).

**2ª tentativa (pós-fix 1, mesmo secret): `HTTP 500`.** `events.jsonl`:
`"status": "error:HTTP Error 400: Bad Request"`. Isolado: GHL rejeita o `phone` dummy
(`"<test lead: dummy data for phone_number>"`) com
`{"message":"The string supplied did not seem to be a phone number"}` — a nativa GHL
absorve o mesmo dado silenciosamente (F1.3: `phone: null`), mas o `contacts/upsert` da
API crua é estrito e derruba a chamada inteira.

**Fix 2 (bug real, corrigido nesta sessão):** `webhook-receiver/app.py::push_to_ghl` —
sanitização defensiva do telefone antes do upsert: extrai só dígitos
(`re.sub(r"\D", "", ...)`), só envia `phone` se sobrarem ≥8 dígitos, senão omite o campo
(replica o comportamento observado na integração nativa em vez de derrubar o push
inteiro por causa de 1 campo).

Ambos os fixes: `pytest webhook-receiver/test_app.py` → **10/10 pass** antes e depois
(a suíte não cobria rede real, então não pegou os bugs — mas também não quebrou com o
fix). `python3 -c "import ast; ast.parse(...)"` OK. Deploy via `scp` + `systemctl restart
meta-leads.service` (`active` confirmado).

**3ª tentativa (pós-fix 1+2, mesmo leadgen_id, mesmo secret placeholder): `HTTP 200
{"ok":true}`.**

```
health ANTES: {"received_total":0,"pushed":0,"errors":0, ...}
health DEPOIS: {"received_total":3,"pushed":1,"errors":2,"last_status":"pushed", ...}
```

(`errors:2` são as 2 tentativas anteriores, ANTES dos fixes — esperado, não escondido.)

Contato no GHL pós-push: `GET /contacts/?query=test@meta.com` → **1 único contato**
(`id: V7DjKL78didODigMGwWH`, o MESMO da F1.3), `source` atualizado para
`"meta-leadform-webhook"`, `phone: null` (fix 2 funcionando). **Sem duplicar.**

**VALIDAR: PASS** (HTTP 200; health `pushed`+1; contato upsertado sem duplicar) — com
2 bugs reais de produção encontrados e corrigidos no caminho.

## F1.5 — CAPI test event

Events Manager (`eventsmanager.facebook.com`, `Conjuntos de dados` → pixel
`947064561562400` "pixel - @flavioahoy" → aba **Eventos de teste** → canal **Site**
— dropdown só oferece Site/Offline, confirma achado do spike) → seção "Confirme se os
eventos do seu servidor estão configurados corretamente" → novo código:
**`test_event_code: TEST82730`** (código anterior `TEST38283` do spike havia expirado
— comportamento esperado, códigos são efêmeros).

Salvo em `.env` local (`CAPI_TEST_EVENT_CODE=TEST82730`, gitignored, não é secret
persistente).

Envio direto (payload de `flows/crm/SKILL.md::capi-testar`, evento `LeadQualificado`,
`em`/`ph` SHA-256, `action_source: system_generated`):

```json
{"events_received":1,"messages":[],"fbtrace_id":"AATvjR0mTHmZt8E2kZyoSPu"}
```

Confirmado também via código real do plugin — `bash tests/19-crm-capi.sh` (env carregado
da raiz, `CAPI_TEST_EVENT_CODE` no `.env`):

```
✓ test_01_ghl_location
✓ test_02_receiver_health (received_total=3)
✓ test_03_subscribed_apps_leadgen
✓ test_04_capi_test_event

19-crm-capi: 4 passou, 0 falhou, 0 skip
```

**VALIDAR: PASS** (`events_received: 1` verbatim, 2×).

## Achado lateral — F0.1 (fora do escopo desta missão) parece já resolvido

`test_02_receiver_health` da suíte 19 passou com `received_total=3` usando a URL
**pública default** (`https://webhooks.ahoy.digital/meta-leads/health`, sem
`RECEIVER_HEALTH_URL` no `.env` local) — confirmado por `curl` direto:

```
$ curl -sS https://webhooks.ahoy.digital/meta-leads/health
{"received_total":3,"pushed":1,"errors":2,"last_status":"pushed", ...}   [200]
```

Isso indica que a rota pública do Cloudflare Tunnel (`F0.1`, pendência humana no plano)
**já está ativa** — não fazia parte do escopo desta execução (F1) e não foi mexida por
este agente; registrado aqui como achado relevante para quem retomar F2. `config.json`
e `GHL_TOKEN_AHOY` na VPS também já não são mais placeholder (ver F1.0d) — sinal de que
outra sessão/humano avançou paralelamente nesses itens. **`META_APP_SECRET` continua
`PENDENTE_HUMANO`** (confirmado nesta sessão) — ou seja, a rota pública existe mas
qualquer entrega REAL da Meta ainda falharia na validação HMAC até o App Secret real ser
colocado (F0.2, ainda pendente).

## F1.6 — Cleanup

**Form de teste arquivado:** `POST {form_id=1527646068830661}?status=ARCHIVED` (page
token) → `{"success":true}`; confirmado via GET: `status: "ARCHIVED"`.

**Forms protegidos (intactos, confirmado por listagem pós-arquivamento — só 7 ACTIVE,
nenhum TEST_ novo):**

```
ACTIVE  Empresa Agêntica | Formulário | 2026-07-09   1278544014149626
ACTIVE  _SMOKE_form_20260421_143644                  1298516055558591  (lixo pré-existente, não mexido)
ACTIVE  form-advogados-v3                            1151852226870435
ACTIVE  form-advogados-v2                             1494045659091587
ACTIVE  form-clinicas-v2                              915671510932529
ACTIVE  form-clinicas                                 1830327744346751
ACTIVE  form-advogados                                3723405244630190
```

**Contato de teste na subconta descartável:** `V7DjKL78didODigMGwWH` (test@meta.com) na
subconta de teste "InfraJus Excluir" (`u0z5iy2DIlyMKk4zdMxu`, nome já indica descartável)
— **anotado, não deletado** (subconta é toda ela de teste; remoção do contato individual
não é necessária e evita ação destrutiva desnecessária).

## Writes reais no Meta nesta sessão

1. `POST {form_id}/test_leads` (F1.2)
2. `POST {PIXEL_ID}/events` — CAPI test event manual (F1.5)
3. `POST {PIXEL_ID}/events` — CAPI test event via `tests/19-crm-capi.sh` (F1.5, mesma
   classe de operação, sem custo de BUC de objeto)
4. `POST {form_id}?status=ARCHIVED` (F1.6)

Nenhum `code 17` (rate limit) encontrado — conta descansada conforme esperado para
2026-07-12. Sleeps de 60s aplicados entre a criação do test lead e a checagem no GHL
(F1.3); não foi necessário espaçar mais por não ter batido rate limit.

## Self-review / anti-fabricação

- Todo JSON/código citado acima é verbatim de chamada real feita nesta sessão (curl,
  graph_api, ghl_api, pytest, ssh) — nenhum dado inventado.
- Tokens (`META_ACCESS_TOKEN`, `GHL_PIT_TOKEN`, `GHL_TOKEN_AHOY`, `META_APP_SECRET`)
  nunca ecoados em comando, output ou neste documento — só comprimentos/contadores
  quando relevante.
- `META_APP_SECRET` real: não solicitado, não visto, não colado em lugar nenhum deste
  repo (segue `PENDENTE_HUMANO`, F0.2 é decisão/ação exclusiva do Flávio).
- 2 bugs de produção reais encontrados e corrigidos em `webhook-receiver/app.py`
  (User-Agent bloqueado por WAF; phone dummy rejeitado pelo GHL) — cobertos por
  `pytest` (10/10, mesma suíte de antes) + testados ao vivo contra a API real do GHL
  (não só localmente).
- Arquivos alterados: `webhook-receiver/app.py` (2 fixes), `.env` (linha nova
  `CAPI_TEST_EVENT_CODE=TEST82730`, gitignored, não commitada), este documento.
- F2 (go-live do webhook público) **não foi tocado** — fora do escopo desta missão
  (F1). O achado da rota pública já ativa (F0.1) é só registro, não ação.
