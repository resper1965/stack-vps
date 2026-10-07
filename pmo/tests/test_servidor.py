import http.client, json, os, tempfile, threading, unittest
from pmo.servidor import criar


class Servidor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        web = os.path.join(cls.tmp, "web"); os.makedirs(web)
        open(os.path.join(web, "index.html"), "w").write("<h1>PMO</h1>")
        cls.painel = os.path.join(cls.tmp, "painel.json")
        json.dump({"gerado_em": "2026-10-06T09:00:00+00:00",
                   "projetos": [{"id": "o/a", "sugestao": {"empresa": "ness", "tipo": "app"}}, {"id": "o/b"}],
                   "arquivados": [{"id": "o/velho"}], "a_destinar": [{"id": "destinar:DESENVOLVIMENTO/ORM Esper"}]},
                  open(cls.painel, "w"))
        cls.ajustes = os.path.join(cls.tmp, "ajustes.json")
        json.dump({"o/b": {"de": "projetos", "para": "arquivados", "em": "2026-10-06T12:00:00+00:00"}}, open(cls.ajustes, "w"))
        cls.fila = os.path.join(cls.tmp, "fila")
        cls.classes = os.path.join(cls.tmp, "classes.json")
        cls.srv = criar("127.0.0.1", 0, web, cls.painel, cls.fila, cls.ajustes, bloquear_local=False, classes=cls.classes)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.porta = cls.srv.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def req(self, metodo, caminho, corpo=None, **cab):
        c = http.client.HTTPConnection("127.0.0.1", self.porta, timeout=5)
        h = {"Content-Type": "application/json", "X-PMO": "1"}
        h.update({k.replace("_", "-"): v for k, v in cab.items() if v is not None})
        for k in [k for k, v in cab.items() if v is None]:
            h.pop(k.replace("_", "-"), None)
        c.request(metodo, caminho, body=json.dumps(corpo) if corpo is not None else None, headers=h)
        r = c.getresponse(); return r.status, r.read()

    def test_pagina_e_dados_com_ajustes(self):
        self.assertEqual(self.req("GET", "/")[0], 200)
        st, corpo = self.req("GET", "/painel.json")
        self.assertEqual(st, 200)
        d = json.loads(corpo)
        self.assertEqual([x["id"] for x in d["projetos"]], ["o/a"])
        self.assertEqual(sorted(x["id"] for x in d["arquivados"]), ["o/b", "o/velho"])

    def test_acao_valida_vai_para_fila(self):
        st, _ = self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"})
        self.assertEqual(st, 202)
        pedidos = [json.load(open(os.path.join(self.fila, f))) for f in os.listdir(self.fila)]
        self.assertIn({"acao": "arquivar", "alvo": "o/a", "confirmacao": None},
                      [{k: p[k] for k in ("acao", "alvo", "confirmacao")} for p in pedidos])

    def test_a_destinar_e_arquivado_sao_alvos(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "trazer", "alvo": "destinar:DESENVOLVIMENTO/ORM Esper"})[0], 202)
        self.assertEqual(self.req("POST", "/acao", {"acao": "restaurar", "alvo": "o/velho"})[0], 202)

    def test_recusas(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "rm", "alvo": "o/a"})[0], 400)
        self.assertEqual(self.req("POST", "/acao", {"acao": "reanalisar", "alvo": "o/a"})[0], 400)
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/inexistente"})[0], 400)
        self.assertEqual(self.req("POST", "/acao", "lixo")[0], 400)
        self.assertEqual(self.req("GET", "/../painel.json")[0], 404)
        self.assertEqual(self.req("GET", "/%2e%2e/%2e%2e/etc/passwd")[0], 404)

    def test_csrf_recusado(self):
        alvo = {"acao": "arquivar", "alvo": "o/a"}
        self.assertEqual(self.req("POST", "/acao", alvo, X_PMO=None)[0], 403, "sem o cabecalho proprio")
        self.assertEqual(self.req("POST", "/acao", alvo, Content_Type="text/plain")[0], 403, "requisicao simples")
        self.assertEqual(self.req("POST", "/acao", alvo, Origin="http://evil.example")[0], 403, "outra origem")
        self.assertEqual(self.req("POST", "/acao", alvo, Origin=f"http://127.0.0.1:{self.porta}")[0], 202)

    def test_dns_rebinding_recusado(self):
        self.assertEqual(self.req("GET", "/painel.json", Host="evil.example")[0], 403)
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"}, Host=f"evil.example:{self.porta}")[0], 403)


    def test_pedido_da_propria_vps_recusado(self):
        # o agente na VPS manda o cabecalho que quiser; acao so vem de fora (laptop pela tailnet)
        srv = criar("127.0.0.1", 0, os.path.join(self.tmp, "web"), self.painel, self.fila, self.ajustes)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            porta = srv.server_address[1]
            c = http.client.HTTPConnection("127.0.0.1", porta, timeout=5)
            c.request("POST", "/acao", body=json.dumps({"acao": "arquivar", "alvo": "o/a"}),
                      headers={"Content-Type": "application/json", "X-PMO": "1"})
            self.assertEqual(c.getresponse().status, 403)
            c = http.client.HTTPConnection("127.0.0.1", porta, timeout=5); c.request("GET", "/painel.json")
            self.assertEqual(c.getresponse().status, 200, "leitura continua livre")
        finally:
            srv.shutdown()

    def test_classificar_grava_na_hora(self):
        st, _ = self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a",
                                           "classe": {"empresa": "bekaa", "area": "ORM", "cliente": "t4isb", "tipo": "site"}})
        self.assertEqual(st, 200)
        a = next(x for x in json.loads(self.req("GET", "/painel.json")[1])["projetos"] if x["id"] == "o/a")
        self.assertEqual(a["classe"], {"empresa": "bekaa", "area": "ORM", "cliente": "t4isb", "tipo": "site", "confirmada": True})

    def test_classificar_recusa_valor_invalido(self):
        for classe in ({"empresa": "acme"}, {"tipo": "foguete"}, {"area": "a\nb"}, {"cliente": "x" * 61}, "lixo"):
            with self.subTest(classe=classe):
                self.assertEqual(self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a", "classe": classe})[0], 400)

    def test_clonar_leva_a_pasta(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "clonar", "alvo": "o/a", "pasta": "ness"})[0], 202)
        pedidos = [json.load(open(os.path.join(self.fila, f))) for f in os.listdir(self.fila)]
        self.assertIn("ness", [p.get("pasta") for p in pedidos if p["acao"] == "clonar"])
        self.assertEqual(self.req("POST", "/acao", {"acao": "clonar", "alvo": "o/a", "pasta": "../x"})[0], 400)


if __name__ == "__main__":
    unittest.main()
