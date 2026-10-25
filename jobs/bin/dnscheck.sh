#!/usr/bin/env bash
# Verificacao diaria de DNS (substitui o workflow dnscheck.yml do dns-repair). Roda no clone de dns-repair
# (diretorio atual, REPO= do .job): python3 dnscheck.py --all e, se HOSTINGER_API existir e wpaudit.py tambem,
# python3 wpaudit.py. Somente leitura (os scripts so consultam as APIs). Segredos so do ambiente
# (CLOUDFLARE_API_TOKEN obrigatorio; HOSTINGER_API opcional); a saida completa fica em <estado>/<nome>.saida/
# (0640) e so contagens vao ao resumo.
# Uso: dnscheck.sh [nome-do-job]   (padrao dns-repair-dnscheck)
# rc 0 sem divergencia | 1 divergencia (dnscheck 1) ou wpaudit 1 | 2 erro de execucao ou pre-requisito ausente.
# Sobrescrevivel nos testes (so com STACK_TESTE=1): DNSCHECK_ESTADO.
set -uo pipefail
umask 027
nome=${1:-dns-repair-dnscheck}
[[ $nome =~ ^[a-z0-9-]+$ ]] || { echo "uso: dnscheck.sh [nome]"; exit 2; }
ESTADO=/srv/dev/state/jobs
[[ ${STACK_TESTE:-} == 1 ]] && ESTADO=${DNSCHECK_ESTADO:-$ESTADO}

[[ -n ${CLOUDFLARE_API_TOKEN:-} ]] || { echo "dnscheck: falta CLOUDFLARE_API_TOKEN no ambiente (43-segredos-guiado.sh job $nome)"; exit 2; }
[[ -f dnscheck.py ]] || { echo "dnscheck: dnscheck.py nao encontrado no diretorio do clone"; exit 2; }
saida=$ESTADO/$nome.saida
rm -rf "$saida"; mkdir -p "$saida" || { echo "dnscheck: nao criei $saida"; exit 2; }

python3 -I dnscheck.py --all > "$saida/dnscheck.txt" 2>&1; drc=$?
# -I ignora o diretorio do script no sys.path; os scripts do repo importam lib/ por caminho proprio (sys.path.insert)
wrc=-; wtxt=
if [[ -n ${HOSTINGER_API:-} && -f wpaudit.py ]]; then
  python3 -I wpaudit.py > "$saida/wpaudit.txt" 2>&1; wrc=$?
  wtxt=", wpaudit rc=$wrc"
fi
fails=$(grep -c '^  FAIL ' "$saida/dnscheck.txt" || true)
warns=$(grep -c '^  WARN ' "$saida/dnscheck.txt" || true)

rc=0
for c in "$drc" "$wrc"; do
  [[ $c == - ]] && continue
  (( c == 1 && rc == 0 )) && rc=1
  (( c > 1 )) && rc=2
done
estado=ok; (( rc == 1 )) && estado=DIVERGENTE; (( rc == 2 )) && estado="ERRO DE EXECUCAO"
echo "dnscheck $nome: $estado (dnscheck rc=$drc, FAIL=$fails WARN=$warns$wtxt); detalhe em $saida"
exit $rc
