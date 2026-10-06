import json, os, subprocess, tempfile, time, unittest
from datetime import datetime, timezone
from pmo.executor import processar

AGORA = datetime(2026, 10, 6, 12, tzinfo=timezone.utc)


class GhFalso:
    def __init__(self): self.chamadas = []
    def arquivar(self, d, r, valor=True): self.chamadas.append(("arquivar", d, r, valor))
    def excluir(self, d, r): self.chamadas.append(("excluir", d, r))


class Executor(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.mkdtemp()
        self.proj = os.path.join(self.t, "projetos"); self.lap = os.path.join(self.t, "laptop")
        self.arq = os.path.join(self.t, "arquivo"); self.fila = os.path.join(self.t, "fila")
        self.painel = os.path.join(self.t, "painel.json"); self.log = os.path.join(self.t, "acoes.log")
        for d in (self.proj, self.lap, self.arq, self.fila): os.makedirs(d)
        self.pasta = os.path.join(self.proj, "bekaa", "ORM Carlos Eugênio")
        os.makedirs(self.pasta)
        subprocess.run(["git", "init", "-q", self.pasta], check=True)
        subprocess.run(["git", "-C", self.pasta, "remote", "add", "origin", "https://github.com/org/orm.git"], check=True)
        open(os.path.join(self.pasta, "a.txt"), "w").write("x")
        os.makedirs(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha"))
        open(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha", "b.md"), "w").write("y")
        json.dump({"projetos": [{"id": "org/orm", "arquivado": False}, {"id": "nessenergy/cliente", "arquivado": False}],
                   "arquivados": [], "a_destinar": [{"id": "destinar:DESENVOLVIMENTO/pasta velha"}]}, open(self.painel, "w"))
        self.gh = GhFalso(); self.trazidos = []

    def pedir(self, acao, alvo, conf=None, quando=None):
        n = f"{int((quando or time.time()) * 1000)}-{acao}-{len(os.listdir(self.fila))}.json"
        json.dump({"acao": acao, "alvo": alvo, "confirmacao": conf, "pedido_em": quando or time.time()}, open(os.path.join(self.fila, n), "w"))

    def rodar(self):
        return processar(self.fila, self.gh, self.proj, self.lap, self.arq, self.log, self.painel, AGORA,
                         trazer=lambda p: (self.trazidos.append(p), "OK")[1])

    def painel_json(self): return json.load(open(self.painel))

    def test_arquivar_e_restaurar(self):
        self.pedir("arquivar", "org/orm"); self.rodar()
        self.assertIn(("arquivar", "org", "orm", True), self.gh.chamadas)
        self.assertFalse(os.path.exists(self.pasta))
        self.assertEqual(len([f for f in os.listdir(self.arq) if f.endswith(".tar.gz")]), 1)
        self.assertEqual([x["id"] for x in self.painel_json()["arquivados"]], ["org/orm"])
        self.pedir("restaurar", "org/orm"); self.rodar()
        self.assertIn(("arquivar", "org", "orm", False), self.gh.chamadas)
        self.assertEqual(open(os.path.join(self.pasta, "a.txt")).read(), "x")
        self.assertIn("org/orm", [x["id"] for x in self.painel_json()["projetos"]])

    def test_excluir_exige_nome(self):
        self.pedir("excluir", "org/orm", "errado"); self.rodar()
        self.assertNotIn(("excluir", "org", "orm"), self.gh.chamadas)
        self.assertTrue(os.path.exists(self.pasta))
        self.assertIn("recusado", open(self.log).read())

    def test_excluir_certo(self):
        self.pedir("excluir", "org/orm", "orm"); self.rodar()
        self.assertIn(("excluir", "org", "orm"), self.gh.chamadas)
        self.assertFalse(os.path.exists(self.pasta))
        self.assertEqual(len(os.listdir(os.path.join(self.arq, "excluidos"))), 1)
        self.assertNotIn("org/orm", [x["id"] for x in self.painel_json()["projetos"]])

    def test_cliente_nunca_exclui(self):
        self.pedir("excluir", "nessenergy/cliente", "cliente"); self.rodar()
        self.assertEqual(self.gh.chamadas, [])
        self.assertIn("recusado", open(self.log).read())

    def test_duplicado_uma_vez(self):
        agora = time.time()
        self.pedir("arquivar", "org/orm", quando=agora); self.pedir("arquivar", "org/orm", quando=agora + 1); self.rodar()
        self.assertEqual(self.gh.chamadas.count(("arquivar", "org", "orm", True)), 1)

    def test_descartar_e_trazer_a_destinar(self):
        self.pedir("trazer", "destinar:DESENVOLVIMENTO/pasta velha"); self.rodar()
        self.assertEqual(self.trazidos, [os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha")])
        self.pedir("descartar", "destinar:DESENVOLVIMENTO/pasta velha"); self.rodar()
        self.assertFalse(os.path.exists(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha")))
        self.assertEqual(self.painel_json()["a_destinar"], [])

    def test_destinar_fora_da_raiz_recusado(self):
        self.pedir("descartar", "destinar:../projetos"); self.rodar()
        self.assertTrue(os.path.exists(self.proj))
        self.assertIn("recusado", open(self.log).read())

    def test_limpeza_30_dias(self):
        lix = os.path.join(self.arq, "excluidos"); os.makedirs(os.path.join(lix, "velho")); os.makedirs(os.path.join(lix, "novo"))
        antigo = AGORA.timestamp() - 31 * 86400; os.utime(os.path.join(lix, "velho"), (antigo, antigo))
        os.utime(os.path.join(lix, "novo"), (AGORA.timestamp(), AGORA.timestamp()))
        self.rodar()
        self.assertEqual(os.listdir(lix), ["novo"])


if __name__ == "__main__":
    unittest.main()
