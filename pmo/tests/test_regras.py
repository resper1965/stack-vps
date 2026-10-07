import unittest
from pmo.regras import ler_state, estagio_sugerido, esquecido, TIPOS


class LerState(unittest.TestCase):
    def test_campos(self):
        t = "# X\n**Tipo:** documento\n**Estágio:** em revisão\n**Próximo passo:** enviar ao cliente\n"
        self.assertEqual(ler_state(t), {"tipo": "documento", "estagio": "em revisão", "proximo": "enviar ao cliente"})

    def test_sem_acento_e_maiusculas(self):
        t = "**Tipo:** App\n**Estagio:** Em Andamento\n**Proximo passo:** x\n"
        self.assertEqual(ler_state(t), {"tipo": "app", "estagio": "em andamento", "proximo": "x"})

    def test_invalidos_viram_none(self):
        t = "**Tipo:** foguete\n**Estágio:** A DEFINIR\n**Próximo passo:** A DEFINIR\n"
        self.assertEqual(ler_state(t), {"tipo": None, "estagio": None, "proximo": None})

    def test_vazio(self):
        self.assertEqual(ler_state(None), {"tipo": None, "estagio": None, "proximo": None})


class Esquecido(unittest.TestCase):
    def test_andamento_14_dias(self):
        self.assertIsNotNone(esquecido("em andamento", 15, "x", False))
        self.assertIsNone(esquecido("em andamento", 13, "x", False))

    def test_revisao_30_dias(self):
        self.assertIsNotNone(esquecido("em revisão", 31, "x", False))
        self.assertIsNone(esquecido("em revisão", 20, "x", False))

    def test_sem_proximo_passo(self):
        self.assertEqual(esquecido("em andamento", 2, None, False), "sem próximo passo")

    def test_arquivado_e_encerrado_nunca(self):
        self.assertIsNone(esquecido("em andamento", 400, None, True))
        self.assertIsNone(esquecido("encerrado", 400, None, False))
        self.assertIsNone(esquecido("parado", 400, None, False))

    def test_parado_sugerido_sem_state_continua_alarmando(self):
        # "parado" so silencia quando declarado no STATE.md; sugerido, e o mais esquecido de todos
        self.assertEqual(esquecido("parado", 200, None, False, declarado=False), "sem atividade há 200 dias")

    def test_sem_state_nao_cobra_proximo_passo(self):
        # sem STATE.md declarado, so a inatividade alarma; senao tudo vira esquecido
        self.assertIsNone(esquecido("em andamento", 2, None, False, declarado=False))
        self.assertIsNotNone(esquecido("em andamento", 20, None, False, declarado=False))

    def test_sem_estagio_usa_atividade(self):
        # estágio desconhecido conta como em andamento quando há atividade recente esquecida
        self.assertIsNotNone(esquecido(None, 20, "x", False))


class Sugerido(unittest.TestCase):
    def test(self):
        self.assertEqual(estagio_sugerido(200, 0, False), "parado")
        self.assertEqual(estagio_sugerido(3, 1, False), "em revisão")
        self.assertEqual(estagio_sugerido(3, 0, False), "em andamento")
        self.assertEqual(estagio_sugerido(3, 0, True), "encerrado")


