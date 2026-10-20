import contextlib
import io
import json
import os
import signal
import stat
import tempfile
import unittest
import urllib.error
from unittest import mock

from ci import runners
from ci.runners import (Docker, Github, LIMITE_POR_CICLO, ciclo, espera_org, planejar, TETO_BACKOFF)

TOKEN = "ghp_SEGREDOSEGREDO123"
JIT = "JITCONFIGBASE64=="
POSIX = os.name == "posix"


class GithubFalso:
    def __init__(self, publico=False, fork=False, visibilidade="all", grupo_existe=True, falha=None):
        self.publico, self.fork, self.visibilidade = publico, fork, visibilidade
        self.grupo_existe, self.falha, self.jits = grupo_existe, falha, []

    def grupo(self, org, nome):
        if self.falha:
            raise RuntimeError(self.falha)
        if not self.grupo_existe:
            raise RuntimeError(f"grupo '{nome}' não encontrado")
        return {"id": 1, "visibility": self.visibilidade, "allows_public_repositories": self.publico}

    def permissoes_fork(self, org):
        return {"run_workflows_from_fork_pull_requests": self.fork}

    def jitconfig(self, org, grupo_id, nome, rotulos):
        self.jits.append((org, nome))
        return JIT


class DockerFalso:
    def __init__(self, ativos=None, falha=False):
        self.iniciados, self._ativos, self.falha, self.parou = [], ativos or {}, falha, False

    def ativos(self, rotulo):
        return {rotulo: self._ativos.get(rotulo, 0)}

    def iniciar(self, nome, imagem, jit, cpus, memoria):
        if self.falha:
            raise RuntimeError("docker run falhou (1): boom")
        self.iniciados.append(nome)

    def parar_todos(self):
        self.parou = True


def cfg(**orgs):
    return {"imagem": "ghcr.io/actions/actions-runner:latest", "cpus": "2", "memoria": "4g", "docker_socket": False,
            "orgs": {o: {"grupo": "Default", "quantidade": q} for o, q in (orgs or {"acme": 2}).items()}}


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.estado = os.path.join(self.dir.name, "status.json")
        err = contextlib.redirect_stderr(io.StringIO())
        err.__enter__()
        self.addCleanup(err.__exit__, None, None, None)

    def caminho(self, nome, conteudo=None, modo=0o600):
        p = os.path.join(self.dir.name, nome)
        if conteudo is not None:
            with open(p, "w") as f:
                f.write(conteudo)
            os.chmod(p, modo)
        return p


class Planejar(unittest.TestCase):
    def test_planejar_calcula_o_que_falta(self):
        c = {"a": {"grupo": "Default", "quantidade": 3}, "b": {"grupo": "Default", "quantidade": 1}}
        self.assertEqual(planejar(c, {"a": 1}), [("a", 2), ("b", 1)])

    def test_planejar_nao_inicia_alem_da_quantidade(self):
        c = {"a": {"grupo": "Default", "quantidade": 2}}
        self.assertEqual(planejar(c, {"a": 2}), [])
        self.assertEqual(planejar(c, {"a": 5}), [])


