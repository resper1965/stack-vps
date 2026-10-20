"""Supervisor dos runners efêmeros de CI: mantém N runners por organização, cada um com configuração JIT, um job e fim.

Segurança: o token de organização (admin) só existe neste processo. O container recebe APENAS a configuração JIT, pelo
ambiente do processo `docker` (nunca no argv, em arquivo ou log). Código de terceiros roda dentro do container; por isso
cada ciclo recusa a organização se o grupo aceita repositório público ou se ela roda workflow de fork."""
import argparse
import json
import os
import re
import secrets
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
ROTULOS = ["self-hosted", "stack"]
LIMITE_POR_CICLO = 4
INTERVALO = 30
TETO_BACKOFF = 600
VAR_JIT = "ACTIONS_RUNNER_INPUT_JITCONFIG"
AMBIENTE_PERMITIDO = ("PATH", "HOME", "DOCKER_HOST", "XDG_RUNTIME_DIR")
RE_ORG = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}")
RE_CPUS = re.compile(r"[0-9.]+")
RE_MEMORIA = re.compile(r"[0-9]+[mMgG]")
RE_IMAGEM = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/:@-]*")
RE_NOME = re.compile(r"stack-(" + RE_ORG.pattern + r")-[0-9a-f]{8}")
CAMINHOS = {"config": "/srv/ci/config.json", "token": "/srv/ci/token", "status": "/srv/ci/status.json"}


def _log(msg):
    print(msg, file=sys.stderr, flush=True)


def _http(req):
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read(2000).decode("utf-8", "replace")).get("message", "")
        except ValueError:
            msg = ""
        raise RuntimeError(f"HTTP {e.code}: {str(msg)[:200]}") from None
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise RuntimeError(f"falha de rede: {e}") from None


def urllib_get(url, cabecalhos):
    return _http(urllib.request.Request(url, headers=cabecalhos, method="GET"))


def urllib_post(url, cabecalhos, corpo):
    cab = {**cabecalhos, "Content-Type": "application/json"}
    return _http(urllib.request.Request(url, data=json.dumps(corpo).encode(), headers=cab, method="POST"))


