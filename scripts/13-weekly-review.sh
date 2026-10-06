#!/usr/bin/env bash
# Rotina semanal: atualiza inventario, reclassifica, consolida dashboard.json e escreve o relatorio.
# Uso: weekly-review.sh [--now]   (--now e so semantico; a rotina e a mesma sob demanda)
set -uo pipefail
HOJE=$(date +%Y-%m-%d)
STATE=/srv/dev/state
BIN=/srv/dev/bin

# 1. inventario atualizado (faz fetch e reclassifica pelo ultimo commit)
bash "$BIN"/09-clonar-escopo.sh "$STATE"/escopo-auditoria.tsv >/dev/null 2>&1
bash "$BIN"/10-inventario.sh >/dev/null 2>&1

# 2. dashboard.json — so metadado de projeto. Sem codigo, sem dado de cliente, sem segredo.
python3 - "$HOJE" <<'PY'
import json,os,re,subprocess,sys,glob
hoje=sys.argv[1]
def campo(txt,nome):
    m=re.search(rf'^\*\*{nome}:\*\*\s*(.+)$',txt,re.M)
    return m.group(1).strip() if m else None
# so o escopo: dormente clonado em disco nao entra no painel
escopo={l.split('	')[3].strip() for l in open('/srv/dev/state/escopo-auditoria.tsv',encoding='utf-8').read().splitlines()[1:] if l.strip()}
projetos=[]
for d in sorted(glob.glob('/srv/dev/repos/*/*/')):
    if not os.path.isdir(os.path.join(d,'.git')): continue
    nome=os.path.basename(d.rstrip('/')); arv=os.path.basename(os.path.dirname(d.rstrip('/')))
    if nome not in escopo: continue
    st=os.path.join(d,'STATE.md')
    if not os.path.exists(st):
        projetos.append({'projeto':nome,'arvore':arv,'lacuna':'sem STATE.md'}); continue
    t=open(st,encoding='utf-8',errors='replace').read()
    try:
        ult=subprocess.run(['git','-C',d,'log','-1','--format=%cs'],capture_output=True,text=True,timeout=20).stdout.strip()
        dias=int(subprocess.run(['git','-C',d,'log','-1','--format=%ct'],capture_output=True,text=True,timeout=20).stdout.strip() or 0)
    except Exception: ult,dias='',0
    import time
    idade=int((time.time()-dias)/86400) if dias else None
    rev=sorted(glob.glob(f'/srv/dev/state/reviews/{nome}-*.md'))
    achado=''
    if rev:
        linhas=[l.strip() for l in open(rev[-1],encoding='utf-8',errors='replace') if l.strip()]
        achado=next((l for l in linhas if not l.startswith('#')),'')[:200]
    projetos.append({
        'projeto':nome,'arvore':arv,'trilha':campo(t,'Trilha') or 'geral',
        'status':campo(t,'Status'),'principal':campo(t,'Agente principal'),
        'revisor':campo(t,'Agente revisor'),'stack':campo(t,'Stack'),
        'ultimo_commit':ult,'dias_sem_commit':idade,
        'proximo_passo':campo(t,'Próximo passo sugerido'),
        'pendencias':campo(t,'Pendências conhecidas'),
        'ultimo_parecer':achado,'parecer_em':os.path.basename(rev[-1]) if rev else None,
    })
div=[p for p in projetos if (p.get('status') or '').startswith('ativo') and (p.get('dias_sem_commit') or 0)>90]
# uma linha por projeto, com os campos pendentes juntos: papel indefinido em 70 projetos
# e UMA decisao (por trilha), nao 70 — inflar a fila esconde o que realmente espera resposta
bloq=[]
for p in projetos:
    faltam=[c for c in ('principal','revisor','proximo_passo') if p.get(c) and re.search(r'A DEFINIR|A CONFIRMAR',p[c])]
    if faltam: bloq.append({'projeto':p['projeto'],'trilha':p.get('trilha'),'campos':faltam})
# 'sem CI' fica so no inventario: por decisao do Ricardo nao vira debito nem recomendacao
def limpa(v):
    return '; '.join(x.strip() for x in v.split(';') if 'sem CI' not in x).strip()
deb=[{'projeto':p['projeto'],'pendencias':limpa(p['pendencias'])} for p in projetos
     if p.get('pendencias') and 'nenhuma' not in p['pendencias'] and limpa(p['pendencias'])]
json.dump({'gerado_em':hoje,'projetos':projetos,
           'divergencia':[p['projeto'] for p in div],'bloqueio':bloq,'debito':deb},
          open('/srv/dev/state/dashboard.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(f"dashboard.json: {len(projetos)} projetos | divergencia {len(div)} | bloqueio {len(bloq)} | debito {len(deb)}")
PY

# 3. relatorio do que mudou
REL="$STATE/review-$HOJE.md"
{
echo "# Revisao semanal — $HOJE"
echo
python3 -c "
import json
d=json.load(open('/srv/dev/state/dashboard.json',encoding='utf-8'))
print(f\"Projetos acompanhados: {len(d['projetos'])}\")
print()
print('## Divergencia — marcados como ativo, sem commit ha mais de 90 dias')
print('\n'.join('- '+p for p in d['divergencia']) or '- nenhuma')
print()
print('## Bloqueio — esperando decisao do Ricardo')
from collections import Counter
cc=Counter(c for b in d['bloqueio'] for c in b['campos'])
for campo,n in cc.most_common(): print(f'- {campo}: {n} projeto(s)')
semrota=[b['projeto'] for b in d['bloqueio'] if 'proximo_passo' in b['campos']]
print(f\"- sem proximo passo declarado: {len(semrota)}\")
print()
print('## Debito por projeto')
for x in d['debito'][:40]: print(f\"- {x['projeto']}: {x['pendencias']}\")
"
echo
echo "## Debito tecnico (ponytail-debt)"
if [[ -f $HOME/.claude/.credentials.json ]]; then
  echo "(a consolidar — rodar ponytail-debt por projeto)"
else
  echo "Nao executado: o Claude Code ainda nao esta autenticado neste host."
fi
} > "$REL"
echo "relatorio: $REL"
