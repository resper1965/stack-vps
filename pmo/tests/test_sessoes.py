import json, os, tempfile, unittest
from datetime import datetime, timezone
from pmo.sessoes import ColetaFalhada, coletar, gravar, listar, rodar

AGORA = datetime(2026, 10, 16, 12, tzinfo=timezone.utc)
PAGINA = "/api/session?limit=100"
LOCAIS = {"bekaa/a": "/srv/dev/projetos/bekaa/a", "org2/b": "/srv/dev/projetos/org2/b"}


def sessao(id="ses_1", diretorio="/srv/dev/projetos/bekaa/a/scripts", titulo="t", outcome="succeeded",
           criada=1, atualizada=50, agent="build", location=None):
    # model/cost/tokens vêm na resposta da API e NÃO podem chegar ao sessoes.json
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
    def test_metadado_apenas(self):
        d = coletar(falso({PAGINA: resposta([sessao()])}), LOCAIS, AGORA)
        (m,) = d["sessoes"]
        self.assertEqual(set(m), {"id", "agent", "outcome", "criada", "atualizada", "titulo", "diretorio", "projeto"},
                         "model, cost, tokens e transcrição ficam de fora")
        self.assertEqual(m["projeto"], "bekaa/a", "subpasta cai no clone")
        self.assertEqual(d["contadores"], {"sessoes": 1, "com_projeto": 1})
        self.assertFalse(d["coleta_incompleta"])

    def test_fora_da_raiz_e_na_raiz(self):
        d = coletar(falso({PAGINA: resposta([sessao(id="ses_x", location={"directory": "/home/agente"}),
                                             sessao(id="ses_r", location={"directory": "/srv/dev/projetos"})])}),
                    LOCAIS, AGORA)
        proj = {m["id"]: m["projeto"] for m in d["sessoes"]}
        self.assertEqual(proj, {"ses_x": None, "ses_r": None}, "raiz e /home não são clones")
        self.assertEqual(d["contadores"]["com_projeto"], 0)

    def test_traversal_nao_associa(self):
        d = coletar(falso({PAGINA: resposta([sessao(location={"directory": "/srv/dev/projetos/../../srv/dev/secrets"})])}),
                    LOCAIS, AGORA)
        m = d["sessoes"][0]
        self.assertEqual(m["diretorio"], "/srv/srv/dev/secrets", "realpath resolve o atalho")
        self.assertIsNone(m["projeto"], "fora da raiz não vira projeto")

    def test_item_invalido_marca_incompleta(self):
        d = coletar(falso({PAGINA: resposta([sessao(), {"lixo": 1}, "texto"])}), LOCAIS, AGORA)
        self.assertEqual([m["id"] for m in d["sessoes"]], ["ses_1"])
        self.assertTrue(d["coleta_incompleta"])

    def test_titulo_truncado(self):
        d = coletar(falso({PAGINA: resposta([sessao(titulo="x" * 500)])}), LOCAIS, AGORA)
        titulo = d["sessoes"][0]["titulo"]
        self.assertEqual(len(titulo), 300)
        self.assertTrue(titulo.endswith("…"))

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

    def test_falha_no_meio_devolve_parcial(self):
        itens, incompleta = listar(falso({PAGINA: resposta([sessao()], "eyJ")}))
        self.assertEqual([m["id"] for m in itens], ["ses_1"], "a 2a página sem rota não perde a 1a")
        self.assertTrue(incompleta)

    def test_falha_na_primeira_levanta(self):
        with self.assertRaises(ColetaFalhada):
            listar(falso({}))

    def test_falha_sem_item_valido_levanta(self):
        paginas = {PAGINA: resposta([{"lixo": 1}], "eyJ")}
        with self.assertRaises(ColetaFalhada):
            listar(falso(paginas))


class Gravar(unittest.TestCase):
    def test_atomica(self):
        pasta = tempfile.mkdtemp()
        caminho = os.path.join(pasta, "sessoes.json")
        gravar({"gerado_em": AGORA.isoformat(), "sessoes": []}, caminho)
        with open(caminho, encoding="utf-8") as f:
            self.assertEqual(json.load(f)["sessoes"], [])
        self.assertEqual(os.listdir(pasta), ["sessoes.json"], "tmp some no replace")
        self.assertEqual(os.stat(caminho).st_mode & 0o777, 0o644)


class Rodar(unittest.TestCase):
    def test_indisponivel_preserva_anterior(self):
        saida = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        gravar({"sessoes": ["anterior"]}, saida)
        rodar(falso({}), LOCAIS, AGORA, saida)
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
