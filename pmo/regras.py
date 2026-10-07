"""Regras puras do PMO: STATE.md, estágio sugerido, projeto esquecido e classificação (empresa, cliente, tipo)."""
import json
import re
import unicodedata

TIPOS = ("app", "site", "agente", "dados", "infra", "documento", "conhecimento")
EMPRESAS = ("ness", "bekaa", "ionic", "forense", "pessoal", "trustness")
ESTAGIOS = ("ideia", "em andamento", "em revisão", "entregue", "encerrado", "parado")
INATIVOS = ("encerrado", "parado", "entregue")
LIMITE_ANDAMENTO = 14
LIMITE_REVISAO = 30


def _sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def _campo(texto, nome):
    alvo = _sem_acento(nome).lower()
    for linha in texto.splitlines():
        m = re.match(r"^\*\*([^*]+):\*\*\s*(.*)$", linha.strip())
        if m and _sem_acento(m.group(1)).strip().lower() == alvo:
            v = m.group(2).strip()
            return None if not v or v.upper().startswith("A DEFINIR") else v
    return None


def ler_state(texto):
    """Extrai tipo, estágio e próximo passo de um STATE.md; inválido ou ausente vira None."""
    if not texto:
        return {"tipo": None, "estagio": None, "proximo": None}
    tipo = (_campo(texto, "Tipo") or "").lower() or None
    est = (_campo(texto, "Estágio") or "").lower() or None
    if est:
        est = next((e for e in ESTAGIOS if _sem_acento(e) == _sem_acento(est)), None)
    return {"tipo": tipo if tipo in TIPOS else None, "estagio": est, "proximo": _campo(texto, "Próximo passo")}


def estagio_sugerido(dias_sem_atividade, prs_abertos, arquivado):
    if arquivado:
        return "encerrado"
    if dias_sem_atividade > 90:
        return "parado"
    if prs_abertos > 0:
        return "em revisão"
    return "em andamento"


def esquecido(estagio, dias, proximo, arquivado, declarado=True):
    """Motivo pelo qual o projeto está esquecido, ou None."""
    if arquivado or (estagio in INATIVOS and (declarado or estagio != "parado")):
        return None
    # "parado" sugerido (sem STATE.md) e palpite: alarma como inatividade, nao silencia
    est = "em andamento" if not estagio or estagio == "parado" else estagio
    if est == "em revisão" and dias > LIMITE_REVISAO:
        return f"em revisão há {dias} dias"
    if est in ("em andamento", "ideia") and dias > LIMITE_ANDAMENTO:
        return f"sem atividade há {dias} dias"
    if declarado and not proximo:
        return "sem próximo passo"
    return None


# ponytail: classificacao por heuristica de dono/nome/linguagem; o Ricardo corrige no painel e a escolha dele vale
EMPRESA_DO_DONO = {"bekaa-trusted-advisors": "bekaa", "t4isb-infra": "bekaa", "forense-io": "forense",
                   "nessenergy": "ness", "familia-almeida": "pessoal"}
CLIENTE_DO_DONO = {"t4isb-infra": "t4isb"}
EMPRESA_DO_NOME = (("ionic", r"ionic|ihos|txramp|pq44"), ("bekaa", r"bekaa|aegis|twyn|orm\b|orm-"),
                   ("forense", r"forense|pericia"), ("pessoal", r"esper|wedding|familia|blog|sabrina|renata|fisio"),
                   ("ness", r"^n[.\-_]?[a-z0-9]|ness"))
TIPO_DO_NOME = (("infra", r"infra|stack|ops\b|terraform|ansible|availab|avaiab|proxmox|router"),
                ("site", r"site|landing|blog"), ("agente", r"agent|mcp|bot\b|pentest|copilot"),
                ("dados", r"data|lake|etl|pipeline"), ("conhecimento", r"skill|template|knowledge|notas|kb\b"),
                ("documento", r"isms|iso|polic|proposta|relatorio|contrato"))


def sugerir(dono, nome, linguagem, descricao):
    """Palpite de empresa, cliente e tipo a partir do dono, do nome, da linguagem e da descrição."""
    n = _sem_acento(f"{nome} {descricao or ''}").lower()
    empresa = EMPRESA_DO_DONO.get(dono.lower())
    if empresa is None:
        empresa = next((e for e, rx in EMPRESA_DO_NOME if re.search(rx, nome.lower())), None)
    cliente = CLIENTE_DO_DONO.get(dono.lower()) or ("alup" if "alup" in n else None)
    if (linguagem or "") == "HCL":
        tipo = "infra"
    else:
        tipo = next((t for t, rx in TIPO_DO_NOME if re.search(rx, n)), None)
        tipo = tipo or ("documento" if not linguagem else "app")
    return {"empresa": empresa, "cliente": cliente, "tipo": tipo}


def primeiro_paragrafo(texto, limite=280):
    """Primeiro parágrafo de texto corrido de um README (sem título, selo, imagem ou HTML)."""
    par = []
    for linha in (texto or "").splitlines():
        s = linha.strip()
        if not s:
            if par:
                break
            continue
        if s.startswith(("#", "<", "![", "[![", "---", "```", "|", ">")):
            if par:
                break
            continue
        par.append(s)
    if not par:
        return None
    r = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", " ".join(par))
    r = re.sub(r"[*_`]{1,3}", "", r)
    return r[:limite]


