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
  if (typeof JsSIP === 'undefined') { status('Error: SIP library missing (reinstall the app)'); return }
  status('Connecting…')
  try { ua = new JsSIP.UA({
    sockets: [new JsSIP.WebSocketInterface(`wss://${d}:${cfg().wssPort}/wss`)],
    uri: `sip:${acc.user}@${d}`, authorization_user: acc.user, password: acc.pass,
    display_name: acc.user, register: true, session_timers: false,
  }) } catch (e) { status(`Error: ${e.message}`); return }
  ua.on('connected', () => status('Connected, registering…'))
  ua.on('disconnected', () => status(`Cannot reach ${d} (retrying)`))
  ua.on('registered', () => status('Registered'))
  ua.on('unregistered', () => status('Not registered'))
  ua.on('registrationFailed', (e) => status(`Failed: ${e.cause}`))
  ua.on('newRTCSession', ({ session: s, originator }) => {
    // DND: refuse as busy; the PBX sends the caller to voicemail (or says there is none). Other phones still ring.
    if (originator === 'remote' && dndUntil()) { s.terminate({ status_code: 486, reason_phrase: 'Busy Here' }); return }
    if (originator === 'remote' && calls.length) { s.terminate({ status_code: 486 }); return }   // busy while in a call
    if (!calls.length) muted = false
    calls.push(s); session = s
    s._audio = document.body.appendChild(Object.assign(document.createElement('audio'), { autoplay: true }))
    // JsSIP sends the INVITE / 200 OK only when ICE gathering ends; a dead interface (VPN, 169.254 adapter) or an
    // unreachable STUN server stalls that for ~40 s. Go once candidates have been quiet for 1 s.
    s.on('icecandidate', ({ ready }) => { clearTimeout(s._ice); s._ice = setTimeout(ready, 1000) })
    // Play the caller's audio. Incoming calls announce their peer connection ('peerconnection'); for calls we
    // place, JsSIP creates it before this handler runs, so hook s.connection directly, and as a last resort pick
    // up the receivers once the call is confirmed (otherwise outgoing calls are silent on our side).
    const playRemote = (stream) => { if (stream && s._audio.srcObject !== stream) { s._audio.srcObject = stream; applySink() } }
    const watch = (pc) => pc.addEventListener('track', (e) => playRemote(e.streams[0] || new MediaStream([e.track])))
    if (s.connection) watch(s.connection)
    s.on('peerconnection', ({ peerconnection: pc }) => watch(pc))
    const pickUpReceivers = () => {
      if (s._audio.srcObject || !s.connection) return
      const tracks = s.connection.getReceivers().map((r) => r.track).filter((t) => t?.kind === 'audio')
      if (tracks.length) playRemote(new MediaStream(tracks))
    }
    s.on('accepted', () => { pickUpReceivers(); refresh() })
    s.on('confirmed', () => { pickUpReceivers(); refresh() })
    s.on('hold', refresh)
    s.on('unhold', () => { if (merging && calls.every((c) => !c.isOnHold().local)) buildMix(); refresh() })
    s.on('ended', () => end(s))
    s.on('failed', (e) => {   // say why (no mic, busy, rejected…) instead of the call just vanishing
      end(s)
      const was = $('status').textContent
      status(`Call failed: ${e.cause}`); setTimeout(() => { if ($('status').textContent.startsWith('Call failed')) status(was) }, 6000)
    })
    s._incoming = originator === 'remote'
    show('idle', false); show('incall', true); show('answer', s._incoming); refresh()
  })
  ua.start()
}

function end(s) {
  s._audio.srcObject = null; s._audio.remove()
  calls = calls.filter((c) => c !== s)
  if (mix) buildMix()   // rebuild for whoever is left (tears down below two calls)
  if (!calls.length) { session = null; show('incall', false); show('audio-pick', false); show('idle', true); return }
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
    ...(c.micId ? { deviceId: c.micId } : {}) }, video: false }   // preferred, not exact: an unplugged headset falls back
}
const pcConfig = () => ({ iceServers: cfg().stun ? [{ urls: cfg().stun }] : [] })
const applySink = () => { const id = cfg().spkId; for (const s of calls) s._audio?.setSinkId?.(id || '').catch(() => {}) }
const dial = (n) => n && ua?.call(`sip:${n}@${domain(acc.tenant)}`, { mediaConstraints: media(), pcConfig: pcConfig() })

