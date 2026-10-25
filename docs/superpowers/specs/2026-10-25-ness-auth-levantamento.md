# Levantamento: autenticação do niso para extração do `@ness/auth`

Data: 2026-10-25. Somente leitura sobre `DESENVOLVIMENTO/niso` (v11.0.0, branch `main`, HEAD `f23dc7d`).
Nenhum arquivo do niso foi alterado; `.env` e segredos não foram lidos; nenhuma chamada de rede.

## 1. Resumo

O niso tem quase tudo o que o `@ness/auth` precisa, e o núcleo mais valioso (SSO OIDC) é código limpo e bem testado. O que **não existe** é o login de emergência de administrador: só há `POST /auth/setup` (cria um `consultor` semente, protegido por `SETUP_KEY`). Também **não há RBAC "nega por padrão" global**: há listas de permissão pontuais (stakeholder, papéis só leitura, papéis do SSO), e o resto do app é liberado por papel. O armazenamento está colado em D1 (SQL cru, 40+ pontos) e em KV (`SESSIONS`), então a extração exige criar a camada `AuthStore`. Todo o código usa WebCrypto e Hono, sem `node:*`, o que ajuda: roda em Workers e em Node 20+ sem polyfill.

Esforço estimado: **M a G** (ver seção 9). Licença: proprietária da ness. (ver seção 10).

## 2. Arquivos de autenticação

Caminhos reais confirmados (todos sob `niso/`). Linhas medidas com `wc -l`.

| Arquivo | Linhas | Papel |
|---|---:|---|
| `src/sso.ts` | 410 | SSO OIDC por tenant: descoberta, PKCE, state, validação do `id_token` (RS256/384/512), troca de código, provisionamento JIT, decifra do segredo |
| `src/secret-crypto.ts` | 63 | AES-256-GCM para segredos em repouso, formato `v1:<iv>:<ct>`, chave derivada por SHA-256 |
| `src/auth-policy.ts` | 153 | Funções puras: papel de chave de API x rota, tentativas de login, inatividade por papel |
| `src/middleware/auth.ts` | 411 | Middleware Hono: resolve agente MCP, chave de API ou sessão; MFA pendente; inatividade; RBAC de papéis só leitura; documento legal; política do tenant; trilha de exclusão |
| `src/routes/auth.ts` | 522 | `/setup`, `/login`, `/logout`, `/me`, `/forgot-password`, `/reset-password`, `/reset-password-first`, `/change-password`, `/trilha` |
| `src/schemas/auth.ts` | 93 | Zod: política de senha (8 a 200), e-mail normalizado, config de SSO, `PAPEIS_SSO` |
| `src/routes/public.ts` (trecho 270-410) | ~140 | Rotas de SSO: `POST /sso/iniciar`, `GET /sso/callback` |
| `src/routes/projects.ts` (trecho 82-140) | ~60 | `GET/PUT /projects/:id/sso` (grava o segredo cifrado) |
| `src/routes/integrations.ts` (trecho 55-190, 285-335) | ~190 | Guarda SSRF (`isValidWebhookUrl`, `resolveHostIsPublic` via DoH) e CRUD de chave de API |
| `src/helpers.ts` (trechos) | ~150 | `hashPassword`/`verifyPassword` (PBKDF2), `sha256Hex`, `genToken`, `genNumericCode`, `constantTimeEqual`, `rateLimit` (KV), `rateLimitD1`, `invalidateUserSessions`, `sessionRevoked`, `logAudit`, `SESSION_TTL_SEC` |
| `src/routes/mfa.ts` / `src/services/totp.ts` | 263 / 144 | TOTP (RFC 6238) em WebCrypto; fora do escopo pedido, mas acoplado ao middleware |
| `src/politica-tenant.ts` | 141 | MFA obrigatório, TTL de sessão e lista de IPs por tenant |
| `src/routes/scim.ts` | 355 | SCIM 2.0 (provisionar/desativar) |

Total do núcleo pedido (sso, secret-crypto, auth-policy, middleware, rotas de auth, schemas): **1.652 linhas**; com os trechos de rotas e helpers, cerca de 2.200.

### 2.1 Exports públicos

**`src/sso.ts`**