class DockerReal(unittest.TestCase):
    def iniciar(self, docker=None, **kw):
        chamadas = []

        def run(args, **k):
            chamadas.append((args, k))
            return mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch("ci.runners.subprocess.run", run):
            (docker or Docker(ambiente={"PATH": "/bin", "HOME": "/srv/ci", "TOKEN_DO_PAI": TOKEN})).iniciar(
                "stack-acme-0a1b2c3d", "img:1", JIT, "2", "4g", **kw)
        return chamadas[0]

    def test_container_recebe_so_a_configuracao_jit(self):
        args, k = self.iniciar()
        self.assertNotIn("shell", k)
        self.assertFalse(any(TOKEN in a for a in args))
        self.assertFalse(any(TOKEN in v for v in k["env"].values()))
        self.assertFalse(any(JIT in a for a in args))
        self.assertEqual(k["env"]["ACTIONS_RUNNER_INPUT_JITCONFIG"], JIT)
        self.assertEqual(sum(JIT in v for v in k["env"].values()), 1)
        i = args.index("-e")
        self.assertEqual(args[i + 1], "ACTIONS_RUNNER_INPUT_JITCONFIG")
        self.assertEqual(args[i + 2], "img:1")
        self.assertEqual(set(k["env"]), {"PATH", "HOME", "ACTIONS_RUNNER_INPUT_JITCONFIG"})
        for esperado in ("--rm", "-d", "--pids-limit", "512", "--cpus", "2", "--memory", "4g", "stack-ci=acme"):
            self.assertIn(esperado, args)
        self.assertEqual(args[-2:], ["img:1", "./run.sh"])

    def test_docker_socket_so_quando_configurado(self):
        args, _ = self.iniciar()
        self.assertNotIn("-v", args)
        d = Docker(docker_socket=True, ambiente={"PATH": "/bin", "DOCKER_HOST": "unix:///run/user/1001/docker.sock"})
        args, _ = self.iniciar(d)
        self.assertEqual(args.count("-v"), 1)
        self.assertEqual(args[args.index("-v") + 1], "/run/user/1001/docker.sock:/var/run/docker.sock")
        with self.assertRaises(RuntimeError):
            Docker(docker_socket=True, ambiente={"PATH": "/bin"})

    def test_nenhuma_flag_nao_verificada(self):
        d = Docker(docker_socket=True, ambiente={"DOCKER_HOST": "unix:///s.sock"})
        for args in (self.iniciar()[0], self.iniciar(d)[0]):
            for proibida in ("--privileged", "--network", "--net", "--cap-add", "--cap-drop", "--pid", "--ipc",
                             "--userns", "--security-opt", "--env-file"):
                self.assertNotIn(proibida, args)

    def test_parametros_invalidos_nao_chegam_ao_docker(self):
        with mock.patch("ci.runners.subprocess.run") as r:
            for ruim in (("stack-acme-xyz", "img", "2", "4g"), ("stack-acme-0a1b2c3d", "--privileged", "2", "4g"),
                         ("stack-acme-0a1b2c3d", "img", "2 --privileged", "4g"),
                         ("stack-acme-0a1b2c3d", "img", "2", "4g -v /:/h")):
                with self.assertRaises(RuntimeError):
                    Docker(ambiente={}).iniciar(ruim[0], ruim[1], JIT, ruim[2], ruim[3])
            r.assert_not_called()

    def test_ativos_conta_por_rotulo(self):
        def run(args, **k):
            self.assertIn("label=stack-ci=acme", args)
            return mock.Mock(returncode=0, stdout="aaa\nbbb\n", stderr="")
        with mock.patch("ci.runners.subprocess.run", run):
            self.assertEqual(Docker(ambiente={}).ativos("acme"), {"acme": 2})

    def test_falha_do_docker_nao_vaza_o_jit(self):
        r = mock.Mock(returncode=125, stdout="", stderr=f"erro com {JIT}")
        with mock.patch("ci.runners.subprocess.run", return_value=r):
            with self.assertRaises(RuntimeError) as c:
                Docker(ambiente={}).iniciar("stack-acme-0a1b2c3d", "img", JIT, "2", "4g")
        self.assertNotIn(JIT, str(c.exception))


class GithubApi(unittest.TestCase):
    def test_cabecalhos_e_corpo(self):
        vistos = []

        def get(url, cab):
            vistos.append((url, cab))
            return {"runner_groups": [{"id": 7, "name": "Default", "allows_public_repositories": False}]}

        def post(url, cab, corpo):
            vistos.append((url, cab, corpo))
            return {"runner": {"id": 1}, "encoded_jit_config": JIT}
        gh = Github(TOKEN, post=post, get=get)
        self.assertEqual(gh.grupo("acme", "default")["id"], 7)
        self.assertEqual(gh.jitconfig("acme", 7, "n", ["self-hosted", "stack"]), JIT)
        cab = vistos[0][1]
        self.assertEqual(cab["Authorization"], f"Bearer {TOKEN}")
        self.assertEqual(cab["X-GitHub-Api-Version"], "2022-11-28")
        self.assertTrue(vistos[1][0].endswith("/orgs/acme/actions/runners/generate-jitconfig"))
        self.assertEqual(vistos[1][2], {"name": "n", "runner_group_id": 7, "labels": ["self-hosted", "stack"]})

    def test_erro_da_api_nao_vaza_o_token(self):
        def get(url, cab):
            raise RuntimeError(f"HTTP 401: Bearer {TOKEN} inválido")
        with self.assertRaises(RuntimeError) as c:
            Github(TOKEN, get=get).permissoes_fork("acme")
        self.assertNotIn(TOKEN, str(c.exception))
        self.assertIn("401", str(c.exception))

    def test_erro_http_real_traz_status_e_mensagem_sem_token(self):
        corpo = io.BytesIO(json.dumps({"message": "Bad credentials"}).encode())
        e = urllib.error.HTTPError("https://api.github.com/x", 401, "x", {}, corpo)
        with mock.patch("ci.runners._abridor.open", side_effect=e) as u:
            with self.assertRaises(RuntimeError) as c:
                Github(TOKEN).runners("acme")
        self.assertEqual(str(c.exception), "HTTP 401: Bad credentials")
        self.assertEqual(u.call_args.kwargs["timeout"], 10)

    def test_grupo_inexistente(self):
        gh = Github(TOKEN, get=lambda u, c: {"runner_groups": [{"id": 1, "name": "Default"}]})
        with self.assertRaises(RuntimeError):
            gh.grupo("acme", "Outro")


