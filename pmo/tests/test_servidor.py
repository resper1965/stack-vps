import http.client, json, os, tempfile, threading, unittest
from pmo.servidor import criar


class Servidor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        web = os.path.join(cls.tmp, "web"); os.makedirs(web)
        open(os.path.join(web, "index.html"), "w").write("<h1>PMO</h1>")
        cls.painel = os.path.join(cls.tmp, "painel.json")
        json.dump({"projetos": [{"id": "o/a"}], "arquivados": [{"id": "o/velho"}],
                   "a_destinar": [{"id": "destinar:DESENVOLVIMENTO/ORM Esper"}]}, open(cls.painel, "w"))
        cls.fila = os.path.join(cls.tmp, "fila")
        cls.srv = criar("127.0.0.1", 0, web, cls.painel, cls.fila)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.porta = cls.srv.server_address[1]

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def req(self, metodo, caminho, corpo=None):
        c = http.client.HTTPConnection("127.0.0.1", self.porta, timeout=5)
        c.request(metodo, caminho, body=json.dumps(corpo) if corpo is not None else None,
                  headers={"Content-Type": "application/json"})
        r = c.getresponse(); return r.status, r.read()

    def test_pagina_e_dados(self):
        self.assertEqual(self.req("GET", "/")[0], 200)
        st, corpo = self.req("GET", "/painel.json")
        self.assertEqual(st, 200); self.assertIn(b"o/a", corpo)

    def test_acao_valida_vai_para_fila(self):
        st, _ = self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"})
        self.assertEqual(st, 202)
        pedidos = [json.load(open(os.path.join(self.fila, f))) for f in os.listdir(self.fila)]
        self.assertIn({"acao": "arquivar", "alvo": "o/a", "confirmacao": None}, [{k: p[k] for k in ("acao", "alvo", "confirmacao")} for p in pedidos])

    def test_a_destinar_e_arquivado_sao_alvos(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "trazer", "alvo": "destinar:DESENVOLVIMENTO/ORM Esper"})[0], 202)
        self.assertEqual(self.req("POST", "/acao", {"acao": "restaurar", "alvo": "o/velho"})[0], 202)

    def test_recusas(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "rm", "alvo": "o/a"})[0], 400)
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/inexistente"})[0], 400)
        self.assertEqual(self.req("POST", "/acao", "lixo")[0], 400)
        self.assertEqual(self.req("GET", "/../painel.json")[0], 404)
        self.assertEqual(self.req("GET", "/%2e%2e/%2e%2e/etc/passwd")[0], 404)


if __name__ == "__main__":
    unittest.main()
