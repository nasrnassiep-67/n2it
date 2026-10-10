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
/** Status text in the top bar, a green / red dot, and the tray icon's tooltip. */
function status(t) {
  $('status').textContent = t
  $('status-pill').dataset.s = t === 'Registered' ? 'ok' : /^(Failed|Cannot|Error|Microphone|Call failed)/.test(t) ? 'bad' : ''
  appShell.state({ status: t })
}
const domain = (t) => (t ? `${t.trim().toLowerCase()}.${BASE}` : '')

// Round keys like the Android app, with the letters under the digits on the dial pad
const LETTERS = { 2: 'ABC', 3: 'DEF', 4: 'GHI', 5: 'JKL', 6: 'MNO', 7: 'PQRS', 8: 'TUV', 9: 'WXYZ', 0: '+' }
for (const [padId, onKey] of [['pad', (k) => { $('num').value += k; $('num').focus() }], ['dpad', (k) => session?.sendDTMF(k)]]) {
  for (const k of '123456789*0#') {
    const b = document.createElement('button'); b.textContent = k; b.onclick = () => onKey(k)
    if (padId === 'pad') b.append(Object.assign(document.createElement('small'), { textContent: LETTERS[k] || '' }))
    $(padId).append(b)
  }
}
$('back').onclick = () => { $('num').value = $('num').value.slice(0, -1); $('num').focus() }
$('num').onkeydown = (e) => { if (e.key === 'Enter') $('call').click() }
$('keys').onclick = () => { const open = $('dpad').classList.contains('hidden'); show('dpad', open); $('keys').classList.toggle('on', open) }
/** Signed in or not: the top bar's buttons and the recent-calls side bar only make sense signed in. */
function signedIn(on) {
  document.body.classList.toggle('signed-out', !on)
  $('me').textContent = on && acc ? `Ext ${acc.user} · ${acc.tenant}` : ''
  if (on) { renderRecent(); loadNames() }
}
$('tenant').oninput = () => ($('domain').textContent = domain($('tenant').value))

/** Retire a UA the user switched away from (or logged out of): de-register it first so the PBX stops sending its
 *  calls here, then stop it. Its listeners are removed first, so its shutdown ("disconnected") can no longer
 *  overwrite the new account's status line or touch the screen. */
function retire(old) {
  if (!old) return
  try { old.removeAllListeners() } catch {}
  let done = false
  const stop = () => { if (done) return; done = true; try { old.stop() } catch {} }
  try {
    if (old.isRegistered()) { old.once('unregistered', stop); old.once('registrationFailed', stop); old.unregister(); setTimeout(stop, 3000) }
    else stop()
  } catch { stop() }
}

function connect() {
  const d = domain(acc.tenant)
  retire(ua); ua = null
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
    if (originator === 'remote' && dndUntil()) {
      s.terminate({ status_code: 486, reason_phrase: 'Busy Here' })
      addRecent({ number: user(s), name: s.remote_identity.display_name, dir: 'in', at: Date.now(), result: 'missed', dnd: true })
      return
    }
    // A call coming in while on a call waits (call-waiting beep, Answer / Decline) instead of being refused as busy
    const waiting = originator === 'remote' && calls.length > 0
    if (!calls.length) muted = false
    calls.push(s); if (!waiting) session = s
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
    s._log = { number: user(s), name: s.remote_identity.display_name, dir: s._incoming ? 'in' : 'out', at: Date.now() }
    s.on('accepted', () => { s._log.answered ??= Date.now() })
    s.on('confirmed', () => { s._log.answered ??= Date.now() })
    show('idle', false); show('incall', true); refresh()
    if (s._incoming) { s._silenced = false; checkOtherCall().then(updateRinging) }
  })
  ua.start()
}

