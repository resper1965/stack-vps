import fcntl, json, os, tempfile, unittest
from pmo.linear import (Linear, LoteGrande, desejado, escolher_status, planejar, sincronizar, verificar_lote)

STATUS = [{"id": "s1", "name": "Planejado", "type": "backlog"}, {"id": "s2", "name": "Em Revisao", "type": "started"},
          {"id": "s3", "name": "Pausado", "type": "paused"}, {"id": "s4", "name": "Cancelado", "type": "canceled"}]


class Falsa:
    def __init__(self, falha_na=None):
        self.chamadas, self.falha_na, self.n = [], falha_na, 0
        self.existentes, self.perde_resposta = set(), False

    def statuses(self):
        self.chamadas.append("statuses"); return STATUS

    def time(self, key):
        self.chamadas.append("time"); return "t1"

    def criar(self, nome, time_id, status_id, linear_id):
        self.n += 1
        self.ids = getattr(self, "ids", [])
        self.ids.append(linear_id)
        if getattr(self, "caminho", None) and not hasattr(self, "no_momento"):
            self.no_momento = ler(self.caminho)
        if linear_id in self.existentes:
            raise RuntimeError("id já existe")
        if self.n == self.falha_na:
            if self.perde_resposta:
                self.existentes.add(linear_id)
            raise RuntimeError("boom")
        self.existentes.add(linear_id)
        self.chamadas.append(("criar", nome)); return linear_id

    def atualizar(self, linear_id, status_id):
        self.chamadas.append(("atualizar", linear_id, status_id))


def ler(caminho):
    with open(caminho) as f:
        return json.load(f)


def painel(n=2):
    return {"projetos": [{"id": f"o/p{i}", "nome": f"p{i}", "estagio": "em andamento"} for i in range(n)],
            "arquivados": [], "a_destinar": [{"id": "destinar:x"}]}


class Status(unittest.TestCase):
    def test_status_por_nome_ignora_acento(self):
        self.assertEqual(escolher_status("em revisão", STATUS), "s2")

    def test_status_por_tipo(self):
        self.assertEqual(escolher_status("congelado", STATUS), "s3")

    def test_status_inexistente_levanta(self):
        with self.assertRaises(ValueError):
            escolher_status("entregue", STATUS)


class Planejar(unittest.TestCase):
    def test_desejado_arquivado_e_sugerido(self):
        p = {"projetos": [{"id": "o/a", "nome": "a", "estagio": None, "estagio_sugerido": "ideia"},
                          {"id": "o/b", "nome": "b"}, {"id": "o/c", "nome": "x", "estagio": "parado"},
                          {"id": "p/c", "nome": "x", "estagio": "parado"}],
             "arquivados": [{"id": "o/d", "nome": "d", "estagio": "parado"}], "a_destinar": [{"id": "destinar:z"}]}
        d = desejado(p)
        self.assertEqual(d["o/a"], ("a", "ideia"))
        self.assertEqual(d["o/b"], ("b", "em andamento"))
        self.assertEqual(d["o/c"], ("o/c", "parado"))  # nome repetido: cai no id completo
        self.assertEqual(d["o/d"], ("d", "arquivado"))
        self.assertNotIn("destinar:z", d)

    def test_planejar_cria_atualiza_e_ignora(self):
        d = {"o/n": ("n", "ideia"), "o/m": ("m", "parado"), "o/i": ("i", "ideia"),
             "o/a1": ("a1", "arquivado"), "o/a2": ("a2", "arquivado"), "o/a3": ("a3", "arquivado")}
        v = {"o/m": {"linear_id": "L1", "enviado": "ideia"}, "o/i": {"linear_id": "L2", "enviado": "ideia"},
             "o/a2": {"linear_id": "L3", "enviado": "parado"}, "o/a3": {"linear_id": "L4", "enviado": "arquivado"}}
        self.assertEqual(planejar(d, v), [
            {"op": "criar", "id": "o/n", "nome": "n", "estagio": "ideia"},
            {"op": "atualizar", "id": "o/m", "linear_id": "L1", "estagio": "parado"},
            {"op": "atualizar", "id": "o/a2", "linear_id": "L3", "estagio": "arquivado"}])

    def test_lote_grande_recusado_sem_confirmacao(self):
        ops = [{"op": "criar"}] * 21
        with self.assertRaises(LoteGrande):
            verificar_lote(ops, False)

    def test_lote_grande_com_confirmacao(self):
        verificar_lote([{"op": "criar"}] * 21, True)
        verificar_lote([{"op": "criar"}] * 20, False)


