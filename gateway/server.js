// Minimal N2IT VoIP push gateway. Node 18+, no dependencies.
//   POST /register    {tenant,user,password,token,bundle,sandbox}   (from the app)
//   POST /unregister  {tenant,user,token}                           (from the app)
//   POST /notify      {tenant,user,caller}   header x-admin-key     (from the PBX on incoming INVITE)
// Env: PORT, ADMIN_KEY, APNS_KEY_FILE (.p8), APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID
const http = require('http'), http2 = require('http2'), crypto = require('crypto'), fs = require('fs');
const E = process.env, DB = './tokens.json';
let db = fs.existsSync(DB) ? JSON.parse(fs.readFileSync(DB)) : {};
const save = () => fs.writeFileSync(DB, JSON.stringify(db));
const key = (t, u) => `${t}/${u}`;

let jwt, jwtAt = 0;
function apnsJwt() {                       // APNs tokens must be refreshed every 20-60 min
  if (jwt && Date.now() - jwtAt < 40 * 60e3) return jwt;
  const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
  const head = b64({ alg: 'ES256', kid: E.APNS_KEY_ID }), body = b64({ iss: E.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1e3) });
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`),
    { key: fs.readFileSync(E.APNS_KEY_FILE), dsaEncoding: 'ieee-p1363' }).toString('base64url');
  jwtAt = Date.now(); return (jwt = `${head}.${body}.${sig}`);
}

function pushVoip(d, payload) {
  return new Promise(resolve => {
    const c = http2.connect(d.sandbox ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com');
    c.on('error', () => resolve(0));
    const r = c.request({
      ':method': 'POST', ':path': `/3/device/${d.token}`, authorization: `bearer ${apnsJwt()}`,
      'apns-topic': `${E.APNS_BUNDLE_ID || d.bundle}.voip`, 'apns-push-type': 'voip', 'apns-priority': '10', 'apns-expiration': '0',
    });
    let status = 0; r.on('response', h => (status = h[':status'])); r.on('close', () => { c.close(); resolve(status); });
    r.end(JSON.stringify(payload));
  });
}

// Verify the caller owns the extension. Replace with a real check against the tenant's PBX
// (e.g. SIP REGISTER probe or PBX API). Until then registrations are open: DO NOT go live like this.
async function verifySip(tenant, user, password) { return Boolean(tenant && user && password); }

const server = http.createServer((req, res) => {
  let raw = ''; req.on('data', c => (raw += c)); req.on('end', async () => {
    const send = (c, o = {}) => { res.writeHead(c, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    let b; try { b = JSON.parse(raw || '{}'); } catch { return send(400); }
    if (req.method !== 'POST') return send(405);
    if (req.url === '/register') {
      if (!(await verifySip(b.tenant, b.user, b.password)) || !b.token) return send(401);
      const k = key(b.tenant, b.user); db[k] = (db[k] || []).filter(d => d.token !== b.token);
      db[k].push({ token: b.token, bundle: b.bundle, sandbox: !!b.sandbox }); save(); return send(200);
    }
    if (req.url === '/unregister') {
      const k = key(b.tenant, b.user); db[k] = (db[k] || []).filter(d => d.token !== b.token); save(); return send(200);
    }
    if (req.url === '/notify') {
      if (!E.ADMIN_KEY || req.headers['x-admin-key'] !== E.ADMIN_KEY) return send(403);
      const devices = db[key(b.tenant, b.user)] || [];
      const out = await Promise.all(devices.map(async d => {
        const s = await pushVoip(d, { caller: b.caller || 'Unknown' });
        if (s === 410 || s === 400) db[key(b.tenant, b.user)] = db[key(b.tenant, b.user)].filter(x => x.token !== d.token);
        return s;
      }));
      save(); return send(200, { sent: out });
    }
    send(404);
  });
});
server.listen(E.PORT || 8080);
