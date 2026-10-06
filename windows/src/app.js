// WebRTC softphone: JsSIP over WSS to FusionPBX at wss://<code>.voip.n2it.co.za/wss. Public port 443: nginx
// proxies /wss to FreeSWITCH's WSS listener (7443 is the XGS VPN portal from outside).
const BASE = 'voip.n2it.co.za'
const DEFAULTS = { wssPort: 443, voicemail: '*97', stun: 'stun:stun.l.google.com:19302',
  micId: '', spkId: '', echo: true, noise: true, agc: true }
const $ = (id) => document.getElementById(id)
let ua, session, acc, muted = false
let calls = [], mix = null, merging = false   // all live calls; mix = conference mixer (see buildMix)
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
    sockets: [new JsSIP.WebSocketInterface(`wss://${d}:${cfg().wssPort}/wss`)],
    uri: `sip:${acc.user}@${d}`, authorization_user: acc.user, password: acc.pass,
    display_name: acc.user, register: true, session_timers: false,
  })
  ua.on('registered', () => status('Registered'))
  ua.on('unregistered', () => status('Not registered'))
  ua.on('registrationFailed', (e) => status(`Failed: ${e.cause}`))
  ua.on('newRTCSession', ({ session: s, originator }) => {
    if (originator === 'remote' && calls.length) { s.terminate({ status_code: 486 }); return }   // busy while in a call
    if (!calls.length) muted = false
    calls.push(s); session = s
    s._audio = document.body.appendChild(Object.assign(document.createElement('audio'), { autoplay: true }))
    s.on('peerconnection', ({ peerconnection: pc }) =>
      pc.addEventListener('track', (e) => { s._audio.srcObject = e.streams[0]; applySink() }))
    s.on('accepted', refresh)
    s.on('confirmed', refresh)
    s.on('hold', refresh)
    s.on('unhold', () => { if (merging && calls.every((c) => !c.isOnHold().local)) buildMix(); refresh() })
    s.on('ended', () => end(s)); s.on('failed', () => end(s))
    s._incoming = originator === 'remote'
    show('idle', false); show('incall', true); show('answer', s._incoming); refresh()
  })
  ua.start()
}

function end(s) {
  s._audio.srcObject = null; s._audio.remove()
  calls = calls.filter((c) => c !== s)
  if (mix) buildMix()   // rebuild for whoever is left (tears down below two calls)
  if (!calls.length) { session = null; show('incall', false); show('idle', true); return }
  if (session === s) session = calls[calls.length - 1]
  show('answer', false); refresh()
}
const user = (s) => s.remote_identity.uri.user
function refresh() {
  if (!session) return
  const held = session.isOnHold().local
  $('hold').classList.toggle('on', held); $('mute').classList.toggle('on', muted)
  const inConf = mix?.calls.length > 1
  $('who').textContent = inConf ? mix.calls.map(user).join(', ') : user(session)
  $('state').textContent = inConf ? `Conference · ${mix.calls.length + 1} people` + (calls.length > mix.calls.length ? ' (+1 ringing)' : '')
    : session.isEstablished() ? (held ? 'On hold' : 'Connected') : session._incoming ? 'Incoming call' : 'Calling…'
  show('hold', !inConf); show('xfer', !inConf)
  show('merge', calls.length > 1 && calls.filter((c) => c.isEstablished()).length > (mix?.calls.length || 1))
}

// ---- Conference: mixed here, so the PBX needs nothing ----
// Each call gets its own WebAudio mix (my mic + every other caller) in place of the mic on its sender;
// every caller's audio still plays locally through their own <audio> element.
const sender = (s) => s.connection.getSenders().find((x) => x.track?.kind === 'audio')
function teardownMix() {
  if (!mix) return
  for (const s of mix.calls) if (!s.isEnded()) { s._mic.enabled = !muted; sender(s)?.replaceTrack(s._mic).catch(() => {}) }
  mix.ctx.close(); mix = null
}
function buildMix() {
  merging = false
  teardownMix()
  const live = calls.filter((c) => c.isEstablished())
  if (live.length < 2) { refresh(); return }
  for (const s of live) s._mic ??= sender(s).track
  live[0]._mic.enabled = true   // muting is done by the gain below while mixed
  const ctx = new AudioContext(), mic = ctx.createGain()
  mic.gain.value = muted ? 0 : 1
  ctx.createMediaStreamSource(new MediaStream([live[0]._mic])).connect(mic)
  const remotes = live.map((s) => ctx.createMediaStreamSource(
    new MediaStream(s.connection.getReceivers().map((r) => r.track).filter((t) => t?.kind === 'audio'))))
  live.forEach((s, i) => {
    const out = ctx.createMediaStreamDestination()
    mic.connect(out)
    remotes.forEach((r, j) => { if (j !== i) r.connect(out) })
    sender(s).replaceTrack(out.stream.getAudioTracks()[0])
  })
  mix = { ctx, mic, calls: live }
  refresh()
}
function merge() {
  merging = true
  const held = calls.filter((c) => c.isEstablished() && c.isOnHold().local)
  if (held.length) held.forEach((c) => c.unhold())   // buildMix runs from the last 'unhold'
  else buildMix()
}
const media = () => {
  const c = cfg()
  return { audio: { echoCancellation: c.echo, noiseSuppression: c.noise, autoGainControl: c.agc,
    ...(c.micId ? { deviceId: { exact: c.micId } } : {}) }, video: false }
}
const pcConfig = () => ({ iceServers: cfg().stun ? [{ urls: cfg().stun }] : [] })
const applySink = () => { const id = cfg().spkId; for (const s of calls) if (id && s._audio?.setSinkId) s._audio.setSinkId(id).catch(() => {}) }
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
$('hang').onclick = () => {   // in a conference, hang up on everyone; otherwise the call in front
  if (mix && !mix.calls.includes(session)) session.terminate()
  else if (mix) [...calls].forEach((c) => c.terminate())
  else session?.terminate()
}
$('mute').onclick = () => {
  muted = !muted
  if (mix) mix.mic.gain.value = muted ? 0 : 1
  else muted ? session?.mute({ audio: true }) : session?.unmute({ audio: true })
  refresh()
}
$('hold').onclick = () => { session?.isOnHold().local ? session.unhold() : session?.hold() }
$('add').onclick = () => {   // hold the call (unless in a conference) and ring the new person; Merge joins them
  const n = prompt(mix ? 'Add to conference: extension or number' : 'Add participant: extension or number\n(the current call goes on hold; press Merge when they answer)')
  if (!n) return
  if (!mix) session?.hold()
  dial(n.trim())
}
$('merge').onclick = merge
$('xfer').onclick = () => {   // blind transfer via SIP REFER
  const n = prompt('Transfer to extension or number'); if (n) session?.refer(`sip:${n}@${domain(acc.tenant)}`)
}

store.load().then((a) => { if (a) { acc = a; show('login', false); show('phone', true); connect() } })
