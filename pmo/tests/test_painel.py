import json, os, tempfile, unittest
from datetime import datetime, timezone
from datetime import timedelta
from pmo.painel import gerar, a_destinar, fundir, ler_sessoes, ler_saude, montar

AGORA = datetime(2026, 10, 6, 6, tzinfo=timezone.utc)


def reg(id_, estagio="em andamento", esquecido=None, arquivado=False):
    return {"id": id_, "nome": id_.split("/")[1], "dono": id_.split("/")[0], "estagio": estagio,
            "estagio_sugerido": estagio, "esquecido": esquecido, "arquivado": arquivado, "prs": 1, "ci": "failure"}


class Gerar(unittest.TestCase):
    def test_separa_e_conta(self):
        p = gerar([reg("o/a"), reg("o/b", esquecido="sem atividade há 20 dias"), reg("o/c", arquivado=True)], [], None, AGORA)
        self.assertEqual([x["id"] for x in p["projetos"]], ["o/a", "o/b"])
        self.assertEqual([x["id"] for x in p["arquivados"]], ["o/c"])
        self.assertEqual(p["contadores"]["esquecidos"], 1)
        self.assertEqual(p["contadores"]["prs_abertos"], 2)
        self.assertEqual(p["contadores"]["ci_vermelho"], 2)
        self.assertFalse(p["coleta_incompleta"])

    def test_mudou_desde_ontem(self):
        ant = gerar([reg("o/a", estagio="em andamento"), reg("o/b")], [], None, AGORA)
        p = gerar([reg("o/a", estagio="em revisão"), reg("o/b", esquecido="x"), reg("o/novo")], [], ant, AGORA)
        m = p["mudou_desde_ontem"]
        self.assertIn("o/novo", m["novos"]); self.assertIn("o/a", m["mudou_estagio"]); self.assertIn("o/b", m["viraram_esquecidos"])

    def test_falha_mantem_anterior(self):
        ant = gerar([reg("o/a")], [], None, AGORA)
        p = gerar(None, [], ant, AGORA)
        self.assertTrue(p["coleta_incompleta"]); self.assertEqual([x["id"] for x in p["projetos"]], ["o/a"])


class Destinar(unittest.TestCase):
    def test_pastas_sem_git(self):
        r = tempfile.mkdtemp(); D = os.path.join(r, "DESENVOLVIMENTO")
        for p in ("ORM Esper", "bekaa-apps/bekaa-gestao", "vazia", "com git"):
            os.makedirs(os.path.join(D, p), exist_ok=True)
        open(os.path.join(D, "ORM Esper", "a.md"), "w").close()
        open(os.path.join(D, "bekaa-apps", "bekaa-gestao", "x.ts"), "w").close()
        os.makedirs(os.path.join(D, "com git", ".git")); open(os.path.join(D, "com git", "y"), "w").close()
        nomes = sorted(x["caminho"] for x in a_destinar(r))
        self.assertEqual(nomes, ["DESENVOLVIMENTO/ORM Esper", "DESENVOLVIMENTO/bekaa-apps/bekaa-gestao"])


