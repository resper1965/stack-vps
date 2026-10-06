import unittest
from pmo.resumo import texto


class Resumo(unittest.TestCase):
    def test_lista_esquecidos(self):
        p = {"projetos": [{"id": "o/a", "nome": "a", "esquecido": "sem atividade há 20 dias", "dias": 20},
                          {"id": "o/b", "nome": "b", "esquecido": None, "dias": 1},
                          {"id": "o/c", "nome": "c", "esquecido": "em revisão há 40 dias", "dias": 40}]}
        titulo, msg = texto(p)
        self.assertEqual(titulo, "PMO: 2 projetos esquecidos")
        self.assertLess(msg.index("c —"), msg.index("a —"), "mais antigo primeiro")
        self.assertIn("http://100.76.167.6:8080", msg)

    def test_nada_esquecido(self):
        self.assertIsNone(texto({"projetos": [{"id": "o/a", "nome": "a", "esquecido": None, "dias": 1}]}))


if __name__ == "__main__":
    unittest.main()