```ts
type ConfigSso = { project_id; issuer; client_id; client_secret; dominios; papel_padrao; ativo: number }
type Descoberta = { issuer; authorization_endpoint; token_endpoint; jwks_uri }
type PedidoAutorizacao = { url: string; state: string }
type EstadoGuardado = { project_id; nonce; verifier; redirectUri }
type Claims = { iss; aud: string|string[]; exp; iat; nonce?; sub; email?; email_verified?; name? }
type Provisionado = { id; email; role; client_project_id; org_id; criado: boolean }

configPorDominio(env: Bindings, email: string): Promise<ConfigSso | null>
buscarChaves(d: Descoberta, fetchImpl?: typeof fetch): Promise<{ keys: (JsonWebKey & { kid?: string })[] }>
descobrir(env, issuer: string, fetchImpl?, verificarHost?: (host: string) => Promise<boolean>): Promise<Descoberta>
iniciarLogin(env, cfg: ConfigSso, d: Descoberta, redirectUri: string): Promise<PedidoAutorizacao>
consumirState(env, state: string): Promise<EstadoGuardado | null>
validarIdToken(idToken: string, opcoes: { jwks; issuer; clientId; nonce; agora? }): Promise<Claims>
trocarCodigo(d, cfg: { client_id; client_secret }, code, verifier, redirectUri, fetchImpl?): Promise<{ id_token: string }>
papelValidoParaSso(papel: string | null | undefined): boolean
provisionar(env, cfg: ConfigSso, claims: Claims): Promise<Provisionado>
segredoDoCliente(env, cfg: ConfigSso): Promise<string>
```

**`src/secret-crypto.ts`**: `isEncrypted(value)`, `encryptSecret(plaintext, keyMaterial)`, `decryptSecret(value, keyMaterial)`.

**`src/auth-policy.ts`**: `isAuditWrite(method, path)`, `apiKeyRoleViolation(permission, method, path)`, `decisaoLogin(falhas, desafioVerificavel)`, `mensagemCredencialInvalida(n)`, `mensagemBloqueio()`, `limiteInatividadeSeg(role)`, `expirouPorInatividade(agoraMs, ultimoAcessoMs, role)`, constantes `FALHAS_ATE_DESAFIO=1`, `FALHAS_ATE_BLOQUEIO=5`, `BLOQUEIO_SEG=900`, `JANELA_FALHAS_SEG=900`, `INATIVIDADE_CLIENTE_SEG=1800`, `INATIVIDADE_CONSULTOR_SEG=28800`, `PAPEIS_IMPLEMENTACAO`.

**`src/middleware/auth.ts`**: `authMiddleware` (único export). `resolveApiKeyUser` e `atorDaChave` são internos.

**`src/routes/auth.ts`**: `authApp`, `sessaoApp` (Hono), `clientIp(c)`, `chavesTentativa(email, ip)`, `registrarFalhaLogin(c, chaves, falhasAntes, desafioVerificavel, ip)`.

**`src/schemas/auth.ts`**: `senhaNovaSchema`, `emailNormalizado`, `loginSchema`, `setupSchema`, `resetRequestSchema`, `resetConfirmSchema`, `primeiroAcessoSchema`, `mudarSenhaSchema`, `ssoInicioSchema`, `ssoConfigSchema`, `PAPEIS_SSO = ['org_admin','org_user','client']`.

### 2.2 Dependências de DOMÍNIO que precisam virar interface injetada

| Dependência no niso | Onde | Tratamento no `@ness/auth` |
|---|---|---|
| `project` / `client_project_id` / `projects.org_id` | `sso.ts` (`provisionar` lê `projects.org_id`), `middleware/auth.ts`, `api_keys.project_id` | Renomear para **escopo de tenant** (`tenantId`) e `orgId` opcional; `AuthStore.tenantOrg(tenantId)` |
| Papéis do niso (`platform_admin`, `consultor`, `consultoria_admin`, `comercial`, `org_admin`, `org_user`, `client`, `stakeholder`, `employee`, `consultant`, `admin`, `user`, `client_admin`) | `auth.ts`, `auth-policy.ts`, `helpers.ts` | Papéis viram **configuração**: `papeis: { cliente: string[]; equipe: string[]; ssoPermitidos: string[]; aliasesLegados: Record<string,string> }`. O mapa de legado (`admin`→`platform_admin` etc.) fica no niso |
| Módulos por pessoa/projeto (`modulosDaPessoa`, `faixaDoCaminho`, `recusaDeModulo`) | `routes/auth.ts` (`/me`), `project-access.ts` | Fora do pacote. O `/me` aceita um enriquecedor `enriquecerUsuario(user)` injetado |
| Trilha de auditoria (`logAudit`, `alvoDaExclusao`, `trilha-exclusao.ts`) | login, lockout, SSO, troca de senha, exclusão, agente | Interface `Trilha` (seção 5) |
| Organização suspensa (`equipeDeOrgSuspensa`, `ORG_SUSPENSA`) | login e middleware | Gancho `podeEntrar(user): Promise<null | {status; corpo}>` injetado |
| Documento legal pendente (`legal_documents`, `legal_acceptances`, `situacaoLegal`) | middleware | Gancho `porta?: (ctx, user) => Promise<Response | null>` (cadeia de portões); o niso registra o seu |
| Política de tenant (`project_security_policy`, `avaliarPolitica`) | middleware | Fora da v1 como código; o pacote expõe o mesmo gancho de portões |
| Agente MCP (`AGENTE`, `resolverAgente`, `acaoDestrutiva`, `agente_concessoes`) | middleware, `change-password`, `reset-password` | Fora do pacote. Gancho `aoRevogarSessoes(userId)` injetado (hoje `revogarAgentesPorTrocaDeSenha`) |
| E-mail (Resend, template "n.iso") | `/forgot-password` | Interface `Mailer.enviar(to, assunto, html)` e template injetável (hoje há marca "n.iso" no HTML) |
| Anti-abuso (Turnstile) | `/login` | Interface `Desafio { verificavel: boolean; conferir(token, ip): Promise<boolean>; siteKey?: string }` |
| `Bindings`/`Variables` do Hono do niso | todos | Genéricos `Hono<{ Variables: AuthVariables }>`; o pacote declara o próprio `AuthEnv` mínimo |
| Banco | ver seção 4 | `AuthStore` |
| Observabilidade (`log` de `observability.ts`) | `sso.ts` | `Logger` mínimo (`info`, `warn`) |
| SSRF (`isValidWebhookUrl`, `resolveHostIsPublic`) | `sso.ts` importa de `routes/integrations.ts` | **Mover para o pacote** (`ssrf.ts`, ~140 linhas, pura) |
| `validateBody`, `erro500`, `genId`, `sendEmail` | rotas | Reescrever dentro do pacote (poucas linhas) |

