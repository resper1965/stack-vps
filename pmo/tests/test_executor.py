import json, os, subprocess, tempfile, time, unittest
from datetime import datetime, timezone
from pmo.executor import processar, aplicar_ajustes
from pmo import pasta

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
        self.ajustes = os.path.join(self.t, "ajustes.json"); self.log = os.path.join(self.t, "acoes.log")
        for d in (self.proj, self.lap, self.arq, self.fila): os.makedirs(d)
        self.pasta = os.path.join(self.proj, "bekaa", "ORM Carlos Eugênio")
        self.clone(self.pasta, "org/orm")
        os.makedirs(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha"))
        open(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha", "b.md"), "w").write("y")
        self.painel = {"gerado_em": "2026-10-06T09:00:00+00:00",
                       "projetos": [{"id": "org/orm", "arquivado": False}, {"id": "nessenergy/cliente", "arquivado": False}],
                       "arquivados": [], "a_destinar": [{"id": "destinar:DESENVOLVIMENTO/pasta velha"}]}
        self.gh = GhFalso(); self.trazidos = []

    def clone(self, onde, alvo):
        os.makedirs(onde)
        subprocess.run(["git", "init", "-q", onde], check=True)
        subprocess.run(["git", "-C", onde, "remote", "add", "origin", f"https://github.com/{alvo}.git"], check=True)
        open(os.path.join(onde, "a.txt"), "w").write(alvo)

    def pedir(self, acao, alvo, conf=None, quando=None):
        n = f"{int((quando or time.time()) * 1000)}-{acao}-{len(os.listdir(self.fila))}.json"
        json.dump({"acao": acao, "alvo": alvo, "confirmacao": conf, "pedido_em": quando or time.time()},
                  open(os.path.join(self.fila, n), "w"))

    def _pasta(self, *args, entrada=None, saida=None):
        if args[0] == "trazer":
            self.trazidos.append(args[1]); return "OK: trazido"
        return pasta.executar(list(args), entrada, saida, raizes=(self.proj, self.lap))

    def rodar(self):
        processar(self.fila, self.gh, self.proj, self.lap, self.arq, self.log, self.ajustes, AGORA,
                  donos={"org", "nessenergy"}, pasta=self._pasta)

    def painel_atual(self):
        return aplicar_ajustes(json.loads(json.dumps(self.painel)), json.load(open(self.ajustes)))

    def log_txt(self): return open(self.log, encoding="utf-8").read()

    def test_arquivar_e_restaurar(self):
        self.pedir("arquivar", "org/orm"); self.rodar()
        self.assertIn(("arquivar", "org", "orm", True), self.gh.chamadas)
        self.assertFalse(os.path.exists(self.pasta))
        self.assertEqual(len([f for f in os.listdir(self.arq) if f.endswith(".tar.gz")]), 1)
        self.assertEqual([x["id"] for x in self.painel_atual()["arquivados"]], ["org/orm"])
        self.pedir("restaurar", "org/orm"); self.rodar()
        self.assertIn(("arquivar", "org", "orm", False), self.gh.chamadas)
        self.assertEqual(open(os.path.join(self.pasta, "a.txt")).read(), "org/orm")
        self.assertIn("org/orm", [x["id"] for x in self.painel_atual()["projetos"]])

    def test_restaurar_nao_pega_copia_de_nome_parecido(self):
        outro = os.path.join(self.proj, "bekaa", "orm-bar"); self.clone(outro, "org/orm-bar")
        self.painel["projetos"].append({"id": "org/orm-bar"})
        self.pedir("arquivar", "org/orm"); self.rodar()
        self.pedir("arquivar", "org/orm-bar", quando=time.time() + 1); self.rodar()
        self.pedir("restaurar", "org/orm", quando=time.time() + 2); self.rodar()
        self.assertTrue(os.path.exists(self.pasta))
        self.assertFalse(os.path.exists(outro), "a copia do orm-bar nao pode voltar no lugar do orm")

    def test_excluir_exige_nome(self):
        self.pedir("excluir", "org/orm", "errado"); self.rodar()
        self.assertNotIn(("excluir", "org", "orm"), self.gh.chamadas)
        self.assertTrue(os.path.exists(self.pasta))
        self.assertIn("recusado", self.log_txt())

    def test_excluir_certo(self):
        self.pedir("excluir", "org/orm", "orm"); self.rodar()
        self.assertIn(("excluir", "org", "orm"), self.gh.chamadas)
        self.assertFalse(os.path.exists(self.pasta))
        self.assertEqual(len(os.listdir(os.path.join(self.arq, "excluidos"))), 1)
        self.assertNotIn("org/orm", [x["id"] for x in self.painel_atual()["projetos"]])

    def test_cliente_nunca_exclui(self):
        self.pedir("excluir", "nessenergy/cliente", "cliente"); self.rodar()
        self.assertEqual(self.gh.chamadas, [])
        self.assertIn("recusado", self.log_txt())

    def test_dono_fora_da_lista_recusado(self):
        self.pedir("excluir", "estranho/repo", "repo"); self.pedir("arquivar", "estranho/outro"); self.rodar()
        self.assertEqual(self.gh.chamadas, [])
        self.assertEqual(self.log_txt().count("recusado"), 2)

    def test_quebra_de_linha_no_alvo_nao_injeta_no_log(self):
        self.pedir("arquivar", "org/orm\nssh-ed25519 AAAA atacante\n"); self.rodar()
        self.assertEqual(self.gh.chamadas, [])
        linhas = self.log_txt().splitlines()
        self.assertEqual(len(linhas), 1)
        self.assertFalse(any(l.startswith("ssh-ed25519") for l in linhas))

    def test_pedido_por_atalho_ignorado(self):
        fora = os.path.join(self.t, "pedido.json")
        json.dump({"acao": "arquivar", "alvo": "org/orm", "pedido_em": time.time()}, open(fora, "w"))
        os.symlink(fora, os.path.join(self.fila, "1-x.json")); self.rodar()
        self.assertEqual(self.gh.chamadas, [])

    def test_duplicado_uma_vez(self):
        agora = time.time()
        self.pedir("arquivar", "org/orm", quando=agora); self.pedir("arquivar", "org/orm", quando=agora + 1); self.rodar()
        self.assertEqual(self.gh.chamadas.count(("arquivar", "org", "orm", True)), 1)

    def test_descartar_e_trazer_a_destinar(self):
        self.pedir("trazer", "destinar:DESENVOLVIMENTO/pasta velha"); self.rodar()
        self.assertEqual(self.trazidos, [os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha")])
        self.pedir("descartar", "destinar:DESENVOLVIMENTO/pasta velha"); self.rodar()
        self.assertFalse(os.path.exists(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha")))
        self.assertEqual(len(os.listdir(os.path.join(self.arq, "excluidos"))), 1, "descarte vai para a lixeira")
        self.assertEqual(self.painel_atual()["a_destinar"], [])

    def test_destinar_raiz_ou_fora_recusado(self):
        for alvo in ("destinar:../projetos", "destinar:", "destinar:.", "destinar:DESENVOLVIMENTO",
                     "destinar:DESENVOLVIMENTO/..", "destinar:./DESENVOLVIMENTO"):
            self.pedir("descartar", alvo)
        self.rodar()
        self.assertTrue(os.path.isdir(os.path.join(self.lap, "DESENVOLVIMENTO", "pasta velha")))
        self.assertTrue(os.path.exists(self.proj))
        self.assertEqual(self.log_txt().count("recusado"), 6)

    def test_reanalisar_nao_existe_mais(self):
        self.pedir("reanalisar", "org/orm"); self.rodar()
        self.assertIn("recusado", self.log_txt())

    def test_limpeza_30_dias(self):
        lix = os.path.join(self.arq, "excluidos"); os.makedirs(lix)
        for n, quando in (("velho.tar.gz", AGORA.timestamp() - 31 * 86400), ("novo.tar.gz", AGORA.timestamp())):
            open(os.path.join(lix, n), "w").close(); os.utime(os.path.join(lix, n), (quando, quando))
        self.rodar()
        self.assertEqual(os.listdir(lix), ["novo.tar.gz"])


class Ajustes(unittest.TestCase):
    def test_coleta_mais_nova_que_a_acao_prevalece(self):
        painel = {"gerado_em": "2026-10-07T09:00:00+00:00", "projetos": [{"id": "o/a"}], "arquivados": [], "a_destinar": []}
        ajustes = {"o/a": {"de": "projetos", "para": "arquivados", "em": "2026-10-06T12:00:00+00:00"}}
        self.assertEqual([x["id"] for x in aplicar_ajustes(painel, ajustes)["projetos"]], ["o/a"])


if __name__ == "__main__":
    unittest.main()
