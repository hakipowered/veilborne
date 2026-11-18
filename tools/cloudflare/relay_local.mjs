// Local stand-in for the Cloudflare relay, for headless tests: node relay_local.mjs [port]
// Needs the `ws` package (npm i ws). Same room logic as relay.js.
import { WebSocketServer } from "ws";
import { RoomCore } from "./relay.js";

const port = Number(process.argv[2] || 8787);
const rooms = new Map();
function storage() {
  const m = new Map();
  return { get: async (k) => m.get(k), put: async (k, v) => m.set(k, v), delete: async (k) => m.delete(k) };
}
const wss = new WebSocketServer({ port });
wss.on("connection", async (ws, req) => {
  const u = new URL(req.url, "http://x");
  const mm = u.pathname.match(/^\/room\/([A-Z2-9]{5})$/);
  if (!mm) return ws.close();
  if (!rooms.has(mm[1])) rooms.set(mm[1], new RoomCore(storage()));
  ws.binaryType = "arraybuffer";
  await rooms.get(mm[1]).connect(ws, u.searchParams);
});
setInterval(() => rooms.forEach((r) => r.tick()), 5000);
console.log("relay on", port);
