import base64, json, os, subprocess, tempfile, unittest
from datetime import datetime, timezone
from pmo.github import GitHub
from pmo.coleta import coletar, mapear_locais

AGORA = datetime(2026, 10, 6, 12, tzinfo=timezone.utc)


class Resp:
    def __init__(self, corpo, link=None, status=200):
        self._c = json.dumps(corpo).encode(); self.headers = {"Link": link} if link else {}; self.status = status
    def read(self): return self._c
    def __enter__(self): return self
    def __exit__(self, *a): pass


def falso(rotas):
    def abrir(req, timeout=None):
        url = req.full_url.replace("https://api.github.com", "")
        for chave, r in rotas.items():
            if url.startswith(chave):
                if isinstance(r, Exception): raise r
                return r
        import urllib.error
        raise urllib.error.HTTPError(req.full_url, 404, "nao achou", {}, None)
    return abrir


def repo(nome, dono="org1", pushed="2026-10-01T10:00:00Z", arquivado=False, issues=3, fork=False, privado=True):
    return {"name": nome, "full_name": f"{dono}/{nome}", "owner": {"login": dono}, "pushed_at": pushed,
            "archived": arquivado, "open_issues_count": issues, "fork": fork, "private": privado,
            "html_url": f"https://github.com/{dono}/{nome}", "default_branch": "main"}


class Coleta(unittest.TestCase):
    def rotas(self):
        state = base64.b64encode("**Tipo:** documento\n**Estágio:** em revisão\n**Próximo passo:** revisar\n".encode()).decode()
        return {
            "/user": Resp({"login": "eu"}),
            "/orgs/org1/repos?type=all&per_page=100&page=2": Resp([repo("b", arquivado=True)]),
            "/orgs/org1/repos?type=all&per_page=100": Resp([repo("a"), repo("garfo", fork=True)],
                link='<https://api.github.com/orgs/org1/repos?type=all&per_page=100&page=2>; rel="next"'),
            "/repos/org1/a/contents/STATE.md": Resp({"content": state}),
            "/repos/org1/a/pulls": Resp([{"number": 1}]),
            "/repos/org1/a/actions/runs": Resp({"workflow_runs": [{"conclusion": "failure"}]}),
            "/repos/org1/a/branches": Resp([{"name": "main"}, {"name": "wip/laptop-2026-10-06"}]),
            "/repos/org1/b/pulls": Resp([]),
            "/repos/org1/b/actions/runs": Resp({"workflow_runs": []}),
            "/repos/org1/b/branches": Resp([{"name": "main"}]),
        }

    def test_registros(self):
        gh = GitHub("t", abrir=falso(self.rotas()))
        regs = {r["id"]: r for r in coletar(gh, ["org1"], {"org1/a": "/srv/dev/projetos/ORM Carlos Eugenio"}, AGORA)}
        self.assertEqual(set(regs), {"org1/a", "org1/b"}, "fork fica de fora; pagina 2 entra")
        a = regs["org1/a"]
        self.assertEqual((a["tipo"], a["estagio"], a["proximo"]), ("documento", "em revisão", "revisar"))
        self.assertEqual((a["prs"], a["issues"], a["ci"]), (1, 2, "failure"))
        self.assertEqual(a["wip"], ["wip/laptop-2026-10-06"])
        self.assertEqual(a["dias"], 5)
        self.assertEqual(a["pasta"], "/srv/dev/projetos/ORM Carlos Eugenio")
        b = regs["org1/b"]
        self.assertTrue(b["arquivado"]); self.assertIsNone(b["esquecido"])
        self.assertIsNone(b["tipo"]); self.assertEqual(b["estagio_sugerido"], "encerrado")

    def test_sem_state_sugere(self):
        rotas = self.rotas(); rotas.pop("/repos/org1/a/contents/STATE.md")
        gh = GitHub("t", abrir=falso(rotas))
        a = {r["id"]: r for r in coletar(gh, ["org1"], {}, AGORA)}["org1/a"]
        self.assertIsNone(a["estagio"]); self.assertEqual(a["estagio_sugerido"], "em revisão")
        self.assertIsNone(a["pasta"])

    def test_falha_de_um_repo_reaproveita_o_anterior(self):
        import urllib.error
        rotas = self.rotas()
        rotas["/repos/org1/a/pulls"] = urllib.error.HTTPError("u", 403, "sso", {}, None)
        gh = GitHub("t", abrir=falso(rotas))
        anterior = {"projetos": [{"id": "org1/a", "nome": "a", "dias": 1}], "arquivados": []}
        regs = {r["id"]: r for r in coletar(gh, ["org1"], {}, AGORA, anterior)}
        self.assertEqual(set(regs), {"org1/a", "org1/b"}, "o b continua sendo coletado")
        self.assertEqual(regs["org1/a"]["dias"], 1, "o a fica com o registro anterior")

    def test_falha_de_repo_sem_anterior_fica_de_fora(self):
        rotas = self.rotas()
        rotas["/repos/org1/a/branches"] = OSError("timeout")
        gh = GitHub("t", abrir=falso(rotas))
        self.assertEqual([r["id"] for r in coletar(gh, ["org1"], {}, AGORA)], ["org1/b"])


class Locais(unittest.TestCase):
    def test_mapeia_origin(self):
        raiz = tempfile.mkdtemp()
        d = os.path.join(raiz, "bekaa", "ORM Carlos Eugenio")
        os.makedirs(d)
        subprocess.run(["git", "init", "-q", d], check=True)
        subprocess.run(["git", "-C", d, "remote", "add", "origin", "https://github.com/Bekaa-Trusted-Advisors/ORM-CarlosEugenio.git"], check=True)
        self.assertEqual(mapear_locais(raiz), {"bekaa-trusted-advisors/orm-carloseugenio": d})


if __name__ == "__main__":
    unittest.main()
