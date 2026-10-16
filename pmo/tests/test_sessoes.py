import json, os, tempfile, unittest
from datetime import datetime, timezone
from pmo.sessoes import ColetaFalhada, coletar, gravar, listar, rodar

AGORA = datetime(2026, 10, 16, 12, tzinfo=timezone.utc)
PAGINA = "/api/session?limit=100"
LOCAIS = {"bekaa/a": "/srv/dev/projetos/bekaa/a", "org2/b": "/srv/dev/projetos/org2/b"}


def sessao(id="ses_1", diretorio="/srv/dev/projetos/bekaa/a/scripts", titulo="t", outcome="succeeded",
           criada=1, atualizada=50, agent="build", location=None):
    # model/cost/tokens/title vêm na resposta real e NÃO podem chegar ao sessoes.json
    return {"id": id, "projectID": "p", "agent": agent, "model": {"id": "m", "providerID": "p"}, "cost": 0.5,
            "tokens": {"input": 1}, "outcome": outcome, "time": {"created": criada, "updated": atualizada},
            "title": titulo, "location": location if location is not None else {"directory": diretorio}}


def falso(paginas):
    def api(caminho):
        if caminho in paginas:
            return paginas[caminho]
        raise ColetaFalhada("sem rota: " + caminho)
    return api


def resposta(data, proximo=None):
    return {"data": data, "cursor": {"next": proximo}}


class Sessoes(unittest.TestCase):
    def test_contrato_minimo(self):
        d = coletar(falso({PAGINA: resposta([sessao()])}), LOCAIS, AGORA)
        (m,) = d["sessoes"]
        self.assertEqual(set(m), {"id", "agent", "outcome", "criada", "atualizada", "projeto"},
                         "título, caminho absoluto, modelo, custo e transcrição ficam de fora")
        self.assertEqual(m["projeto"], "bekaa/a", "subpasta cai no clone")
        self.assertEqual(d["contadores"], {"sessoes": 1, "com_projeto": 1})
        self.assertFalse(d["coleta_incompleta"])

    def test_tipos_rigidos(self):
        d = coletar(falso({PAGINA: resposta([sessao(id=5)])}), LOCAIS, AGORA)
        self.assertEqual(d["sessoes"], [], "id de tipo errado fica de fora")
        self.assertTrue(d["coleta_incompleta"])
        s = sessao(id="ses_2", agent=7, criada="ontem", atualizada=True, location={"directory": 9})
        d = coletar(falso({PAGINA: resposta([s])}), LOCAIS, AGORA)
        m = d["sessoes"][0]
        self.assertIsNone(m["agent"]); self.assertIsNone(m["criada"])
        self.assertIsNone(m["atualizada"], "bool não vale como int")
        self.assertIsNone(m["projeto"], "diretório de tipo errado não associa")
        self.assertTrue(d["coleta_incompleta"], "campo presente com tipo errado marca incompleta")

    def test_id_vazio_fica_de_fora(self):
        d = coletar(falso({PAGINA: resposta([sessao(id="")])}), LOCAIS, AGORA)
        self.assertEqual(d["sessoes"], [])
        self.assertTrue(d["coleta_incompleta"])

    def test_fora_da_raiz_e_na_raiz(self):
        d = coletar(falso({PAGINA: resposta([sessao(id="ses_x", location={"directory": "/home/agente"}),
                                             sessao(id="ses_r", location={"directory": "/srv/dev/projetos"})])}),
                    LOCAIS, AGORA)
        proj = {m["id"]: m["projeto"] for m in d["sessoes"]}
        self.assertEqual(proj, {"ses_x": None, "ses_r": None}, "raiz e /home não são clones")
        self.assertEqual(d["contadores"]["com_projeto"], 0)
        self.assertFalse(d["coleta_incompleta"])

    def test_traversal_nao_associa(self):
        d = coletar(falso({PAGINA: resposta([sessao(location={"directory": "/srv/dev/projetos/../../srv/dev/secrets"})])}),
                    LOCAIS, AGORA)
        m = d["sessoes"][0]
        self.assertIsNone(m["projeto"], "fora da raiz não vira projeto")
        self.assertNotIn("diretorio", m, "o caminho entra e sai: só vira projeto")

    def test_item_invalido_marca_incompleta(self):
        d = coletar(falso({PAGINA: resposta([sessao(), {"lixo": 1}, "texto"])}), LOCAIS, AGORA)
        self.assertEqual([m["id"] for m in d["sessoes"]], ["ses_1"])
        self.assertTrue(d["coleta_incompleta"])

    def test_mais_recente_primeiro(self):
        d = coletar(falso({PAGINA: resposta([sessao(id="ses_a", atualizada=5), sessao(id="ses_b", atualizada=60)])}),
                    LOCAIS, AGORA)
        self.assertEqual([m["id"] for m in d["sessoes"]], ["ses_b", "ses_a"])


