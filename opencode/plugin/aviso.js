// stack-vps (marcador: a copia do repo e a unica que o 36-opencode.sh atualiza)
// Plugin do OpenCode: avisa no celular (ntfy via alertar.sh) quando o agente fica ocioso depois de
// trabalhar um bom tempo. Falha do alerta nunca derruba o OpenCode. O segredo mora so no aviso.env:
// o plugin passa ao alertar.sh apenas o CAMINHO dele, por variavel de ambiente (nada no argv).
import { execFile } from "node:child_process"
import { basename } from "node:path"

const MIN_OCUPADA_S = 120
const ALERTA = "/usr/local/lib/stack-vps/alertar.sh"
const ALERTA_ENV = "/srv/dev/secrets/aviso.env"

const executaPadrao = (cmd, args, env) =>
  new Promise((ok, erro) =>
    execFile(cmd, args, { env: { ...process.env, ...env }, timeout: 20000 }, (e) => (e ? erro(e) : ok())))

// O unico export e o plugin (o OpenCode chama todo export como plugin); `exec` e `agora` no contexto
// existem para os testes, o OpenCode nao os passa.
export const AvisoPlugin = async (ctx = {}) => {
  const exec = ctx.exec ?? executaPadrao
  const agora = ctx.agora ?? Date.now
  const sessoes = new Map() // id -> { info, desde, avisado }
  const de = (id) => {
    if (!sessoes.has(id)) sessoes.set(id, { info: null, desde: null, avisado: true })
    return sessoes.get(id)
  }

  async function ocioso(id) {
    const s = de(id)
    if (s.avisado || s.desde === null) return
    s.avisado = true // no maximo um aviso por transicao para ocioso
    if (agora() - s.desde < MIN_OCUPADA_S * 1000) return
    const dir = s.info?.directory ?? ctx.directory ?? ""
    const projeto = (dir && basename(dir)) || "sessao"
    const titulo = s.info?.title || "sem titulo"
    await exec(ALERTA, ["agente terminou", `${projeto}: ${titulo}`], { ALERTA_ENV })
  }

  return {
    event: async ({ event }) => {
      try {
        const p = event?.properties ?? {}
        switch (event?.type) {
          case "session.updated":
            if (p.info?.id) de(p.info.id).info = p.info
            break
          case "session.deleted":
            sessoes.delete(p.info?.id ?? p.sessionID)
            break
          case "message.updated":
            if (p.info?.role === "user" && p.info.sessionID) {
              const s = de(p.info.sessionID)
              s.desde = agora() // a espera conta da ultima mensagem do usuario
              s.avisado = false
            }
            break
          case "session.idle":
            if (p.sessionID) await ocioso(p.sessionID)
            break
          case "session.status": // suposicao a conferir na VPS: 2.x pode so emitir este
            if (p.status?.type === "idle" && p.sessionID) await ocioso(p.sessionID)
            break
        }
      } catch {
        // engolido de proposito: aviso e conforto, nao pode quebrar o agente
      }
    },
  }
}