### 2.3 Bibliotecas (de `niso/package.json`)

Uso direto pelo código de autenticação: `hono ^4.13.13`, `zod ^4.6.5`. Tipos: `@cloudflare/workers-types` via `worker-configuration.d.ts` (`D1Database`, `KVNamespace`). Não usam: `agents`, `docx`, `@modelcontextprotocol/server`, `@cloudflare/workers-oauth-provider` (este só aparece em `routes/oauth-autorizacao.ts`, que reaproveita `registrarFalhaLogin`). Dev: `vitest ^4.1.11`, `@cloudflare/vitest-pool-workers ^0.23.0`, `typescript ^5.5.2`. **Nenhuma biblioteca de JWT, de hash de senha ou de TOTP**: tudo em WebCrypto, por escolha declarada no código (`ponytail:`).

### 2.4 APIs de runtime

- WebCrypto global (`crypto.subtle`, `crypto.getRandomValues`, `crypto.randomUUID`), `btoa`/`atob`, `TextEncoder`/`TextDecoder`, `fetch`, `FormData`, `URL`: todos existem em Workers e em Node 20+.
- Sem `node:*` e sem `cloudflare:*` nos arquivos de autenticação.
- Específico de Workers: `redirect: 'manual'` devolve a resposta 3xx (em Node/undici também devolve a 3xx; só o navegador devolve `opaqueredirect`; o código trata os dois). `CF-Connecting-IP` em `clientIp` (precisa de gancho para `X-Forwarded-For` confiável em Postgres/Node). KV com `expirationTtl` e `D1` com `.prepare().bind().first()/.all()/.run()`.
- Pontos de atenção em Node: `hashPassword` usa PBKDF2 com **100.000 iterações** (teto do workerd; o OWASP 2023 pede 600.000 para PBKDF2-SHA256). No Node dá para subir; o formato `salt:hash` não guarda iterações, então a migração precisa de um novo prefixo versionado.

## 3. Como o niso trata cada requisito

| Requisito | Estado | Observações |
|---|---|---|
| E-mail e senha | Existe | PBKDF2-SHA256 100k, salt UUID, compara em tempo constante; migra hash legado SHA-256 no login; senha nova 8 a 200 caracteres (NIST 800-63B); mensagem única "e-mail ou senha"; bloqueio por (e-mail+IP) em KV após 5 falhas; teto por conta no D1 (10 em 300 s, atômico); teto por IP no KV (20 em 300 s) |
| Sessão | Existe | Token de 32 bytes hex; JSON no KV sob **duas chaves** (`session_<t>` e `<t>`, legado); TTL absoluto 24 h; inatividade 30 min (cliente) ou 8 h (equipe) com renovação a cada 60 s sem esticar o teto; revogação em massa por marco `sessions_invalid_before:<userId>`; sessão sem `iat` é tratada como revogada; MFA pendente restringe a `/auth/mfa/verify` e `/status`. Aceita o token em `X-Session-ID`, `Authorization: Bearer` **e query string** (`token`, `sessionId`, `session_id`, `session`): a query vaza em log e Referer, deve sair do pacote |
| RBAC que nega por padrão | **Parcial** | Há allow-list fechada só para `stakeholder` (regex de caminhos) e para papéis só leitura (`org_user`, `client`: escritas permitidas por método+rota). Papel desconhecido (ex.: `comercial`) cai em acesso liberado no middleware; o resto do controle está espalhado em `requireProjectAccess` e nos handlers. O pacote precisa de um motor novo (ver seção 6) |
| Chave de API | Existe | `X-API-Key`; guarda só `sha256(key)`; chave `randomUUID()+'-'+randomUUID()` mostrada uma vez; estados `Active`/`Revoked`; `expires_at`; `permissions` em `read|write|admin|consultant|auditor`; exige `project_id` (falha fechada se nulo); vira usuário `apikey:<id>` com papel `client` preso ao projeto; nome da chave sanitizado na trilha; `last_used_at` best-effort. A criação e a revogação estão em `integrations.ts`, fora dos arquivos de auth |
| SSO OIDC por tenant | Existe, completo | Ver 3.1 |
| Login de emergência de administrador | **Não existe** | Só `POST /auth/setup` com `SETUP_KEY` (falha fechada se a variável não existe; compara com `!==`, **não** em tempo constante; cria `consultor`, não admin). O login por senha continua aberto mesmo para domínio com SSO ativo (a senha local do administrador serve de emergência por omissão, sem controle nem trilha específica). Precisa ser projetado |
| Armazenamento por adaptador | Não existe | Tudo em D1+KV direto |