class Ciclo(Base):
    def test_recusa_grupo_com_repositorio_publico(self):
        gh, dk = GithubFalso(publico=True), DockerFalso()
        with self.assertRaises(RuntimeError):
            runners.validar_org(gh, "acme", "Default")
        r = ciclo(cfg(), gh, dk, self.estado, 1.0)
        self.assertEqual(dk.iniciados, [])
        self.assertEqual(gh.jits, [])
        self.assertIn("públicos", r["erro"])

    def test_recusa_organizacao_que_roda_workflow_de_fork(self):
        gh, dk = GithubFalso(fork=True), DockerFalso()
        with self.assertRaises(RuntimeError):
            runners.validar_org(gh, "acme", "Default")
        r = ciclo(cfg(), gh, dk, self.estado, 1.0)
        self.assertEqual(dk.iniciados, [])
        self.assertIn("forks", r["erro"])

    def test_aceita_grupo_default_com_visibilidade_all(self):
        dk = DockerFalso()
        r = ciclo(cfg(), GithubFalso(visibilidade="all"), dk, self.estado, 1.0)
        self.assertEqual(len(dk.iniciados), 2)
        self.assertIsNone(r["erro"])

    def test_grupo_inexistente_nao_inicia_nada(self):
        dk = DockerFalso()
        r = ciclo(cfg(), GithubFalso(grupo_existe=False), dk, self.estado, 1.0)
        self.assertEqual(dk.iniciados, [])
        self.assertIn("acme", r["erro"])

    def test_api_caindo_nao_cria_container(self):
        dk = DockerFalso()
        r = ciclo(cfg(), GithubFalso(falha="falha de rede: x"), dk, self.estado, 1.0)
        self.assertEqual(dk.iniciados, [])
        self.assertTrue(r["erro"])

    def test_docker_falhando_nao_vaza_nem_derruba(self):
        gh = GithubFalso()
        r = ciclo(cfg(), gh, DockerFalso(falha=True), self.estado, 1.0)
        self.assertNotIn(JIT, json.dumps(r))
        self.assertEqual(r["runners"], 0)
        self.assertTrue(r["erro"])

    def test_limite_por_ciclo(self):
        dk = DockerFalso()
        r = ciclo(cfg(acme=10), GithubFalso(), dk, self.estado, 1.0)
        self.assertEqual(len(dk.iniciados), LIMITE_POR_CICLO)
        self.assertEqual(r["runners"], LIMITE_POR_CICLO)

    def test_limite_por_ciclo_vale_entre_organizacoes(self):
        dk = DockerFalso()
        r = ciclo(cfg(a=3, b=3), GithubFalso(), dk, self.estado, 1.0)
        self.assertEqual(len(dk.iniciados), LIMITE_POR_CICLO)
        self.assertEqual(r["orgs"]["b"]["ativos"], 1)

    def test_nomes_unicos(self):
        dk = DockerFalso()
        ciclo(cfg(acme=5), GithubFalso(), dk, self.estado, 1.0)
        self.assertEqual(len(set(dk.iniciados)), len(dk.iniciados))
        for n in dk.iniciados:
            self.assertRegex(n, r"^stack-acme-[0-9a-f]{8}$")

    def test_org_com_erro_nao_bloqueia_as_outras(self):
        class Misto(GithubFalso):
            def grupo(self, org, nome):
                if org == "ruim":
                    raise RuntimeError("HTTP 403: nope")
                return super().grupo(org, nome)
        dk = DockerFalso()
        r = ciclo(cfg(ruim=1, boa=1), Misto(), dk, self.estado, 1.0)
        self.assertEqual(len(dk.iniciados), 1)
        self.assertTrue(dk.iniciados[0].startswith("stack-boa-"))
        self.assertIn("ruim", r["erro"])

    def test_nao_chama_a_api_quando_nada_falta(self):
        gh = GithubFalso(falha="nao deveria chamar")
        r = ciclo(cfg(acme=2), gh, DockerFalso({"acme": 2}), self.estado, 1.0)
        self.assertIsNone(r["erro"])

    def test_estado_atomico_e_sem_token(self):
        gh = Github(TOKEN, get=lambda u, c: {"runner_groups": [{"id": 1, "name": "Default",
                                                                 "allows_public_repositories": False}],
                                             "run_workflows_from_fork_pull_requests": False},
                    post=lambda u, c, b: {"encoded_jit_config": JIT})
        r = ciclo(cfg(acme=1), gh, DockerFalso(), self.estado, 123.5)
        bruto = open(self.estado).read()
        self.assertNotIn(TOKEN, bruto)
        self.assertNotIn(JIT, bruto)
        self.assertEqual(json.loads(bruto), {"atualizado": 123.5, "runners": 1, "erro": None,
                                             "orgs": {"acme": {"ativos": 1, "esperados": 1}}})
        self.assertEqual(r["atualizado"], 123.5)
        self.assertEqual(os.listdir(self.dir.name), ["status.json"])
        if POSIX:
            self.assertEqual(stat.S_IMODE(os.stat(self.estado).st_mode), 0o644)

    def test_falha_ao_gravar_nao_deixa_tmp(self):
        with mock.patch("ci.runners.os.replace", side_effect=OSError("x")):
            with self.assertRaises(OSError):
                ciclo(cfg(), GithubFalso(), DockerFalso(), self.estado, 1.0)
        self.assertEqual(os.listdir(self.dir.name), [])


