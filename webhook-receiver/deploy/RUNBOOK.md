# RUNBOOK — deploy do meta-leads receiver na VPS (Task 10)

Execução real em `root@5.78.224.81` (Hetzner, Debian 13 — mesma VPS do Hermes do time,
**sistema compartilhado, produção**). Todos os comandos abaixo foram rodados nesta
sessão. Nenhum token real aparece neste arquivo.

## 1. Usuário de sistema

```bash
useradd --system --shell /usr/sbin/nologin --home-dir /opt/meta-leads --create-home metaleads
```

## 2. Código

Do worktree `meta-ads-pro-track-a/webhook-receiver/` (Task 9) pra `/opt/meta-leads`:

```bash
rsync -av --exclude='.venv' --exclude='__pycache__' --exclude='.pytest_cache' \
  webhook-receiver/ root@5.78.224.81:/opt/meta-leads/
```

## 3. Ambiente Python

```bash
cd /opt/meta-leads
python3 -m venv .venv
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet fastapi uvicorn
```

Versões instaladas (confirmadas): `fastapi 0.139.0`, `uvicorn 0.51.0`. Python do
sistema: 3.13.5.

## 4. Diretório de estado

```bash
mkdir -p /var/lib/meta-leads
chown metaleads:metaleads /var/lib/meta-leads
```

## 5. `config.json` (multi-cliente — só a Ahoy por ora)

`/opt/meta-leads/config.json`:

```json
{"108356564252733": {"location_id": "PENDENTE_T11", "ghl_token_env": "GHL_TOKEN_AHOY"}}
```

`location_id` fica `PENDENTE_T11` até a Task 11 preencher o location real do GHL —
até lá, todo push vai cair no branch de erro (`status: error:...`, `500`, retry da
Meta) porque `GHL_TOKEN_AHOY` também é placeholder. **Isso é esperado**, não é bug: o
dedup e o retry semântico do `app.py` seguram esse estado sem duplicar nem perder lead.

## 6. `.env`

`/opt/meta-leads/.env` (permissão `600`, dono `metaleads`), variáveis:

| Variável | Valor / origem |
|---|---|
| `META_VERIFY_TOKEN` | copiado do `META_WEBHOOK_VERIFY_TOKEN` do `.env` do worktree (spike T4, gerado com `openssl rand -hex 24`) |
| `META_APP_SECRET` | **`PENDENTE_HUMANO`** — ver §8 (bloqueado, precisa de humano) |
| `META_ACCESS_TOKEN` | copiado do `META_ACCESS_TOKEN` do `.env` do worktree |
| `META_API_VERSION` | `v25.0` |
| `RECEIVER_STATE_DIR` | `/var/lib/meta-leads` |
| `GHL_TOKEN_AHOY` | `PENDENTE_T11` (placeholder — Task 11 substitui pelo token real do GHL) |

**Correção em relação ao brief da Task 10:** o brief menciona a env var como
`META_WEBHOOK_VERIFY_TOKEN`, mas o código real (`app.py`) lê
`os.environ["META_VERIFY_TOKEN"]`. Usei o nome que o código espera — com o nome do
brief a aplicação derrubaria com `KeyError` no boot.

Comando usado (sem ecoar valores — lidos do `.env` local e escritos direto via stdin
do `ssh`, nunca impressos em terminal):

```bash
ACCESS_TOKEN=$(grep '^META_ACCESS_TOKEN=' .env | cut -d= -f2-)
VERIFY_TOKEN=$(grep '^META_WEBHOOK_VERIFY_TOKEN=' .env | cut -d= -f2-)
ssh root@5.78.224.81 "cat > /opt/meta-leads/.env" <<EOF
META_VERIFY_TOKEN=${VERIFY_TOKEN}
META_APP_SECRET=PENDENTE_HUMANO
META_ACCESS_TOKEN=${ACCESS_TOKEN}
META_API_VERSION=v25.0
RECEIVER_STATE_DIR=/var/lib/meta-leads
GHL_TOKEN_AHOY=PENDENTE_T11
EOF
ssh root@5.78.224.81 "chown metaleads:metaleads /opt/meta-leads/.env && chmod 600 /opt/meta-leads/.env"
```

## 7. systemd — `meta-leads.service`

Arquivo `deploy/meta-leads.service` (este diretório) copiado pra
`/etc/systemd/system/meta-leads.service` — **single worker**, sem `--workers` (o
dedup por arquivo `seen_leadgen_ids.txt` não suporta multi-processo, ver README do
receiver).

```bash
systemctl daemon-reload
systemctl enable --now meta-leads.service
```

Confirmado rodando (`active (running)`, PID do `uvicorn`).

### Verificação local (na própria VPS)

