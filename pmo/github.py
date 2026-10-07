"""Cliente mínimo da API REST do GitHub (só biblioteca padrão)."""
import base64
import json
import re
import urllib.error
import urllib.request

API = "https://api.github.com"


class GitHub:
    def __init__(self, token, abrir=urllib.request.urlopen):
        self.token, self._abrir, self._login = token, abrir, None

    def _req(self, caminho, metodo="GET", corpo=None):
        url = caminho if caminho.startswith("http") else API + caminho
        dados = json.dumps(corpo).encode() if corpo is not None else None
        req = urllib.request.Request(url, data=dados, method=metodo, headers={
            "Authorization": f"Bearer {self.token}", "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "stack-pmo"})
        for tentativa in (1, 2):  # leitura tenta de novo uma vez em 5xx ou falha de rede; escrita nao
            try:
                with self._abrir(req, timeout=30) as r:
                    txt = r.read()
                    return (json.loads(txt) if txt else None), (r.headers.get("Link") or "")
            except urllib.error.HTTPError as e:
                if e.code < 500 or tentativa == 2 or metodo != "GET":
                    raise
            except urllib.error.URLError:
                if tentativa == 2 or metodo != "GET":
                    raise

    def get(self, caminho):
        return self._req(caminho)[0]

    def paginas(self, caminho):
        itens, url = [], caminho
        while url:
            corpo, link = self._req(url)
            itens.extend(corpo or [])
            m = re.search(r'<([^>]+)>;\s*rel="next"', link)
            url = m.group(1) if m else None
        return itens

    def login(self):
        if self._login is None:
            self._login = self.get("/user")["login"]
        return self._login

    def repos(self, dono):
        if dono.lower() == self.login().lower():
            return self.paginas("/user/repos?affiliation=owner&visibility=all&per_page=100")
        try:
            return self.paginas(f"/orgs/{dono}/repos?type=all&per_page=100")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            return self.paginas(f"/users/{dono}/repos?per_page=100")

    def state_md(self, dono, repo):
        return self._texto(f"/repos/{dono}/{repo}/contents/STATE.md")

    def readme(self, dono, repo):
        return self._texto(f"/repos/{dono}/{repo}/readme")

    def _texto(self, caminho):
        try:
            c = self.get(caminho)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
        return base64.b64decode(c.get("content", "")).decode("utf-8", "replace")

    def resumo(self, dono, repo, issues_e_prs):
        prs = len(self.paginas(f"/repos/{dono}/{repo}/pulls?state=open&per_page=100"))
        try:
            runs = self.get(f"/repos/{dono}/{repo}/actions/runs?per_page=1").get("workflow_runs") or []
            ci = runs[0].get("conclusion") or runs[0].get("status") if runs else None
        except urllib.error.HTTPError:
            ci = None
        ramos = [b["name"] for b in self.paginas(f"/repos/{dono}/{repo}/branches?per_page=100")]
        wip = [b for b in ramos if b.startswith("wip/") or "laptop-wip" in b]
        return {"prs": prs, "issues": max(0, issues_e_prs - prs), "ci": ci, "wip": wip}

    # ações (usadas pelo executor)
    def arquivar(self, dono, repo, valor=True):
        self._req(f"/repos/{dono}/{repo}", "PATCH", {"archived": valor})

    def excluir(self, dono, repo):
        self._req(f"/repos/{dono}/{repo}", "DELETE")
