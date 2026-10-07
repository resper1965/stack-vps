import unittest
from pmo.regras import ler_state, estagio_sugerido, esquecido


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


if __name__ == "__main__":
    unittest.main()