### 3.1 Proteções do SSO (conferidas no código e nos testes)

- Host público: `exigirHostPublico` = `isValidWebhookUrl` (literais internos, IPv4 em formas alternativas, IPv6 loopback/ULA/link-local/IPv4-mapeado) + `resolveHostIsPublic` (DoH da Cloudflare, A e AAAA, todos os IPs públicos, falha fechada). Aplicado ao `issuer`, `token_endpoint` e `jwks_uri`. Limite conhecido: o fetch do Workers não permite fixar o IP resolvido, então resta janela TOCTOU; o comentário do código admite isso. A dependência de DoH de terceiro (`cloudflare-dns.com`) precisa ser configurável no pacote.
- Redirect manual: `buscarNoIdp` usa `redirect: 'manual'` e recusa qualquer 3xx/`opaqueredirect` na descoberta, no `jwks_uri` e no `token_endpoint`.
- Algoritmos: allow-list RS256/384/512 (recusa `none` e HS*). Assinatura verificada **antes** de qualquer claim. `iss`, `aud`, `exp`/`iat` com skew de 120 s, `nonce`, e-mail presente e `email_verified === true`. Não confere `azp` quando `aud` é lista (ressalva menor).
- `state` de uso único (lido e apagado do KV, TTL 600 s) e PKCE S256 mesmo com `client_secret`.
- Papel nunca vem do IdP: vem de `papel_padrao`, restrito por allow-list (`PAPEIS_SSO`) na gravação e de novo no provisionamento. Conta existente não é reescopada para outro tenant; conta de equipe e conta desativada recusadas.
- Segredo do IdP cifrado (AES-256-GCM, `TOKEN_ENC_KEY`); a gravação devolve 503 sem a chave; nunca volta na leitura. Fragilidades: chave derivada por um SHA-256 simples (sem KDF e sem rotação; qualquer string serve); sem AAD ligando o ciphertext ao tenant; `decryptSecret` devolve valor sem prefixo `v1:` como texto claro (migração legada que o pacote deve eliminar).
- Retorno por fragmento: `/#sso_token=<token>` e `/#sso_erro=<motivo genérico>`; o motivo real só vai para a trilha (`auth.sso_failed`).
- Mensagens genéricas: `POST /sso/iniciar` responde `{sso:false}` igual para domínio desconhecido e tenant sem SSO; falha de callback sempre "falha na autenticação federada".
- Redirect URI fixa por configuração (`redirectUriDe`), nunca o host da requisição. No niso ela tem regra especial de domínio legado, que não deve ir ao pacote (vira parâmetro).
- O JWKS não é cacheado (uma busca por callback); só a descoberta é cacheada por 3600 s no KV, e a regra de host público roda antes de cachear.

## 4. Tabelas de autenticação e acoplamento a banco

SQLite (D1). Acoplamento: SQL cru via `env.DB.prepare()`, sem ORM. Há 40+ chamadas espalhadas nos arquivos acima.

**`users`** (schema.sql:9, migrations 0002, 0019, 0020, 0028, 0040)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | TEXT PK | `genId()` (timestamp base36 + 2 aleatórios) ou UUID cortado a 16 no SSO |
| `email` | TEXT UNIQUE NOT NULL | busca sempre `lower(trim(email)) = ?`; há contas antigas com caixa mista |
| `password_hash` | TEXT NOT NULL | `salt:hex` PBKDF2, hash SHA-256 legado sem `:`, marcadores `sso:sem-senha-local` e `scim:...` |
| `name` | TEXT NOT NULL | |
| `role` | TEXT NOT NULL | sem CHECK |
| `client_project_id` | TEXT | nulo para equipe |
| `requires_password_change` | INTEGER DEFAULT 0 | primeiro acesso |
| `totp_secret`, `totp_enabled`, `totp_recovery_hashes`, `totp_last_window`, `totp_fail_count`, `totp_fail_window` | TEXT/INTEGER | MFA (fora da v1) |
| `ativo` | INTEGER NOT NULL DEFAULT 1 | desativação (SCIM e tela) |
| `created_at` | DATETIME | |
| `org_id` | TEXT NOT NULL DEFAULT 'org_ness' | organização da equipe |

