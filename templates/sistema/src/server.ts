import { serve } from "@hono/node-server";
import app from "./index.js";

serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 8080) });