function end(s) {
  logCall(s)
  if (xferFrom === s) xferFrom = null
  s._audio.srcObject = null; s._audio.remove()
  s._stream?.getTracks().forEach((t) => t.stop())
  calls = calls.filter((c) => c !== s)
  if (mix) buildMix()   // rebuild for whoever is left (tears down below two calls)
  updateRinging()
  if (!calls.length) {
    session = null; show('incall', false); show('audio-pick', false); show('xfer-pick', false); show('dpad', false)
    $('keys').classList.remove('on'); show('idle', true); appShell.state({ inCall: false }); return
  }
  if (session === s) session = calls.find((c) => c.isEstablished()) || calls[calls.length - 1]
  refresh()
}
const user = (s) => s.remote_identity.uri.user
function refresh() {
  if (!session) return
  const held = session.isOnHold().local
  $('hold').classList.toggle('on', held); $('mute').classList.toggle('on', muted)
  const inConf = mix?.calls.length > 1
  $('who').textContent = inConf ? mix.calls.map(user).join(', ') : nameOf(user(session), session.remote_identity.display_name)
  $('who-av').textContent = inConf ? mix.calls.length + 1 : initial($('who').textContent)
  appShell.state({ inCall: true })
  tick()
  $('state').textContent = inConf ? `Conference · ${mix.calls.length + 1} people` + (calls.length > mix.calls.length ? ' (+1 ringing)' : '')
    : session.isEstablished() ? (held ? 'On hold' : 'Connected') : session._incoming ? 'Incoming call' : 'Calling…'
  show('hold', !inConf); show('xfer', !inConf)
  show('merge', calls.length > 1 && calls.filter((c) => c.isEstablished()).length > (mix?.calls.length || 1))
  const ringingFront = session._incoming && !session.isEstablished() && !session.isEnded()
  show('answer', ringingFront)
  const w = waitingCall()
  show('waiting', !!w)
  if (w) $('w-who').textContent = `${user(w)} is calling` + (w._silenced ? ' (silenced)' : '')
  show('other-note', !!otherApps.length && calls.some((c) => c._autoHeld))
  if (otherApps.length) $('other-note').textContent = `On hold while ${otherApps.join(', ')} uses the microphone (another call). It comes back when that call ends, or press Hold to resume now.`
  show('x-complete', !!xferFrom && !xferFrom.isEnded() && session !== xferFrom && session.isEstablished())
}

// ---- Ringing (owner 2026-10-08): a ringtone, the window popping up and a Windows call notification. While another
// call is going on (ours, or Teams / Zoom / WhatsApp / Skype…) a quiet call-waiting beep instead, and no pop-up. ----
const waitingCall = () => calls.find((c) => c !== session && c._incoming && !c.isEstablished() && !c.isEnded())
const ringingCall = () => calls.find((c) => c._incoming && !c.isEstablished() && !c.isEnded() && !c._answering)
let ringCtx = null, ringTimer = null, ringMode = null, ringFor = null, ringNoted = ''
function startTone(mode) {   // 'ring': South African double ring (400+450 Hz); 'beep': one short 440 Hz beep every 4 s
  if (ringMode === mode) return
  stopTone(); ringMode = mode
  ringCtx = new AudioContext()
  if (cfg().spkId && ringCtx.setSinkId) ringCtx.setSinkId(cfg().spkId).catch(() => {})
  const burst = (freqs, dur, vol, at) => { for (const f of freqs) {
    const o = ringCtx.createOscillator(), g = ringCtx.createGain()
    o.frequency.value = f; g.gain.value = vol; o.connect(g).connect(ringCtx.destination); o.start(at); o.stop(at + dur) } }
  const cycle = () => {
    if (!ringCtx) return
    const t = ringCtx.currentTime + 0.05
    if (mode === 'ring') { burst([400, 450], 0.4, 0.12, t); burst([400, 450], 0.4, 0.12, t + 0.6) }
    else burst([440], 0.3, 0.05, t)
  }
  cycle(); ringTimer = setInterval(cycle, mode === 'ring' ? 3000 : 4000)
}
function stopTone() { clearInterval(ringTimer); ringTimer = null; ringCtx?.close().catch(() => {}); ringCtx = null; ringMode = null }
function updateRinging() {
  const r = ringingCall()
  if (!r) { stopTone(); if (ringFor) { ringFor = null; ringNoted = ''; callUi.ringStop() }; return }
  const busy = calls.some((c) => c !== r && c.isEstablished()) || otherApps.length > 0
  if (r._silenced) stopTone(); else startTone(busy ? 'beep' : 'ring')
  const note = `${user(r)}|${busy}|${r._silenced}`
  if (ringFor !== r || ringNoted !== note) { ringFor = r; ringNoted = note; callUi.ringStart({ number: user(r), busy, silenced: r._silenced }) }
  refresh()
}
async function answerCall(s) {
  if (!s || s.isEnded() || s.isEstablished()) return
  s._answering = true; updateRinging()
  const stream = await openMic()
  if (!stream) { s._answering = false; updateRinging(); return }   // keeps ringing: free the mic and press Answer again
  if (s.isEnded()) { stream.getTracks().forEach((t) => t.stop()); return }
  // the call in progress waits on hold (in a conference the new call simply joins the list; Merge adds it)
  if (!mix) for (const c of calls) if (c !== s && c.isEstablished() && !c.isOnHold().local) c.hold()
  session = s
  own(s, stream).answer({ mediaStream: stream, pcConfig: pcConfig() }); refresh()
}
function declineCall(s) {
  if (!s || s.isEnded() || s.isEstablished()) return
  s._declined = true; s.terminate({ status_code: 486, reason_phrase: 'Busy Here' })
}
function silenceCall(s) { if (s) { s._silenced = true; updateRinging() } }
callUi.onAction((a) => {
  const r = ringingCall()
  if (a === 'answer') answerCall(r); else if (a === 'decline') declineCall(r); else if (a === 'silence') silenceCall(r)
})