class Sincronizar(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.v, self.t = os.path.join(self.d, "linear.json"), os.path.join(self.d, "linear.lock")

    def roda(self, api, p, previa=False, lote=False):
        return sincronizar(api, p, self.v, self.t, previa, lote, "ABC")

    def test_previa_nao_chama_escrita(self):
        api = Falsa()
        ops = self.roda(api, painel(), previa=True)
        self.assertEqual(len(ops), 2)
        self.assertEqual([c for c in api.chamadas if isinstance(c, tuple)], [])
        self.assertFalse(os.path.exists(self.v))

    def test_cria_grava_e_nao_repete(self):
        api = Falsa()
        self.roda(api, painel())
        v = ler(self.v)
        self.assertEqual(v["o/p1"], {"linear_id": api.ids[1], "enviado": "em andamento"})
        api2 = Falsa()
        self.assertEqual(self.roda(api2, painel()), [])
        self.assertEqual(api2.chamadas, [])

    def test_falha_no_meio_guarda_progresso(self):
        with self.assertRaises(RuntimeError):
            self.roda(Falsa(falha_na=2), painel(3))
        v = ler(self.v)
        self.assertEqual(sorted(v), ["o/p0", "o/p1"])
        self.assertEqual(v["o/p0"]["enviado"], "em andamento")
        self.assertIsNone(v["o/p1"]["enviado"])

    def test_criar_perdido_nao_duplica(self):
        api = Falsa(falha_na=1); api.perde_resposta = True
        with self.assertRaises(RuntimeError):
            self.roda(api, painel(1))
        self.roda(api, painel(1))
        self.assertEqual(len(api.ids), 2)
        self.assertEqual(api.ids[0], api.ids[1])
        self.assertEqual(len(api.existentes), 1)
        self.assertEqual(ler(self.v)["o/p0"]["enviado"], "em andamento")

    def test_atualizar_quando_ja_existe(self):
        api = Falsa(falha_na=1); api.perde_resposta = True
        with self.assertRaises(RuntimeError):
            self.roda(api, painel(1))
        self.roda(api, painel(1))
        self.assertEqual([c[:2] for c in api.chamadas if c[0] == "atualizar"], [("atualizar", api.ids[0])])

    def test_criar_que_nunca_chegou_e_refeito(self):
        api = Falsa(falha_na=1)  # falha sem criar: segunda corrida cria de verdade com o mesmo id
        with self.assertRaises(RuntimeError):
            self.roda(api, painel(1))
        self.roda(api, painel(1))
        self.assertEqual(api.existentes, {api.ids[0]})
        self.assertEqual(api.ids[0], api.ids[1])

    def test_vinculo_pendente_grava_antes_da_chamada(self):
        api = Falsa(); api.caminho = self.v
        self.roda(api, painel(1))
        self.assertEqual(api.no_momento, {"o/p0": {"linear_id": api.ids[0], "enviado": None}})

    def test_previa_nao_grava_id(self):
        self.roda(Falsa(), painel(), previa=True)
        self.assertFalse(os.path.exists(self.v))

    def test_pendente_na_previa_aparece_como_criar_e_conta_no_lote(self):
        with open(self.v, "w") as f:
            json.dump({"o/p0": {"linear_id": "U", "enviado": None}}, f)
        ops = self.roda(Falsa(), painel(1), previa=True)
        self.assertEqual([(o["op"], o["linear_id"]) for o in ops], [("criar", "U")])
        with self.assertRaises(LoteGrande):
            verificar_lote(ops * 21, False)

    def test_segunda_corrida_com_trava_nao_faz_nada(self):
        fd = os.open(self.t, os.O_CREAT | os.O_RDWR)
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            api = Falsa()
            self.assertEqual(self.roda(api, painel()), [])
            self.assertEqual(api.chamadas, [])
        finally:
            os.close(fd)


class Cliente(unittest.TestCase):
    def test_erro_da_api_sem_token_na_mensagem(self):
        def post(url, headers, corpo):
            raise RuntimeError(f"HTTP 401 {headers['Authorization']}")
        with self.assertRaises(RuntimeError) as c:
            Linear("lin_api_SEGREDO", post).statuses()
        self.assertNotIn("SEGREDO", str(c.exception))

    def test_errors_no_json_vira_runtimeerror(self):
        with self.assertRaises(RuntimeError):
            Linear("t", lambda u, h, c: {"errors": [{"message": "ruim"}]}).statuses()

    def test_cabecalho_sem_bearer_e_operacoes(self):
        vistos = []

        def post(url, headers, corpo):
            vistos.append((url, headers, corpo))
            return {"data": {"projectCreate": {"project": {"id": "P"}}, "teams": {"nodes": [{"id": "T"}]},
                             "projectStatuses": {"nodes": STATUS}}}
        api = Linear("tok", post)
        self.assertEqual(api.criar("n", "T", "s1", "U"), "P")
        self.assertEqual(api.time("K"), "T")
        self.assertEqual(api.statuses(), STATUS)
        self.assertEqual(vistos[0][0], "https://api.linear.app/graphql")
        self.assertEqual(vistos[0][1]["Authorization"], "tok")
        self.assertEqual(vistos[0][2]["variables"], {"i": "U", "n": "n", "t": "T", "s": "s1"})