class Sessoes(unittest.TestCase):
    def painel(self, *ids):
        return gerar([reg(i) for i in ids], [], None, AGORA)

    def sessoes(self, *sess, gerado="2026-10-06T05:00:00+00:00"):
        return {"gerado_em": gerado, "coleta_incompleta": False, "contadores": {"sessoes": len(sess)},
                "sessoes": [{"id": i, "projeto": p, "atualizada": a} for i, p, a in sess]}

    def test_fusao_junta_id_minusculo(self):
        d = self.painel("Resper1965/Stack-VPS")
        fundir(d, self.sessoes(("ses_1", "resper1965/stack-vps", 1792183738118)), AGORA)
        p = d["projetos"][0]
        self.assertEqual(p["sessoes"], 1)
        self.assertEqual(p["ultima_sessao"], 1792183738118)
        self.assertEqual(p["sessao_id"], "ses_1", "id completo, para o comando opencode -s")
        self.assertEqual(d["contadores"]["projetos_com_sessao"], 1)
        self.assertEqual(d["sessoes_gerado_em"], "2026-10-06T05:00:00+00:00")

    def test_id_da_mais_recente_vence(self):
        d = self.painel("o/a")
        fundir(d, self.sessoes(("ses_1", "o/a", 5), ("ses_2", "o/a", 60)), AGORA)
        p = d["projetos"][0]
        self.assertEqual((p["sessoes"], p["ultima_sessao"], p["sessao_id"]), (2, 60, "ses_2"), "a mais recente vence, não importa a ordem")

    def test_ausencia_nao_marca_nada(self):
        d = self.painel("o/a")
        antes = json.loads(json.dumps(d))
        fundir(d, None, AGORA)
        fundir(d, self.sessoes(), AGORA)
        fundir(d, self.sessoes(("ses_1", None, 5)), AGORA)
        self.assertEqual(d, antes, "sessões ausentes, vazias ou fora de projeto: painel idêntico")

    def test_invalidos_ficam_de_fora(self):
        d = self.painel("o/a")
        fundir(d, self.sessoes((7, "o/a", 5), ("ses_3", 7, 5)), AGORA)
        self.assertEqual(d, self.painel("o/a"), "id ou projeto de tipo errado: nada fundido")
        fundir(d, self.sessoes(("ses_1", "o/a", True)), AGORA)
        p = d["projetos"][0]
        self.assertEqual(p["sessoes"], 1)
        self.assertIsNone(p["ultima_sessao"], "bool não vale como int")
        self.assertEqual(p["sessao_id"], "ses_1")

    def test_contrato_sem_lista_integral(self):
        d = self.painel("o/a", "o/b")
        fundir(d, self.sessoes(("ses_1", "o/a", 5)), AGORA)
        self.assertNotIn("sessoes", d, "a lista bruta (0600) nunca vem para o painel")
        self.assertNotIn("sessoes", d["projetos"][1], "projeto sem sessão não ganha campo")
        d2 = self.painel("o/a")
        fundir(d2, {"sessoes": "lixo"}, AGORA)
        fundir(d2, {"lixo": 1}, AGORA)
        fundir(d2, 7, AGORA)
        self.assertEqual(d2, self.painel("o/a"), "estrutura inválida não marca nada")

    def test_defazada(self):
        d = self.painel("o/a")
        fundir(d, self.sessoes(("ses_1", "o/a", 5), gerado="2026-10-01T05:00:00+00:00"), AGORA)
        self.assertTrue(d["sessoes_defasada"])
        d2 = self.painel("o/a")
        fundir(d2, self.sessoes(("ses_1", "o/a", 5), gerado="2026-10-06T05:00:00+00:00"), AGORA)
        self.assertNotIn("sessoes_defasada", d2)
        d3 = self.painel("o/a")
        fundir(d3, self.sessoes(("ses_1", "o/a", 5), gerado="garbage"), AGORA)
        self.assertNotIn("sessoes_defasada", d3, "gerado_em de tipo errado não derruba nada")

    def test_projeto_desconhecido_conta_zero(self):
        d = self.painel("o/a")
        fundir(d, self.sessoes(("ses_1", "o/inexistente", 5)), AGORA)
        self.assertEqual(d["contadores"]["projetos_com_sessao"], 0, "sessão em projeto fora do painel não funde")
        self.assertNotIn("sessoes", d["projetos"][0])


    def test_incompleta_tratada_como_ausente(self):
        d = self.painel("o/a")
        antes = json.loads(json.dumps(d))
        s = self.sessoes(("ses_1", "o/a", 5))
        s["coleta_incompleta"] = True
        fundir(d, s, AGORA)
        self.assertEqual(d, antes, "coleta incompleta (o coletor nunca grava) não funde nada")

    def test_fusao_em_arquivados(self):
        d = gerar([reg("o/a"), reg("o/velho", arquivado=True)], [], None, AGORA)
        fundir(d, self.sessoes(("ses_1", "o/velho", 1792183738118)), AGORA)
        p = d["arquivados"][0]
        self.assertEqual((p["sessoes"], p["sessao_id"]), (1, "ses_1"), "projeto arquivado também recebe sessões")
        self.assertEqual(d["contadores"]["projetos_com_sessao"], 1)


    def test_itens_nao_dicionario_ficam_de_fora(self):
        d = self.painel("o/a")
        antes = json.loads(json.dumps(d))
        cru = {"gerado_em": "2026-10-06T05:00:00+00:00", "coleta_incompleta": False,
               "contadores": {}, "sessoes": ["lixo", 7, None, ["x"], ("tupla",)]}
        fundir(d, cru, AGORA)
        self.assertEqual(d, antes, "itens que não são dict são ignorados sem interromper")
        cru["sessoes"] = [{"id": "ses_2"}, {"projeto": "o/a"}, 7,
                          {"id": "ses_1", "projeto": "o/a", "atualizada": 60}]
        fundir(d, cru, AGORA)
        p = d["projetos"][0]
        self.assertEqual((p["sessoes"], p["ultima_sessao"], p["sessao_id"]), (1, 60, "ses_1"),
                         "só itens completos fundem; os demais somem sem erro")

    def test_defazagem_datas_incompativeis_nao_levantam(self):
        for gerado, agora in (("2026-10-06T05:00:00", AGORA),
                              ("2026-10-06T05:00:00+00:00", AGORA.replace(tzinfo=None)),
                              ("2026-10-06T05:00:00+00:00", "lixo")):
            with self.subTest(gerado=gerado, agora=agora):
                d = self.painel("o/a")
                fundir(d, self.sessoes(("ses_1", "o/a", 5), gerado=gerado), agora)
                self.assertEqual(d["sessoes_gerado_em"], gerado, "gerado_em fica de pé")
                self.assertEqual(d["projetos"][0]["sessoes"], 1, "a fusão acontece apesar da data")
                self.assertNotIn("sessoes_defasada", d, "data inválida/sem tz/incompatível não marca nem lança")

    def antigo(self, id_, dias, esquecido_="sem atividade há 40 dias"):
        r = dict(reg(id_, esquecido=esquecido_), dias=dias, proximo="seguir")
        return gerar([r], [], None, AGORA)

    def test_sessao_recente_tira_do_esquecido(self):
        d = self.antigo("o/a", 40)
        ontem = int(AGORA.timestamp() * 1000) - 86400000
        fundir(d, self.sessoes(("ses_1", "o/a", ontem)), AGORA)
        p = d["projetos"][0]
        self.assertEqual((p["dias"], p["atividade_origem"]), (1, "sessão"))
        self.assertIsNone(p["esquecido"])
        self.assertEqual(d["contadores"]["esquecidos"], 0, "contadores refeitos depois da fusão")

    def test_sessao_mais_antiga_que_o_push_nao_muda(self):
        d = self.antigo("o/a", 3, esquecido_=None)
        velha = int(AGORA.timestamp() * 1000) - 30 * 86400000
        fundir(d, self.sessoes(("ses_1", "o/a", velha)), AGORA)
        p = d["projetos"][0]
        self.assertEqual(p["dias"], 3)
        self.assertNotIn("atividade_origem", p)

    def test_sessao_no_futuro_vira_zero_dias(self):
        d = self.antigo("o/a", 40)
        futuro = int(AGORA.timestamp() * 1000) + 5 * 86400000
        fundir(d, self.sessoes(("ses_1", "o/a", futuro)), AGORA)
        self.assertEqual(d["projetos"][0]["dias"], 0)

    def test_sessao_sem_data_nao_conta_como_atividade(self):
        d = self.antigo("o/a", 40)
        fundir(d, self.sessoes(("ses_1", "o/a", None)), AGORA)
        p = d["projetos"][0]
        self.assertEqual(p["dias"], 40)
        self.assertEqual(p["esquecido"], "sem atividade há 40 dias")


