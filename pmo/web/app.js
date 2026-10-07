// Painel do PMO. Todo texto vindo dos dados entra por textContent (nunca innerHTML).
"use strict";

const CORES = {
  "ideia": "var(--e-ideia)", "em andamento": "var(--e-andamento)", "em revisão": "var(--e-revisao)",
  "entregue": "var(--e-entregue)", "encerrado": "var(--e-encerrado)", "parado": "var(--e-parado)",
};
const ESTAGIOS = Object.keys(CORES);
const TIPOS = ["app", "site", "agente", "dados", "infra", "documento", "conhecimento"];
const EMPRESAS = ["ness", "bekaa", "ionic", "forense", "pessoal", "trustness"];
const SEM_CLONE = "(sem clone na VPS)";
const RAIZ = "/srv/dev/projetos/";
let dados = null;

function el(tag, attrs = {}, ...filhos) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue;
    if (k === "class") n.className = v;
    else if (k === "style") n.setAttribute("style", v);
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v === true ? "" : v);
  }
  for (const f of filhos.flat()) if (f !== null && f !== undefined && f !== false) n.append(f instanceof Node ? f : String(f));
  return n;
}
const $ = (id) => document.getElementById(id);
const estagio = (p) => p.estagio || p.estagio_sugerido || "em andamento";
const pastaDe = (p) => (p.pasta && p.pasta.startsWith(RAIZ)) ? p.pasta.slice(RAIZ.length).split("/")[0] : SEM_CLONE;
const classe = (p) => p.classe || {};
const tipoDe = (p) => classe(p).tipo || p.tipo || "";
const quando = (dias) => dias === 0 ? "hoje" : dias === 1 ? "ontem" : dias >= 9999 ? "sem atividade" : `${dias} dias`;
// repositorios de cliente: so arquivar (o executor recusa excluir de qualquer forma)
const ehCliente = (p) => ["nessenergy/alupdatalake", "nessenergy/sitealupar"].includes((p.id || "").toLowerCase());

function toast(msg) {
  const t = $("toast"); t.textContent = msg; t.hidden = false;
  clearTimeout(toast._t); toast._t = setTimeout(() => (t.hidden = true), 3500);
}

async function acao(acao, alvo, confirmacao, extra = {}) {
  try {
    const r = await fetch("acao", { method: "POST", headers: { "Content-Type": "application/json", "X-PMO": "1" },
      body: JSON.stringify({ acao, alvo, confirmacao, ...extra }) });
    if (!r.ok) throw new Error(await r.text());
    if (acao === "classificar") { toast(`${alvo} classificado.`); fechar(); await carregar(); }
    else toast(`Pedido registrado: ${acao} ${alvo}. Executa em até 1 minuto.`);
  } catch (e) { toast(`Não foi possível registrar: ${e.message}`); }
}

function etiquetaEstagio(p) {
  const e = estagio(p), sug = !p.estagio;
  return el("span", { class: `etiqueta estagio${sug ? " sugerido" : ""}`, style: `--cor:${CORES[e] || CORES.parado}`,
    title: sug ? "estágio sugerido pelo PMO — confirmar no STATE.md" : "" }, sug ? `~${e}` : e);
}

function cartao(p) {
  const passo = (p.analise && p.analise.proximos_passos && p.analise.proximos_passos[0] && p.analise.proximos_passos[0].descricao) || p.proximo;
  return el("button", { class: "cartao", style: `--cor:${CORES[estagio(p)] || CORES.parado}`, onclick: () => abrir(p) },
    el("h3", {}, el("span", {}, p.nome), p.esquecido ? el("span", { class: "marca-esquecido", title: p.esquecido }, "●") : null),
    el("div", { class: "dono" }, [classe(p).empresa, classe(p).area, classe(p).cliente && `cliente ${classe(p).cliente}`]
      .filter(Boolean).join(" · ") || `${p.dono} · a classificar`),
    p.resumo ? el("div", { class: "resumo" }, p.resumo) : null,
    el("div", { class: "linha" }, etiquetaEstagio(p), tipoDe(p) ? el("span", { class: "etiqueta" }, tipoDe(p)) : null,
      ...(p.tecnologias || []).filter((t) => t !== (p.linguagem || "").toLowerCase()).slice(0, 3).map((t) => el("span", { class: "etiqueta tec" }, t)),
      (p.segredos_no_repo || []).length ? el("span", { class: "etiqueta ruim", title: p.segredos_no_repo.join(", ") }, "segredo no repo") : null,
      el("span", { class: "etiqueta" }, quando(p.dias)),
      p.prs ? el("span", { class: "etiqueta" }, `${p.prs} PR`) : null,
      p.ci === "failure" ? el("span", { class: "etiqueta ruim" }, "CI vermelho") : null),
    el("div", { class: "passo" }, passo ? `→ ${passo}` : (p.esquecido || "sem próximo passo")));
}

