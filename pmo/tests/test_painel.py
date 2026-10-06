import os, tempfile, unittest
from datetime import datetime, timezone
from pmo.painel import gerar, a_destinar

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


if __name__ == "__main__":
    unittest.main()