**`api_keys`** (schema.sql:639): `id` TEXT PK, `project_id` TEXT NOT NULL FK, `key_hash` TEXT NOT NULL (sem índice nem UNIQUE: a busca é por `key_hash`, falta índice), `name` TEXT NOT NULL, `permissions` TEXT DEFAULT 'read', `last_used_at` DATETIME, `expires_at` DATETIME, `status` TEXT DEFAULT 'Active', `created_at` DATETIME.

**`project_sso`** (migration 0027): `project_id` TEXT PK FK, `issuer` TEXT NOT NULL, `client_id` TEXT NOT NULL, `client_secret` TEXT NOT NULL (cifrado), `dominios` TEXT NOT NULL (lista separada por vírgula; a busca por domínio carrega **todas** as linhas `ativo=1` e filtra em memória), `papel_padrao` TEXT NOT NULL DEFAULT 'org_user', `ativo` INTEGER NOT NULL DEFAULT 0, `criado_em`, `atualizado_em` DATETIME, `atualizado_por` TEXT. Índice `idx_project_sso_ativo(ativo)`.

**`project_scim`** (0028, fora da v1): `project_id` PK, `token_hash` NOT NULL, `ativo`, `criado_em`, `criado_por`, `ultimo_uso_em`; índice no hash.

**`project_security_policy`** (0026, fora da v1): `project_id` PK, `mfa_obrigatorio` INTEGER, `sessao_ttl_seg` INTEGER, `ip_allowlist` TEXT, `updated_at`, `updated_by`.

**`rate_limits`** (0024): `key` TEXT PK, `count` INTEGER, `window_start` INTEGER. Upsert atômico com `RETURNING count`.

**`audit_logs`** (schema.sql:254): `id` TEXT PK, `action` TEXT NOT NULL, `actor` TEXT NOT NULL, `details`, `justification`, `ip_address`, `project_id`, `created_at` + colunas por campo (`entity_type`, `entity_id`, `field`, `old_value`, `new_value`, `operation_id`). Append-only por trigger (`audit_logs_no_update`, `audit_logs_no_delete`). Pertence ao domínio, não ao pacote.

**`agente_concessoes`**, **`legal_documents`/`legal_acceptances`**, **`organizations`**, **`projects`**: do domínio do niso; o pacote só toca `projects.org_id` (provisionamento) e `organizations.status` (suspensão), ambos via gancho.

**Convites**: não há tabela. O convite é um e-mail com **senha provisória** (conta nasce com `requires_password_change = 1`, `routes/users.ts:175-256`). Não existe token de convite.

**Estado em KV (`SESSIONS`)**: `session_<token>` e `<token>` (sessão JSON, TTL 86400), `sessions_invalid_before:<userId>` (marco, TTL 86400), `login_fail:<email>:<ip>` e `login_lock:<email>:<ip>` (TTL 900), `ratelimit:<chave>` (janela deslizante, não atômico), `reset_token:<código6>` (JSON `{email}`, TTL 3600), `sso_state:<state>` (TTL 600), `sso_descoberta:<issuer>` (TTL 3600). O código de redefinição tem **6 dígitos** e é chaveado só pelo código (colisão tratada com até 5 sorteios; teto de 10 tentativas por IP por hora): fraco, o pacote deve usar token longo.

## 5. Testes existentes

Rodam no runtime Workers real (`@cloudflare/vitest-pool-workers`, D1 e KV de Miniflare, `test/helpers/d1.ts` com 181 linhas aplica o `schema.sql`). Contagem por `it()`; não executei a suíte nesta passada (somente leitura).

| Arquivo | Linhas | Casos | Cobre |
|---|---:|---:|---|
| `test/sso.test.ts` | 502 | 44 | Cada recusa de `validarIdToken` (none, HS256, assinatura alheia, payload adulterado, iss, aud, exp, nonce, e-mail não verificado, kid ausente), `descobrir` (issuer diferente, http, host não público, endpoints ausentes, token_endpoint/jwks_uri), state de uso único e PKCE, JIT, não mover conta de outro cliente, não aceitar staff, `configPorDominio`, rotas, 302 recusado nos três fetches. Chaves RSA e tokens assinados de verdade |
| `test/sso-org.test.ts` | 214 | 10 | SSO com organizações |
| `test/secret-crypto.test.ts` | 43 | 6 | Cifrar/decifrar, legado em claro, malformado |
| `test/auth-senha.test.ts` | 75 | 3 | Política de senha |
| `test/auth-tentativas.test.ts` | 138 | 19 | Bloqueio, desafio, mensagens, contagem por e-mail+IP |
| `test/apikey-role.test.ts` | 55 | 12 | `apiKeyRoleViolation` e separação consultor x auditor |
| `test/reset-primeiro-acesso.test.ts` | 64 | 5 | Troca de senha no primeiro acesso |
| `test/stakeholder-acesso.test.ts` | 257 | 15 | Allow-list de caminhos do stakeholder (varre as rotas) |
| `test/oauth-autorizacao.test.ts` | 296 | 19 | Tela OAuth do agente (usa `registrarFalhaLogin`) |
| `src/routes/integrations.test.ts` | n/d | n/d | `isValidWebhookUrl` (SSRF) |

