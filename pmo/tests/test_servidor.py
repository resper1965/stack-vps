import http.client, io, json, os, shutil, socket, stat, tempfile, threading, time, unittest
from unittest import mock
from pmo import servidor
from pmo.servidor import criar


class Servidor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        web = os.path.join(cls.tmp, "web"); os.makedirs(web)
        open(os.path.join(web, "index.html"), "w").write("<h1>PMO</h1>")
        cls.painel = os.path.join(cls.tmp, "painel.json")
        json.dump({"gerado_em": "2026-10-06T09:00:00+00:00",
                   "projetos": [{"id": "o/a", "sessoes": 2, "ultima_sessao": 60, "sessao_id": "ses_9",
                                 "sugestao": {"empresa": "ness", "tipo": "app"}}, {"id": "o/b"}],
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
        cls.srv.server_close()

    def req(self, metodo, caminho, corpo=None, **cab):
        c = http.client.HTTPConnection("127.0.0.1", self.porta, timeout=5)
        h = {"Content-Type": "application/json", "X-PMO": "1"}
        h.update({k.replace("_", "-"): v for k, v in cab.items() if v is not None})
        for k in [k for k, v in cab.items() if v is None]:
            h.pop(k.replace("_", "-"), None)
        c.request(metodo, caminho, body=json.dumps(corpo) if corpo is not None else None, headers=h)
        r = c.getresponse(); corpo = r.read(); c.close(); return r.status, corpo

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
            c.close()
            c = http.client.HTTPConnection("127.0.0.1", porta, timeout=5); c.request("GET", "/painel.json")
            self.assertEqual(c.getresponse().status, 200, "leitura continua livre")
            c.close()
        finally:
            srv.shutdown()
            srv.server_close()

    def test_classificar_grava_na_hora(self):
        st, _ = self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a",
                                           "classe": {"empresa": "bekaa", "area": "ORM", "cliente": "t4isb", "tipo": "site", "linear": "BEK", "estagio": "parado"}})
        self.assertEqual(st, 200)
        a = next(x for x in json.loads(self.req("GET", "/painel.json")[1])["projetos"] if x["id"] == "o/a")
        self.assertEqual(a["classe"], {"empresa": "bekaa", "area": "ORM", "cliente": "t4isb", "tipo": "site", "linear": "BEK", "estagio": "parado", "confirmada": True})
        self.assertEqual(a["estagio"], "parado")

    def test_classificar_congelado_aceito(self):
        st, _ = self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a", "classe": {"estagio": "congelado"}})
        self.assertEqual(st, 200)
        a = next(x for x in json.loads(self.req("GET", "/painel.json")[1])["projetos"] if x["id"] == "o/a")
        self.assertEqual((a["estagio"], a["classe"]["estagio"]), ("congelado", "congelado"))
        self.assertEqual(self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a", "classe": {"estagio": ""}})[0], 200)

    def test_classificar_recusa_valor_invalido(self):
        for classe in ({"empresa": "acme"}, {"tipo": "foguete"}, {"estagio": "voando"}, {"area": "a\nb"}, {"cliente": "x" * 61}, "lixo"):
            with self.subTest(classe=classe):
                self.assertEqual(self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a", "classe": classe})[0], 400)

    def test_fundidos_sobrevivem_a_classificar(self):
        a = next(x for x in json.loads(self.req("GET", "/painel.json")[1])["projetos"] if x["id"] == "o/a")
        self.assertEqual((a["sessoes"], a["sessao_id"]), (2, "ses_9"), "campos fundidos passam pelo servidor")
        self.assertEqual(self.req("POST", "/acao", {"acao": "classificar", "alvo": "o/a", "classe": {"empresa": "bekaa"}})[0], 200)
        a = next(x for x in json.loads(self.req("GET", "/painel.json")[1])["projetos"] if x["id"] == "o/a")
        self.assertEqual((a["sessoes"], a["sessao_id"]), (2, "ses_9"), "classificar preserva os campos fundidos")

    def test_painel_sem_sessoes_serve_normal(self):
        st, corpo = self.req("GET", "/painel.json")
        d = json.loads(corpo)
        self.assertEqual(st, 200, "painel sem sessões segue servido")
        todos = (*d["projetos"], *d["arquivados"])
        self.assertNotIn("sessoes", next(x for x in todos if x["id"] == "o/b"), "registro sem fundidos passa intato")
        self.assertNotIn("sessoes", next(x for x in todos if x["id"] == "o/velho"), "registro sem fundidos passa intato")

    def test_clonar_leva_a_pasta(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "clonar", "alvo": "o/a", "pasta": "ness"})[0], 202)
        pedidos = [json.load(open(os.path.join(self.fila, f))) for f in os.listdir(self.fila)]
        self.assertIn("ness", [p.get("pasta") for p in pedidos if p["acao"] == "clonar"])
        self.assertEqual(self.req("POST", "/acao", {"acao": "clonar", "alvo": "o/a", "pasta": "../x"})[0], 400)