class Backoff(unittest.TestCase):
    def test_backoff_cresce_e_tem_teto(self):
        vistos = [espera_org(n) for n in range(1, 12)]
        self.assertEqual(vistos[:4], [60, 120, 240, 480])
        self.assertEqual(max(vistos), TETO_BACKOFF)
        self.assertEqual(vistos[-1], TETO_BACKOFF)


class Config(Base):
    def escrever(self, d):
        return self.caminho("config.json", json.dumps(d))

    def test_config_invalida_sai_com_2(self):
        ok = cfg()
        ruins = [{**ok, "cpus": "2 --privileged"}, {**ok, "memoria": "muito"}, {**ok, "imagem": "a b"},
                 {**ok, "imagem": "-v"}, {**ok, "extra": 1}, {**ok, "docker_socket": "sim"}, {**ok, "orgs": {}},
                 {**ok, "orgs": {"bad org": {"grupo": "Default", "quantidade": 1}}},
                 {**ok, "orgs": {"a": {"grupo": "Default", "quantidade": 11}}},
                 {**ok, "orgs": {"a": {"grupo": "Default", "quantidade": True}}},
                 {**ok, "orgs": {"a": {"grupo": "Default", "quantidade": -1}}},
                 {**ok, "orgs": {"a": {"grupo": "", "quantidade": 1}}},
                 {**ok, "orgs": {"a": {"grupo": "Default"}}},
                 {**ok, "cpus": "0"}, {**ok, "cpus": "."}, {**ok, "memoria": "0g"}, {**ok, "cpus": "1.2.3"},
                 {**ok, "orgs": {"Acme": {"grupo": "D", "quantidade": 1}, "acme": {"grupo": "D", "quantidade": 1}}},
                 {**ok, "docker_socket": True},
                 {**ok, "docker_socket": True, "docker_socket_ciente_do_risco": False}]
        token = self.caminho("token", TOKEN)
        for ruim in ruins:
            self.assertEqual(runners.main(["--config", self.escrever(ruim), "--token-file", token,
                                           "--status", self.estado, "--uma-vez"]), 2, ruim)
        self.assertEqual(runners.main(["--config", self.caminho("nao-existe"), "--token-file", token,
                                       "--status", self.estado, "--uma-vez"]), 2)

    def test_config_valida_e_padrao_do_socket(self):
        c = runners.carregar_config(self.escrever({k: v for k, v in cfg().items() if k != "docker_socket"}))
        self.assertIs(c["docker_socket"], False)

    def test_sem_override_por_ambiente(self):
        with mock.patch.dict(os.environ, {"CI_CONFIG": "/x", "CI_TOKEN": "/y", "STACK_TESTE": "1"}):
            self.assertEqual(runners.main(["--uma-vez", "--config", self.caminho("nada")]), 2)


