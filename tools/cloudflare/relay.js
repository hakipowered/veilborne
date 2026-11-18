// Veilborne online co-op relay (Cloudflare Worker + one Durable Object per room).
//
// The host and each friend hold one WebSocket to the room. The room only
// forwards packets: the game itself (host-authoritative, see autoload/net.gd)
// runs on the phones. Godot's SceneMultiplayer relays friend<->friend traffic
// through the host, so the room only ever links host <-> friend.
//
// Rooms survive phones going to the background (switching to WhatsApp to send
// the invite): a peer that goes away keeps its id and token; reliable packets
// for it are queued and delivered when it reconnects, and the others are never
// told it left. A friend's slot is freed after 10 minutes away, the room after
// 30 minutes without its host.
//
//   GET /room/<CODE>?role=host&token=T       host (creates the room, or rejoins with T)
//   GET /room/<CODE>?role=join[&id=N&token=T] friend (new, or rejoining as N)
//   GET /j/<CODE>                             invite page (copy code, get the game)
//
// Frames. Text = JSON control:
//   server -> peer: {t:"welcome", id, token, peers?}, {t:"join", id}, {t:"leave", id},
//                   {t:"host_away"}, {t:"host_back"}, {t:"error", code}, {t:"closed"}
//   peer -> server: {t:"away"} (going to background), {t:"bye"} (leaving), {t:"kick", id}
// Binary = game packets, first byte flags (bit0 = reliable):
//   friend -> server: [flags][payload]            server -> host:   [flags][i32 from][payload]
//   host -> server:   [flags][i32 to][payload]    server -> friend: [flags][payload]
//   to: 0 = every friend, n > 0 = friend n, n < 0 = every friend but -n.

const CODE_RE = /^[A-HJ-NP-Z2-9]{5}$/;
const FRIEND_KEEP_MS = 10 * 60 * 1000;
const ROOM_KEEP_MS = 30 * 60 * 1000;
const QUEUE_MAX = 4 * 1024 * 1024;
const MAX_FRIENDS = 3;

