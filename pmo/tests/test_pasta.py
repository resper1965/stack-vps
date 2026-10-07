import io, os, tarfile, tempfile, unittest
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


if __name__ == "__main__":
    unittest.main()
