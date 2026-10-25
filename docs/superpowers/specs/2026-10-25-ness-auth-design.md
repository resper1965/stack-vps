# `@ness/auth` v1: autenticação reutilizável para os sistemas da ness

**Data:** 2026-10-25 · **Estado:** aprovado pelo Ricardo ("rotina pronta à disposição para ser usada no app"); decisões abaixo pela melhor recomendação
**Base:** `2026-10-25-ness-auth-levantamento.md` (mapa do código do niso) e `2026-10-18-lugar-de-trabalho-design.md` seção 4.

## Escopo
Pacote TypeScript + Hono, em repositório **próprio e privado** (`ness-auth`, fora do `stack-vps`), com:
e-mail e senha, sessão, **RBAC que nega por padrão**, chave de API, **SSO OIDC por tenant** (proteções do niso), **login de emergência de administrador** e adaptadores de armazenamento (D1 + KV e Postgres). Não depende de `node:*` nem de `cloudflare:*` no núcleo (WebCrypto + Hono), para rodar em Workers, Node e Vercel.

**Fora da v1:** SCIM, MFA/TOTP (só o gancho `mfa_pendente`), lista de IPs, política de segurança por tenant (só o gancho de portão), agente MCP, módulos do niso. O niso **continua com o código dele**; migrá-lo para consumir o pacote é trabalho separado.

## Decisões (do levantamento)
| Tema | Decisão |
|---|---|
| Licença | O código do niso é da ness. (All Rights Reserved) e o dono é o Ricardo; a instrução dele de extrair para o `@ness/auth` vale como autorização de reuso. O pacote nasce **privado** com a mesma licença proprietária. Nada é publicado fora da ness. |
| Cópia | Portar com revisão linha a linha, **sem** as falhas do levantamento (ver "Não replicar"). Sem marca "n.iso", sem remetente `ness.com.br`, sem `org_ness` como nome de coluna, sem regra de domínio legado. |
| Hash de senha | **PBKDF2-SHA256 com 600 000 iterações** em formato **versionado** (`v1$pbkdf2-sha256$600000$salt$hash`), rehash transparente no login quando a versão ou as iterações mudarem. Argon2id fica para quando o runtime tiver suporte nativo |
| Cifra do segredo do IdP | AES-256-GCM com chave derivada por **HKDF** (não derivação direta), formato versionado; **decrypt nunca aceita texto claro** |
| RBAC | Motor novo: papéis e permissões declarados pelo sistema consumidor; toda rota protegida exige permissão explícita; papel ou permissão desconhecida **nega** |
| Login de emergência | Segredo de ≥ 32 caracteres vindo do ambiente (nunca no banco), comparação em tempo constante, limitado por taxa, sessão de **15 minutos** sem renovação, **sempre** registra na `Trilha` com falha fechada (sem registrar, não loga) e dispara o alerta do sistema consumidor. Só vale para papel `admin`; desligável por configuração |
| MFA | Fora da v1; gancho `mfa_pendente` na sessão |
| Armazenamento | `AuthStore` por adaptador. **D1** (usuários, chaves, SSO) + **KV** (estado efêmero) e **Postgres** (estado efêmero em tabela com expiração). Contrato único testado contra todos os adaptadores |
| Resolvedor DoH (anti rebinding) | Configurável, padrão `https://cloudflare-dns.com/dns-query` |
| Consumidor | Entregue com o template `sistema` da stack (ponto de ligação opcional) e um exemplo mínimo. Primeiro consumidor real: o sistema novo que você criar com `/novo-projeto` |

## Não replicar (falhas do niso apontadas no levantamento)
Token de sessão aceito na query string; PBKDF2 a 100k sem versão; reset com código de 6 dígitos (usar token longo de uso único); `decrypt` aceitando texto claro; derivação de chave sem KDF; enumeração de usuário por tempo no login; comparação do `SETUP_KEY` sem tempo constante.

## Interfaces
- `AuthStore` (≈ 20 métodos): usuários (criar, buscar por e-mail e id, atualizar senha, desativar), chaves de API (criar com hash, buscar por prefixo, revogar), SSO (guardar e ler configuração do tenant), estado efêmero (`ler`, `gravar` com TTL, `apagar`, `lerEApagar`, `incrementarJanela` atômico) e marco de revogação de sessões.
- `Trilha`: `registrar(evento): Promise<void>`; o evento de emergência exige sucesso (falha fechada).
- `criarAuth({ store, trilha, rbac, ambiente })` devolve o middleware Hono, as rotas (`/auth/*`) e os helpers (`exigir(permissao)`).

## Testes
Contrato do `AuthStore` rodado contra memória, D1 (via shim compatível ou Miniflare) e Postgres (PGlite). Portar e ampliar os ~120 casos do niso (sso, sso-org, secret-crypto, senha, tentativas, apikey-role, SSRF) e acrescentar os que faltavam (inatividade, revogação, reset, chave de API no middleware, RBAC nega por padrão, emergência).

## Entrega
Repositório `ness-auth` (privado), pacote **não publicado** nesta etapa (consumo por caminho git ou `file:`); publicar no GitHub Packages é decisão posterior. README com o passo a passo de uso em um sistema novo.

## Estado da implementação (2026-10-25)

**Entrou (repositório `ness-auth`, tag local `v0.1.0`, ainda sem push):** `criarAuth` com login, logout, `me`, troca e redefinição de senha (token longo de uso único), usuários e chaves de API (`nak_...`, validade padrão de 365 dias, revogação em cascata); sessões com expiração absoluta e por inatividade; RBAC que nega por padrão e `exigir(recurso:acao)`; adaptadores memória, D1 (KV opcional, não atômico) e Postgres sobre um contrato único; migrações 0001 a 0003; SSO OIDC por tenant (segredo cifrado com AAD do tenant, vínculo por `(iss, sub)`, SSRF com DoH e `criarFetchSeguro` no Node); login de emergência com limite por IP e global e sessão restrita; `semearAdmin`; CSRF por `Origin` e limite de corpo; `ipDe` obrigatório em produção. Cerca de 410 testes (2 pulados de propósito, KV), mais um exemplo testado para Workers+D1 e outro para Node+Postgres. O template `sistema` ganhou `docs/AUTH.md` (opcional, sem dependência no `package.json`).

**Ficou fora:** MFA (só o gancho `exigeMfa`), SCIM, política por tenant, lista de IPs, prova de posse de domínio do SSO (DNS TXT), rota para trocar o IdP de um tenant (exige SQL), pacote compilado, publicação no GitHub Packages, e a migração do niso para consumir o pacote.

**Riscos aceitos (detalhe no README, "Limitações conhecidas"):** administrador de tenant pode reivindicar domínio livre; `#sso_token=` no fragmento até o app trocá-lo; `/sso/:tenant/iniciar` é anônimo; trilha inundável por quem tem muitos IPs (retenção e alerta ficam com o consumidor); atraso progressivo não limita paralelismo; checar-e-criar do `semearAdmin` não é atômico (script de operador). O código é entregue em TypeScript, então o consumidor precisa transpilar `node_modules/@ness/auth`.

**Contra o niso:** o pacote não replica as falhas do levantamento (token na query string, PBKDF2 a 100k sem versão, reset com código de 6 dígitos, decrypt aceitando texto claro, derivação sem KDF, enumeração por tempo, comparação sem tempo constante). Acrescenta o que o niso não tem: IP confiável por injeção, CSRF por `Origin`, vínculo SSO por `(iss, sub)`, domínio exclusivo por tenant, chave que não emite chave, emergência restrita e checklist de produção. O niso segue com o código dele; migrá-lo é trabalho separado.