Total diretamente reaproveitável para o pacote: cerca de **120 casos** (sso, sso-org, secret-crypto, auth-senha, auth-tentativas, apikey-role, reset-primeiro-acesso, SSRF). A cobertura global do repositório tem piso de 69% de statements; não há medição por arquivo nesta passada. **Sem testes dedicados** a: expiração por inatividade no middleware, revogação de sessão (`sessionRevoked`), `/forgot-password` e `/reset-password`, chave de API no middleware (só a função pura), ordem das trilhas de auditoria.

## 6. Proposta

### (a) `AuthStore` mínimo

Interface única, assíncrona, sem vazar SQL. Dois grupos: **estado transacional** (usuários, chaves, SSO) e **estado efêmero com TTL** (sessão, state, contadores, tokens de reset). O segundo grupo permite KV, Redis ou uma tabela com `expires_at` no Postgres.

```ts
interface AuthStore {
  // Usuários
  usuarioPorEmail(email: string): Promise<UsuarioAuth | null>          // normaliza lower(trim); desempate: caixa exata primeiro
  usuarioPorId(id: string): Promise<UsuarioAuth | null>
  criarUsuario(u: NovoUsuario): Promise<UsuarioAuth>                   // email único
  atualizarSenha(id: string, hash: string, opts?: { exigeTroca?: boolean }): Promise<void>
  definirAtivo(id: string, ativo: boolean): Promise<void>

  // Chaves de API
  chavePorHash(hash: string): Promise<ChaveApi | null>
  criarChave(c: NovaChaveApi): Promise<void>
  revogarChave(id: string): Promise<void>
  marcarUsoDaChave(id: string): Promise<void>                          // best-effort

  // SSO por tenant
  ssoAtivos(): Promise<ConfigSso[]>                                    // ou ssoPorDominio(dominio) no Postgres
  ssoPorTenant(tenantId: string): Promise<ConfigSso | null>
  gravarSso(c: ConfigSso): Promise<void>                               // segredo já cifrado pelo pacote
  orgDoTenant(tenantId: string): Promise<string | null>

  // Efêmero (chave, valor, TTL)
  ler(chave: string): Promise<string | null>
  gravar(chave: string, valor: string, ttlSeg: number): Promise<void>
  apagar(chave: string): Promise<void>
  incrementarJanela(chave: string, max: number, janelaSeg: number): Promise<boolean>   // ATÔMICO, janela fixa
  lerEApagar(chave: string): Promise<string | null>                    // state de uso único, atômico

  // Revogação em massa
  marcarSessoesInvalidasAte(userId: string, epochMs: number, ttlSeg: number): Promise<void>
  sessoesInvalidasAte(userId: string): Promise<number | null>
}
```

Notas de projeto. `lerEApagar` e `incrementarJanela` precisam ser atômicos: no KV o niso faz get e depois delete (state) e get-then-put (rate limit por IP), o que **não** é atômico; no D1 o upsert com `RETURNING` é. Postgres cobre os dois com `DELETE ... RETURNING` e `INSERT ... ON CONFLICT DO UPDATE ... RETURNING`. Em KV puro, `lerEApagar` não é atômico: documentar a limitação ou exigir adaptador de D1/DO para o state. O adaptador D1/KV sai quase direto do código atual; o de Postgres é novo (tabela `auth_kv(chave, valor, expira_em)` com varredura de expiradas, mais as tabelas acima).

Esquema canônico do pacote: renomear `client_project_id` para `tenant_id`, `project_sso` para `auth_sso`, acrescentar `UNIQUE` em `lower(email)` e índice em `api_keys.key_hash`, guardar `dominio` em linhas próprias (`auth_sso_dominios(dominio PK, tenant_id)`) para evitar a varredura em memória.

### (b) `Trilha` injetada

```ts
interface Trilha {
  registrar(e: EventoAuth): Promise<void>
}
type EventoAuth = {
  acao: string            // 'auth.login' | 'auth.lockout' | 'auth.sso_login' | 'auth.sso_provisioned' | 'auth.sso_failed'
                          // | 'auth.password_changed' | 'auth.password_changed_first' | 'auth.password_reset'
                          // | 'auth.reset_primeiro_recusado' | 'project.sso_updated' | 'api_key_created' | 'api_key_revoked'
                          // | 'auth.emergencia_usada' (novo)
  ator: string            // e-mail ou 'anonimo' ou 'apikey:<id> (<nome>)'
  detalhes: string
  tenantId?: string
  ip?: string
  justificativa?: string
}
```

