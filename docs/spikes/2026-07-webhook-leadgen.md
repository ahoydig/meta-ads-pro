# Spike: requisitos do webhook de leadgen (app, permissões, subscrição) — 2026-07

Repo `meta-ads-pro`, branch `feat/v1.1-operacao-ahoy`, API v25.0. Objetivo: levantar tudo
que as Tasks 9–11 (receiver FastAPI + deploy VPS + subscrição definitiva) precisam saber
antes de escrever código, sem configurar nada que dependa do receiver (que ainda não
existe).

## 1. App dono do token

```
$ graph_api GET "app?fields=id,name"
{"id":"995722365981851","name":"Ahoy - APP"}

$ graph_api GET "995722365981851?fields=name,link,category"
{"name":"Ahoy - APP","link":"https://www.facebook.com/games/?app_id=995722365981851","category":"Utilitários","id":"995722365981851"}
```

**APP_ID = `995722365981851`** ("Ahoy - APP"). Confirmado também no painel
(`developers.facebook.com/apps/995722365981851/dashboard/`) — o app aparece sob o
Business Manager **"BM - Ahoy Digital"** (ID `147944019817160`), com a Página
**"Flávio Ahoy"** (`108356564252733`, = `PAGE_ID` do `.env`) e a conta de anúncios
**"CA - Flávio Ahoy"** (`763408067802379`) já linkadas ao mesmo app/negócio.

Nota à parte, sem relação com este spike: a lista global "Ações necessárias" do painel
mostra 1 item pendente, mas é de **outro app** ("Ahoy Dev", ID `287246995891632`,
status "Restrito") — não afeta o "Ahoy - APP" usado aqui. `[não verificado — fora de
escopo]`.

## 2. Modo do app: dev ou live

Via API, `check_app_mode` (`plugins/meta-ads-pro/lib/preflight.sh:65-109`) faz um POST de
teste em `{AD_ACCOUNT_ID}/adcreatives` com `status: PAUSED` e deleta em seguida —
subcode `1885183` indicaria dev mode:

```
$ source plugins/meta-ads-pro/lib/preflight.sh
$ check_app_mode
✓ App em LIVE mode (criativos diretos liberados)
(exit code: 0)
```

Confirmado também no painel: barra superior do dashboard mostra
`Modo do aplicativo: desenvolvimento [toggle] Ao vivo`, com o toggle no estado ligado —
verificado via DOM (`aria-checked="true"` no elemento `role=switch"`) e pelo indicador
🟢 no título da aba ("🟢 Ahoy - APP — Painel").

**Conclusão: app em LIVE MODE**, nas duas fontes (API e painel).

## 3. Subscrição da página (`subscribed_apps`) — testada ao vivo

Page token obtido via `graph_api GET "${PAGE_ID}?fields=access_token"` (nunca ecoado —
só o `length` foi impresso: 203 chars). Como o page token ≠ `META_ACCESS_TOKEN`, a
chamada foi feita com `curl` direto (exceção documentada ao wrapper `graph_api`, mesma
usada no brief):

```
$ curl -sS -X POST "https://graph.facebook.com/v25.0/${PAGE_ID}/subscribed_apps" \
    -d "subscribed_fields=leadgen" -d "access_token=${PAGE_TOKEN}"
{"success":true}

$ curl -sS "https://graph.facebook.com/v25.0/${PAGE_ID}/subscribed_apps?fields=subscribed_fields&access_token=${PAGE_TOKEN}"
{"data":[{"id":"995722365981851","subscribed_fields":["leadgen"]}]}
```

**A Página `108356564252733` (Flávio Ahoy) está, neste momento, subscrita ao app
`995722365981851` com o campo `leadgen`.** Confirmado duas vezes (imediatamente após o
POST e de novo ao escrever este doc) — a subscrição não foi desfeita, conforme
instrução: **ela fica ativa pra Task 10** (quando o receiver existir, os eventos de
leadgen desta Página já vão começar a ser entregues assim que a URL de callback for
configurada na Task 11). Até lá, **não há tentativa de entrega alguma** — sem URL de
callback configurada no nível do app não existe destino cadastrado; a subscrição da
Página em si não depende da URL de callback estar configurada e permanece válida.

## 4. Permissões: Standard vs Advanced Access

Verificado ao vivo no painel (`Análise do app → Permissões e recursos`,
`developers.facebook.com/apps/995722365981851/app-review/permissions/`):