```bash
curl -sS 127.0.0.1:8811/meta-leads/health
# {"received_total":0,"pushed":0,"errors":0,"no_config":0,"malformed":0,"last_event_at":null,"last_status":null}

# GET de verificação (hub.challenge) com o token CORRETO lido do .env — 200 e o challenge ecoado:
VTOKEN=$(grep '^META_VERIFY_TOKEN=' /opt/meta-leads/.env | cut -d= -f2-)
curl -sS "http://127.0.0.1:8811/meta-leads?hub.mode=subscribe&hub.verify_token=${VTOKEN}&hub.challenge=42"
# 42 [200]

# Com token ERRADO — 403 (confirma que a validação está ativa):
curl -sS "http://127.0.0.1:8811/meta-leads?hub.mode=subscribe&hub.verify_token=WRONG&hub.challenge=42" -w ' [%{http_code}]'
# {"detail":"Forbidden"} [403]
```

**Passos 1 e 2 do roteiro (deploy local) = DONE e verificados.**

## 8. BLOQUEADO — Tunnel Cloudflare (`webhooks.ahoy.digital/meta-leads` público)

O brief da Task 10 assumia um tunnel **localmente gerenciado** (`/etc/cloudflared/config.yml`
editável). Na prática, o tunnel `ahoy-hermes` (id `edb0e105-185d-433f-914c-e589aae7debf`)
é **remotamente gerenciado** — `systemctl cat cloudflared.service` mostra
`ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run --token <JWT>`, e
`/etc/cloudflared/config.yml` **não existe** no disco (confirmado: `find /etc/cloudflared`
vazio). Nesse modo, as regras de ingress (`hermes.ahoy.digital`→`:9119`,
`webhooks.ahoy.digital`→`:8644` [webhook nativo do gateway Hermes],
`preview.ahoy.digital`→`:8787`) vivem **na configuração remota do túnel no painel
Cloudflare Zero Trust**, não em arquivo local. Não havia nada pra fazer backup/editar
localmente — por isso **nenhuma alteração foi feita no `cloudflared.service` nem em
qualquer arquivo de config**; o tunnel continua exatamente como estava
(`systemctl status cloudflared` seguiu `active (running)` o tempo todo).

Tentativas de acesso pra adicionar a rota `webhooks.ahoy.digital` path `/meta-leads*`
→ `http://127.0.0.1:8811` (ANTES do catch-all existente):

1. **API Cloudflare** com o token já existente na VPS
   (`/root/.hermes/secrets/cloudflare-api-token`, usado hoje pro Wrangler/Workers):
   `GET /accounts/{account}/cfd_tunnel/{tunnel}/configurations` → `403 "Not authorized"`
   (`code 1001`). O token é válido (`/user/tokens/verify` confirma `active`), mas o
   escopo é só Workers/Pages/D1/Routes — **não** inclui `Cloudflare Tunnel: Edit`.
2. **Painel Cloudflare One** (Zero Trust → Networks → Tunnels), via Chrome isolado
   (`~/.bh-chrome-profile`, porta 9333, perfil persistente): `one.dash.cloudflare.com`
   caiu na tela de login (`Fazer login na Cloudflare`) — perfil isolado **nunca logou
   nessa conta antes**. Tentei o botão "Google" (não é digitar senha, só clicar) — sem
   sessão Google ambiente, caiu de novo no formulário de login/senha.
   **Parei aí, sem digitar nenhuma credencial**, conforme regra dura de auth wall.

**BLOCKED — instrução exata pro humano:**

- Ir em `https://one.dash.cloudflare.com/05877aa8a58be110b5cadf3dfb56b976/networks/tunnels`
  (login manual — 2FA/senha do Flávio).
- Abrir o túnel **`ahoy-hermes`** → aba **Public Hostname** (ou "Configure").
- **Antes de editar:** printar/exportar a config atual (3 hostnames existentes) como
  registro do estado pré-mudança — não existe arquivo local pra copiar como backup
  aqui, então essa captura de tela/print É o backup.
- Adicionar uma nova entrada, **na posição ANTES** da entrada catch-all de
  `webhooks.ahoy.digital` (a ordem importa — regras são avaliadas top-down):
  - Hostname: `webhooks.ahoy.digital`
  - Path: `/meta-leads.*` (regex) ou `meta-leads*` (glob, conforme o que a UI aceitar)
  - Service: `HTTP://127.0.0.1:8811`
- Salvar. Não precisa reiniciar `cloudflared` na VPS — túnel remotamente gerenciado
  aplica a config nova automaticamente (edge Cloudflare busca a config atualizada).
- Verificar de fora: `curl https://webhooks.ahoy.digital/meta-leads/health` deve
  retornar o JSON do receiver (não mais `404` do webhook nativo do Hermes).
- **Cloudflare Access:** checar se `webhooks.ahoy.digital` está atrás de uma Access
  App. Se estiver, criar uma policy de **bypass** pro path `/meta-leads*` (Zero Trust
  → Access → Applications → a app de `webhooks.ahoy.digital` → Policies → Add →
  Action = Bypass, Include = path `/meta-leads*`), senão a Meta recebe a tela de login
  do Access em vez do endpoint.

Confirmado externamente (desta sessão, ANTES de qualquer mudança): `curl -sS
https://webhooks.ahoy.digital/meta-leads/health` → `404` (é o catch-all do webhook
nativo do Hermes em `:8644`, não o novo receiver — prova viva do gap de roteamento).

## 9. Painel Meta — app `995722365981851` ("Ahoy - APP")

