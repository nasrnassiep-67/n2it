// WebRTC softphone: JsSIP over WSS to FusionPBX. Assumes FusionPBX serves WSS on 7443
// (default) at <code>.voip.n2it.co.za with a valid certificate and WebRTC-enabled extensions.
const BASE = 'voip.n2it.co.za', WSS_PORT = 7443, VOICEMAIL = '*97'
const $ = (id) => document.getElementById(id)
let ua, session, acc, held = false, muted = false

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
    sockets: [new JsSIP.WebSocketInterface(`wss://${d}:${WSS_PORT}`)],
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
      pc.addEventListener('track', (e) => { $('remote').srcObject = e.streams[0] }))
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
const dial = (n) => n && ua?.call(`sip:${n}@${domain(acc.tenant)}`, {
  mediaConstraints: { audio: true, video: false }, pcConfig: { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] },
})

$('signin').onclick = async () => {
  acc = { tenant: $('tenant').value, user: $('user').value, pass: $('pass').value }
  if (!acc.tenant || !acc.user || !acc.pass) return
  await store.save(acc); show('login', false); show('phone', true); connect()
}
$('out').onclick = async () => { ua?.stop(); await store.clear(); show('phone', false); show('login', true); status('Not registered') }
$('call').onclick = () => { dial($('num').value.trim()); $('num').value = '' }
$('vm').onclick = () => dial(VOICEMAIL)
$('answer').onclick = () => { session?.answer({ mediaConstraints: { audio: true, video: false } }); show('answer', false) }
$('hang').onclick = () => session?.terminate()
$('mute').onclick = () => { muted = !muted; muted ? session?.mute({ audio: true }) : session?.unmute({ audio: true }); refresh() }
$('hold').onclick = () => { held ? session?.unhold() : session?.hold(); }
$('xfer').onclick = () => {   // blind transfer via SIP REFER
  const n = prompt('Transfer to extension or number'); if (n) session?.refer(`sip:${n}@${domain(acc.tenant)}`)
}

store.load().then((a) => { if (a) { acc = a; show('login', false); show('phone', true); connect() } })