function abrir(p) {
  const d = $("detalhe"); d.replaceChildren();
  const a = p.analise || {};
  const vscode = p.pasta ? "vscode://vscode-remote/ssh-remote+stack-agente" + p.pasta.split("/").map(encodeURIComponent).join("/") : null;
  const github = typeof p.url === "string" && p.url.startsWith("https://github.com/") ? p.url : null;
  // append nativo escreve "null" para secao vazia: filtrar antes
  d.append(...[
    el("header", {}, el("div", {}, el("h2", {}, p.nome), el("div", { class: "sub" }, `${p.dono} · ${p.privado ? "privado" : "público"}`)),
      el("button", { class: "fechar", "aria-label": "Fechar", onclick: fechar }, "×")),
    p.esquecido ? el("section", {}, el("div", { class: "alerta-caixa" }, `Esquecido: ${p.esquecido}. Retome, marque como parado ou descarte.`)) : null,
    p.resumo ? el("section", {}, el("h4", {}, "Do que se trata"), el("p", {}, p.resumo)) : null,
    (p.segredos_no_repo || []).length ? el("section", {}, el("div", { class: "alerta-caixa" },
      `Arquivo com cara de segredo versionado: ${p.segredos_no_repo.join(", ")}. Tire do repositório, troque o valor e guarde onde indicado abaixo.`)) : null,
    (p.tecnologias || []).length ? el("section", {}, el("h4", {}, "Tecnologias"),
      el("div", { class: "linha" }, p.tecnologias.map((t) => el("span", { class: "etiqueta tec" }, t)))) : null,
    (p.segredos_onde || []).length ? el("section", {}, el("h4", {}, "Onde ficam os segredos"),
      el("ul", {}, p.segredos_onde.map((s) => el("li", {}, s)))) : null,
    el("section", {}, el("dl", { class: "kv" },
      el("dt", {}, "Empresa"), el("dd", {}, (classe(p).empresa || "a classificar") + (classe(p).confirmada ? "" : " (sugerida)")),
      el("dt", {}, "Área"), el("dd", {}, classe(p).area || "—"),
      el("dt", {}, "Cliente"), el("dd", {}, classe(p).cliente || "—"),
      el("dt", {}, "Linear"), el("dd", {}, classe(p).linear || "—"),
      el("dt", {}, "Estágio"), el("dd", {}, etiquetaEstagio(p)),
      el("dt", {}, "Tipo"), el("dd", {}, tipoDe(p) || "não declarado"),
      el("dt", {}, "Última atividade"), el("dd", {}, quando(p.dias)),
      el("dt", {}, "Pasta na VPS"), el("dd", {}, p.pasta || "sem clone na VPS"),
      el("dt", {}, "PRs / issues"), el("dd", {}, `${p.prs || 0} / ${p.issues || 0}`),
      el("dt", {}, "CI"), el("dd", {}, p.ci || "sem CI"))),
    a.situacao ? el("section", {}, el("h4", {}, "Situação"), el("p", {}, a.situacao)) : null,
    el("section", {}, el("h4", {}, "Próximos passos"),
      a.proximos_passos && a.proximos_passos.length
        ? el("ol", {}, a.proximos_passos.map((s) => el("li", {}, s.descricao,
            s.issue_sugerida ? el("button", { class: "bt", style: "margin-left:6px;padding:2px 8px;font-size:12px",
              onclick: () => navigator.clipboard.writeText(`${s.issue_sugerida.titulo}\n\n${s.issue_sugerida.corpo}`).then(() => toast("Issue copiada")) }, "copiar issue") : null)))
        : el("p", {}, p.proximo || "Nenhum declarado. Peça ao agente no projeto ou preencha o STATE.md.")),
    a.bloqueios && a.bloqueios.length ? el("section", {}, el("h4", {}, "Bloqueios"), el("ul", {}, a.bloqueios.map((b) => el("li", {}, b)))) : null,
    a.riscos && a.riscos.length ? el("section", {}, el("h4", {}, "Riscos"), el("ul", {}, a.riscos.map((b) => el("li", {}, b)))) : null,
    p.wip && p.wip.length ? el("section", {}, el("h4", {}, "Trabalho em andamento salvo"),
      el("ul", {}, p.wip.map((w) => el("li", {}, w))), el("p", { class: "nota" }, "Decida se vira PR ou se descarta a branch.")) : null,
    el("section", { class: "botoes" },
      vscode ? el("a", { class: "bt primario", href: vscode }, "Abrir no VS Code") : null,
      github ? el("a", { class: "bt", href: github, target: "_blank", rel: "noopener" }, "Abrir no GitHub") : null,
      !p.pasta && !p.arquivado ? el("button", { class: "bt primario", onclick: () => clonar(p) }, "Clonar na VPS") : null,
      el("button", { class: "bt", onclick: () => classificar(p) }, "Classificar"),
      !["parado", "encerrado", "entregue"].includes(estagio(p)) ? el("button", { class: "bt",
        onclick: () => acao("classificar", p.id, null, { classe: classeAtual(p, { estagio: "parado" }) }) }, "Marcar como parado") : null,
      p.arquivado
        ? el("button", { class: "bt", onclick: () => acao("restaurar", p.id) }, "Restaurar")
        : el("button", { class: "bt perigo", onclick: () => descartar(p) }, "Descartar"))].filter(Boolean));
  $("veu").hidden = false; d.hidden = false; d.scrollTop = 0;
}
function fechar() { $("detalhe").hidden = true; $("veu").hidden = true; }