function rnd(n) {
  const a = new Uint8Array(n);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function bytesOf(d) {
  if (d instanceof ArrayBuffer) return new Uint8Array(d);
  if (ArrayBuffer.isView(d)) return new Uint8Array(d.buffer, d.byteOffset, d.byteLength);
  return null;
}

class Link {
  constructor(id, token) {
    this.id = id;
    this.token = token;
    this.ws = null;
    this.queue = [];
    this.qbytes = 0;
    this.awaySince = Date.now();
  }
  send(data) {
    if (this.ws) {
      try { this.ws.send(data); return; } catch (e) { this.ws = null; this.awaySince = Date.now(); }
    }
  }
  sendOrQueue(bytes, reliable) {
    if (this.ws) return this.send(bytes);
    if (!reliable || this.qbytes + bytes.byteLength > QUEUE_MAX) return;
    this.queue.push(bytes);
    this.qbytes += bytes.byteLength;
  }
  flush() {
    const q = this.queue;
    this.queue = [];
    this.qbytes = 0;
    for (const b of q) this.send(b);
  }
}

// Runtime-neutral room logic (also used by tools/cloudflare/relay_local.mjs for tests).
export class RoomCore {
  constructor(storage, now = () => Date.now()) {
    this.storage = storage;
    this.now = now;
    this.loaded = false;
    this.host = null;      // Link (id 1)
    this.friends = new Map(); // id -> Link
    this.nextId = 2;
    this.closed = false;
  }

  async load() {
    if (this.loaded) return;
    this.loaded = true;
    const s = await this.storage.get("room");
    if (!s) return;
    this.host = new Link(1, s.hostToken);
    this.nextId = s.nextId;
    for (const f of s.friends || []) this.friends.set(f.id, new Link(f.id, f.token));
  }

  async save() {
    if (!this.host) return;
    await this.storage.put("room", {
      hostToken: this.host.token, nextId: this.nextId,
      friends: [...this.friends.values()].map((f) => ({ id: f.id, token: f.token })),
    });
  }

  ctl(link, obj) { link.send(JSON.stringify(obj)); }

  // ws: a server-side WebSocket already accepted. Returns nothing; wires events.
  async connect(ws, params) {
    await this.load();
    const role = params.get("role");
    const token = params.get("token") || "";
    const reject = (code) => { try { ws.send(JSON.stringify({ t: "error", code })); ws.close(4000, code); } catch (e) {} };
    let link;
    if (role === "host") {
      if (this.host && this.host.token !== token) return reject("taken");
      const fresh = !this.host;
      if (fresh) this.host = new Link(1, token || rnd(16));
      link = this.host;
      this._attach(link, ws);
      this.ctl(link, { t: "welcome", id: 1, token: link.token, peers: [...this.friends.keys()] });
      link.flush();
      if (!fresh) for (const f of this.friends.values()) this.ctl(f, { t: "host_back" });
    } else {
      if (!this.host) return reject("no_room");
      const id = Number(params.get("id") || 0);
      link = id ? this.friends.get(id) : null;
      if (link && link.token !== token) return reject("bad_token");
      if (!link) {
        if (this.friends.size >= MAX_FRIENDS) return reject("full");
        link = new Link(this.nextId++, rnd(16));
        this.friends.set(link.id, link);
        this._toHost({ t: "join", id: link.id });
      }
      this._attach(link, ws);
      this.ctl(link, { t: "welcome", id: link.id, token: link.token });
      if (!this.host.ws) this.ctl(link, { t: "host_away" });
      link.flush();
    }
    await this.save();
    await this.schedule();
  }

  _toHost(obj) {
    const s = JSON.stringify(obj);
    if (this.host.ws) this.host.send(s);
    else this.host.queue.push(s); // control messages always queue
  }

  _attach(link, ws) {
    if (link.ws && link.ws !== ws) { try { link.ws.close(4001, "replaced"); } catch (e) {} }
    link.ws = ws;
    ws.addEventListener("message", (ev) => this._onMessage(link, ws, ev.data));
    const gone = () => this._onGone(link, ws);
    ws.addEventListener("close", gone);
    ws.addEventListener("error", gone);
  }

  _onGone(link, ws) {
    if (link.ws !== ws) return;
    link.ws = null;
    link.awaySince = this.now();
    if (link === this.host) for (const f of this.friends.values()) this.ctl(f, { t: "host_away" });
    this.schedule();
  }

  _onMessage(link, ws, data) {
    if (link.ws !== ws) return;
    if (typeof data === "string") {
      let m;
      try { m = JSON.parse(data); } catch (e) { return; }
      if (m.t === "away") { link.ws = null; link.awaySince = this.now(); try { ws.close(1000, "away"); } catch (e) {}
        if (link === this.host) for (const f of this.friends.values()) this.ctl(f, { t: "host_away" });
        this.schedule(); }
      else if (m.t === "bye") this._leave(link);
      else if (m.t === "kick" && link === this.host) { const f = this.friends.get(Number(m.id)); if (f) this._leave(f); }
      return;
    }
    const b = bytesOf(data);
    if (!b || b.byteLength < 1) return;
    const reliable = (b[0] & 1) === 1;
    if (link === this.host) {
      if (b.byteLength < 5) return;
      const to = new DataView(b.buffer, b.byteOffset, b.byteLength).getInt32(1, true);
      const out = new Uint8Array(b.byteLength - 4);
      out[0] = b[0];
      out.set(b.subarray(5), 1);
      for (const f of this.friends.values()) {
        if (to === 0 || to === f.id || (to < 0 && f.id !== -to)) f.sendOrQueue(out, reliable);
      }
    } else {
      const out = new Uint8Array(b.byteLength + 4);
      out[0] = b[0];
      new DataView(out.buffer).setInt32(1, link.id, true);
      out.set(b.subarray(1), 5);
      this.host.sendOrQueue(out, reliable);
    }
  }

  _leave(link) {
    if (link === this.host) { this.closeRoom(); return; }
    this.friends.delete(link.id);
    if (link.ws) { try { link.ws.close(1000, "bye"); } catch (e) {} }
    this._toHost({ t: "leave", id: link.id });
    this.save();
  }

  closeRoom() {
    this.closed = true;
    for (const f of this.friends.values()) { this.ctl(f, { t: "closed" }); try { f.ws && f.ws.close(1000, "closed"); } catch (e) {} }
    if (this.host && this.host.ws) { try { this.host.ws.close(1000, "closed"); } catch (e) {} }
    this.friends.clear();
    this.host = null;
    this.storage.delete("room");
  }

  // Expire friends away too long, and the room when its host is gone too long.
  async tick() {
    await this.load();
    if (!this.host) return;
    const t = this.now();
    for (const f of [...this.friends.values()]) {
      if (!f.ws && t - f.awaySince > FRIEND_KEEP_MS) this._leave(f);
    }
    if (!this.host.ws && t - this.host.awaySince > ROOM_KEEP_MS) { this.closeRoom(); return; }
    await this.schedule();
  }

  async schedule() {
    if (this.storage.setAlarm) await this.storage.setAlarm(this.now() + 60 * 1000);
  }
}

export class Room {
  constructor(state) {
    this.core = new RoomCore(state.storage);
  }
  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
    const pair = new WebSocketPair();
    const server = pair[1];
    server.accept();
    await this.core.connect(server, new URL(request.url).searchParams);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }
  async alarm() {
    await this.core.tick();
  }
}

function invitePage(code) {
  return `<!doctype html><meta name=viewport content="width=device-width,initial-scale=1"><title>Join me in Veilborne</title>
<body style="background:#120814;color:#f3dca8;font:18px sans-serif;text-align:center;padding:32px 16px">
<h1 style="margin:0 0 8px">Veilborne</h1><p>Your friend is waiting in their game.</p>
<p style="opacity:.8;margin-top:28px">Room code</p>
<div id=c style="font:700 56px monospace;letter-spacing:10px;color:#ffd27a">${code}</div>
<p><button id=b style="font-size:22px;padding:14px 28px;border-radius:12px;border:0;background:#ffd27a;color:#2a1020">Copy code</button></p>
<p style="opacity:.85">Then open Veilborne, tap <b>Co-op</b>, then <b>Join</b>. The code fills in by itself.</p>
<p style="margin-top:36px"><a style="color:#ffd27a" href="https://veilborne-download.hakipowered.workers.dev/Veilborne.apk">Don't have the game? Download it for Android</a></p>
<script>document.getElementById('b').onclick=async()=>{try{await navigator.clipboard.writeText('VEILBORNE ${code}');document.getElementById('b').textContent='Copied!'}catch(e){}}</script></body>`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/(room|j)\/([A-Za-z0-9]{5})$/);
    if (!m) return new Response("Veilborne relay", { status: url.pathname === "/" ? 200 : 404 });
    const code = m[2].toUpperCase();
    if (!CODE_RE.test(code)) return new Response("bad code", { status: 400 });
    if (m[1] === "j") return new Response(invitePage(code), { headers: { "content-type": "text/html; charset=utf-8" } });
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    return stub.fetch(request);
  },
};
