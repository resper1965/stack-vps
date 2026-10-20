"""Supervisor dos runners efêmeros de CI: mantém N runners por organização, cada um com configuração JIT, um job e fim.

Segurança: o token de organização (admin) só existe neste processo. O container recebe APENAS a configuração JIT, pelo
ambiente do processo `docker` (nunca no argv, em arquivo ou log). Código de terceiros roda dentro do container; por isso
cada ciclo recusa a organização se o grupo aceita repositório público ou se ela roda workflow de fork (falha fechado:
só `False` exato passa). A validação da organização roda sempre que ela está com runners faltando (não a cada ciclo
se nada falta). Falhas têm backoff por organização e um laço de reinício (container que morre ao nascer) pausa a
criação de JIT para aquela organização.

Operação: a unidade systemd não deve definir variáveis de proxy (o opener ignora proxies de qualquer forma, para o
token nunca passar por um intermediário); DOCKER_HOST só é exigido com docker_socket."""
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
BACKOFF_ORG = 60
TETO_BACKOFF = 600
MORTE_PRECOCE = 40  # s: runner legítimo leva ~10 s para subir e fica vivo esperando/rodando um job
SEGUIDOS_LACO = 5
PAUSA_LACO = 900
VAR_JIT = "ACTIONS_RUNNER_INPUT_JITCONFIG"
AMBIENTE_PERMITIDO = ("PATH", "HOME", "DOCKER_HOST", "XDG_RUNTIME_DIR")
RE_ORG = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}")
RE_CPUS = re.compile(r"[0-9.]+")
RE_MEMORIA = re.compile(r"[0-9]+[mMgG]")
RE_IMAGEM = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/:@-]*")
RE_TOKEN = re.compile(r"[A-Za-z0-9_]{20,255}")
RE_NOME = re.compile(r"stack-(" + RE_ORG.pattern + r")-[0-9a-f]{8}")
CAMINHOS = {"config": "/srv/ci/config.json", "token": "/srv/ci/token", "status": "/srv/ci/status.json"}
AVISO_SOCKET = ("WARNING: docker_socket ativo. Jobs com o socket do Docker podem ler o token da organização "
                "(/srv/ci/token) e as configurações JIT dos runners vizinhos; use só com repositórios totalmente "
                "confiáveis.")


def _log(msg):
    print(msg, file=sys.stderr, flush=True)


def _limpa(texto, n=200):
    """Sem caracteres de controle (nem quebra de linha) e com tamanho limitado: vai a log e status.json."""
    return "".join(" " if ord(c) < 32 or 127 <= ord(c) <= 159 or ord(c) in (0x2028, 0x2029) else c
                   for c in str(texto))[:n]


def _txt(x):
    if isinstance(x, bytes):
        return x.decode("utf-8", "replace")
    return x or ""


def _cpus_ok(s):
    try:
        return bool(RE_CPUS.fullmatch(s)) and float(s) > 0
    except ValueError:
        return False


def _memoria_ok(s):
    return bool(RE_MEMORIA.fullmatch(s)) and int(s[:-1]) > 0


class _SemRedirecionamento(urllib.request.HTTPRedirectHandler):
    # redirecionar copiaria o Authorization para outro host
    def redirect_request(self, *args, **kwargs):
        raise RuntimeError("redirecionamento recusado")


_abridor = urllib.request.build_opener(urllib.request.ProxyHandler({}), _SemRedirecionamento)


def _mensagem(e):
    try:
        m = json.loads(e.read(2000).decode("utf-8", "replace")).get("message", "")
    except (ValueError, AttributeError, OSError):
        m = ""
    return _limpa(m)