// ---- Another app's call (Teams, Zoom, WhatsApp, Skype…): Windows says which other apps use the microphone. While
// one does, our calls go on hold (the other side hears hold music) and come back when it stops; a call coming in
// beeps instead of ringing. Pressing Hold resumes anyway (e.g. an app that keeps the microphone open). ----
let otherApps = [], userResumed = false
async function checkOtherCall() {
  if (!calls.length) { otherApps = []; userResumed = false; return }
  try { otherApps = await callUi.micOthers() } catch { otherApps = [] }
  if (!otherApps.length) {
    userResumed = false
    for (const c of calls) if (c._autoHeld) { c._autoHeld = false; if (!c.isEnded() && c.isOnHold().local && !mix) c.unhold() }
    if (mixAutoMuted && mix) { mix.mic.gain.value = muted ? 0 : 1 }
    mixAutoMuted = false
  } else if (!userResumed) {
    for (const c of calls) if (c.isEstablished() && !c.isOnHold().local && !mix) { c._autoHeld = true; c.hold() }
    if (mix && !mixAutoMuted) { mixAutoMuted = true; mix.mic.gain.value = 0; for (const c of mix.calls) c._autoHeld = true }
  }
  refresh()
}
let mixAutoMuted = false
setInterval(() => { if (calls.length) checkOtherCall().then(updateRinging) }, 1500)

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
/** The microphone for a call. Windows can refuse the chosen one ("NotReadableError: Could not start audio source":
 *  held by another app, antivirus mic protection, a format it cannot open), so fall back: saved settings -> plain
 *  default -> each other microphone. null (and a clear message) when none starts. */
async function openMic() {
  const tries = [media(), { audio: true, video: false }]
  try {
    for (const d of await navigator.mediaDevices.enumerateDevices())
      if (d.kind === 'audioinput' && !['default', 'communications'].includes(d.deviceId)) tries.push({ audio: { deviceId: { exact: d.deviceId } }, video: false })
  } catch {}
  let err
  for (const c of tries) {
    try { return await navigator.mediaDevices.getUserMedia(c) } catch (e) { err = e; console.warn('mic', JSON.stringify(c), e.name, e.message); if (e.name === 'NotAllowedError') break }
  }
  status(err?.name === 'NotAllowedError' ? 'Microphone blocked: allow apps to use it in Windows Settings > Privacy > Microphone'
    : 'Microphone busy or blocked: close apps using it, check antivirus microphone protection, then try again')
  return null
}
/** JsSIP leaves a stream it was given running, so stop it when the call ends. */
const own = (s, stream) => { s._stream = stream; return s }
async function dial(n) {
  if (!n || !ua) return
  const stream = await openMic()
  if (stream) own(ua.call(`sip:${n}@${domain(acc.tenant)}`, { mediaStream: stream, pcConfig: pcConfig() }), stream)
}