class Classificacao(unittest.TestCase):
    def test_empresa_e_cliente_pelo_dono(self):
        from pmo.regras import sugerir
        self.assertEqual(sugerir("bekaa-trusted-advisors", "fixfacilities", "TypeScript", "")["empresa"], "bekaa")
        s = sugerir("t4isb-infra", "rede", "HCL", "")
        self.assertEqual((s["empresa"], s["cliente"], s["tipo"]), ("bekaa", "t4isb", "infra"))
        s = sugerir("nessenergy", "Alupdatalake", "Python", "datalake da Alup")
        self.assertEqual((s["empresa"], s["cliente"], s["tipo"]), ("ness", "alup", "dados"))
        self.assertEqual(sugerir("forense-io", "caso", None, "")["empresa"], "forense")
        self.assertEqual(sugerir("familia-almeida", "x", None, "")["empresa"], "pessoal")

    def test_empresa_pelo_nome_na_conta_pessoal(self):
        from pmo.regras import sugerir
        self.assertEqual(sugerir("resper1965", "ihOS", "TypeScript", "")["empresa"], "ionic")
        self.assertEqual(sugerir("resper1965", "n.360", "TypeScript", "")["empresa"], "ness")
        self.assertEqual(sugerir("resper1965", "Aegis-Auditor", "TypeScript", "")["empresa"], "bekaa")
        self.assertEqual(sugerir("resper1965", "esper-site", "Astro", "")["empresa"], "pessoal")
        self.assertIsNone(sugerir("resper1965", "qualquer", "Go", "")["empresa"])

    def test_tipo(self):
        from pmo.regras import sugerir
        tipo = lambda nome, ling=None, desc="": sugerir("resper1965", nome, ling, desc)["tipo"]
        self.assertEqual(tipo("stack-vps", "Shell"), "infra")
        self.assertEqual(tipo("esper-site", "Astro"), "site")
        self.assertEqual(tipo("ness-report-mcp", "TypeScript"), "agente")
        self.assertEqual(tipo("claude-skills", "Python"), "conhecimento")
        self.assertEqual(tipo("twyn-isms", None), "documento")
        self.assertEqual(tipo("n.sign", "TypeScript"), "app")

    def test_primeiro_paragrafo_do_readme(self):
        from pmo.regras import primeiro_paragrafo
        t = "# Titulo\n\n[![ci](x)](y)\n<p align=center><img src=a></p>\n\nPainel de **riscos** para a [Ness](https://n).\nSegunda linha.\n\nOutro paragrafo."
        self.assertEqual(primeiro_paragrafo(t), "Painel de riscos para a Ness. Segunda linha.")
        self.assertIsNone(primeiro_paragrafo("# so titulo\n"))
        self.assertEqual(len(primeiro_paragrafo("a" * 500)), 280)

    def test_classe_final_precedencia(self):
        from pmo.regras import aplicar_classes
        p = {"projetos": [{"id": "o/a", "tipo": "documento", "sugestao": {"empresa": "ness", "cliente": None, "tipo": "app"}},
                          {"id": "o/b", "tipo": None, "sugestao": {"empresa": None, "cliente": None, "tipo": "site"}}],
             "arquivados": []}
        aplicar_classes(p, {"o/a": {"empresa": "bekaa", "area": "orm", "cliente": "", "tipo": ""}})
        a, b = p["projetos"]
        self.assertEqual(a["classe"], {"empresa": "bekaa", "area": "orm", "cliente": None, "tipo": "documento", "linear": None, "estagio": None, "confirmada": True})
        self.assertEqual(b["classe"], {"empresa": None, "area": None, "cliente": None, "tipo": "site", "linear": None, "estagio": None, "confirmada": False})


class Tecnologias(unittest.TestCase):
    def test_detecta_pelos_arquivos_e_package_json(self):
        from pmo.regras import detectar_tecnologias
        caminhos = ["package.json", "apps/core/wrangler.jsonc", "supabase/config.toml", "Dockerfile",
                    "infra/main.tf", ".env.production", ".env.example", "pyproject.toml"]
        pkg = '{"dependencies": {"next": "15", "react": "19", "@supabase/supabase-js": "2"}, "devDependencies": {"@anthropic-ai/sdk": "1"}}'
        t = detectar_tecnologias(caminhos, pkg, "TypeScript")
        for esperado in ("typescript", "next.js", "react", "cloudflare", "supabase", "docker", "terraform", "python", "ia"):
            self.assertIn(esperado, t["tecnologias"])
        self.assertEqual(t["segredos_no_repo"], [".env.production"])

    def test_sem_nada(self):
        from pmo.regras import detectar_tecnologias
        self.assertEqual(detectar_tecnologias([], None, None), {"tecnologias": [], "segredos_no_repo": []})
        self.assertEqual(detectar_tecnologias(["package.json"], "lixo{", None)["tecnologias"], ["node"])

    def test_onde_ficam_os_segredos(self):
        from pmo.regras import segredos_esperados
        self.assertIn("Cloudflare: wrangler secret / Secrets Store", segredos_esperados(["cloudflare", "next.js"]))
        self.assertIn("Vercel: Environment Variables do projeto", segredos_esperados(["vercel"]))
        self.assertEqual(segredos_esperados([])[-1], "Desenvolvimento na VPS: projetos.env ou .envrc (nunca no repositório)")


class EstagioPeloPainel(unittest.TestCase):
    def test_marcar_parado_tira_do_alarme_e_recalcula_contadores(self):
        from pmo.regras import aplicar_classes
        p = {"projetos": [{"id": "o/a", "estagio": None, "estagio_sugerido": "em andamento", "esquecido": "sem atividade há 200 dias"},
                          {"id": "o/b", "estagio": None, "estagio_sugerido": "em andamento", "esquecido": "sem atividade há 30 dias"}],
             "arquivados": [], "a_destinar": [], "contadores": {"esquecidos": 2, "parados": 0}}
        aplicar_classes(p, {"o/a": {"estagio": "parado", "linear": "NESS-Core"}})
        a = p["projetos"][0]
        self.assertEqual((a["estagio"], a["esquecido"]), ("parado", None))
        self.assertEqual(a["classe"]["linear"], "NESS-Core")
        self.assertEqual((p["contadores"]["esquecidos"], p["contadores"]["parados"]), (1, 1))


class Tipos(unittest.TestCase):
    def test_state_aceita_tipos_novos(self):
        for t in ("site", "dados", "infra"):
            self.assertIn(t, TIPOS)
            self.assertEqual(ler_state(f"**Tipo:** {t}\n")["tipo"], t)


if __name__ == "__main__":
    unittest.main()