class LerSessoes(unittest.TestCase):
    def test_ausente_corrupto_e_fora_de_contrato(self):
        caminho = os.path.join(tempfile.mkdtemp(), "sessoes.json")
        self.assertIsNone(ler_sessoes(caminho), "arquivo ausente vira None")
        open(caminho, "w").write("{ lixo")
        self.assertIsNone(ler_sessoes(caminho))
        open(caminho, "w").write('{"outra": 1}')
        self.assertIsNone(ler_sessoes(caminho))
        open(caminho, "w").write('{"sessoes": []}')
        self.assertEqual(ler_sessoes(caminho), {"sessoes": []})


class Saude(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.f = os.path.join(self.tmp.name, "health.txt")

    def escreve(self, texto, idade_min=0):
        with open(self.f, "w") as fh:
            fh.write(texto)
        t = (AGORA - timedelta(minutes=idade_min)).timestamp()
        os.utime(self.f, (t, t))

    def test_ler_saude_agrupa_por_secao(self):
        self.escreve("acesso\n  ok    tailscale na tailnet\n  FALHA cloudflared parado\nbackup\n  pend  backup restic desligado\nlixo solto\n  ??? x\n", 5)
        s = ler_saude(self.f, AGORA)
        self.assertEqual(s["itens"], [
            {"secao": "acesso", "estado": "ok", "texto": "tailscale na tailnet"},
            {"secao": "acesso", "estado": "falha", "texto": "cloudflared parado"},
            {"secao": "backup", "estado": "pend", "texto": "backup restic desligado"}])
        self.assertFalse(s["velho"])
        self.assertTrue(s["gerado_em"].startswith("2026-10-06T05:55:00"))

    def test_ler_saude_secao_ci(self):
        self.escreve("hostinger\n  ok    x\nci\n  ok    isolamento de rede da conta ci\n  FALHA runners sem atualização há 4 min\n"
                     "  pend  runners instalados, mas não habilitados\ndisco\n  ok    /srv em 10%\n", 1)
        itens = [i for i in ler_saude(self.f, AGORA)["itens"] if i["secao"] == "ci"]
        self.assertEqual([(i["estado"], i["texto"]) for i in itens], [
            ("ok", "isolamento de rede da conta ci"),
            ("falha", "runners sem atualização há 4 min"),
            ("pend", "runners instalados, mas não habilitados")])

    def test_ler_saude_ausente(self):
        self.assertEqual(ler_saude(self.f, AGORA), {"gerado_em": None, "velho": True, "itens": []})

    def test_ler_saude_vazio(self):
        self.escreve("")
        self.assertEqual(ler_saude(self.f, AGORA), {"gerado_em": None, "velho": True, "itens": []})

    def test_ler_saude_velho(self):
        for idade, velho in ((1, False), (89, False), (91, True)):
            self.escreve("acesso\n  ok    x\n", idade)
            s = ler_saude(self.f, AGORA)
            self.assertEqual(s["velho"], velho, idade)
            self.assertEqual(len(s["itens"]), 1)

    def test_ler_saude_recusa_symlink_pasta_fifo_e_arquivo_grande(self):
        vazio = {"gerado_em": None, "velho": True, "itens": []}
        self.escreve("acesso\n  ok    x\n", 1)
        link = os.path.join(self.tmp.name, "link.txt")
        os.symlink(self.f, link)
        self.assertEqual(ler_saude(link, AGORA), vazio, "symlink nao e seguido")
        self.assertEqual(ler_saude(self.tmp.name, AGORA), vazio, "pasta")
        fifo = os.path.join(self.tmp.name, "fifo")
        os.mkfifo(fifo)
        self.assertEqual(ler_saude(fifo, AGORA), vazio, "fifo nao prende o painel")
        self.escreve("acesso\n  ok    x\n" + "  ok    y\n" * 10000, 1)
        self.assertGreater(os.path.getsize(self.f), 64 * 1024)
        self.assertEqual(ler_saude(self.f, AGORA), vazio, "arquivo acima de 64 KiB")


class Montar(unittest.TestCase):
    def base(self):
        return gerar([reg("o/x"), reg("o/y")], [], None, AGORA)

    def test_montar_aplica_ajuste_e_classe(self):
        ajustes = {"o/x": {"de": "projetos", "para": "arquivados", "em": "2026-10-06T07:00:00+00:00"}}
        classes = {"o/y": {"estagio": "congelado", "empresa": "ness", "area": "dev"}}
        p = montar(self.base(), ajustes, classes)
        self.assertEqual([x["id"] for x in p["projetos"]], ["o/y"])
        self.assertEqual([x["id"] for x in p["arquivados"]], ["o/x"])
        self.assertTrue(p["arquivados"][0]["arquivado"])
        y = p["projetos"][0]
        self.assertEqual(y["classe"]["estagio"], "congelado")
        self.assertEqual(y["estagio"], "congelado")
        self.assertFalse(y["esquecido"])
        self.assertEqual(p["contadores"]["projetos"], 1)

    def test_montar_vazio_nao_muda_projetos(self):
        p = montar(self.base(), {}, {})
        self.assertEqual([x["id"] for x in p["projetos"]], ["o/x", "o/y"])
        self.assertEqual(p["arquivados"], [])


if __name__ == "__main__":
    unittest.main()