def aplicar_classes(painel, classes):
    """Classe final de cada projeto: escolha do Ricardo > STATE.md (tipo) > sugestão.

    O estágio marcado no painel (ex.: parado) vale como declarado: tira o projeto do alarme."""
    for chave in ("projetos", "arquivados"):
        for p in painel.get(chave, []):
            c, s = classes.get(p["id"]) or {}, p.get("sugestao") or {}
            p["classe"] = {"empresa": c.get("empresa") or s.get("empresa"), "area": c.get("area") or None,
                           "cliente": c.get("cliente") or (None if c else s.get("cliente")),
                           "tipo": c.get("tipo") or p.get("tipo") or s.get("tipo"), "linear": c.get("linear") or None,
                           "estagio": c.get("estagio") or None,
                           "confirmada": bool(c)}
            if c.get("estagio"):
                p["estagio"] = c["estagio"]
                p["esquecido"] = esquecido(c["estagio"], p.get("dias", 0), p.get("proximo") or "-", p.get("arquivado"))
    if "contadores" in painel:
        painel["contadores"].update(contar(painel.get("projetos", []), len(painel.get("a_destinar", []))))
    return painel


def contar(ativos, n_destinar):
    est = lambda r: r.get("estagio") or r.get("estagio_sugerido")
    return {
        "projetos": len(ativos),
        "esquecidos": sum(1 for r in ativos if r.get("esquecido")),
        "em_andamento": sum(1 for r in ativos if est(r) == "em andamento"),
        "em_revisao": sum(1 for r in ativos if est(r) == "em revisão"),
        "parados": sum(1 for r in ativos if est(r) == "parado"),
        "prs_abertos": sum(r.get("prs") or 0 for r in ativos),
        "ci_vermelho": sum(1 for r in ativos if r.get("ci") == "failure"),
        "a_destinar": n_destinar,
    }


# ponytail: deteccao por nome de arquivo e dependencia do package.json da raiz; monorepo com
# package.json por app so entra pelos arquivos. Ler os package.json de apps/* se faltar precisao.
POR_ARQUIVO = (("cloudflare", r"(^|/)wrangler\.(toml|jsonc?)$"), ("vercel", r"(^|/)vercel\.json$"),
               ("supabase", r"(^|/)supabase/"), ("docker", r"(^|/)(Dockerfile|docker-compose[^/]*|compose\.ya?ml)$"),
               ("terraform", r"\.tf$"), ("python", r"(^|/)(pyproject\.toml|requirements[^/]*\.txt)$"),
               ("node", r"(^|/)package\.json$"), ("go", r"(^|/)go\.mod$"), ("rust", r"(^|/)Cargo\.toml$"),
               ("github actions", r"^\.github/workflows/"), ("firebase", r"(^|/)firebase\.json$"))
POR_DEPENDENCIA = (("next.js", "next"), ("react", "react"), ("vue", "vue"), ("astro", "astro"), ("svelte", "svelte"),
                   ("hono", "hono"), ("express", "express"), ("supabase", "@supabase/supabase-js"),
                   ("prisma", "prisma"), ("drizzle", "drizzle-orm"), ("tailwind", "tailwindcss"),
                   ("ia", "@anthropic-ai/sdk"), ("ia", "openai"), ("ia", "ai"), ("ia", "@modelcontextprotocol/sdk"))
SEGREDO_NO_REPO = re.compile(r"(^|/)(\.env(\.[\w-]+)?|\.envrc|id_(rsa|ed25519|ecdsa)|[^/]+\.(pem|key|pfx|p12))$")
NAO_E_SEGREDO = re.compile(r"\.env\.(example|exemplo|sample|template|dist|modelo)$")


def detectar_tecnologias(caminhos, package_json, linguagem):
    """Stack pelos caminhos versionados e dependências; e arquivo com cara de segredo dentro do repositório."""
    tec = {linguagem.lower()} if linguagem else set()
    for nome, rx in POR_ARQUIVO:
        if any(re.search(rx, c) for c in caminhos):
            tec.add(nome)
    if package_json:
        try:
            pj = json.loads(package_json)
            deps = {**(pj.get("dependencies") or {}), **(pj.get("devDependencies") or {})}
        except (ValueError, AttributeError):
            deps = {}
        tec.update(nome for nome, dep in POR_DEPENDENCIA if dep in deps)
    segredos = sorted(c for c in caminhos if SEGREDO_NO_REPO.search(c) and not NAO_E_SEGREDO.search(c))
    return {"tecnologias": sorted(tec), "segredos_no_repo": segredos}


ONDE_FICA = (("cloudflare", "Cloudflare: wrangler secret / Secrets Store"),
             ("vercel", "Vercel: Environment Variables do projeto"),
             ("supabase", "Supabase: Vault / segredos das Edge Functions"),
             ("terraform", "Nuvem do Terraform: cofre do provedor (no GCP, Secret Manager)"),
             ("firebase", "Firebase: Secret Manager do projeto GCP"),
             ("github actions", "GitHub Actions: Secrets do repositório ou da organização"))


def segredos_esperados(tecnologias):
    """Onde os segredos do projeto devem ficar, pela regra do ambiente, conforme as tecnologias."""
    return [onde for t, onde in ONDE_FICA if t in tecnologias] + \
        ["Desenvolvimento na VPS: projetos.env ou .envrc (nunca no repositório)"]