@unittest.skipUnless(POSIX, "modos de arquivo exigem sistema POSIX")
class Token(Base):
    def test_token_valido(self):
        self.assertEqual(runners.ler_token(self.caminho("t", TOKEN + "\n", 0o400)), TOKEN)

    def test_token_com_permissao_aberta_e_recusado(self):
        for modo in (0o640, 0o604, 0o644):
            with self.assertRaises(ValueError) as c:
                runners.ler_token(self.caminho("t", TOKEN, modo))
            self.assertNotIn(TOKEN, str(c.exception))

    def test_token_symlink_recusado(self):
        alvo = self.caminho("alvo", TOKEN, 0o600)
        link = os.path.join(self.dir.name, "link")
        os.symlink(alvo, link)
        with self.assertRaises(ValueError):
            runners.ler_token(link)

    def test_token_de_outro_dono_ou_fora_do_formato(self):
        with mock.patch("ci.runners.os.geteuid", return_value=os.geteuid() + 1):
            with self.assertRaises(ValueError):
                runners.ler_token(self.caminho("t", TOKEN, 0o600))
        for conteudo in ("ghp_curto", "ghp_" + "é" * 30, "a" * 300, "a" * 5000):
            with self.assertRaises(ValueError, msg=conteudo[:10]):
                runners.ler_token(self.caminho("t2", conteudo, 0o600))

    def test_token_nao_regular_recusado(self):
        with self.assertRaises(ValueError):
            runners.ler_token(self.dir.name)

    def test_token_vazio_ou_com_espaco_recusado(self):
        for conteudo in ("", "  \n", "ghp abc", 'ghp"abc', "ghp\tabc", "ghp\x01abc"):
            with self.assertRaises(ValueError, msg=repr(conteudo)):
                runners.ler_token(self.caminho("t", conteudo, 0o600))

    def test_main_recusa_token_inseguro_sem_imprimir_o_segredo(self):
        saida = io.StringIO()
        with contextlib.redirect_stderr(saida):
            rc = runners.main(["--config", self.caminho("c.json", json.dumps(cfg())), "--status", self.estado,
                               "--token-file", self.caminho("t", TOKEN, 0o644), "--uma-vez"])
        self.assertEqual(rc, 2)
        self.assertNotIn(TOKEN, saida.getvalue())