def _http(req):
    try:
        with _abridor.open(req, timeout=10) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        erro = f"HTTP {e.code}: {_mensagem(e)}"
    except RuntimeError:
        raise
    except (urllib.error.URLError, OSError, ValueError) as e:
        erro = f"falha de rede: {_limpa(e)}"
    raise RuntimeError(erro)  # fora do except: sem __context__ carregando a exceção original


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

    def _obj(self, fn, *args):
        """Chama e devolve um objeto JSON; o erro sai sem o token e sem a exceção original encadeada."""
        try:
            r = fn(*args)
            erro = None if isinstance(r, dict) else "resposta inesperada da API (não é um objeto)"
        except RuntimeError as e:
            r, erro = None, _limpa(str(e).replace(self.token, "***"))
        if erro:
            raise RuntimeError(erro)
        return r

    def _url(self, org, resto):
        return f"{API}/orgs/{urllib.parse.quote(org, safe='')}/actions/{resto}"

    def grupo(self, org, nome):
        gs = self._obj(self._get, self._url(org, "runner-groups?per_page=100"), self._cab()).get("runner_groups")
        if not isinstance(gs, list) or not all(
                isinstance(g, dict) and isinstance(g.get("id"), int) and not isinstance(g.get("id"), bool)
                and isinstance(g.get("name"), str) for g in gs):
            raise RuntimeError("resposta inesperada da API: runner_groups")
        for g in gs:
            if g["name"].casefold() == nome.casefold():
                return g
        raise RuntimeError(f"grupo '{_limpa(nome, 100)}' não encontrado na organização {org}")

    def permissoes_fork(self, org):
        return self._obj(self._get, self._url(org, "permissions/fork-pr-workflows-private-repos"), self._cab())

    def runners(self, org):
        rs = self._obj(self._get, self._url(org, "runners?per_page=100"), self._cab()).get("runners")
        if not isinstance(rs, list) or not all(isinstance(r, dict) for r in rs):
            raise RuntimeError("resposta inesperada da API: runners")
        return rs

    def jitconfig(self, org, grupo_id, nome, rotulos):
        r = self._obj(self._post, self._url(org, "runners/generate-jitconfig"), self._cab(),
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
        r, erro = None, None
        try:
            r = subprocess.run(args, env=env, capture_output=True, timeout=120, check=False)
        except (OSError, subprocess.SubprocessError) as e:
            erro = f"docker {args[1]}: {type(e).__name__}"
        if r is not None and r.returncode != 0:
            err = _txt(r.stderr).strip()
            if segredo:
                err = err.replace(segredo, "***")
            err = _limpa(err)  # redige antes de truncar: um segredo cortado ao meio não seria mais encontrado
            erro = f"docker {args[1]} falhou ({r.returncode}): {err}"
        if erro:
            raise RuntimeError(erro)
        return _txt(r.stdout)

    def iniciar(self, nome, imagem, jit, cpus, memoria):
        m = RE_NOME.fullmatch(nome)
        if not (m and RE_IMAGEM.fullmatch(imagem) and _cpus_ok(cpus) and _memoria_ok(memoria)):
            raise RuntimeError("parâmetros inválidos para o container")
        args = ["docker", "run", "-d", "--rm", "--name", nome, "--label", f"stack-ci={m.group(1)}",
                "--cpus", cpus, "--memory", memoria, "--pids-limit", "512"]
        if self._socket:
            args += ["-v", f"{self._socket}:/var/run/docker.sock"]
        # "-e NOME" sem valor: o docker lê o valor do SEU ambiente, então o JIT não aparece no argv
        args += ["-e", VAR_JIT, imagem, "./run.sh"]
        self._run(args, {VAR_JIT: jit}, jit)

    def nomes(self, rotulo):
        out = self._run(["docker", "ps", "--filter", f"label=stack-ci={rotulo}", "--format", "{{.Names}}"])
        return [ln for ln in out.splitlines() if RE_NOME.fullmatch(ln)]

    def ativos(self, rotulo):
        return {rotulo: len(self.nomes(rotulo))}

    def parar_todos(self):
        ids = self._run(["docker", "ps", "-q", "--filter", "label=stack-ci"]).split()
        if ids:
            self._run(["docker", "stop", *ids])


def validar_org(gh, org, nome_grupo):
    """Devolve o id do grupo ou levanta RuntimeError. Falha fechado: campo ausente ou que não seja exatamente
    False recusa a organização."""
    g = gh.grupo(org, nome_grupo)
    if g.get("allows_public_repositories") is not False:
        raise RuntimeError(f"grupo '{_limpa(nome_grupo, 100)}' permite (ou não informa) repositórios públicos; recusado")
    if gh.permissoes_fork(org).get("run_workflows_from_fork_pull_requests") is not False:
        raise RuntimeError("a organização roda (ou não informa) workflows de pull requests de forks; recusado")
    return g["id"]


class LacoDeReinicio(RuntimeError):
    pass


def espera_org(falhas):
    return min(BACKOFF_ORG * 2 ** min(max(falhas, 1) - 1, 10), TETO_BACKOFF)


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


def _formatar(e, segredos):
    msg = str(e)
    for s in segredos:
        if s:
            msg = msg.replace(s, "***")
    msg = _limpa(msg)
    return msg if isinstance(e, RuntimeError) else f"{type(e).__name__}: {msg}"


def _observar_mortes(m, vivos, t):
    """Container que já sumiu na primeira observação (idade < MORTE_PRECOCE) é sinal de laço de reinício;
    um que viveu o bastante, ou ainda vive, zera o contador."""
    for nome, t0 in list(m["recem"].items()):
        idade = t - t0
        if nome in vivos:
            if idade >= MORTE_PRECOCE:
                del m["recem"][nome]
                m["precoces"] = 0
        else:
            del m["recem"][nome]
            m["precoces"] = m["precoces"] + 1 if idade < MORTE_PRECOCE else 0


def ciclo(cfg, gh, dk, estado_path, agora, memoria=None, mono=None):
    """Um passe. `memoria` guarda o estado por organização (backoff, mortes precoces) entre ciclos; os tempos desse
    estado usam `mono` (relógio monotônico, padrão `agora`), e `agora` só vai para o status.json."""
    memoria = {} if memoria is None else memoria
    t = agora if mono is None else mono
    orgs, erros, iniciados = {}, [], 0
    for org, o in cfg["orgs"].items():
        m = memoria.setdefault(org, {"falhas": 0, "proximo": 0.0, "recem": {}, "precoces": 0, "pausa_ate": 0.0,
                                     "ativos": 0, "ultimo": ""})
        if t < m["proximo"]:
            erros.append(f"{org}: em espera por {int(m['proximo'] - t)} s após falha ({m['ultimo']})")
            orgs[org] = {"ativos": m["ativos"], "esperados": o["quantidade"]}
            continue
        ativos, jit, falha = m["ativos"], None, None
        try:
            vivos = dk.nomes(org)
            ativos = len(vivos)
            _observar_mortes(m, vivos, t)
            if m["pausa_ate"] and t >= m["pausa_ate"]:
                m["pausa_ate"], m["precoces"] = 0.0, 0
            faltam = dict(planejar({org: o}, {org: ativos})).get(org, 0)
            if faltam:
                msg = (f"runners morrem logo após iniciar ({m['precoces']} seguidos); parado por "
                       f"{PAUSA_LACO // 60} min")
                if t < m["pausa_ate"]:
                    raise LacoDeReinicio(msg)
                if m["precoces"] >= SEGUIDOS_LACO:
                    m["pausa_ate"] = t + PAUSA_LACO
                    _log(f"{org}: {msg}")
                    raise LacoDeReinicio(msg)
                if iniciados < LIMITE_POR_CICLO:
                    gid = validar_org(gh, org, o["grupo"])
                    for _ in range(min(faltam, LIMITE_POR_CICLO - iniciados)):
                        nome = f"stack-{org}-{secrets.token_hex(4)}"
                        jit = gh.jitconfig(org, gid, nome, ROTULOS)
                        dk.iniciar(nome, cfg["imagem"], jit, cfg["cpus"], cfg["memoria"])  # se falhar, o JIT expira
                        m["recem"][nome] = t
                        iniciados += 1
                        ativos += 1
                        _log(f"{org} {nome}")
        except Exception as e:  # noqa: BLE001 — uma organização nunca derruba as outras nem o status.json
            falha = _formatar(e, [getattr(gh, "token", None), jit])
            if not isinstance(e, LacoDeReinicio):
                _log(f"erro {org}: {falha}")
        m["ativos"] = ativos
        if falha:
            m["falhas"] += 1
            m["proximo"] = t + espera_org(m["falhas"])
            m["ultimo"] = falha
            erros.append(f"{org}: {falha}")
        else:
            m["falhas"], m["proximo"], m["ultimo"] = 0, 0.0, ""
        orgs[org] = {"ativos": ativos, "esperados": o["quantidade"]}
    resumo = {"atualizado": agora, "runners": sum(v["ativos"] for v in orgs.values()),
              "erro": "; ".join(erros)[:500] or None, "orgs": orgs}
    _gravar_estado(resumo, estado_path)
    return resumo


def carregar_config(caminho):
    """Valida estritamente; levanta ValueError com mensagem clara."""
    try:
        with open(caminho, encoding="utf-8") as f:
            c = json.load(f)
    except (OSError, ValueError) as e:
        raise ValueError(f"config ilegível: {type(e).__name__}") from None
    if not isinstance(c, dict):
        raise ValueError("config deve ser um objeto")
    extras = set(c) - {"imagem", "cpus", "memoria", "docker_socket", "docker_socket_ciente_do_risco", "orgs"}
    if extras:
        raise ValueError(f"chaves desconhecidas na config: {sorted(extras)}")
    if not isinstance(c.get("imagem"), str) or not RE_IMAGEM.fullmatch(c["imagem"]):
        raise ValueError("'imagem' ausente ou inválida")
    if not isinstance(c.get("cpus"), str) or not _cpus_ok(c["cpus"]):
        raise ValueError("'cpus' ausente ou inválido (número maior que zero)")
    if not isinstance(c.get("memoria"), str) or not _memoria_ok(c["memoria"]):
        raise ValueError("'memoria' ausente ou inválida (ex.: 4g, maior que zero)")
    for chave in ("docker_socket", "docker_socket_ciente_do_risco"):
        if not isinstance(c.setdefault(chave, False), bool):
            raise ValueError(f"'{chave}' deve ser booleano")
    if c["docker_socket"] and c["docker_socket_ciente_do_risco"] is not True:
        raise ValueError("docker_socket dá aos jobs acesso ao token da organização e aos JIT dos runners vizinhos; "
                         "para aceitar o risco defina também 'docker_socket_ciente_do_risco': true")
    if not isinstance(c.get("orgs"), dict) or not c["orgs"]:
        raise ValueError("'orgs' deve ser um objeto não vazio")
    vistos = set()
    for org, o in c["orgs"].items():
        if not RE_ORG.fullmatch(org):
            raise ValueError(f"nome de organização inválido: {org!r}")
        if org.lower() in vistos:
            raise ValueError(f"organização repetida (maiúsculas/minúsculas): {org}")
        vistos.add(org.lower())
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
    """Recusa arquivo que não seja regular, do próprio usuário e privado; as mensagens nunca trazem o conteúdo."""
    try:
        modo = os.lstat(caminho).st_mode
        if stat.S_ISLNK(modo):
            raise ValueError("token é um link simbólico")
        if not stat.S_ISREG(modo):  # antes do open: um FIFO bloquearia
            raise ValueError("token não é arquivo regular")
        fd = os.open(caminho, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as f:
            st = os.fstat(f.fileno())
            if not stat.S_ISREG(st.st_mode) or st.st_mode & 0o077:
                raise ValueError("token não é arquivo regular ou tem permissão de grupo/outros; use chmod 0400")
            if hasattr(os, "geteuid") and st.st_uid != os.geteuid():
                raise ValueError("token pertence a outro usuário")
            bruto = f.read(4097)
    except OSError as e:
        raise ValueError(f"token ilegível: {type(e).__name__}") from None
    if len(bruto) > 4096:
        raise ValueError("token grande demais")
    t = bruto.decode("utf-8", "replace").strip()
    if not t:
        raise ValueError("token vazio")
    if not RE_TOKEN.fullmatch(t):
        raise ValueError("token fora do formato esperado (20 a 255 caracteres de A-Z a-z 0-9 _)")
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
    if cfg["docker_socket"]:
        _log(AVISO_SOCKET)
    parar = threading.Event()
    antigos = {s: signal.signal(s, lambda *_: parar.set()) for s in (signal.SIGTERM, signal.SIGINT)}
    memoria = {}
    try:
        while True:
            try:
                erro = bool(ciclo(cfg, gh, dk, o.status, time.time(), memoria, time.monotonic())["erro"])
            except Exception as e:  # noqa: BLE001 — o laço sobrevive; só o tipo vai ao log, nunca dados
                _log(f"erro no ciclo: {type(e).__name__}")
                erro = True
            if o.uma_vez:
                return 1 if erro else 0
            # SIGTERM só interrompe a espera: containers com job em andamento continuam até terminar
            if parar.wait(INTERVALO) or parar.is_set():
                return 0
    finally:
        for s, h in antigos.items():
            signal.signal(s, h)


if __name__ == "__main__":
    sys.exit(main())