// ---- Accounts: several saved, one active (acc); the others are kept in acc.saved ----
let adding = false
const login = (a) => ({ tenant: a.tenant.trim(), user: a.user.trim(), pass: a.pass })
const key = (a) => `${domain(a.tenant)}|${a.user.trim()}`
/** Make [a] the active account (registers it); the previous one stays in the list. Device settings and DND stay. */
async function useAccount(a) {
  if (calls.length) { alert('Finish the call to switch accounts.'); return }
  await activate(a, [acc && login(acc), ...(acc?.saved || [])].filter((x) => x && key(x) !== key(a)))
}
async function activate(a, saved) {
  acc = { ...login(a), settings: acc?.settings, dndUntil: acc?.dndUntil, saved }
  await store.save(acc); directory = []
  for (const id of ['settings', 'login', 'contacts']) show(id, false)
  show('phone', true); connect(); renderDnd(); signedIn(true)
}
/** Log [a] out and forget it; with no account left, back to the sign-in screen. */
async function logOut(a) {
  if (calls.length) { alert('Finish the call first.'); return }
  if (!confirm(`Log out of extension ${a.user} (${domain(a.tenant)})? It is removed from this computer.`)) return
  if (key(a) !== key(acc)) { acc.saved = acc.saved.filter((x) => key(x) !== key(a)); await store.save(acc); renderAccounts(); return }
  const [next, ...rest] = acc.saved || []
  if (next) { await activate(next, rest); return }
  retire(ua); ua = null; await store.clear(); acc = null; directory = []
  show('settings', false); show('login', true); status('Not registered'); signedIn(false)
}
function renderAccounts() {
  $('s-accounts').replaceChildren(...[acc, ...(acc.saved || [])].map((a) => {
    const active = a === acc
    const row = document.createElement('div'); row.className = 'contact'
    const who = document.createElement('div'); who.textContent = `Extension ${a.user}${active ? ' (active)' : ''}`
    const sub = document.createElement('small'); sub.textContent = domain(a.tenant); who.append(document.createElement('br'), sub)
    const btns = document.createElement('div')
    if (!active) btns.append(Object.assign(document.createElement('button'), { className: 'go', textContent: 'Use', onclick: () => useAccount(a) }))
    btns.append(Object.assign(document.createElement('button'), { className: 'end', textContent: 'Log out', onclick: () => logOut(a) }))
    row.append(who, btns); return row
  }))
}
$('s-add').onclick = () => {
  if (calls.length) { alert('Finish the call to add an account.'); return }
  adding = true
  for (const id of ['tenant', 'user', 'pass']) $(id).value = ''
  $('domain').textContent = ''; show('login-cancel', true); show('settings', false); show('login', true)
}
$('login-cancel').onclick = () => { adding = false; show('login-cancel', false); show('login', false); show('settings', true) }