class Endurecimento(Base):
    def gh_real(self, grupos_por_org):
        def get(url, cab):
            if "runner-groups" in url:
                org = url.split("/orgs/")[1].split("/")[0]
                return grupos_por_org[org]
            return {"run_workflows_from_fork_pull_requests": False}
        return Github(TOKEN, get=get, post=lambda u, c, b: {"encoded_jit_config": JIT})

    def test_resposta_sem_id_nao_derruba_as_outras_orgs(self):
        ok = {"runner_groups": [{"id": 1, "name": "Default", "allows_public_repositories": False}]}
        gh = self.gh_real({"ruim": {"runner_groups": [{"name": "Default"}]}, "boa": ok})
        dk = DockerFalso()
        r = ciclo(cfg(ruim=1, boa=1), gh, dk, self.estado, 1.0)
        self.assertEqual(len(dk.iniciados), 1)
        self.assertIn("ruim", r["erro"])
        self.assertEqual(json.load(open(self.estado))["orgs"]["boa"]["ativos"], 1)

    def test_runner_groups_null(self):
        gh = Github(TOKEN, get=lambda u, c: {"runner_groups": None})
        with self.assertRaises(RuntimeError):
            gh.grupo("acme", "Default")
        for ruim in ([1], [{"id": "1", "name": "x"}], [{"id": True, "name": "x"}], [{"id": 1, "name": None}]):
            with self.assertRaises(RuntimeError):
                Github(TOKEN, get=lambda u, c, r=ruim: {"runner_groups": r}).grupo("acme", "x")

    def test_corpo_json_nao_dict(self):
        with self.assertRaises(RuntimeError):
            Github(TOKEN, get=lambda u, c: []).permissoes_fork("acme")
        with self.assertRaises(RuntimeError):
            Github(TOKEN, get=lambda u, c: {"runners": "x"}).runners("acme")
        with self.assertRaises(RuntimeError):
            Github(TOKEN, post=lambda u, c, b: {"encoded_jit_config": 5}).jitconfig("acme", 1, "n", [])
        with mock.patch("ci.runners._abridor.open", return_value=io.BytesIO(b"[1]")):
            with self.assertRaises(RuntimeError):
                Github(TOKEN).permissoes_fork("acme")

    def test_saida_do_docker_nao_utf8(self):
        r = mock.Mock(returncode=0, stdout=b"\xff\xfeab\n", stderr=b"")
        with mock.patch("ci.runners.subprocess.run", return_value=r):
            self.assertEqual(Docker(ambiente={}).ativos("acme"), {"acme": 1})
        r = mock.Mock(returncode=1, stdout=b"", stderr=b"\xff\xfe erro")
        with mock.patch("ci.runners.subprocess.run", return_value=r):
            with self.assertRaises(RuntimeError):
                Docker(ambiente={}).ativos("acme")

    def test_status_json_atualizado_mesmo_com_erro_inesperado(self):
        class Quebra(GithubFalso):
            def grupo(self, org, nome):
                raise KeyError("id")
        r = ciclo(cfg(), Quebra(), DockerFalso(), self.estado, 55.0)
        d = json.load(open(self.estado))
        self.assertEqual(d["atualizado"], 55.0)
        self.assertIn("KeyError", d["erro"])
        self.assertEqual(r["erro"], d["erro"])

    def test_grupo_sem_campo_publico_e_recusado(self):
        class Gh:
            def grupo(self, org, nome):
                return {"id": 1}

            def permissoes_fork(self, org):
                return {"run_workflows_from_fork_pull_requests": False}
        with self.assertRaises(RuntimeError):
            runners.validar_org(Gh(), "acme", "Default")

    def test_permissoes_sem_campo_fork_e_recusado(self):
        class Gh:
            def grupo(self, org, nome):
                return {"id": 1, "allows_public_repositories": False}

            def permissoes_fork(self, org):
                return {}
        with self.assertRaises(RuntimeError):
            runners.validar_org(Gh(), "acme", "Default")

    def test_campos_com_tipo_errado_sao_recusados(self):
        for pub, fork in ((None, False), ("false", False), (0, False), (True, False),
                          (False, None), (False, "false"), (False, 0), (False, True)):
            class Gh:
                def grupo(self, org, nome, pub=pub):
                    return {"id": 1, "allows_public_repositories": pub}

                def permissoes_fork(self, org, fork=fork):
                    return {"run_workflows_from_fork_pull_requests": fork}
            with self.assertRaises(RuntimeError, msg=(pub, fork)):
                runners.validar_org(Gh(), "acme", "Default")

        class Ok:
            def grupo(self, org, nome):
                return {"id": 9, "allows_public_repositories": False}

            def permissoes_fork(self, org):
                return {"run_workflows_from_fork_pull_requests": False}
        self.assertEqual(runners.validar_org(Ok(), "acme", "Default"), 9)

    def test_org_recusada_nao_atrasa_as_outras_ao_longo_dos_ciclos(self):
        class Misto(GithubFalso):
            tentativas = 0

            def grupo(self, org, nome):
                if org == "ruim":
                    Misto.tentativas += 1
                    raise RuntimeError("HTTP 403: nope")
                return super().grupo(org, nome)
        gh, dk, mem = Misto(), DockerFalso({"boa": 9}), {}
        for t in range(0, 360, 30):
            dk._ativos["boa"] = 9
            antes = len(dk.iniciados)
            r = ciclo(cfg(ruim=1, boa=10), gh, dk, self.estado, float(t), memoria=mem)
            self.assertEqual(len(dk.iniciados), antes + 1, t)
            self.assertIn("ruim", r["erro"])
            self.assertNotIn("boa:", r["erro"])
        self.assertEqual(Misto.tentativas, 3)  # t = 0, 60, 180
        self.assertEqual(set(r["orgs"]), {"ruim", "boa"})

    def test_laco_de_reinicio_para_de_criar_jit_e_avisa(self):
        gh, dk, mem = GithubFalso(), DockerFalso(), {}
        erros = []
        for t in range(0, 600, 30):
            erros.append(ciclo(cfg(acme=1), gh, dk, self.estado, float(t), memoria=mem)["erro"])
        self.assertEqual(len(gh.jits), 7)
        self.assertTrue(any(e and "acme: runners reiniciando em laço (7 inícios em 10 min)" in e for e in erros))
        ciclo(cfg(acme=1), gh, dk, self.estado, 2000.0, memoria=mem)
        self.assertEqual(len(gh.jits), 8)

    def test_docker_socket_exige_ciencia_do_risco(self):
        base = {**cfg(), "docker_socket": True}
        with self.assertRaises(ValueError) as c:
            runners.carregar_config(self.caminho("c.json", json.dumps(base)))
        self.assertIn("token", str(c.exception))
        ok = runners.carregar_config(self.caminho("d.json", json.dumps({**base,
                                                                         "docker_socket_ciente_do_risco": True})))
        self.assertTrue(ok["docker_socket"])

    def test_docker_socket_avisa_alto(self):
        c = {**cfg(acme=1), "docker_socket": True, "docker_socket_ciente_do_risco": True}
        saida = io.StringIO()
        with mock.patch("ci.runners._novo_github", return_value=GithubFalso()), \
                mock.patch("ci.runners._novo_docker", return_value=DockerFalso()), \
                contextlib.redirect_stderr(saida):
            rc = runners.main(["--config", self.caminho("c.json", json.dumps(c)), "--status", self.estado,
                               "--token-file", self.caminho("t", TOKEN, 0o600), "--uma-vez"])
        self.assertEqual(rc, 0)
        self.assertEqual(saida.getvalue().count("WARNING"), 1)
        self.assertIn("token", saida.getvalue())
        self.assertNotIn(TOKEN, saida.getvalue())

    def test_cadeia_de_excecoes_nao_guarda_o_token(self):
        def get(url, cab):
            raise RuntimeError(f"HTTP 401: {TOKEN}")
        with self.assertRaises(RuntimeError) as c:
            Github(TOKEN, get=get).permissoes_fork("acme")
        e = c.exception
        while e is not None:
            self.assertNotIn(TOKEN, str(e))
            self.assertIsNone(e.__cause__)
            e = e.__context__

    def test_mensagem_da_api_e_sanitizada(self):
        corpo = io.BytesIO(json.dumps({"message": "x\n\x1b[31m" + "A" * 500}).encode())
        e = urllib.error.HTTPError("https://api.github.com/x", 500, "x", {}, corpo)
        with mock.patch("ci.runners._abridor.open", side_effect=e):
            with self.assertRaises(RuntimeError) as c:
                Github(TOKEN).runners("acme")
        m = str(c.exception)
        self.assertTrue(m.isprintable())
        self.assertLessEqual(len(m), 220)

    def test_redirecionamento_e_recusado(self):
        h = runners._SemRedirecionamento()
        with self.assertRaises(RuntimeError):
            h.redirect_request(mock.Mock(), None, 302, "Found", {}, "https://evil.example/")