Regras: falha de trilha **não derruba** o login (hoje o `logAudit` do login dentro do `try` derruba; o de exclusão usa `.catch(() => {})`), exceto para `auth.emergencia_usada`, que deve falhar fechado (sem trilha, sem emergência). O adaptador do niso mapeia para `logAudit`; o pacote traz um adaptador que grava numa tabela append-only e outro que só escreve em log. Nenhum segredo, código ou token em `detalhes` (regra já seguida no niso).

### (c) Fora da v1

- **SCIM 2.0** (`routes/scim.ts`, 355 linhas): é o que faz o desligamento no IdP cair sozinho; depende de `users.ativo` (já no `AuthStore`), então entra na v1.1 sem quebrar contrato.
- **MFA/TOTP** (`mfa.ts` + `totp.ts`, 407 linhas) e a trava de "sessão pendente de segundo fator": o middleware já tem o campo `mfa_pending`; manter o campo e o gancho na v1, sem implementação. Se a emergência exigir segundo fator, é esse o primeiro item a puxar.
- **Lista de IPs / política por tenant** (`politica-tenant.ts`): fica como gancho de "portão" (`porta`), sem implementação.
- Agente MCP/OAuth do `workers-oauth-provider`, documento legal pendente, módulos por pessoa, trilha de exclusão, `stakeholder`, convite por e-mail, recuperação de senha por código (reescrever com token longo antes de entrar), Turnstile (entra só a interface `Desafio`).

### Dentro da v1 (escopo proposto)

E-mail e senha com bloqueio, sessão com inatividade e revogação em massa, chave de API, motor RBAC novo, SSO OIDC por tenant com todas as proteções da seção 3.1, cifra de segredo, SSRF, login de emergência, adaptadores D1/KV e Postgres, suíte de testes portada.

**RBAC que nega por padrão (novo, não é extração).** Proposta mínima: `politica: Array<{ papel: string; metodos: string[]; caminho: RegExp|string }>` avaliada por `autorizar(user, método, caminho)`; **ausência de regra = 403**; chave de API herda a regra do seu `permissions`. O allow-list do stakeholder e o de escritas dos papéis só leitura do niso viram os dois primeiros conjuntos de regras de teste.

**Login de emergência (novo).** Desenho a decidir com o dono (seção 8): rota própria (`POST /auth/emergencia`) fora do fluxo normal, desligada por padrão, exigindo um segredo de ambiente comparado em tempo constante **e** uma conta administradora nomeada; rate limit próprio; sessão curta (ex.: 15 min) sem renovação; trilha obrigatória e fail-closed; alerta fora de banda (e-mail/webhook) a cada uso; contas SSO-only não perdem a senha local, mas ela só vale por esta rota.

## 7. Riscos da extração

**Segredos em código.** Nenhum segredo literal nos arquivos de auth (busca por "ness", "niso", "n360" nesses arquivos só encontrou rótulos de e-mail). Segredos são lidos de `env`: `SETUP_KEY`, `TOKEN_ENC_KEY`, `TURNSTILE_SECRET_KEY`, `RESEND_API_KEY`. Não li `.env`, `wrangler.jsonc` com valores, nem `backups/`/`debug.log`. Recomendo, antes de copiar qualquer arquivo, rodar varredura de segredos (gitleaks) no histórico do niso, porque o repositório tem `backups/` e `debug.log` na raiz.

**Específico de cliente / de produto.**
- Marca "n.iso" e cor `#00ade8` no e-mail de recuperação (`routes/auth.ts:364-376`).
- Remetente `n.iso <noreply@ness.com.br>` em `helpers.ts` (`enviarEmail`).
- `org_ness` como padrão da coluna `users.org_id`; `URL_NISO`/`APP_URL_PADRAO` na regra de redirect do SSO (`public.ts`).
- Vocabulário de papéis do niso e legados (`employee`, `consultant`, `admin`) e comentários que citam incidentes e datas reais ("conta em produção de 22/07/2026"). Tudo isso fica no niso.
- Referência a `ISO 27001, 9.2` na separação consultor x auditor (`auth-policy.ts`): pertence ao domínio, sai do pacote (a função fica no niso).
- Exigência de que só a equipe ness. configure o SSO (`somenteNess`) é regra do niso, não do pacote.

**Falhas a corrigir durante a extração (não replicar).** Token de sessão aceito na query string; duas chaves KV por sessão; PBKDF2 a 100k sem versão no formato; `SETUP_KEY` comparada com `!==`; recuperação de senha com código de 6 dígitos chaveado só pelo código; `decryptSecret` aceitando texto claro; derivação de chave AES sem KDF e sem rotação; ausência de `azp`; busca de SSO por domínio varrendo a tabela; falta de índice em `api_keys.key_hash`; tempo de resposta do login diferente quando o e-mail não existe (não roda `verifyPassword`): enumeração por tempo; `rateLimit` por IP não atômico; sessão de papel antigo reescrita pelo middleware a cada requisição (normalização de papel dentro do middleware, que o niso precisa manter como gancho).

