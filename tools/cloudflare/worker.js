// Veilborne download service (Cloudflare Worker, KV namespace bound as BUILDS).
//
// Builds are "blobs": the full APK (apk-<code>) and, between full releases,
// a small content pack (pack-<code>) holding only the files changed since
// that APK. tools/release.sh pushes each blob to the repo's `downloads` branch
// as 45 MiB parts and the release manifest is written to KV key "pending".
// A cron trigger copies every blob of the pending release into KV as 24 MiB
// chunks (blob:<id>:<i>) and only then makes it live (key "manifest"), so
// players always download from Cloudflare's own storage at full speed.
//
// Manifest: {version_code, version_name, notes,
//            apk:  {id, code, size, sha256, parts},
//            pack: null | {id, code, base_code, size, sha256, parts}}
//
//   GET/HEAD /Veilborne.apk       newest full APK (one stream)
//   GET      /blob/<id>/<i>       one chunk of a blob (immutable)
//   GET      /blob/<id>           whole blob
//   GET      /version.json        what the game's updater reads
//   GET      /status              copy progress and last error
//   GET      /ingest?token=...    run one copy step now
//   GET      /                    small download page
const APK_TYPE = "application/vnd.android.package-archive";
const CHUNK = 24 * 1024 * 1024; // KV values are capped at 25 MiB
const PART = 45 * 1024 * 1024;  // size of each GitHub part (tools/release.sh)
const PER_RUN = 3;              // chunks copied per cron run

const chunkCount = (size) => Math.max(1, Math.ceil(size / CHUNK));
const chunkSize = (b, i) => Math.min(CHUNK, b.size - i * CHUNK);

// Older manifests had {size, parts} at the top level for the APK.
function normalize(m) {
  if (!m) return null;
  if (!m.apk) m.apk = { id: `apk-${m.version_code}`, code: m.version_code, size: m.size, parts: m.parts };
  return m;
}

function blobsOf(m) {
  return [m.apk, m.pack].filter(Boolean);
}

async function isReady(env, b) {
  return (await env.BUILDS.get(`ready:${b.id}`, { cacheTtl: 60 })) === "1";
}

async function chunkKeys(env, id) {
  const out = new Set();
  let cursor;
  do {
    const r = await env.BUILDS.list({ prefix: `blob:${id}:`, cursor });
    r.keys.forEach((k) => out.add(k.name));
    cursor = r.list_complete ? null : r.cursor;
  } while (cursor);
  return out;
}

// Copies chunk i of a blob from its GitHub parts into KV, streaming.
async function ingestChunk(env, b, i) {
  const start = i * CHUNK;
  const len = chunkSize(b, i);
  const { readable, writable } = new FixedLengthStream(len);
  const pump = (async () => {
    let pos = start;
    const end = start + len;
    while (pos < end) {
      const p = Math.floor(pos / PART);
      const inPart = pos - p * PART;
      const take = Math.min(end - pos, PART - inPart);
      const r = await fetch(b.parts[p], { headers: { range: `bytes=${inPart}-${inPart + take - 1}` } });
      if (r.status !== 206) throw new Error(`part ${p} -> HTTP ${r.status}`);
      await r.body.pipeTo(writable, { preventClose: true });
      pos += take;
    }
    await writable.close();
  })();
  pump.catch((e) => writable.abort(e).catch(() => {}));
  await Promise.all([env.BUILDS.put(`blob:${b.id}:${i}`, readable), pump]);
}

async function ingest(env) {
  const pending = normalize(await env.BUILDS.get("pending", { type: "json" }));
  const live = normalize(await env.BUILDS.get("manifest", { type: "json" }));
  const target = pending || live;
  if (!target) return "no manifest";
  let budget = PER_RUN;
  let allReady = true;
  for (const b of blobsOf(target)) {
    if (await isReady(env, b)) continue;
    const have = await chunkKeys(env, b.id);
    const n = chunkCount(b.size);
    for (let i = 0; i < n; i++) {
      if (have.has(`blob:${b.id}:${i}`)) continue;
      if (budget <= 0) break;
      await ingestChunk(env, b, i);
      have.add(`blob:${b.id}:${i}`);
      budget--;
    }
    let done = true;
    for (let i = 0; i < n; i++) if (!have.has(`blob:${b.id}:${i}`)) done = false;
    if (done) await env.BUILDS.put(`ready:${b.id}`, "1");
    else allReady = false;
  }
  if (!allReady) return "copying";
  if (pending) {
    await env.BUILDS.put("manifest", JSON.stringify(pending));
    await env.BUILDS.delete("pending");
  }
  // Drop blobs the live release no longer uses.
  const keep = new Set(blobsOf(target).map((b) => b.id));
  let cursor;
  do {
    const r = await env.BUILDS.list({ prefix: "blob:", cursor });
    for (const k of r.keys) {
      const id = k.name.split(":")[1];
      if (!keep.has(id)) {
        await env.BUILDS.delete(k.name);
        await env.BUILDS.delete(`ready:${id}`);
      }
    }
    cursor = r.list_complete ? null : r.cursor;
  } while (cursor);
  return pending ? "promoted" : "ready";
}

async function runIngest(env) {
  try {
    const r = await ingest(env);
    await env.BUILDS.put("ingest:last", JSON.stringify({ at: new Date().toISOString(), result: r }));
  } catch (e) {
    await env.BUILDS.put("ingest:last", JSON.stringify({ at: new Date().toISOString(), error: String(e && e.stack || e) }));
  }
}