| Permissão | Nível atual | Chamadas de API | Status de análise | Requisitos p/ Advanced |
|---|---|---|---|---|
| `leads_retrieval` | **Standard access** | Ativo (89) | Nenhuma análise do app solicitada | Verificação da empresa 🟢 (feita) · Verificação de acesso ⚪ (pendente) · Análise do app ⚪ (pendente) |
| `pages_manage_ads` | **Standard access** | Ativo (10.407 mil) | Nenhuma análise do app solicitada | Verificação da empresa 🟢 (feita) · Verificação de acesso ⚪ (pendente) · Análise do app ⚪ (pendente) |
| `pages_manage_metadata` (permissão que cobre inscrever/receber webhooks de Página) | **Standard access** | Ativo (95) | Nenhuma análise do app solicitada | (mesmo padrão) |

Popup "Requisitos" do painel, texto exato pra `leads_retrieval` (idêntico pra
`pages_manage_ads`): **"Acesso padrão — Nenhum requisito"** / **"Acesso avançado —
Verificação da empresa · Verificação de acesso · Análise do app"**.

O que Standard vs Advanced significa, segundo a doc oficial
(https://developers.facebook.com/docs/graph-api/overview/access-levels, via WebFetch):

> **Acesso padrão**: "As permissões com acesso padrão só podem ser solicitadas de
> usuários que têm uma função no app solicitante."
>
> **Acesso avançado**: "As permissões com acesso avançado podem ser solicitadas de
> qualquer usuário, e os recursos com acesso avançado ficam ativos para todos os
> usuários." Necessário quando o app "será usado por pessoas que não têm uma função
> nele". Desde 1º/02/2023, apps que solicitam acesso avançado precisam estar conectados
> a uma empresa verificada (paráfrase da mesma página), e cada permissão é aprovada
> individualmente via App Review.

**Leitura pro nosso caso** `[inferência, ancorada na doc acima + no painel]`: a Página
`108356564252733` e a conta de anúncios já pertencem ao mesmo Business Manager do app
("BM - Ahoy Digital") e o usuário que controla ambos (Flávio) tem função no app — esse
é exatamente o caso que **Standard Access já cobre** ("usuários que têm uma função no
app"). O que os testes acima provam: a **subscrição** funciona em LIVE mode sem Advanced
Access, e o scope `leads_retrieval` está presente no token (`check_scopes`,
`preflight.sh:46-62`). A **leitura completa de um lead** (`GET {leadgen_id}?fields=field_data`)
ainda não foi exercitada — não existe lead entregue por webhook; o teste ponta-a-ponta é
o item 7 do checklist da Task 10. **Advanced Access só vira necessário se/quando o Ahoy operar leadgen
para Páginas de clientes fora do BM Ahoy Digital** (cenário "Tech Provider" — app usado
por gente sem função nele). Como a Verificação da empresa já está feita (🟢), falta só
Verificação de acesso + Análise do app pra essa expansão futura — não é bloqueador
para o piloto com a própria Página da Ahoy.

## 5. Tela de Webhooks do app — aceita a URL, não configurada ainda

`developers.facebook.com/apps/995722365981851/webhooks/`, produto **"Page"**
selecionável no dropdown (junto com User, Permissions, Application, Instagram, Whatsapp
Business Account, Ad Account, Catalog). Tela tem exatamente dois campos: **"URL de
callback"** e **"Verificar token"**, e um botão **"Verificar e salvar"**.

Testado (sem salvar): digitei `https://webhooks.ahoy.digital/meta-leads` no campo URL de
callback — aceito sem erro de formato; o botão "Verificar e salvar" ficaria habilitado
assim que houvesse também um verify token preenchido. **Limpei o campo antes de sair da tela —
nada foi salvo** (não cliquei em "Verificar e salvar" nem em "Remover assinatura"),
conforme instrução de não configurar ainda (o receiver da Task 9 não existe, e a Meta só
salva a config se o `GET` de verificação responder `hub.challenge` corretamente).

**App Secret**: `[não verificado — ação manual necessária]`. Fica em
`Configurações do app → Básico`, atrás de um botão "Mostrar" (requer reautenticação). Não
foi revelado nem capturado em screenshot nesta sessão — é um segredo equivalente a senha
e o roteiro desta task não pediu a extração dele. **Checklist pra Task 10**: um humano
(ou a Task 10 com confirmação explícita) deve copiar o App Secret diretamente do painel
para o `.env` do receiver — nunca para este repo, nunca ecoado em terminal/log.

## 6. Doc oficial: verificação, payload, assinatura

### GET de verificação (hub challenge)

Fonte: https://developers.facebook.com/docs/graph-api/webhooks/getting-started, seção
"Solicitações de verificação":

> `GET https://www.your-clever-domain-name.com/webhooks?hub.mode=subscribe&hub.challenge=1158201444&hub.verify_token=meatyhamhock`

O endpoint deve conferir que `hub.verify_token` bate com o token configurado e
**"Respond with the `hub.challenge` value"** (responder com o valor puro de
`hub.challenge`, tipicamente como texto/plaintext, HTTP 200).

### Assinatura da entrega (X-Hub-Signature-256)

Mesma fonte, seção "Validating Payloads":

> Header `X-Hub-Signature-256`, "preceded with `sha256=`". "Generate a SHA256 signature
> using the payload and your app's App Secret. Compare your signature to the signature
> in the `X-Hub-Signature-256` header (everything after `sha256=`). If the signatures
> match, the payload is genuine."

Ou seja: HMAC-SHA256 do corpo raw do POST, usando o **App Secret** como chave —
confirma por que o App Secret (item 5) precisa estar no `.env` do receiver: sem ele o
receiver não consegue validar que a entrega é genuína da Meta.

### Formato do payload de entrega — genérico

Mesma fonte, seção "Notificações de eventos":

```json
"entry": [{
  "time": 1520383571,
  "changes": [{
    "field": "photos",
    "value": { "verb": "update", "object_id": "..." }
  }],
  "id": "...",
  "uid": "..."
}]
```

O endpoint deve responder **200 OK HTTPS** a toda notificação recebida (senão a Meta
reenvia/desativa a subscrição).

### Formato do payload de entrega — especifico de `leadgen`

Fonte: https://developers.facebook.com/docs/marketing-api/guides/lead-ads/webhooks:

```json
"field": "leadgen",
"value": {
  "leadgen_id": 123123123123,
  "page_id": 123123123,
  "form_id": 12312312312,
  "adgroup_id": 12312312312,
  "ad_id": 12312312312,
  "created_time": 1440120384
}
```

Ou seja: o payload de leadgen **não traz os dados do formulário** (nome, telefone,
e-mail etc.) — só o `leadgen_id`. O receiver (Task 9) precisa, ao receber o evento, fazer
um `GET {leadgen_id}?fields=field_data,...` (com `leads_retrieval`) pra buscar os campos
reais capturados. Isso é importante pro design do receiver: o webhook é só o "aviso",
não o lead completo.

## 7. Verify token — gerado, não exposto

```
$ openssl rand -hex 24
```

Gerado e salvo em `.env` como `META_WEBHOOK_VERIFY_TOKEN=...` (48 chars hex). O `.env`
está no `.gitignore` (`git check-ignore -v .env` → `.gitignore:6:.env`) e **não** foi
commitado. O valor do token **não** é ecoado neste documento nem em nenhum output de
terminal desta sessão.

## 8. Checklist exato pra Task 10/11

Pré-requisitos já prontos (não repetir):
- [x] APP_ID identificado (`995722365981851`, "Ahoy - APP", LIVE mode).
- [x] Subscrição da Página `108356564252733` em `leadgen` — ativa, confirmada 2x via API.
- [x] `META_WEBHOOK_VERIFY_TOKEN` gerado no `.env` (não commitado).
- [x] Permissões `leads_retrieval` e `pages_manage_ads` confirmadas ativas em Standard
  Access — suficiente pro piloto com a Página própria da Ahoy.

O que a Task 10 (deploy do receiver na VPS) e a Task 11 (config final do painel) vão
executar, na ordem:

1. Subir o receiver FastAPI (Task 9) na VPS, expor via `webhooks.ahoy.digital/meta-leads`
   (TLS já resolvido pelo domínio existente — checar Cloudflare/tunnel conforme runbook
   de deploy do projeto Hermes, se aplicável a este host).
2. Receiver deve implementar:
   - `GET /meta-leads` → valida `hub.verify_token == $META_WEBHOOK_VERIFY_TOKEN`, responde
     com `hub.challenge` puro (texto), HTTP 200.
   - `POST /meta-leads` → valida `X-Hub-Signature-256` (HMAC-SHA256 do body raw com o
     App Secret), responde HTTP 200 rápido, processa assíncrono (buscar
     `field_data` via `GET {leadgen_id}?fields=...` com `leads_retrieval`).
3. Copiar o App Secret do painel (`Configurações do app → Básico → Mostrar`) direto pro
   `.env` do receiver na VPS — nunca por este repo, nunca ecoado em terminal.
4. Copiar `META_WEBHOOK_VERIFY_TOKEN` deste `.env` local pro `.env` do receiver (mesmo
   valor dos dois lados, ou o `GET` de verificação vai falhar).
5. No painel → **Webhooks → produto "Page"**: preencher URL de callback
   `https://webhooks.ahoy.digital/meta-leads` + o verify token, clicar **"Verificar e
   salvar"** — só depois do receiver estar no ar e respondendo ao `hub.challenge`.
6. Confirmar no painel (ou via `GET /{PAGE_ID}/subscribed_apps?fields=subscribed_fields`)
   que a subscrição em `leadgen` continua ativa — já está, não precisa recriar.
7. Testar ponta a ponta: gerar um lead de teste (Ads Manager → formulário de teste ou
   lead real de baixo volume) e confirmar que o receiver recebeu o POST, validou a
   assinatura, e conseguiu buscar `field_data` via `leads_retrieval`.
8. Só se/quando o Ahoy for operar leadgen pra Páginas de clientes fora do BM Ahoy
   Digital: solicitar Advanced Access pra `leads_retrieval`/`pages_manage_ads`
   (Verificação da empresa já feita; falta Verificação de acesso + Análise do app) —
   não bloqueia o piloto atual.

## Atualização — execução real da Task 10 (2026-07-09)

Runbook completo em `webhook-receiver/deploy/RUNBOOK.md`. Resumo do que mudou em
relação ao checklist acima:

- [x] Item 1-2 (subir o receiver + implementar GET/POST) — **DONE**. Serviço
  `meta-leads.service` rodando em `127.0.0.1:8811` na VPS (`root@5.78.224.81`),
  `GET /meta-leads/health` e o handshake `hub.challenge` testados e OK localmente.
- [ ] Item 1 (expor via `webhooks.ahoy.digital/meta-leads`) — **BLOCKED**. Achado
  importante: o tunnel `ahoy-hermes` é **remotamente gerenciado** (`cloudflared tunnel
  run --token ...`), não tem `/etc/cloudflared/config.yml` local — as rotas
  (`hermes.ahoy.digital`, `webhooks.ahoy.digital`→`:8644`, `preview.ahoy.digital`)
  vivem na config remota do painel Cloudflare Zero Trust. Adicionar a rota
  `/meta-leads*`→`:8811` exige login no painel (Cloudflare One → Networks → Tunnels →
  `ahoy-hermes` → Public Hostname) — o token de API já presente na VPS
  (`/root/.hermes/secrets/cloudflare-api-token`) não tem escopo de `Cloudflare Tunnel:
  Edit` (`403`/`code 1001` testado ao vivo). Confirmado externamente: `curl
  https://webhooks.ahoy.digital/meta-leads/health` → `404` (cai no catch-all do
  webhook nativo do Hermes). Detalhe completo + instrução exata pro humano no
  RUNBOOK.md §8.
- [x] Item 3 (App Secret) — **tentado, BLOCKED**. Painel pediu reautenticação por
  senha ao clicar "Mostrar" em Configurações do app → Básico — modal cancelado sem
  submeter (regra: agente não digita/confirma senha). `.env` da VPS ficou com
  `META_APP_SECRET=PENDENTE_HUMANO`.
- [x] Item 5 (Verify and Save no painel) — **não tentado de propósito**: sem a rota
  pública (item acima), a Meta chamaria o `GET` e bateria no `404` do webhook do
  Hermes — não faz sentido tentar salvar antes do §8 do runbook ser resolvido.
  Documentado na mesma visita: a tela "Configurar um webhook" tem um toggle **"Anexe
  um certificado de cliente às solicitações de webhook"** — é a opção de **mTLS** do
  changelog v25, existe na UI, desligada por padrão, não ativada (fora de escopo desta
  task).
- [x] Item 6 (reconfirmar subscrição da Página em `leadgen`) — **reconfirmado ao
  vivo**, 3ª vez: `GET /108356564252733/subscribed_apps?fields=subscribed_fields` (com
  page token) → `{"data":[{"id":"995722365981851","subscribed_fields":["leadgen"]}]}`.
- [ ] Item 7 (teste e2e com lead de teste) — **pulado**, depende dos dois blockers
  acima (rota pública + App Secret).

## Fontes consultadas (2026-07-09, via WebFetch)

- https://developers.facebook.com/docs/graph-api/webhooks/getting-started — verificação
  (`hub.challenge`), assinatura (`X-Hub-Signature-256`), payload genérico.
- https://developers.facebook.com/docs/graph-api/webhooks/getting-started/webhooks-for-pages
  — estrutura `entry[].changes[].value` específica de Página.
- https://developers.facebook.com/docs/marketing-api/guides/lead-ads/webhooks — payload
  específico de `leadgen` (`leadgen_id`, `page_id`, `form_id`, `adgroup_id`, `ad_id`,
  `created_time`).
- https://developers.facebook.com/docs/permissions/reference/leads_retrieval — descrição
  da permissão.
- https://developers.facebook.com/docs/graph-api/overview/access-levels — Standard vs
  Advanced Access.
- Painel `developers.facebook.com/apps/995722365981851/` (Dashboard, Permissões e
  recursos, Webhooks) — via browser isolado (`~/.bh-chrome-profile`, perfil já logado),
  screenshots e leitura de DOM em 2026-07-09.