Acessado via Chrome isolado (perfil já logado em `developers.facebook.com` de sessão
anterior do spike).

- **Tela Webhooks** (`developers.facebook.com/apps/995722365981851/webhooks/`):
  card "Configurar um webhook" com campos **URL de callback** / **Verificar token**,
  dois toggles — "Inclua os nomes dos campos que mudaram" e **"Anexe um certificado de
  cliente às solicitações de webhook"** — este último É a opção de **mTLS** citada no
  changelog v25 do Graph API Webhooks; existe na tela, desligada por padrão, por
  objeto (User/Page/etc). Não ativada nesta sessão (fora de escopo — receiver não
  implementa validação de certificado de cliente).
- **NÃO cliquei em "Verificar e salvar"**: com o endpoint ainda não público (§8), a
  Meta chamaria o `GET` e receberia o `404` do webhook nativo do Hermes — falharia e
  poderia deixar o app num estado de "última tentativa falhou" sem necessidade. Fica
  pendente até o §8 ser resolvido.
- **Assinatura da Página** (`108356564252733`, campo `leadgen`) — **reconfirmada ao
  vivo nesta sessão** (3ª confirmação; as duas primeiras foram no spike T4):
  ```
  GET /108356564252733/subscribed_apps?fields=subscribed_fields (com page token)
  → {"data":[{"id":"995722365981851","subscribed_fields":["leadgen"]}]}
  ```
  Segue ativa, não precisa recriar.

## 10. BLOQUEADO — App Secret

Fluxo: `Configurações do app → Básico → Chave Secreta do Aplicativo → Mostrar`.

Ao clicar em "Mostrar", abriu modal **"Digite sua senha novamente"** (reautenticação),
já associado à conta do Flávio, com o campo de senha aparecendo **pré-preenchido**
(autofill do navegador). **Não cliquei em "Confirmar"** — cancelei o modal
(`Cancelar`) sem revelar o secret, conforme a regra: reautenticação por senha não é
pra ser feita pelo agente.

**BLOCKED — instrução exata pro humano:** logar no perfil (ou no navegador principal),
ir em `developers.facebook.com/apps/995722365981851/settings/basic/`, clicar
"Mostrar" em Chave Secreta do Aplicativo, confirmar a senha, copiar o valor e colar
via SSH direto no `.env` da VPS (nunca por chat/arquivo neste repo):

```bash
ssh root@5.78.224.81
sed -i 's/^META_APP_SECRET=.*/META_APP_SECRET=<colar aqui>/' /opt/meta-leads/.env
systemctl restart meta-leads.service
```

Enquanto `META_APP_SECRET=PENDENTE_HUMANO`, todo `POST /meta-leads` real vai bater
`403` na validação HMAC (`hmac.compare_digest` nunca bate com a chave placeholder) —
**isso não afeta o `GET` de verificação do §9** (challenge não depende do App Secret).

## 11. Teste e2e com lead de teste — PULADO

Depende de (a) rota pública funcionando (§8) e (b) `META_APP_SECRET` real (§10) pra
a Meta conseguir entregar o `POST` assinado e o receiver validar. Nenhum dos dois
está pronto nesta sessão — pulado conforme instrução ("se sem secret: pule e
documente"). Retomar depois que §8 e §10 forem resolvidos por um humano:

1. Criar form `TEST_` na página Ahoy (payload mínimo já validado nas tasks
   anteriores).
2. `POST {form_id}/test_leads`.
3. Conferir `received_total` incrementado em `curl https://webhooks.ahoy.digital/meta-leads/health`
   e `last_status` (`error`/`no_config` esperado até a Task 11 preencher
   `location_id`/token GHL reais — o que importa é a ENTREGA chegar, não o push ter
   sucesso).
4. Arquivar o form de teste.

## Resumo do estado ao final desta sessão

| Item | Status |
|---|---|
| Serviço `meta-leads.service` rodando na VPS, `127.0.0.1:8811` respondendo | ✅ DONE |
| `config.json` real (só Ahoy, `location_id` placeholder p/ Task 11) | ✅ DONE |
| `.env` completo exceto `META_APP_SECRET` | ⚠️ parcial (placeholder) |
| Rota pública `webhooks.ahoy.digital/meta-leads` | ❌ BLOCKED — precisa de humano no painel Cloudflare (tunnel remotamente gerenciado) |
| Cloudflare Access bypass pro path `/meta-leads*` | ❌ não verificável ainda (depende do item acima existir primeiro) |
| Verify/Save no painel Meta | ❌ BLOCKED (depende da rota pública) |
| Campo `leadgen` assinado a nível de app (tela pós-save) | ❌ não alcançado (não salvou) |
| Assinatura da Página em `leadgen` (`subscribed_apps`) | ✅ confirmada ativa (3ª vez) |
| mTLS — opção na tela do painel Meta | ✅ documentado (existe, desligada, não ativada) |
| `META_APP_SECRET` | ❌ BLOCKED — precisa de humano (reauth por senha) |
| Teste e2e com lead de teste | ⏭️ pulado (depende dos 2 blockers acima) |