class Paginacao(unittest.TestCase):
    def test_pagina_por_cursor(self):
        paginas = {PAGINA: resposta([sessao()], "eyJ"),
                   f"{PAGINA}&cursor=eyJ": resposta([])}
        itens, incompleta = listar(falso(paginas))
        self.assertEqual([m["id"] for m in itens], ["ses_1"])
        self.assertFalse(incompleta)

    def test_cursor_repetido_termina_em_incompleta(self):
        paginas = {PAGINA: resposta([sessao(id="ses_1")], "eyJ"),
                   f"{PAGINA}&cursor=eyJ": resposta([sessao(id="ses_2")], "eyJ")}
        itens, incompleta = listar(falso(paginas))
        self.assertEqual([m["id"] for m in itens], ["ses_1", "ses_2"], "o loop termina")
        self.assertTrue(incompleta)

    def test_sessao_duplicada_fica_de_fora(self):
        paginas = {PAGINA: resposta([sessao(), sessao(id="ses_1", diretorio="/srv/dev/projetos/org2/b")])}
        itens, incompleta = listar(falso(paginas))
        self.assertEqual([m["id"] for m in itens], ["ses_1"])
        self.assertTrue(incompleta)

    def test_limite_de_paginas_marca_incompleta(self):
        paginas = {PAGINA: resposta([sessao(id="ses_1")], "A"),
                   f"{PAGINA}&cursor=A": resposta([sessao(id="ses_2")], "B"),
                   f"{PAGINA}&cursor=B": resposta([sessao(id="ses_3")], "C")}
        itens, incompleta = listar(falso(paginas), max_paginas=2)
        self.assertEqual([m["id"] for m in itens], ["ses_1", "ses_2"])
        self.assertTrue(incompleta)

    def test_falha_no_meio_devolve_parcial(self):
        itens, incompleta = listar(falso({PAGINA: resposta([sessao()], "eyJ")}))
        self.assertEqual([m["id"] for m in itens], ["ses_1"], "a 2a página sem rota não perde a 1a")
        self.assertTrue(incompleta)

    def test_falha_na_primeira_levanta(self):
        with self.assertRaises(ColetaFalhada):
            listar(falso({}))

    def test_falha_sem_item_valido_levanta(self):
        with self.assertRaises(ColetaFalhada):
            listar(falso({PAGINA: resposta([{"lixo": 1}], "eyJ")}))

    def test_cursor_de_tipo_errado_marca_incompleta(self):
        itens, incompleta = listar(falso({PAGINA: {"data": [sessao()], "cursor": "lixo"}}))
        self.assertEqual(len(itens), 1)
        self.assertTrue(incompleta)


class Gravar(unittest.TestCase):
    def test_atomica_0600(self):
        pasta = tempfile.mkdtemp()
        caminho = os.path.join(pasta, "sessoes.json")
        gravar({"gerado_em": AGORA.isoformat(), "sessoes": []}, caminho)
        with open(caminho, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["sessoes"], [])
        self.assertEqual(os.listdir(pasta), ["sessoes.json"], "tmp some no replace")
        self.assertEqual(os.stat(caminho).st_mode & 0o777, 0o600)


class Rodar(unittest.TestCase):
    def test_indisponivel_preserva_anterior(self):
        saida = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        gravar({"sessoes": ["anterior"]}, saida)
        rodar(falso({}), LOCAIS, AGORA, saida)
        with open(saida, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["sessoes"], ["anterior"])

    def test_incompleta_preserva_anterior(self):
        saida = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        gravar({"sessoes": ["anterior"]}, saida)
        rodar(falso({PAGINA: resposta([sessao()], "eyJ")}), LOCAIS, AGORA, saida)
        with open(saida, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["sessoes"], ["anterior"])

    def test_so_invalido_preserva_anterior(self):
        saida = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        gravar({"sessoes": ["anterior"]}, saida)
        rodar(falso({PAGINA: resposta([{"lixo": 1}])}), LOCAIS, AGORA, saida)
        with open(saida, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["sessoes"], ["anterior"])

    def test_ok_grava(self):
        saida = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        rodar(falso({PAGINA: resposta([sessao()])}), LOCAIS, AGORA, saida)
        d = json.load(open(saida, encoding="utf-8"))
        self.assertEqual(d["contadores"]["com_projeto"], 1)


if __name__ == "__main__":
    unittest.main()