**Acoplamento e regressão.** O middleware tem 411 linhas e mistura 9 preocupações (agente, chave, sessão, MFA, inatividade, RBAC, legal, política do tenant, trilha de exclusão). Dividir em cadeia de portões muda a ordem de execução, e a ordem aqui é de segurança (identidade antes de política; sessão pendente de MFA antes de tudo). Os testes de integração que passam pelo `index.ts` do niso (263 arquivos em `test/`) são a rede de segurança da migração do niso para consumir o pacote; sem eles a troca é arriscada. Há um achado documentado no próprio código: sub-routers montados antes do `authMiddleware` ficam sem autenticação em Hono (três rotas ficaram mortas por isso); o pacote deve exportar o router já com o middleware aplicado onde couber.

**Licença.** `niso/LICENSE` é proprietária ("All Rights Reserved", ness. Cybersecurity, contato `legal@ness.lat`) e proíbe copiar, adaptar ou criar derivados sem permissão escrita da ness. Se o `@ness/auth` é da mesma titular (ness.), basta uma **autorização escrita registrada** e definir a licença do pacote (proprietária, ou MIT/Apache se a intenção for abrir). Se algum trecho tiver contribuição de terceiro, conferir o histórico (`git log --format=%ae -- src/sso.ts src/secret-crypto.ts src/auth-policy.ts src/middleware/auth.ts src/routes/auth.ts`). Dependências: `hono` e `zod` são MIT. A cláusula de terceiros do LICENSE só cita material MIT das skills de conhecimento, não de auth. Os helpers `isValidWebhookUrl`/`resolveHostIsPublic` são código do niso (mesma titularidade), sem biblioteca externa.

## 8. Decisões que dependem do dono

1. **Titularidade e licença do `@ness/auth`**: autorizar a cópia do código do niso (licença proprietária) e escolher a licença do pacote (privada, MIT, Apache-2.0).
2. **Login de emergência**: confirmar que é para criar (não existe hoje) e o desenho: segredo de ambiente, conta nomeada, segundo fator obrigatório?, validade da sessão, alerta fora de banda, em quais ambientes fica ligado.
3. **RBAC nega por padrão**: aceitar que é código novo (não extração) e que o niso, ao consumir o pacote, perde a liberdade atual de papel desconhecido (vira 403 até ter regra).
4. **MFA na v1 ou não**: se a emergência ou o admin exigirem segundo fator, TOTP (407 linhas, pronto) sobe para a v1 e o esforço sobe cerca de 20%.
5. **Postgres**: confirmar o consumidor real (projeto/stack) para dimensionar o adaptador e o esquema; e se o estado efêmero fica em Postgres, Redis ou outro.
6. **PBKDF2**: manter 100k (compatível com hashes existentes do niso) ou migrar para formato versionado com iterações maiores/Argon2id no adaptador Node.
7. **O niso passa a consumir o pacote?** Se sim, é a segunda fase (migrar o niso sem regressão) e dobra o prazo; se não, o pacote nasce por cópia e os dois divergem.
8. **DoH**: o resolvedor de DNS da proteção contra rebinding (hoje Cloudflare) fica fixo, configurável, ou aceita resolvedor próprio do host.

## 9. Viabilidade e esforço

Viável e com bom retorno: o SSO e a cifra são quase autocontidos (troca de `env.DB`/`env.SESSIONS` por `AuthStore` e de `isValidWebhookUrl` por import local), e a suíte de ~120 casos já existe e mede o que importa.

| Bloco | Linhas aprox. | Esforço |
|---|---:|---|
| Núcleo portável: `sso.ts`, `secret-crypto.ts`, `ssrf.ts`, `auth-policy` (parte pura) | ~700 | P |
| Senha, sessão, bloqueio, reset, chave de API sobre `AuthStore` | ~700 | M |
| Interfaces (`AuthStore`, `Trilha`, `Mailer`, `Desafio`, portões) e montagem Hono | ~300 | M |
| Adaptador D1/KV (a partir do código atual) | ~250 | M |
| Adaptador Postgres (novo, com `lerEApagar` e `incrementarJanela` atômicos) | ~350 | M |
| RBAC nega por padrão (novo) | ~150 | P |
| Login de emergência (novo, com desenho) | ~200 | M |
| Portar e adaptar ~120 testes (contrato do `AuthStore` rodando nos dois adaptadores) | ~1.500 | M |
| **Total** | **~4.000 (≈2.100 portadas + ≈1.900 novas)** | **G** (M se MFA, SCIM e consumo pelo niso ficarem de fora e Postgres vier depois do D1) |

Sequência sugerida: (1) `ssrf` + `secret-crypto` + `sso` com testes (rápido, risco baixo); (2) `AuthStore` com adaptador em memória e D1/KV; (3) senha/sessão/chave de API; (4) RBAC; (5) emergência; (6) Postgres rodando o mesmo contrato de testes.
