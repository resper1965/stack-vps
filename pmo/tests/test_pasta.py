import io, json, os, subprocess, tarfile, tempfile, unittest
from pmo.pasta import Recusado, executar


class Pasta(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.proj = os.path.join(self.t, "projetos"); self.lap = os.path.join(self.t, "laptop")
        self.p = os.path.join(self.proj, "apps", "orm")
        os.makedirs(self.p); os.makedirs(os.path.join(self.lap, "DESENVOLVIMENTO", "velha"))
        open(os.path.join(self.p, "a.txt"), "w").write("x")

    def rodar(self, *args, entrada=None, saida=None):
        return executar(list(args), entrada, saida, raizes=(self.proj, self.lap))

    def test_compactar_remover_extrair(self):
        tgz = io.BytesIO()
        self.rodar("compactar", self.p, saida=tgz)
        self.rodar("remover", self.p)
        self.assertFalse(os.path.exists(self.p))
        tgz.seek(0)
        self.rodar("extrair", self.proj, entrada=tgz)
        self.assertEqual(open(os.path.join(self.p, "a.txt")).read(), "x")

    def test_recusa_raiz_e_raso(self):
        for alvo in (self.proj, self.lap, os.path.join(self.lap, "."), os.path.join(self.proj, "apps"),
                     os.path.join(self.lap, "DESENVOLVIMENTO"), os.path.join(self.proj, "..", "x", "y"), "/etc/ssh"):
            with self.subTest(alvo=alvo), self.assertRaises(Recusado):
                self.rodar("remover", alvo)
        self.assertTrue(os.path.isdir(os.path.join(self.lap, "DESENVOLVIMENTO")))

    def test_atalho_para_fora_recusado(self):
        fora = os.path.join(self.t, "fora", "dados"); os.makedirs(fora)
        os.symlink(os.path.join(self.t, "fora"), os.path.join(self.proj, "atalho"))
        with self.assertRaises(Recusado):
            self.rodar("remover", os.path.join(self.proj, "atalho", "dados"))
        self.assertTrue(os.path.isdir(fora))

    def test_extrair_recusa_caminho_e_atalho_para_fora(self):
        for nome, tipo in (("../fora.txt", tarfile.REGTYPE), ("apps/link", tarfile.SYMTYPE)):
            with self.subTest(nome=nome):
                tgz = io.BytesIO()
                with tarfile.open(fileobj=tgz, mode="w:gz") as t:
                    m = tarfile.TarInfo(nome); m.type = tipo
                    if tipo == tarfile.SYMTYPE:
                        m.linkname = "/etc"
                    t.addfile(m, io.BytesIO(b""))
                tgz.seek(0)
                with self.assertRaises(Exception):
                    self.rodar("extrair", self.proj, entrada=tgz)
                self.assertFalse(os.path.exists(os.path.join(self.t, "fora.txt")))
                self.assertFalse(os.path.islink(os.path.join(self.proj, "apps", "link")))

    def test_extrair_so_em_raiz_conhecida(self):
        with self.assertRaises(Recusado):
            self.rodar("extrair", self.t, entrada=io.BytesIO())

    def test_comando_desconhecido(self):
        with self.assertRaises(Recusado):
            self.rodar("rm", self.p)


class Clonar(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.proj = os.path.join(self.t, "projetos"); os.makedirs(self.proj)
        # "GitHub" local: base/<dono>/<repo>.git
        self.base = os.path.join(self.t, "gh") + "/"
        origem = os.path.join(self.t, "origem")
        subprocess.run(["git", "init", "-q", "-b", "main", origem], check=True)
        open(os.path.join(origem, "a.txt"), "w").write("x")
        subprocess.run(["git", "-C", origem, "add", "."], check=True)
        subprocess.run(["git", "-C", origem, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "a"], check=True)
        subprocess.run(["git", "clone", "-q", "--bare", origem, os.path.join(self.base, "org", "repo.git")], check=True)

    def rodar(self, *args):
        return executar(list(args), raizes=(self.proj,), base_git=self.base)

    def test_clona(self):
        destino = os.path.join(self.proj, "ness", "repo")
        self.assertTrue(self.rodar("clonar", "org/repo", destino).startswith("OK"))
        self.assertEqual(open(os.path.join(destino, "a.txt")).read(), "x")

    def test_recusas(self):
        os.makedirs(os.path.join(self.proj, "ness", "existe"))
        for alvo, destino in (("org/repo", os.path.join(self.proj, "ness", "existe")),
                              ("org/repo", os.path.join(self.proj, "raso")),
                              ("org/repo", os.path.join(self.proj, "a", "b", "fundo")),
                              ("org/repo", os.path.join(self.t, "fora", "repo")),
                              ("org/../x", os.path.join(self.proj, "ness", "x")),
                              ("--upload-pack=x/y", os.path.join(self.proj, "ness", "y"))):
            with self.subTest(alvo=alvo, destino=destino), self.assertRaises(Recusado):
                self.rodar("clonar", alvo, destino)


class Verticais(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.proj = os.path.join(self.t, "projetos"); self.v = os.path.join(self.t, "verticais")
        for d in ("ionic-health/ihOS", "ness/n360", "ness/outro"):
            os.makedirs(os.path.join(self.proj, d))

    def rodar(self, mapa):
        return executar(["verticais", "-"], io.BytesIO(json.dumps(mapa).encode()), raizes=(self.proj,), verticais=self.v)

    def test_monta_e_refaz(self):
        p = lambda d: os.path.join(self.proj, d)
        self.rodar([{"empresa": "ionic", "area": "saude", "pasta": p("ionic-health/ihOS")},
                    {"empresa": "ness", "area": None, "pasta": p("ness/n360")}])
        self.assertEqual(os.readlink(os.path.join(self.v, "ionic", "saude", "ihOS")), p("ionic-health/ihOS"))
        self.assertTrue(os.path.islink(os.path.join(self.v, "ness", "geral", "n360")))
        self.rodar([{"empresa": "ness", "area": "geral", "pasta": p("ness/outro")}])
        self.assertFalse(os.path.exists(os.path.join(self.v, "ionic")), "atalho antigo sai")
        self.assertTrue(os.path.islink(os.path.join(self.v, "ness", "geral", "outro")))

    def test_ignora_item_invalido(self):
        self.rodar([{"empresa": "../x", "area": "a", "pasta": os.path.join(self.proj, "ness/n360")},
                    {"empresa": "ness", "area": "../../etc", "pasta": os.path.join(self.proj, "ness/n360")},
                    {"empresa": "ness", "area": "a", "pasta": "/etc/ssh"},
                    {"empresa": "ness", "area": "a", "pasta": os.path.join(self.proj, "ness/outro")}])
        self.assertEqual(sorted(os.listdir(self.v)), ["ness"])
        self.assertEqual(os.listdir(os.path.join(self.v, "ness", "a")), ["outro"])


if __name__ == "__main__":
    unittest.main()
