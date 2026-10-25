import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { AvisoPlugin } from "./aviso.js"

const monta = async (opts = {}) => {
  const chamadas = []
  let t = 1_000_000
  const hooks = await AvisoPlugin({
    directory: "/srv/dev/projetos/meu-proj",
    agora: () => t,
    exec: opts.exec ?? (async (cmd, args, env) => { chamadas.push({ cmd, args, env }) }),
  })
  const ev = (type, properties) => hooks.event({ event: { type, properties } })
  const avanca = (s) => { t += s * 1000 }
  const fala = () => ev("message.updated", { info: { role: "user", sessionID: "s1" } })
  const titulo = () => ev("session.updated", { info: { id: "s1", title: "Corrige o login", directory: "/srv/dev/projetos/meu-proj" } })
  return { chamadas, ev, avanca, fala, titulo }
}

test("ocupada 30 s: nenhum aviso", async () => {
  const a = await monta(); await a.titulo(); await a.fala(); a.avanca(30)
  await a.ev("session.idle", { sessionID: "s1" })
  assert.equal(a.chamadas.length, 0)
})

test("ocupada 300 s: um aviso com projeto e titulo", async () => {
  const a = await monta(); await a.titulo(); await a.fala(); a.avanca(300)
  await a.ev("session.idle", { sessionID: "s1" })
  assert.equal(a.chamadas.length, 1)
  assert.deepEqual(a.chamadas[0].args, ["agente terminou", "meu-proj: Corrige o login"])
})

test("dois ociosos seguidos sem nova mensagem: um aviso", async () => {
  const a = await monta(); await a.titulo(); await a.fala(); a.avanca(300)
  await a.ev("session.idle", { sessionID: "s1" })
  await a.ev("session.idle", { sessionID: "s1" })
  await a.ev("session.status", { sessionID: "s1", status: { type: "idle" } })
  assert.equal(a.chamadas.length, 1)
  await a.fala(); a.avanca(200); await a.ev("session.idle", { sessionID: "s1" })
  assert.equal(a.chamadas.length, 2)
})

test("session.status idle tambem avisa; busy nao", async () => {
  const a = await monta(); await a.titulo(); await a.fala(); a.avanca(300)
  await a.ev("session.status", { sessionID: "s1", status: { type: "busy" } })
  assert.equal(a.chamadas.length, 0)
  await a.ev("session.status", { sessionID: "s1", status: { type: "idle" } })
  assert.equal(a.chamadas.length, 1)
})

test("executor lanca erro: o plugin nao lanca", async () => {
  const a = await monta({ exec: async () => { throw new Error("falhou") } })
  await a.titulo(); await a.fala(); a.avanca(300)
  await assert.doesNotReject(a.ev("session.idle", { sessionID: "s1" }))
})

test("segredo fora do argv: so o caminho do ALERTA_ENV, por ambiente", async () => {
  const a = await monta(); await a.titulo(); await a.fala(); a.avanca(300)
  await a.ev("session.idle", { sessionID: "s1" })
  const { cmd, args, env } = a.chamadas[0]
  assert.equal(cmd, "/usr/local/lib/stack-vps/alertar.sh")
  assert.deepEqual(env, { ALERTA_ENV: "/srv/dev/secrets/aviso.env" })
  assert.ok(!args.join(" ").includes("NTFY"))
})

test("MIN_OCUPADA_S = 120 e marcador na primeira linha", () => {
  const src = readFileSync(new URL("./aviso.js", import.meta.url), "utf8")
  assert.match(src, /const MIN_OCUPADA_S = 120\b/)
  assert.match(src.split("\n")[0], /stack-vps/)
})