function streamBlob(env, b, ready) {
  const { readable, writable } = new FixedLengthStream(b.size);
  (async () => {
    try {
      if (ready) {
        for (let i = 0; i < chunkCount(b.size); i++) {
          const s = await env.BUILDS.get(`blob:${b.id}:${i}`, { type: "stream", cacheTtl: 86400 });
          if (!s) throw new Error("missing chunk " + i);
          await s.pipeTo(writable, { preventClose: true });
        }
      } else {
        for (const u of b.parts) {
          const r = await fetch(u);
          if (!r.ok || !r.body) throw new Error("part " + u + " -> " + r.status);
          await r.body.pipeTo(writable, { preventClose: true });
        }
      }
      await writable.close();
    } catch (e) {
      await writable.abort(e);
    }
  })();
  return readable;
}

async function describe(env, b, origin) {
  const out = { code: b.code, size: b.size, sha256: b.sha256 || "", url: `${origin}/blob/${b.id}` };
  if (b.base_code) out.base_code = b.base_code;
  if (await isReady(env, b)) {
    out.chunks = [];
    for (let i = 0; i < chunkCount(b.size); i++) {
      out.chunks.push({ url: `${origin}/blob/${b.id}/${i}`, size: chunkSize(b, i) });
    }
  }
  return out;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const m = normalize(await env.BUILDS.get("manifest", { type: "json", cacheTtl: 30 }));
    if (!m && path !== "/") return new Response("no build", { status: 404 });

    if (path === "/version.json") {
      const out = {
        version_code: m.version_code,
        version_name: m.version_name,
        notes: m.notes || "",
        // Fields read by game versions up to 0.6.0:
        apk_url: `${url.origin}/Veilborne.apk?v=${m.apk.code}`,
        size: m.apk.size,
        apk: await describe(env, m.apk, url.origin),
      };
      if (m.pack) out.pack = await describe(env, m.pack, url.origin);
      return new Response(JSON.stringify(out), {
        headers: { "content-type": "application/json", "cache-control": "no-store" },
      });
    }

    const bm = path.match(/^\/blob\/([\w.-]+)(?:\/(\d+))?$/);
    if (bm) {
      const b = blobsOf(m).find((x) => x.id === bm[1]);
      if (bm[2] !== undefined) {
        const i = Number(bm[2]);
        const s = await env.BUILDS.get(`blob:${bm[1]}:${i}`, { type: "stream", cacheTtl: 86400 });
        if (!s) return new Response("not found", { status: 404 });
        const headers = { "content-type": "application/octet-stream", "cache-control": "public, max-age=31536000, immutable" };
        if (b) headers["content-length"] = String(chunkSize(b, i));
        return new Response(s, { headers });
      }
      if (!b) return new Response("not found", { status: 404 });
      const headers = { "content-type": "application/octet-stream", "content-length": String(b.size), "cache-control": "no-store" };
      if (request.method === "HEAD") return new Response(null, { headers });
      return new Response(streamBlob(env, b, await isReady(env, b)), { headers });
    }

    if (path === "/Veilborne.apk") {
      const headers = {
        "content-type": APK_TYPE,
        "content-length": String(m.apk.size),
        "content-disposition": 'attachment; filename="Veilborne.apk"',
        "cache-control": "no-store",
      };
      if (request.method === "HEAD") return new Response(null, { headers });
      return new Response(streamBlob(env, m.apk, await isReady(env, m.apk)), { headers });
    }

    // Manual copy step (same as the cron), for when a release should go live sooner.
    if (path === "/ingest") {
      const token = await env.BUILDS.get("ingest:token");
      if (!token || url.searchParams.get("token") !== token) return new Response("forbidden", { status: 403 });
      await runIngest(env);
      return Response.json(await env.BUILDS.get("ingest:last", { type: "json" }), { headers: { "cache-control": "no-store" } });
    }

    if (path === "/status") {
      const pending = normalize(await env.BUILDS.get("pending", { type: "json" }));
      const report = async (mm) => mm && {
        version: mm.version_name,
        blobs: await Promise.all(blobsOf(mm).map(async (b) => ({
          id: b.id, size: b.size, chunks: chunkCount(b.size),
          in_kv: (await chunkKeys(env, b.id)).size, ready: await isReady(env, b),
        }))),
      };
      return Response.json({
        live: await report(m),
        pending: await report(pending),
        last: await env.BUILDS.get("ingest:last", { type: "json" }),
      }, { headers: { "cache-control": "no-store" } });
    }

    if (path === "/") {
      return new Response(
        `<!doctype html><meta name=viewport content="width=device-width"><title>Veilborne</title>` +
        `<body style="background:#120814;color:#f3dca8;font:18px sans-serif;text-align:center;padding:40px">` +
        `<h1>Veilborne</h1><p>v${m ? m.version_name : "?"}</p>` +
        `<p><a style="color:#ffd27a;font-size:24px" href="/Veilborne.apk">Download for Android</a></p>` +
        `<p style="opacity:.6">Install once; after that the game updates itself.</p></body>`,
        { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response("not found", { status: 404 });
  },

  async scheduled(event, env, ctx) {
    ctx.waitUntil(runIngest(env));
  },
};
