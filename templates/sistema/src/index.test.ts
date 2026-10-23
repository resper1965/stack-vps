import { expect, test } from "vitest";
import { app } from "./index.js";

test("health responde ok", async () => {
  const res = await app.request("/health");
  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ ok: true });
});
