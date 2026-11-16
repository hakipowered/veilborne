// Veilborne download service (Cloudflare Worker).
// The APK is stored on the repo's `downloads` branch as numbered parts
// (GitHub caps single files at 100 MB). The live build's manifest lives in
// Workers KV (key "manifest", written by the release flow after the parts are
// pushed), and this Worker streams the parts back as one APK.
//   GET/HEAD /Veilborne.apk   newest APK
//   GET      /version.json    {version_code, version_name, notes, apk_url, size}
//   GET      /                small download page
const APK_TYPE = "application/vnd.android.package-archive";

async function streamParts(parts, size) {
  const { readable, writable } = new FixedLengthStream(size);
  (async () => {
    try {
      for (const u of parts) {
        const r = await fetch(u, { cf: { cacheTtl: 86400, cacheEverything: true } });
        if (!r.ok || !r.body) throw new Error("part " + u + " -> " + r.status);
        await r.body.pipeTo(writable, { preventClose: true });
      }
      await writable.close();
    } catch (e) {
      await writable.abort(e);
    }
  })();
  return readable;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const manifest = await env.BUILDS.get("manifest", { type: "json", cacheTtl: 60 });
    if (path === "/version.json") {
      if (!manifest) return new Response("no build", { status: 404 });
      return new Response(JSON.stringify({
        version_code: manifest.version_code,
        version_name: manifest.version_name,
        notes: manifest.notes || "",
        apk_url: `${url.origin}/Veilborne.apk?v=${manifest.version_code}`,
        size: manifest.size,
      }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
    }
    if (path === "/Veilborne.apk") {
      if (!manifest) return new Response("no build", { status: 404 });
      const headers = {
        "content-type": APK_TYPE,
        "content-length": String(manifest.size),
        "content-disposition": 'attachment; filename="Veilborne.apk"',
        "cache-control": "no-store",
      };
      if (request.method === "HEAD") return new Response(null, { headers });
      return new Response(await streamParts(manifest.parts, manifest.size), { headers });
    }
    if (path === "/") {
      return new Response(
        `<!doctype html><meta name=viewport content="width=device-width"><title>Veilborne</title>` +
        `<body style="background:#120814;color:#f3dca8;font:18px sans-serif;text-align:center;padding:40px">` +
        `<h1>Veilborne</h1><p>v${manifest ? manifest.version_name : "?"}</p>` +
        `<p><a style="color:#ffd27a;font-size:24px" href="/Veilborne.apk">Download for Android</a></p>` +
        `<p style="opacity:.6">Install once; after that the game updates itself.</p></body>`,
        { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response("not found", { status: 404 });
  },
};
