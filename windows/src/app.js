// WebRTC softphone: JsSIP over WSS to FusionPBX. Assumes FusionPBX serves WSS on 7443
// (default) at <code>.voip.n2it.co.za with a valid certificate and WebRTC-enabled extensions.
const BASE = 'voip.n2it.co.za'
const DEFAULTS = { wssPort: 7443, voicemail: '*97', stun: 'stun:stun.l.google.com:19302',
  micId: '', spkId: '', echo: true, noise: true, agc: true }
const $ = (id) => document.getElementById(id)
let ua, session, acc, held = false, muted = false
const cfg = () => ({ ...DEFAULTS, ...(acc?.settings || {}) })

const show = (id, on) => $(id).classList.toggle('hidden', !on)
const status = (t) => ($('status').textContent = t)
const domain = (t) => (t ? `${t.trim().toLowerCase()}.${BASE}` : '')

for (const [padId, onKey] of [['pad', (k) => ($('num').value += k)], ['dpad', (k) => session?.sendDTMF(k)]]) {
  for (const k of '123456789*0#') {
    const b = document.createElement('button'); b.textContent = k; b.onclick = () => onKey(k); $(padId).append(b)
  }
}
$('tenant').oninput = () => ($('domain').textContent = domain($('tenant').value))

function connect() {
  const d = domain(acc.tenant)
  ua?.stop()
  ua = new JsSIP.UA({
    sockets: [new JsSIP.WebSocketInterface(`wss://${d}:${cfg().wssPort}`)],
    uri: `sip:${acc.user}@${d}`, authorization_user: acc.user, password: acc.pass,
    display_name: acc.user, register: true, session_timers: false,
  })
  ua.on('registered', () => status('Registered'))
  ua.on('unregistered', () => status('Not registered'))
  ua.on('registrationFailed', (e) => status(`Failed: ${e.cause}`))
  ua.on('newRTCSession', ({ session: s, originator }) => {
    if (session) { s.terminate({ status_code: 486 }); return }   // one call at a time
    session = s; held = muted = false
    s.on('peerconnection', ({ peerconnection: pc }) =>
      pc.addEventListener('track', (e) => { $('remote').srcObject = e.streams[0]; applySink() }))
    s.on('accepted', () => $('state').textContent = 'Connected')
    s.on('hold', () => { held = true; refresh() })
    s.on('unhold', () => { held = false; refresh() })
    s.on('ended', end); s.on('failed', end)
    $('who').textContent = s.remote_identity.uri.user
    $('state').textContent = originator === 'remote' ? 'Incoming call' : 'Calling…'
    show('idle', false); show('incall', true); show('answer', originator === 'remote'); refresh()
  })
  ua.start()
}

function end() { session = null; $('remote').srcObject = null; show('incall', false); show('idle', true) }
function refresh() {
  $('hold').classList.toggle('on', held); $('mute').classList.toggle('on', muted)
  if (held) $('state').textContent = 'On hold'
}
const media = () => {
  const c = cfg()
  return { audio: { echoCancellation: c.echo, noiseSuppression: c.noise, autoGainControl: c.agc,
    ...(c.micId ? { deviceId: { exact: c.micId } } : {}) }, video: false }
}
const pcConfig = () => ({ iceServers: cfg().stun ? [{ urls: cfg().stun }] : [] })
const applySink = () => { const id = cfg().spkId; if (id && $('remote').setSinkId) $('remote').setSinkId(id).catch(() => {}) }
const dial = (n) => n && ua?.call(`sip:${n}@${domain(acc.tenant)}`, { mediaConstraints: media(), pcConfig: pcConfig() })

$('signin').onclick = async () => {
  acc = { tenant: $('tenant').value, user: $('user').value, pass: $('pass').value }
  if (!acc.tenant || !acc.user || !acc.pass) return
  await store.save(acc); show('login', false); show('phone', true); connect()
}
$('out').onclick = async () => { ua?.stop(); await store.clear(); acc = null; show('settings', false); show('login', true); status('Not registered') }

// ---- Settings ----
const fill = (sel, devs, cur, label) => {
  sel.replaceChildren(new Option('System default', ''))
  devs.forEach((d, i) => sel.add(new Option(d.label || `${label} ${i + 1}`, d.deviceId)))
  sel.value = cur
}
async function openSettings() {
  try { (await navigator.mediaDevices.getUserMedia({ audio: true })).getTracks().forEach((t) => t.stop()) } catch {}  // unlocks device names
  const devs = await navigator.mediaDevices.enumerateDevices(), c = cfg()
  fill($('s-mic'), devs.filter((d) => d.kind === 'audioinput' && d.deviceId !== 'default'), c.micId, 'Microphone')
  fill($('s-spk'), devs.filter((d) => d.kind === 'audiooutput' && d.deviceId !== 'default'), c.spkId, 'Speaker')
  $('s-echo').checked = c.echo; $('s-noise').checked = c.noise; $('s-agc').checked = c.agc
  $('s-port').value = c.wssPort; $('s-vm').value = c.voicemail; $('s-stun').value = c.stun
  $('s-acct').textContent = `Signed in as ${acc.user} @ ${domain(acc.tenant)}`
  show('phone', false); show('settings', true)
}
$('cfg').onclick = openSettings
$('s-back').onclick = () => { show('settings', false); show('phone', true) }
$('s-save').onclick = async () => {
  const old = cfg().wssPort, port = parseInt($('s-port').value, 10)
  acc.settings = { micId: $('s-mic').value, spkId: $('s-spk').value, echo: $('s-echo').checked, noise: $('s-noise').checked,
    agc: $('s-agc').checked, wssPort: port > 0 && port < 65536 ? port : DEFAULTS.wssPort,
    voicemail: $('s-vm').value.trim() || DEFAULTS.voicemail, stun: $('s-stun').value.trim() }
  await store.save(acc); applySink()
  if (cfg().wssPort !== old && !session) connect()   // new port: re-register (not mid-call)
  $('s-back').click()
}
$('call').onclick = () => { dial($('num').value.trim()); $('num').value = '' }
$('vm').onclick = () => dial(cfg().voicemail)
$('answer').onclick = () => { session?.answer({ mediaConstraints: media(), pcConfig: pcConfig() }); show('answer', false) }
$('hang').onclick = () => session?.terminate()
$('mute').onclick = () => { muted = !muted; muted ? session?.mute({ audio: true }) : session?.unmute({ audio: true }); refresh() }
$('hold').onclick = () => { held ? session?.unhold() : session?.hold(); }
$('xfer').onclick = () => {   // blind transfer via SIP REFER
  const n = prompt('Transfer to extension or number'); if (n) session?.refer(`sip:${n}@${domain(acc.tenant)}`)
}

store.load().then((a) => { if (a) { acc = a; show('login', false); show('phone', true); connect() } })
