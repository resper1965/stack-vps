"""Regras puras do PMO: leitura do STATE.md, estágio sugerido e detecção de projeto esquecido."""
import re
import unicodedata

TIPOS = ("app", "documento", "conhecimento", "agente")
ESTAGIOS = ("ideia", "em andamento", "em revisão", "entregue", "encerrado", "parado")
INATIVOS = ("encerrado", "parado", "entregue")
LIMITE_ANDAMENTO = 14
LIMITE_REVISAO = 30


def _sem_acento(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def _campo(texto, nome):
    alvo = _sem_acento(nome).lower()
    for linha in texto.splitlines():
        m = re.match(r"^\*\*([^*]+):\*\*\s*(.*)$", linha.strip())
        if m and _sem_acento(m.group(1)).strip().lower() == alvo:
            v = m.group(2).strip()
            return None if not v or v.upper().startswith("A DEFINIR") else v
    return None


def ler_state(texto):
    """Extrai tipo, estágio e próximo passo de um STATE.md; inválido ou ausente vira None."""
    if not texto:
        return {"tipo": None, "estagio": None, "proximo": None}
    tipo = (_campo(texto, "Tipo") or "").lower() or None
    est = (_campo(texto, "Estágio") or "").lower() or None
    if est:
        est = next((e for e in ESTAGIOS if _sem_acento(e) == _sem_acento(est)), None)
    return {"tipo": tipo if tipo in TIPOS else None, "estagio": est, "proximo": _campo(texto, "Próximo passo")}


def estagio_sugerido(dias_sem_atividade, prs_abertos, arquivado):
    if arquivado:
        return "encerrado"
    if dias_sem_atividade > 90:
        return "parado"
    if prs_abertos > 0:
        return "em revisão"
    return "em andamento"


def esquecido(estagio, dias, proximo, arquivado, declarado=True):
    """Motivo pelo qual o projeto está esquecido, ou None."""
    if arquivado or estagio in INATIVOS:
        return None
    est = estagio or "em andamento"
    if est == "em revisão" and dias > LIMITE_REVISAO:
        return f"em revisão há {dias} dias"
    if est in ("em andamento", "ideia") and dias > LIMITE_ANDAMENTO:
        return f"sem atividade há {dias} dias"
    if declarado and not proximo:
        return "sem próximo passo"
    return None