function descartar(p) {
  const dlg = $("dlg-descartar"), cliente = ehCliente(p);
  $("dlg-nome").textContent = p.nome; $("dlg-confirma-nome").textContent = p.nome; $("dlg-confirma").value = "";
  $("opcao-excluir").hidden = cliente; $("dlg-cliente").hidden = !cliente;
  dlg.querySelector('input[value="arquivar"]').checked = true; $("confirma-bloco").hidden = true;
  dlg.onchange = () => { $("confirma-bloco").hidden = dlg.querySelector('input[name="modo"]:checked').value !== "excluir"; };
  dlg.onclose = () => {
    if (dlg.returnValue !== "ok") return;
    const modo = dlg.querySelector('input[name="modo"]:checked').value;
    if (modo === "excluir") {
      if ($("dlg-confirma").value.trim() !== p.nome) { toast("Nome não confere. Nada foi feito."); return; }
      acao("excluir", p.id, $("dlg-confirma").value.trim());
    } else acao("arquivar", p.id);
  };
  dlg.showModal();
}

const todos = () => [...dados.projetos, ...(dados.arquivados || [])];
const distintos = (f) => [...new Set(todos().map(f).filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt-BR"));

function preencher(lista, valores) { $(lista).replaceChildren(...valores.map((v) => el("option", { value: v }))); }

// classe salva hoje (para nao apagar campos ao mudar so um)
const classeAtual = (p, mudar = {}) => ({ empresa: classe(p).empresa || "", area: classe(p).area || "",
  cliente: classe(p).cliente || "", tipo: tipoDe(p), linear: classe(p).linear || "", estagio: classe(p).estagio || "", ...mudar });

function classificar(p) {
  const dlg = $("dlg-classificar"), c = classe(p);
  $("cls-nome").textContent = p.nome;
  $("cls-empresa").replaceChildren(el("option", { value: "" }, "a classificar"), ...EMPRESAS.map((e) => el("option", { value: e }, e)));
  $("cls-tipo").replaceChildren(el("option", { value: "" }, "não declarado"), ...TIPOS.map((t) => el("option", { value: t }, t)));
  $("cls-empresa").value = c.empresa || ""; $("cls-tipo").value = tipoDe(p);
  $("cls-area").value = c.area || ""; $("cls-cliente").value = c.cliente || ""; $("cls-linear").value = c.linear || "";
  $("cls-estagio").replaceChildren(el("option", { value: "" }, "pelo STATE.md / sugerido"), ...ESTAGIOS.map((e) => el("option", { value: e }, e)));
  $("cls-estagio").value = c.estagio || "";
  preencher("lista-linear", distintos((x) => classe(x).linear));
  preencher("lista-areas", distintos((x) => classe(x).area)); preencher("lista-clientes", distintos((x) => classe(x).cliente));
  dlg.onclose = () => {
    if (dlg.returnValue !== "ok") return;
    acao("classificar", p.id, null, { classe: { empresa: $("cls-empresa").value, area: $("cls-area").value.trim(),
      cliente: $("cls-cliente").value.trim(), tipo: $("cls-tipo").value, linear: $("cls-linear").value.trim(),
      estagio: $("cls-estagio").value } });
  };
  dlg.showModal();
}

function clonar(p) {
  const dlg = $("dlg-clonar"), pastas = distintos((x) => pastaDe(x) === SEM_CLONE ? null : pastaDe(x));
  // sugestao: a pasta onde ja estao mais projetos da mesma empresa; senao o nome da empresa
  const conta = {};
  for (const x of todos()) if (classe(x).empresa && classe(x).empresa === classe(p).empresa && pastaDe(x) !== SEM_CLONE)
    conta[pastaDe(x)] = (conta[pastaDe(x)] || 0) + 1;
  const sugerida = Object.entries(conta).sort((a, b) => b[1] - a[1])[0]?.[0] || classe(p).empresa || "";
  $("cln-nome").textContent = p.nome; $("cln-pasta").value = sugerida; preencher("lista-pastas", pastas);
  const mostrar = () => { $("cln-destino").textContent = `vai para ${RAIZ}${$("cln-pasta").value.trim() || "…"}/${p.nome}`; };
  $("cln-pasta").oninput = mostrar; mostrar();
  dlg.onclose = () => { if (dlg.returnValue === "ok" && $("cln-pasta").value.trim()) acao("clonar", p.id, null, { pasta: $("cln-pasta").value.trim() }); };
  dlg.showModal();
}

function opcoes(sel, valores) {
  const atual = sel.value;
  while (sel.options.length > 1) sel.remove(1);
  for (const v of valores) sel.append(el("option", { value: v }, v));
  sel.value = atual;
}

function filtrar() {
  const q = $("busca").value.trim().toLowerCase(), fp = $("f-pasta").value, fd = $("f-dono").value,
    ft = $("f-tipo").value, fe = $("f-estagio").value, fem = $("f-empresa").value, fa = $("f-area").value,
    fte = $("f-tec").value;
  const lista = dados.projetos.filter((p) =>
    (!q || p.nome.toLowerCase().includes(q) || p.dono.toLowerCase().includes(q) || (p.resumo || "").toLowerCase().includes(q)) &&
    (!fp || pastaDe(p) === fp) && (!fd || p.dono === fd) && (!ft || tipoDe(p) === ft) && (!fe || estagio(p) === fe) &&
    (!fem || (classe(p).empresa || "a classificar") === fem) && (!fa || classe(p).area === fa) &&
    (!fte || (fte === "segredo no repo" ? (p.segredos_no_repo || []).length : (p.tecnologias || []).includes(fte))));
  lista.sort((a, b) => (b.esquecido ? 1 : 0) - (a.esquecido ? 1 : 0) || a.dias - b.dias);
  const g = $("grade"); g.replaceChildren();
  if (!lista.length) g.append(el("div", { class: "vazio" }, "Nenhum projeto com esses filtros."));
  else g.append(...lista.map(cartao));
}

function render() {
  const c = dados.contadores;
  const quandoGerado = new Date(dados.gerado_em).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
  const at = $("atualizado"); at.textContent = `atualizado ${quandoGerado}` + (dados.coleta_incompleta ? " · coleta incompleta" : "");
  at.classList.toggle("incompleta", !!dados.coleta_incompleta);

  const cont = $("contadores"); cont.replaceChildren();
  const add = (n, rotulo, filtro, alerta) => cont.append(el("button", { class: `contador${alerta && n ? " alerta" : ""}`,
    onclick: filtro }, el("b", {}, n), el("span", {}, rotulo)));
  add(c.projetos, "projetos", () => { $("f-estagio").value = ""; filtrar(); });
  add(c.esquecidos, "esquecidos", () => $("faixa-esquecidos").scrollIntoView({ behavior: "smooth" }), true);
  add(c.em_andamento, "em andamento", () => { $("f-estagio").value = "em andamento"; filtrar(); });
  add(c.em_revisao, "em revisão", () => { $("f-estagio").value = "em revisão"; filtrar(); });
  add(c.parados, "parados", () => { $("f-estagio").value = "parado"; filtrar(); });
  add(c.prs_abertos, "PRs abertos");
  add(c.ci_vermelho, "CI vermelho", null, true);
  add(c.a_destinar, "a destinar", () => $("secao-destinar").scrollIntoView({ behavior: "smooth" }));

  const esq = dados.projetos.filter((p) => p.esquecido).sort((a, b) => b.dias - a.dias);
  $("faixa-esquecidos").hidden = !esq.length; $("qtd-esquecidos").textContent = esq.length;
  $("lista-esquecidos").replaceChildren(...esq.map((p) => el("button", { class: "chip", onclick: () => abrir(p) }, p.nome, el("small", {}, p.esquecido))));

  const m = dados.mudou_desde_ontem || {};
  const linhas = [["Novos", m.novos], ["Mudaram de estágio", m.mudou_estagio], ["Viraram esquecidos", m.viraram_esquecidos]]
    .filter(([, l]) => l && l.length);
  $("mudou").hidden = !linhas.length;
  $("mudou-corpo").replaceChildren(...linhas.map(([t, l]) => el("p", {}, el("b", {}, `${t}: `), l.join(", "))));

  opcoes($("f-pasta"), [...new Set(dados.projetos.map(pastaDe))].sort());
  opcoes($("f-dono"), [...new Set(dados.projetos.map((p) => p.dono))].sort());
  opcoes($("f-tipo"), TIPOS); opcoes($("f-estagio"), ESTAGIOS);
  opcoes($("f-empresa"), [...EMPRESAS, "a classificar"]); opcoes($("f-area"), distintos((x) => classe(x).area));
  opcoes($("f-tec"), ["segredo no repo", ...[...new Set(dados.projetos.flatMap((x) => x.tecnologias || []))].sort()]);
  filtrar();

  const dest = dados.a_destinar || [];
  $("secao-destinar").hidden = !dest.length; $("qtd-destinar").textContent = dest.length;
  $("lista-destinar").replaceChildren(...dest.map((x) => el("div", { class: "item" },
    el("span", {}, `${x.caminho} `, el("small", { style: "color:var(--suave)" }, `${x.arquivos} arquivos`)),
    el("span", { class: "acoes" },
      el("button", { class: "bt", onclick: () => acao("trazer", x.id) }, "Trazer"),
      el("button", { class: "bt perigo", onclick: () => { if (confirm(`Descartar ${x.caminho}? Vai para a lixeira da VPS por 30 dias.`)) acao("descartar", x.id); } }, "Descartar")))));

  const arq = dados.arquivados || [];
  $("secao-arquivados").hidden = !arq.length; $("qtd-arquivados").textContent = arq.length;
  $("lista-arquivados").replaceChildren(...arq.map((p) => el("div", { class: "item" },
    el("span", {}, `${p.dono}/${p.nome}`),
    el("span", { class: "acoes" }, el("button", { class: "bt", onclick: () => abrir(p) }, "Ver"),
      el("button", { class: "bt", onclick: () => acao("restaurar", p.id) }, "Restaurar")))));
}

async function carregar() {
  // so arquivo local (exemplo.json para demonstracao); nunca dado de outra origem
  const pedido = new URLSearchParams(location.search).get("dados");
  const fonte = pedido && /^[\w.-]+\.json$/.test(pedido) ? pedido : "painel.json";
  try {
    const r = await fetch(`${fonte}?t=${Date.now()}`);
    dados = await r.json();
    render();
  } catch (e) { $("atualizado").textContent = `não foi possível carregar os dados (${e.message})`; }
}

for (const id of ["busca", "f-empresa", "f-area", "f-tec", "f-pasta", "f-dono", "f-tipo", "f-estagio"]) $(id).addEventListener("input", filtrar);
$("veu").addEventListener("click", fechar);
document.addEventListener("keydown", (e) => { if (e.key === "Escape") fechar(); });
carregar();
setInterval(carregar, 5 * 60 * 1000);
