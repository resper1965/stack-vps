#!/usr/bin/env bash
# Varredura de seguranca (substitui o CodeQL dos workflows desligados): semgrep + gitleaks + osv-scanner sobre um
# clone. So le o diretorio; resultado em <estado>/<nome>.varredura/ (semgrep.sarif/json, gitleaks.json, osv.json),
# sempre redigido (gitleaks --redact; nenhum segredo achado e impresso). Imprime UMA linha de resumo.
# Uso: varredura.sh <diretorio-clonado> <nome>
# rc 0 limpo | 10 ACHADOS (segredo gitleaks, osv High/Critical ou semgrep ERROR; nao e falha) | 2 ferramenta ausente/falhou/uso.
# Sobrescreviveis nos testes (so com STACK_TESTE=1): VARREDURA_ESTADO.
set -uo pipefail
umask 027
dir=${1:-}; nome=${2:-}
[[ -d $dir && $nome =~ ^[a-z0-9-]+$ ]] || { echo "uso: varredura.sh <diretorio> <nome ([a-z0-9-]+)>"; exit 2; }
export PATH="$HOME/.local/bin:$PATH"
ESTADO=/srv/dev/state/jobs
[[ ${STACK_TESTE:-} == 1 ]] && ESTADO=${VARREDURA_ESTADO:-$ESTADO}

faltam=()
for t in semgrep gitleaks osv-scanner python3; do command -v "$t" >/dev/null 2>&1 || faltam+=("$t"); done
if (( ${#faltam[@]} )); then
  echo "varredura $nome: ferramenta ausente (${faltam[*]}); rode scripts/46-ferramentas-varredura.sh como agente"; exit 2
fi

saida=$ESTADO/$nome.varredura
rm -rf "$saida"; mkdir -p "$saida" || { echo "varredura $nome: nao criei $saida"; exit 2; }
falha=()

# semgrep: sem --error (ele sairia 1 por qualquer achado); a severidade vem do JSON. Saida do comando descartada.
semgrep scan --config p/default --metrics=off --quiet --disable-version-check \
  --json-output "$saida/semgrep.json" --sarif-output "$saida/semgrep.sarif" "$dir" >/dev/null 2>&1
[[ -s $saida/semgrep.json ]] || falha+=("semgrep")

# gitleaks: --redact tira o segredo do relatorio; stdout/stderr descartados. Exit 0 sempre: a contagem vem do JSON.
gitleaks detect --source "$dir" --redact --no-banner --exit-code 0 \
  --report-format json --report-path "$saida/gitleaks.json" >/dev/null 2>&1
[[ -s $saida/gitleaks.json ]] || falha+=("gitleaks")

# osv-scanner: rc 0 limpo, 1 com vulnerabilidades, 128 sem dependencias; o resto e erro da ferramenta
osv-scanner scan source -r --format json "$dir" > "$saida/osv.json" 2>/dev/null
orc=$?
case $orc in
  0|1) ;;
  128) echo '{"results":[]}' > "$saida/osv.json" ;;
  *) falha+=("osv-scanner") ;;
esac
(( orc == 128 || orc <= 1 )) && [[ ! -s $saida/osv.json ]] && echo '{"results":[]}' > "$saida/osv.json"

if (( ${#falha[@]} )); then
  echo "varredura $nome: ferramenta falhou (${falha[*]}); sem resultado confiavel"; exit 2
fi

python3 -I - "$nome" "$saida" <<'PY'
import json, sys
nome, d = sys.argv[1], sys.argv[2]
rank = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1}
sg = {"ERROR": 0, "WARNING": 0, "INFO": 0}
for r in json.load(open(d + "/semgrep.json")).get("results", []):
    s = str(r.get("extra", {}).get("severity", "INFO")).upper()
    sg[s if s in sg else "INFO"] += 1
gl = json.load(open(d + "/gitleaks.json"))
n_gl = len(gl) if isinstance(gl, list) else 0
osv = {k: 0 for k in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN")}
def nivel(texto, score):
    t = str(texto or "").upper()
    if t == "MODERATE": t = "MEDIUM"
    if t in rank: return t
    try: x = float(score)
    except (TypeError, ValueError): return "UNKNOWN"
    return "CRITICAL" if x >= 9 else "HIGH" if x >= 7 else "MEDIUM" if x >= 4 else "LOW" if x > 0 else "UNKNOWN"
for res in json.load(open(d + "/osv.json")).get("results") or []:
    for pkg in res.get("packages") or []:
        vulns = {v.get("id"): v for v in pkg.get("vulnerabilities") or []}
        for g in pkg.get("groups") or []:
            sev = nivel(None, g.get("max_severity"))
            if sev == "UNKNOWN":   # sem CVSS: usa o pior rotulo textual dos avisos do grupo
                for i in g.get("ids") or []:
                    c = nivel((vulns.get(i, {}).get("database_specific") or {}).get("severity"), None)
                    if rank.get(c, 0) > rank.get(sev, 0): sev = c
            osv[sev] += 1
bad = []
if n_gl: bad.append("segredos")
if osv["CRITICAL"] or osv["HIGH"]: bad.append("osv alto/critico")
if sg["ERROR"]: bad.append("semgrep ERROR")
print("varredura %s: semgrep ERROR=%d WARNING=%d INFO=%d | gitleaks segredos=%d | osv CRITICAL=%d HIGH=%d MEDIUM=%d LOW=%d sem-nivel=%d | %s"
      % (nome, sg["ERROR"], sg["WARNING"], sg["INFO"], n_gl, osv["CRITICAL"], osv["HIGH"], osv["MEDIUM"], osv["LOW"],
         osv["UNKNOWN"], "ACHADOS (" + ", ".join(bad) + ")" if bad else "ok"))
sys.exit(10 if bad else 0)
PY