class Github:
    def __init__(self, token, post=urllib_post, get=urllib_get):
        self.token, self._post, self._get = token, post, get

    def _cab(self):
        return {"Authorization": f"Bearer {self.token}", "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "stack-ci"}

    def _chamar(self, fn, *args):
        try:
            return fn(*args)
        except RuntimeError as e:
            raise RuntimeError(str(e).replace(self.token, "***")) from None

    def _url(self, org, resto):
        return f"{API}/orgs/{urllib.parse.quote(org, safe='')}/actions/{resto}"

    def grupo(self, org, nome):
        r = self._chamar(self._get, self._url(org, "runner-groups?per_page=100"), self._cab())
        for g in r.get("runner_groups", []):
            if str(g.get("name", "")).casefold() == nome.casefold():
                return g
        raise RuntimeError(f"grupo '{nome}' não encontrado na organização {org}")

    def permissoes_fork(self, org):
        return self._chamar(self._get, self._url(org, "permissions/fork-pr-workflows-private-repos"), self._cab())

    def runners(self, org):
        return self._chamar(self._get, self._url(org, "runners?per_page=100"), self._cab()).get("runners", [])

    def jitconfig(self, org, grupo_id, nome, rotulos):
        r = self._chamar(self._post, self._url(org, "runners/generate-jitconfig"), self._cab(),
                         {"name": nome, "runner_group_id": grupo_id, "labels": rotulos})
        jit = r.get("encoded_jit_config")
        if not isinstance(jit, str) or not jit:
            raise RuntimeError("resposta sem encoded_jit_config")
        return jit


def planejar(configuracao, ativos):
    faltas = [(org, c["quantidade"] - ativos.get(org, 0)) for org, c in configuracao.items()]
    return [(org, n) for org, n in faltas if n > 0]


class Docker:
    def __init__(self, docker_socket=False, ambiente=None):
        amb = os.environ if ambiente is None else ambiente
        # lista explícita: o ambiente do pai (que pode ter segredos) nunca chega ao docker
        self._env = {k: amb[k] for k in AMBIENTE_PERMITIDO if k in amb}
        self._socket = None
        if docker_socket:
            host = self._env.get("DOCKER_HOST", "")
            if not host.startswith("unix://") or len(host) <= 7:
                raise RuntimeError("docker_socket exige DOCKER_HOST=unix:///caminho")
            self._socket = host[len("unix://"):]

    def _run(self, args, env_extra=None, segredo=None):
        env = {**self._env, **(env_extra or {})}
        try:
            r = subprocess.run(args, env=env, capture_output=True, text=True, timeout=120, check=False)
        except (OSError, subprocess.SubprocessError) as e:
            raise RuntimeError(f"docker {args[1]}: {type(e).__name__}") from None
        if r.returncode != 0:
            err = (r.stderr or "").strip()[:200]
            if segredo:
                err = err.replace(segredo, "***")
            raise RuntimeError(f"docker {args[1]} falhou ({r.returncode}): {err}")
        return r.stdout

    def iniciar(self, nome, imagem, jit, cpus, memoria):
        m = RE_NOME.fullmatch(nome)
        if not (m and RE_IMAGEM.fullmatch(imagem) and RE_CPUS.fullmatch(cpus) and RE_MEMORIA.fullmatch(memoria)):
            raise RuntimeError("parâmetros inválidos para o container")
        args = ["docker", "run", "-d", "--rm", "--name", nome, "--label", f"stack-ci={m.group(1)}",
                "--cpus", cpus, "--memory", memoria, "--pids-limit", "512"]
        if self._socket:
            args += ["-v", f"{self._socket}:/var/run/docker.sock"]
        # "-e NOME" sem valor: o docker lê o valor do SEU ambiente, então o JIT não aparece no argv
        args += ["-e", VAR_JIT, imagem, "./run.sh"]
        self._run(args, {VAR_JIT: jit}, jit)

    def ativos(self, rotulo):
        out = self._run(["docker", "ps", "--filter", f"label=stack-ci={rotulo}", "--format", "{{.ID}}"])
        return {rotulo: len([ln for ln in out.splitlines() if ln.strip()])}

    def parar_todos(self):
        ids = self._run(["docker", "ps", "-q", "--filter", "label=stack-ci"]).split()
        if ids:
            self._run(["docker", "stop", *ids])


def validar_org(gh, org, nome_grupo):
    """Devolve o id do grupo ou levanta RuntimeError: nada é iniciado para uma organização que aceita código alheio."""
    g = gh.grupo(org, nome_grupo)
    if g.get("allows_public_repositories"):
        raise RuntimeError(f"grupo '{nome_grupo}' permite repositórios públicos; recusado")
    if gh.permissoes_fork(org).get("run_workflows_from_fork_pull_requests"):
        raise RuntimeError("a organização roda workflows de pull requests de forks; recusado")
    return g["id"]


def _gravar_estado(estado, caminho):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(caminho) or ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(estado, f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, caminho)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def ciclo(cfg, gh, dk, estado_path, agora):
    orgs, erros, iniciados = {}, [], 0
    for org, o in cfg["orgs"].items():
        ativos = 0
        try:
            ativos = dk.ativos(org).get(org, 0)
            faltam = dict(planejar({org: o}, {org: ativos})).get(org, 0)
            if faltam and iniciados < LIMITE_POR_CICLO:
                gid = validar_org(gh, org, o["grupo"])
                for _ in range(min(faltam, LIMITE_POR_CICLO - iniciados)):
                    nome = f"stack-{org}-{secrets.token_hex(4)}"
                    jit = gh.jitconfig(org, gid, nome, ROTULOS)
                    dk.iniciar(nome, cfg["imagem"], jit, cfg["cpus"], cfg["memoria"])  # se falhar, o JIT expira
                    iniciados += 1
                    ativos += 1
                    _log(f"{org} {nome}")
        except RuntimeError as e:
            erros.append(f"{org}: {e}")
            _log(f"erro {org}: {e}")
        orgs[org] = {"ativos": ativos, "esperados": o["quantidade"]}
    resumo = {"atualizado": agora, "runners": sum(v["ativos"] for v in orgs.values()),
              "erro": "; ".join(erros)[:500] or None, "orgs": orgs}
    _gravar_estado(resumo, estado_path)
    return resumo


def proxima_espera(anterior, erro):
    return min(max(anterior, INTERVALO) * 2, TETO_BACKOFF) if erro else INTERVALO


def carregar_config(caminho):
    """Valida estritamente; levanta ValueError com mensagem clara."""
    try:
        with open(caminho, encoding="utf-8") as f:
            c = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError(f"config ilegível: {type(e).__name__}") from None
    if not isinstance(c, dict):
        raise ValueError("config deve ser um objeto")
    extras = set(c) - {"imagem", "cpus", "memoria", "docker_socket", "orgs"}
    if extras:
        raise ValueError(f"chaves desconhecidas na config: {sorted(extras)}")
    for chave, padrao in (("imagem", RE_IMAGEM), ("cpus", RE_CPUS), ("memoria", RE_MEMORIA)):
        if not isinstance(c.get(chave), str) or not padrao.fullmatch(c[chave]):
            raise ValueError(f"'{chave}' ausente ou inválido")
    if not isinstance(c.setdefault("docker_socket", False), bool):
        raise ValueError("'docker_socket' deve ser booleano")
    if not isinstance(c.get("orgs"), dict) or not c["orgs"]:
        raise ValueError("'orgs' deve ser um objeto não vazio")
    for org, o in c["orgs"].items():
        if not RE_ORG.fullmatch(org):
            raise ValueError(f"nome de organização inválido: {org!r}")
        if not isinstance(o, dict) or set(o) != {"grupo", "quantidade"}:
            raise ValueError(f"{org}: esperado exatamente 'grupo' e 'quantidade'")
        if not isinstance(o["grupo"], str) or not o["grupo"].strip() or len(o["grupo"]) > 100 \
                or any(ord(ch) < 32 or ord(ch) == 127 for ch in o["grupo"]):
            raise ValueError(f"{org}: 'grupo' inválido")
        q = o["quantidade"]
        if isinstance(q, bool) or not isinstance(q, int) or not 0 <= q <= 10:
            raise ValueError(f"{org}: 'quantidade' deve ser inteiro de 0 a 10")
    return c


def ler_token(caminho):
    """Recusa arquivo que não seja regular e privado; as mensagens nunca trazem o conteúdo."""
    try:
        modo = os.lstat(caminho).st_mode
        if stat.S_ISLNK(modo):
            raise ValueError("token é um link simbólico")
        if not stat.S_ISREG(modo):  # antes do open: um FIFO bloquearia
            raise ValueError("token não é arquivo regular")
        fd = os.open(caminho, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError as e:
        raise ValueError(f"token ilegível: {type(e).__name__}") from None
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:
            raise ValueError("token não é arquivo regular ou tem permissão de grupo/outros; use chmod 0400")
        t = f.read(4096).decode("utf-8", "replace").strip()
    if not t:
        raise ValueError("token vazio")
    if any(ord(ch) <= 32 or ord(ch) == 127 or ch == '"' for ch in t):
        raise ValueError("token com espaço, caractere de controle ou aspas")
    return t


def _novo_github(token):
    return Github(token)


def _novo_docker(cfg):
    return Docker(docker_socket=cfg["docker_socket"])


def main(argv=None):
    a = argparse.ArgumentParser()
    a.add_argument("--config", default=CAMINHOS["config"])
    a.add_argument("--token-file", default=CAMINHOS["token"])
    a.add_argument("--status", default=CAMINHOS["status"])
    a.add_argument("--uma-vez", action="store_true")
    o = a.parse_args(argv)
    try:
        cfg = carregar_config(o.config)
        token = ler_token(o.token_file)
        gh, dk = _novo_github(token), _novo_docker(cfg)
    except (ValueError, RuntimeError) as e:
        _log(f"ci: {e}")
        return 2
    parar = threading.Event()
    antigos = {s: signal.signal(s, lambda *_: parar.set()) for s in (signal.SIGTERM, signal.SIGINT)}
    try:
        espera = INTERVALO
        while True:
            try:
                erro = bool(ciclo(cfg, gh, dk, o.status, time.time())["erro"])
            except Exception as e:  # noqa: BLE001 — o laço sobrevive; só o tipo vai ao log, nunca dados
                _log(f"erro no ciclo: {type(e).__name__}")
                erro = True
            if o.uma_vez:
                return 1 if erro else 0
            espera = proxima_espera(espera, erro)
            # SIGTERM só interrompe a espera: containers com job em andamento continuam até terminar
            if parar.wait(espera) or parar.is_set():
                return 0
    finally:
        for s, h in antigos.items():
            signal.signal(s, h)


if __name__ == "__main__":
    sys.exit(main())