$('signin').onclick = async () => {
  const a = { tenant: $('tenant').value, user: $('user').value, pass: $('pass').value }
  if (!a.tenant.trim() || !a.user.trim() || !a.pass) return
  if (adding) { adding = false; show('login-cancel', false); await useAccount(a); return }
  acc = { ...login(a), saved: [] }
  await store.save(acc); show('login', false); show('phone', true); connect(); renderDnd(); signedIn(true)
}

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
  renderAccounts()
  show('s-startup-row', navigator.userAgent.includes('Windows')); $('s-startup').checked = await appShell.startup()
  for (const id of ['contacts', 'dnd-pick', 'login']) show(id, false)
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
  await store.save(acc); applySink(); appShell.setStartup($('s-startup').checked)
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
  show('phone', false); show('contacts', true); $('c-search').focus()
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
$('answer').onclick = () => answerCall(session)
$('w-answer').onclick = () => answerCall(waitingCall())
$('w-decline').onclick = () => declineCall(waitingCall())
$('w-silence').onclick = () => silenceCall(waitingCall())
$('hang').onclick = () => {   // in a conference, hang up on everyone; otherwise the call in front
  if (session && session._incoming && !session.isEstablished()) { declineCall(session); return }
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
$('hold').onclick = () => {
  if (!session) return
  if (session.isOnHold().local) {
    if (session._autoHeld) { session._autoHeld = false; userResumed = true }   // resume although another app has the mic
    for (const c of calls) if (c !== session && c.isEstablished() && !c.isOnHold().local && !mix) c.hold()
    session.unhold()
  } else session.hold()
}
$('add').onclick = () => {   // hold the call (unless in a conference) and ring the new person; Merge joins them
  const n = prompt(mix ? 'Add to conference: extension or number' : 'Add participant: extension or number\n(the current call goes on hold; press Merge when they answer)')
  if (!n) return
  if (!mix) session?.hold()
  dial(n.trim())
}
$('merge').onclick = merge
// ---- Transfer: "Transfer now" (blind, SIP REFER) or "Ask first" (attended: the caller waits on hold while you talk to
// the new person, then Complete transfer joins them: REFER with Replaces; the PBX connects them and drops us) ----
let xferFrom = null
$('xfer').onclick = () => { $('x-num').value = ''; show('xfer-pick', true); $('x-num').focus() }
$('x-cancel').onclick = () => show('xfer-pick', false)
$('x-blind').onclick = () => {
  const n = $('x-num').value.trim(); if (!n || !session) return
  show('xfer-pick', false); session.refer(`sip:${n}@${domain(acc.tenant)}`)
}
$('x-ask').onclick = () => {
  const n = $('x-num').value.trim(); if (!n || !session) return
  show('xfer-pick', false)
  xferFrom = session
  if (!session.isOnHold().local) session.hold()
  dial(n)
}
$('x-complete').onclick = () => {
  const from = xferFrom, to = session
  if (!from || from.isEnded() || !to || to === from) return
  xferFrom = null
  from.refer(to.remote_identity.uri.toString(), { replaces: to })
  setTimeout(() => { for (const c of [from, to]) if (!c.isEnded()) c.terminate() }, 4000)   // normally the PBX ends both first
  refresh()
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
  const stream = await openMic()
  if (!stream) return
  track = stream.getAudioTracks()[0]
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
  for (const id of ['contacts', 'settings', 'dnd-pick']) show(id, false)
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
  $('dnd').title = u ? `Do Not Disturb until ${when(u)}` : 'Do Not Disturb'; $('dnd').classList.toggle('dndon', !!u)
  $('status').classList.toggle('dnd', !!u); $('status-pill').classList.toggle('dnd', !!u)
}
setInterval(renderDnd, 15000)
$('dnd').onclick = () => {
  const now = Date.now()
  $('dnd-morning').textContent = `Until ${when(nextMorning())}`
  Object.assign($('dnd-at'), { min: localInput(now), max: localInput(now + MAX_DND), value: localInput(now + 3600000) })
  show('dnd-stop', !!dndUntil())
  for (const id of ['contacts', 'settings', 'login']) show(id, false)
  show('phone', false); show('dnd-pick', true)
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

store.version().then((v) => { for (const e of document.querySelectorAll('.version')) e.textContent = `Version: ${v}` })

store.load().then(async (a) => {
  if (a) { acc = a; show('login', false); show('phone', true); connect(); renderDnd(); signedIn(true) }
  dialFromLink(await links.pending())
})

// ---- Call timer and caller names ----
const initial = (t) => (/[a-z]/i.test(t) ? t.trim()[0].toUpperCase() : '#')
const mmss = (ms) => { const t = Math.round(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, x = String(t % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${x}` : `${m}:${x}` }
function tick() { $('timer').textContent = session?._log?.answered && session.isEstablished() ? `· ${mmss(Date.now() - session._log.answered)}` : '' }
setInterval(() => { if (session) tick() }, 1000)
/** Names for numbers from the company contacts (loaded quietly after sign-in), else the caller ID name. */
let names = new Map()
async function loadNames() {
  const r = await store.directory().catch(() => ({}))
  if (!r?.contacts) return
  names = new Map(r.contacts.flatMap((c) => c.numbers.map((n) => [n.number.replace(/[^+0-9*#]/g, ''), c.name])))
  renderRecent()
}
const nameOf = (number, cid) => names.get(number) || (cid && cid !== number ? cid : number)

// ---- Recent calls (owner 2026-10-08): kept on this computer per account, newest first, at most 300 ----
const RECENT_MAX = 300
const recentKey = () => acc && `n2it.recent.${key(acc)}`
const ls = { get: (k, d) => { try { return JSON.parse(localStorage.getItem(k)) ?? d } catch { return d } },
  set: (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)) } catch {} } }
const recent = () => (acc ? ls.get(recentKey(), []) : [])
function addRecent(r) { if (!acc) return; ls.set(recentKey(), [r, ...recent()].slice(0, RECENT_MAX)); renderRecent() }
function logCall(s) {
  if (!s._log || s._logged) return
  s._logged = true
  const l = s._log, answered = !!l.answered
  addRecent({ number: l.number, name: l.name, dir: l.dir, at: l.at, secs: answered ? Math.round((Date.now() - l.answered) / 1000) : 0,
    result: answered ? 'answered' : l.dir === 'out' ? 'no-answer' : s._declined ? 'declined' : 'missed' })
}
let recentFilter = 'all'
const dayOf = (t) => { const d = new Date(t), now = new Date(), y = new Date(now); y.setDate(now.getDate() - 1)
  if (d.toDateString() === now.toDateString()) return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  if (d.toDateString() === y.toDateString()) return 'Yesterday'
  return d.toLocaleDateString([], { day: 'numeric', month: 'short' }) }
const icon = (id) => { const ns = 'http://www.w3.org/2000/svg', v = document.createElementNS(ns, 'svg'), u = document.createElementNS(ns, 'use')
  v.setAttribute('class', 'i'); u.setAttribute('href', `#i-${id}`); v.append(u); return v }
function renderRecent() {
  const all = recent(), rows = recentFilter === 'missed' ? all.filter((r) => r.result === 'missed') : all
  $('recent').replaceChildren(...rows.map((r) => {
    const row = document.createElement('div'); row.className = 'rc' + (r.result === 'missed' ? ' missed' : '')
    const name = nameOf(r.number, r.name)
    const av = Object.assign(document.createElement('div'), { className: 'av', textContent: initial(name) })
    const who = document.createElement('div'); who.className = 'who'
    const sub = document.createElement('small')
    const what = r.result === 'missed' ? (r.dnd ? 'Missed (DND)' : 'Missed') : r.result === 'declined' ? 'Declined'
      : r.result === 'no-answer' ? 'No answer' : `${r.dir === 'in' ? 'Incoming' : 'Outgoing'} · ${mmss(r.secs * 1000)}`
    sub.append(icon(r.result === 'missed' ? 'missed' : r.dir), `${name !== r.number ? r.number + ' · ' : ''}${what}`)
    who.append(Object.assign(document.createElement('div'), { textContent: name }), sub)
    const t = Object.assign(document.createElement('time'), { textContent: dayOf(r.at), title: new Date(r.at).toLocaleString() })
    const call = Object.assign(document.createElement('button'), { className: 'go', title: `Call ${r.number}` }); call.append(icon('call'))
    call.onclick = (e) => { e.stopPropagation(); narrowClose(); dial(r.number) }
    row.onclick = () => { if (!calls.length) { dialFromLink(r.number); narrowClose() } }   // into the dial box, ready to call
    row.ondblclick = () => { narrowClose(); dial(r.number) }
    row.append(av, who, t, call); return row
  }))
  if (!rows.length) $('recent').append(Object.assign(document.createElement('div'), { className: 'empty',
    textContent: recentFilter === 'missed' ? 'No missed calls' : 'Calls you make and receive show here' }))
  badge()
}
for (const b of document.querySelectorAll('.seg button')) b.onclick = () => {
  recentFilter = b.dataset.f; for (const x of document.querySelectorAll('.seg button')) x.classList.toggle('sel', x === b); renderRecent()
}
$('s-clear-recent').onclick = () => { if (acc && confirm('Clear the recent calls list on this computer?')) { ls.set(recentKey(), []); renderRecent() } }

// ---- Side bar: open or closed (remembered); on a narrow window it slides over the keypad ----
const sideOpen = () => !document.body.classList.contains('side-closed')
const narrow = () => innerWidth <= 720
function setSide(open, remember = true) {
  document.body.classList.toggle('side-closed', !open)
  if (remember && !narrow()) ls.set('n2it.side', open)
  if (open) { ls.set(`n2it.seen.${key(acc || { tenant: '', user: '' })}`, Date.now()); badge() }
}
const narrowClose = () => { if (narrow()) setSide(false, false) }
/** Red count on the side bar button: missed calls since the list was last looked at. */
function badge() {
  if (!acc) return
  if (sideOpen() && document.hasFocus()) ls.set(`n2it.seen.${key(acc)}`, Date.now())
  const seen = ls.get(`n2it.seen.${key(acc)}`, 0), n = recent().filter((r) => r.result === 'missed' && r.at > seen).length
  $('missed-badge').textContent = n > 9 ? '9+' : n; show('missed-badge', n > 0)
}
addEventListener('focus', badge)
$('side-toggle').onclick = () => setSide(!sideOpen())
$('side-close').onclick = () => setSide(false)
document.querySelector('main').addEventListener('mousedown', narrowClose)
setSide(narrow() ? false : ls.get('n2it.side', true), false)