class Main(Base):
    def rodar(self, gh, dk, extra=()):
        c = self.caminho("c.json", json.dumps(cfg(acme=1)))
        t = self.caminho("t", TOKEN, 0o600)
        with mock.patch("ci.runners._novo_github", return_value=gh), \
                mock.patch("ci.runners._novo_docker", return_value=dk), \
                mock.patch("ci.runners.INTERVALO", 0.01):
            return runners.main(["--config", c, "--token-file", t, "--status", self.estado, *extra])

    def test_uma_vez(self):
        dk = DockerFalso()
        self.assertEqual(self.rodar(GithubFalso(), dk, ["--uma-vez"]), 0)
        self.assertEqual(len(dk.iniciados), 1)
        self.assertEqual(self.rodar(GithubFalso(falha="HTTP 500: x"), DockerFalso(), ["--uma-vez"]), 1)

    @unittest.skipUnless(POSIX, "sinais POSIX")
    def test_sigterm_nao_para_containers(self):
        class Gh(GithubFalso):
            def grupo(self, org, nome):
                signal.raise_signal(signal.SIGTERM)
                return super().grupo(org, nome)
        dk = DockerFalso()
        anterior = signal.getsignal(signal.SIGTERM)
        self.assertEqual(self.rodar(Gh(), dk), 0)
        self.assertFalse(dk.parou)
        self.assertEqual(len(dk.iniciados), 1)  # o ciclo em curso terminou antes de sair
        self.assertIs(signal.getsignal(signal.SIGTERM), anterior)


if __name__ == "__main__":
    unittest.main()
