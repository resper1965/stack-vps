import OpenAI from "openai";

// O 9router escuta só em loopback; a chave vem do ambiente, nunca do código.
const apiKey = process.env.NINE_ROUTER_API_KEY;
if (!apiKey) throw new Error("NINE_ROUTER_API_KEY ausente");

const client = new OpenAI({ apiKey, baseURL: "http://127.0.0.1:20128/v1" });

export async function perguntar(pergunta: string, model = process.env.MODELO ?? "default"): Promise<string> {
  const r = await client.chat.completions.create({
    model,
    messages: [{ role: "user", content: pergunta }],
  });
  return r.choices[0]?.message?.content ?? "";
}

if (process.argv[1]?.endsWith("index.ts")) {
  console.log(await perguntar(process.argv.slice(2).join(" ") || "Diga olá."));
}