$('signin').onclick = async () => {
  acc = { tenant: $('tenant').value, user: $('user').value, pass: $('pass').value }
  if (!acc.tenant || !acc.user || !acc.pass) return
  await store.save(acc); show('login', false); show('phone', true); connect(); renderDnd()
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
$('cfg').onclick = async () => {
  await openSettings()
  // Phone links: Windows lets the user (not the app) choose the app for tel: links.
  const l = await links.status()
  show('s-links', l.platform === 'win32')
  $('s-links-msg').textContent = l.tel ? 'Phone number links open in N2IT Phone.' : 'Phone number links open in another app.'
}
$('s-links-set').onclick = () => links.settings()
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

// ---- Company contacts (from the PBX) ----
let directory = []
function renderContacts() {
  const q = $('c-search').value.trim().toLowerCase()
  const rows = directory.flatMap((c) => c.numbers.map((n) => ({ name: c.name, label: n.label, number: n.number })))
    .filter((r) => !q || r.name.toLowerCase().includes(q) || r.number.includes(q))
  $('c-list').replaceChildren(...rows.map((r) => {
    const row = document.createElement('div'); row.className = 'contact'
    const who = document.createElement('div'); who.textContent = r.name
    const sub = document.createElement('small'); sub.textContent = ` ${r.label ? r.label + ' ' : ''}${r.number}`
    who.append(document.createElement('br'), sub)
    const call = Object.assign(document.createElement('button'), { className: 'go', textContent: 'Call' })
    call.onclick = () => { $('c-back').click(); dial(r.number) }
    row.append(who, call); return row
  }))
  if (directory.length && !rows.length) $('c-msg').textContent = 'No matches'
}
$('contacts-open').onclick = async () => {
  show('phone', false); show('contacts', true)
  $('c-msg').textContent = directory.length ? '' : 'Loading…'
  const r = await store.directory()
  if (r.error) { $('c-msg').textContent = r.error; return }
  directory = r.contacts || []
  $('c-msg').textContent = directory.length ? '' : 'No company contacts'
  renderContacts()
}
$('c-search').oninput = () => { $('c-msg').textContent = ''; renderContacts() }
$('c-back').onclick = () => { show('contacts', false); show('phone', true) }
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

// ---- Audio during a call: switch microphone and speaker (headset, Bluetooth, laptop) without hanging up ----
async function fillAudio() {
  const devs = await navigator.mediaDevices.enumerateDevices(), c = cfg()
  const ins = devs.filter((d) => d.kind === 'audioinput' && d.deviceId !== 'default')
  const outs = devs.filter((d) => d.kind === 'audiooutput' && d.deviceId !== 'default')
  fill($('a-mic'), ins, ins.some((d) => d.deviceId === c.micId) ? c.micId : '', 'Microphone')
  fill($('a-spk'), outs, outs.some((d) => d.deviceId === c.spkId) ? c.spkId : '', 'Speaker')
}
async function saveAudio(change) { acc.settings = { ...cfg(), ...change }; await store.save(acc) }
$('audio').onclick = async () => {
  const open = $('audio-pick').classList.contains('hidden')
  if (open) await fillAudio()
  show('audio-pick', open); $('audio').classList.toggle('on', open)
}
$('a-spk').onchange = async () => { await saveAudio({ spkId: $('a-spk').value }); applySink() }
/** New microphone on every live call: replace the track being sent (and the conference mix's input). */
async function switchMic() {
  if (!calls.length) return
  let track
  try { track = (await navigator.mediaDevices.getUserMedia(media())).getAudioTracks()[0] } catch (e) { status(`Microphone: ${e.message}`); return }
  track.enabled = mix ? true : !muted   // in a conference, muting is the mix gain
  const old = new Set()
  for (const s of calls) {
    if (s.isEnded() || !s.connection) continue
    const cur = s._mic || sender(s)?.track
    if (cur) old.add(cur)
    if (mix) s._mic = track
    else await sender(s)?.replaceTrack(track).catch(() => {})
  }
  if (mix) buildMix()
  old.forEach((t) => { if (t !== track) t.stop() })
}
$('a-mic').onchange = async () => { await saveAudio({ micId: $('a-mic').value }); switchMic() }
// A headset or Bluetooth device plugged in or removed mid-call: refresh the lists; if the chosen one is gone,
// go back to the system default (the browser keeps playing to a dead device otherwise).
navigator.mediaDevices.addEventListener('devicechange', async () => {
  if (!calls.length) return
  const devs = await navigator.mediaDevices.enumerateDevices(), c = cfg()
  const has = (kind, id) => !id || devs.some((d) => d.kind === kind && d.deviceId === id)
  if (!has('audiooutput', c.spkId)) { await saveAudio({ spkId: '' }); applySink() }
  if (!has('audioinput', c.micId)) { await saveAudio({ micId: '' }); switchMic() }
  if (!$('audio-pick').classList.contains('hidden')) fillAudio()
})

// ---- Phone links: a number clicked in a browser or email lands in the dial box, ready to call ----
function dialFromLink(n) {
  if (!n) return
  $('num').value = n
  if (!acc) return   // not signed in: stays in the box for after sign-in
  for (const id of ['contacts', 'settings']) show(id, false)
  show('phone', true)
  if (!calls.length) $('num').focus()
}
links.onDial(dialFromLink)

// ---- Do Not Disturb (this app only; always ends, at most 2 weeks) ----
const MAX_DND = 14 * 24 * 3600 * 1000
const dndUntil = () => (acc?.dndUntil > Date.now() ? acc.dndUntil : null)
const when = (t) => new Date(t).toLocaleString([], { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
const localInput = (t) => { const d = new Date(t - new Date(t).getTimezoneOffset() * 60000); return d.toISOString().slice(0, 16) }
const nextMorning = () => { const d = new Date(); d.setHours(8, 0, 0, 0); if (d <= new Date()) d.setDate(d.getDate() + 1); return d.getTime() }
async function setDnd(until) {
  const now = Date.now()
  acc.dndUntil = until && until > now ? Math.min(until, now + MAX_DND) : null
  await store.save(acc); renderDnd()
  show('dnd-pick', false); show('phone', true)
}
function renderDnd() {   // banner, button and status follow the end time; an expired DND switches itself off
  if (!acc) return
  const u = dndUntil()
  if (acc.dndUntil && !u) { acc.dndUntil = null; store.save(acc) }
  show('dnd-banner', !!u); $('dnd-until').textContent = u ? `Until ${when(u)}` : ''
  $('dnd').textContent = u ? `DND until ${when(u)}` : 'Do Not Disturb'; $('dnd').classList.toggle('dndon', !!u)
  $('status').classList.toggle('dnd', !!u)
}
setInterval(renderDnd, 15000)
$('dnd').onclick = () => {
  const now = Date.now()
  $('dnd-morning').textContent = `Until ${when(nextMorning())}`
  Object.assign($('dnd-at'), { min: localInput(now), max: localInput(now + MAX_DND), value: localInput(now + 3600000) })
  show('dnd-stop', !!dndUntil()); show('phone', false); show('dnd-pick', true)
}
for (const b of document.querySelectorAll('#dnd-pick [data-hours]')) b.onclick = () => setDnd(Date.now() + b.dataset.hours * 3600000)
$('dnd-morning').onclick = () => setDnd(nextMorning())
$('dnd-set').onclick = () => {
  const t = new Date($('dnd-at').value).getTime(), now = Date.now()
  if (!(t > now && t <= now + MAX_DND)) { alert('Choose a time within the next 2 weeks.'); return }
  setDnd(t)
}
$('dnd-stop').onclick = $('dnd-off').onclick = () => setDnd(null)
$('dnd-back').onclick = () => { show('dnd-pick', false); show('phone', true) }

store.load().then(async (a) => {
  if (a) { acc = a; show('login', false); show('phone', true); connect(); renderDnd() }
  dialFromLink(await links.pending())
})