class ServidorSocket(unittest.TestCase):
    HOST = "stack.tailnet.ts.net:8443"
    LOGIN = "resper@bekaa.eu"

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        web = os.path.join(self.tmp, "web"); os.makedirs(web)
        self.painel = os.path.join(self.tmp, "painel.json")
        with open(self.painel, "w") as f:
            json.dump({"projetos": [{"id": "o/a"}], "arquivados": [], "a_destinar": []}, f)
        self.web = web
        self.fila = os.path.join(self.tmp, "fila")
        self.sock = os.path.join(self.tmp, "pmo.sock")
        velho = socket.socket(socket.AF_UNIX); velho.bind(self.sock); velho.close()  # socket velho: criar() remove antes do bind
        self.srv = self.sobe(self.sock)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.addCleanup(self.srv.server_close)
        self.addCleanup(self.srv.shutdown)

    def sobe(self, sock, **k):
        k = {"hosts": (self.HOST, "localhost:8080"), "logins": (self.LOGIN,), **k}
        return criar(None, None, self.web, self.painel, self.fila, os.path.join(self.tmp, "aj.json"),
                     socket=sock, classes=os.path.join(self.tmp, "cl.json"), **k)

    def test_sem_hosts_ou_sem_logins_falha_fechado(self):
        for k in ({"hosts": ()}, {"logins": ()}):
            with self.assertRaises(ValueError):
                self.sobe(os.path.join(self.tmp, "outro.sock"), **k)

    def test_arquivo_comum_no_caminho_do_socket_nao_e_apagado(self):
        f = os.path.join(self.tmp, "importante")
        open(f, "w").close()
        with self.assertRaises(ValueError):
            self.sobe(f)
        self.assertTrue(os.path.isfile(f))

    def test_main_socket_sem_logins_ou_hosts_sai_2(self):
        for args in (["--socket", "x.sock", "--hosts", "h"], ["--socket", "x.sock", "--logins", "a@b.c"]):
            with mock.patch("sys.argv", ["pmo"] + args), mock.patch("sys.stderr", io.StringIO()),                     mock.patch.object(servidor, "criar") as c:
                with self.assertRaises(SystemExit) as e:
                    servidor.main()
            self.assertEqual(e.exception.code, 2)
            c.assert_not_called()

    def test_origin_propria_aceita_e_alheia_recusada(self):
        h = dict(Tailscale_User_Login=self.LOGIN)
        ped = {"acao": "arquivar", "alvo": "o/a"}
        self.assertEqual(self.req("POST", "/acao", ped, Origin="https://" + self.HOST, **h), 202)
        self.assertEqual(self.req("POST", "/acao", ped, Origin="https://evil.example", **h), 403)

    def req(self, metodo, caminho, corpo=None, **cab):
        s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(self.sock)
        c = http.client.HTTPConnection("localhost", timeout=5); c.sock = s
        h = {"Host": self.HOST, "Content-Type": "application/json", "X-PMO": "1"}
        h.update({k.replace("_", "-"): v for k, v in cab.items()})
        self.addCleanup(c.close); self.addCleanup(s.close)
        try:
            c.request(metodo, caminho, body=json.dumps(corpo) if corpo is not None else None, headers=h)
        except BrokenPipeError:
            pass  # recusa antes de ler o corpo: o servidor fecha e a resposta ja esta no buffer
        r = c.getresponse(); r.read(); return r.status

    def bruto(self, cab_extra, corpo=b"", srv=None):
        """Request cru, sem meia-fechada; devolve (primeira linha da resposta ou b'', segundos)."""
        s = socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(srv.server_address if srv else self.sock)
        self.addCleanup(s.close)
        cab = ("POST /acao HTTP/1.1%(n)sHost: %(h)s%(n)sContent-Type: application/json%(n)sX-PMO: 1%(n)s%(c)s%(n)s%(n)s"
               % {"n": chr(13) + chr(10), "h": self.HOST, "c": cab_extra}).encode()
        t = time.time()
        try:
            s.sendall(cab + corpo)
        except OSError:
            pass
        try:
            r = s.recv(200)
        except (ConnectionResetError, socket.timeout):
            r = b""
        return r.split(bytes([13, 10]))[0], time.time() - t

    def test_content_length_negativo_nao_le_ate_eof(self):
        linha, dt = self.bruto("Content-Length: -1", b"x" * 100_000)
        self.assertIn(linha, (b"HTTP/1.0 403 Forbidden", b"HTTP/1.0 400 Bad Request", b""))
        self.assertLess(dt, 3)
        self.assertEqual(self.pedidos(), [])

    def test_corpo_prometido_e_nao_enviado_expira(self):
        srv = self.sobe(os.path.join(self.tmp, "t.sock"), timeout=1)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.server_close); self.addCleanup(srv.shutdown)
        linha, dt = self.bruto("Content-Length: 4096", srv=srv)
        self.assertEqual(linha, b"")  # fechou sem responder, nao ficou pendurado
        self.assertLess(dt, 4)

    def pedidos(self):
        return [f for f in os.listdir(self.fila) if not f.startswith(".")]

    def test_socket_criado_0660(self):
        self.assertEqual(stat.S_IMODE(os.stat(self.sock).st_mode), 0o660)

    def test_get_host_da_lista_200(self):
        self.assertEqual(self.req("GET", "/painel.json"), 200)
        self.assertEqual(self.req("GET", "/painel.json", Host="localhost:8080"), 200)

    def test_get_host_fora_da_lista_403(self):
        self.assertEqual(self.req("GET", "/painel.json", Host="evil.example"), 403)

    def test_post_com_login_permitido_202(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"}, Tailscale_User_Login=self.LOGIN), 202)
        self.assertEqual(len(self.pedidos()), 1)

    def test_post_sem_login_tailscale_recusado(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"}), 403)
        self.assertEqual(self.pedidos(), [])

    def test_post_login_fora_da_lista_recusado(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"}, Tailscale_User_Login="outro@x.com"), 403)
        self.assertEqual(self.pedidos(), [])

    def test_post_host_fora_da_lista_recusado(self):
        self.assertEqual(self.req("POST", "/acao", {"acao": "arquivar", "alvo": "o/a"}, Host="evil.example", Tailscale_User_Login=self.LOGIN), 403)
        self.assertEqual(self.pedidos(), [])


class ServidorSaude(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup); self.tmp = tmp.name
        web = os.path.join(self.tmp, "web"); os.makedirs(web)
        self.painel = os.path.join(self.tmp, "painel.json")
        with open(self.painel, "w") as f:
            json.dump({"projetos": [], "arquivados": [], "a_destinar": []}, f)
        self.web, self.saude = web, os.path.join(self.tmp, "health.txt")
        with open(self.saude, "w") as f:
            f.write("acesso\n  FALHA cloudflared parado\n")

    def pega(self, **k):
        srv = criar("127.0.0.1", 0, self.web, self.painel, os.path.join(self.tmp, "fila"), os.path.join(self.tmp, "a.json"),
                    bloquear_local=False, classes=os.path.join(self.tmp, "c.json"), **k)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        self.addCleanup(srv.server_close); self.addCleanup(srv.shutdown)
        c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1], timeout=5)
        c.request("GET", "/painel.json"); r = c.getresponse(); d = json.loads(r.read()); c.close()
        return d

    def test_painel_json_tem_saude(self):
        d = self.pega(saude=self.saude)
        self.assertEqual(d["saude"]["itens"], [{"secao": "acesso", "estado": "falha", "texto": "cloudflared parado"}])
        self.assertFalse(d["saude"]["velho"])

    def test_sem_saude_a_chave_some(self):
        self.assertNotIn("saude", self.pega())
        self.assertNotIn("atalhos", self.pega())

    def test_atalho_so_https(self):
        for url, esperado in (("https://stack.ts.net/", "https://stack.ts.net/"), ("http://x/", None),
                              ("javascript:alert(1)", None), ("", None), (None, None)):
            self.assertEqual(self.pega(atalhos={"opencode": url})["atalhos"], {"opencode": esperado}, url)


if __name__ == "__main__":
    unittest.main()
