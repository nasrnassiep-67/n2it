package za.co.n2it.phone

import android.content.Context
import android.provider.ContactsContract
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import kotlinx.coroutines.launch
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.DateFormat
import java.util.Date

private val Green = Color(0xFF2E9E4F)
private val Red = Color(0xFFD64545)
private val Orange = Color(0xFFE65100)
private val dndTime = java.text.SimpleDateFormat("EEE d MMM, HH:mm", java.util.Locale.getDefault())

/** True while a call is up but the user left the call screen to use the rest of the app. */
private val callMinimised = mutableStateOf(false)

/** Dial from the app: with a call already up, hold it and ring [number] (ready to merge or transfer). */
private fun dial(number: String) {
    if (SipManager.call.value != null) { SipManager.addParticipant(number); callMinimised.value = false }
    else SipManager.call(number)
}

@Composable
fun App(onSignedIn: () -> Unit, onSignedOut: () -> Unit) {
    val ctx = LocalContext.current
    var loggedIn by remember { mutableStateOf(Account.load(ctx).isConfigured) }
    val call by SipManager.call.collectAsState()

    var minimised by callMinimised
    // A new incoming call, or the end of the call, always brings the call screen back.
    LaunchedEffect(call == null, call?.state == CallState.IncomingReceived) {
        if (call == null || call?.state == CallState.IncomingReceived) minimised = false
    }
    if (call != null && !minimised) { CallScreen(call!!, onMinimise = { minimised = true }); return }
    if (!loggedIn) {
        LoginScreen { loggedIn = true; onSignedIn() }
    } else {
        Column {
            call?.let { ReturnToCallBar(it) { minimised = false } }
            DndBanner(topOfScreen = call == null)
            MainTabs(onSignOut = { SipManager.signOut(ctx); onSignedOut(); loggedIn = false })
        }
    }
}

@Composable
private fun ReturnToCallBar(call: CallInfo, onClick: () -> Unit) {
    Surface(color = Green, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Call, null, tint = Color.White); Spacer(Modifier.width(10.dp))
            Text((if (call.onHold) "On hold: " else "On call: ") + (call.name ?: call.number) + " · tap to return",
                color = Color.White, maxLines = 1)
        }
    }
}

@Composable
fun StatusRow() {
    val ok by SipManager.registered.collectAsState()
    val status by SipManager.status.collectAsState()
    val dnd by SipManager.dndUntil.collectAsState()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Surface(color = if (!ok) Red else if (dnd != null) Orange else Green, shape = CircleShape, modifier = Modifier.size(10.dp)) {}
        Spacer(Modifier.width(6.dp)); Text(if (ok && dnd != null) "Do Not Disturb" else status, style = MaterialTheme.typography.bodySmall)
    }
}

/** Orange banner on every screen while DND is on, so it can't be forgotten. */
@Composable
private fun DndBanner(topOfScreen: Boolean) {
    val until by SipManager.dndUntil.collectAsState()
    val u = until ?: return
    Surface(color = Orange, modifier = Modifier.fillMaxWidth()) {
        Row((if (topOfScreen) Modifier.statusBarsPadding() else Modifier).padding(start = 16.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.DoNotDisturbOn, null, tint = Color.White); Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text("DND enabled. Please disable DND to receive calls.", color = Color.White, fontSize = 14.sp)
                Text("Until " + dndTime.format(java.util.Date(u)), color = Color.White, fontSize = 12.sp)
            }
            TextButton({ SipManager.setDnd(null) }) { Text("Turn off", color = Color.White) }
        }
    }
}

/** DND button: always with an end time, from 1 hour up to 2 weeks. */
@Composable
fun DndButton() {
    val until by SipManager.dndUntil.collectAsState()
    var open by remember { mutableStateOf(false) }
    FilterChip(selected = until != null, onClick = { open = true },
        leadingIcon = { Icon(Icons.Default.DoNotDisturbOn, null) },
        label = { Text(until?.let { "DND until " + dndTime.format(java.util.Date(it)) } ?: "Do Not Disturb") },
        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Orange, selectedLabelColor = Color.White,
            selectedLeadingIconColor = Color.White))
    if (open) DndDialog(active = until != null) { open = false }
}

@Composable
private fun DndDialog(active: Boolean, onDone: () -> Unit) {
    val ctx = LocalContext.current
    fun set(until: Long) { SipManager.setDnd(until); onDone() }
    val hour = 3_600_000L
    // Next 08:00 (today if it's still early, otherwise tomorrow)
    val morning = java.util.Calendar.getInstance().apply {
        set(java.util.Calendar.HOUR_OF_DAY, 8); set(java.util.Calendar.MINUTE, 0); set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0)
        if (timeInMillis <= System.currentTimeMillis()) add(java.util.Calendar.DAY_OF_MONTH, 1)
    }.timeInMillis
    AlertDialog(
        onDismissRequest = onDone,
        title = { Text("Do Not Disturb") },
        text = { Column {
            Text("Calls to this app go to voicemail until the time you choose. Other phones on your extension still ring.",
                style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.height(8.dp))
            listOf("1 hour" to 1, "2 hours" to 2, "4 hours" to 4).forEach { (label, h) ->
                TextButton({ set(System.currentTimeMillis() + h * hour) }) { Text(label) }
            }
            TextButton({ set(morning) }) { Text("Until " + dndTime.format(java.util.Date(morning))) }
            TextButton({ pickDndTime(ctx) { set(it) } }) { Text("Choose date and time…") }
            if (active) TextButton({ SipManager.setDnd(null); onDone() }) { Text("Turn off now", color = Red) }
        } },
        confirmButton = { TextButton(onDone) { Text("Cancel") } })
}

/** Date then time, within the next 2 weeks. */
private fun pickDndTime(ctx: Context, onPicked: (Long) -> Unit) {
    val now = System.currentTimeMillis()
    val c = java.util.Calendar.getInstance()
    android.app.DatePickerDialog(ctx, { _, y, m, d ->
        android.app.TimePickerDialog(ctx, { _, h, min ->
            val t = java.util.Calendar.getInstance().apply { set(y, m, d, h, min, 0) }.timeInMillis
            if (t <= now || t > now + SipManager.MAX_DND_MS)
                android.widget.Toast.makeText(ctx, "Choose a time within the next 2 weeks", android.widget.Toast.LENGTH_LONG).show()
            else onPicked(t)
        }, c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE), true).show()
    }, c.get(java.util.Calendar.YEAR), c.get(java.util.Calendar.MONTH), c.get(java.util.Calendar.DAY_OF_MONTH)).apply {
        datePicker.minDate = now
        datePicker.maxDate = now + SipManager.MAX_DND_MS
    }.show()
}

/**
 * SIP password box. KeyboardType.Password tells the keyboard it is a password, so it does not autocorrect, suggest or
 * capitalise a pasted 20-character password (2026-10-20: a pasted password reached the PBX changed). Invisible
 * characters a chat app adds when it is copied (spaces, line breaks, zero-width marks) are dropped; the eye shows it.
 */
@Composable
fun PasswordField(value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    var show by remember { mutableStateOf(false) }
    OutlinedTextField(value, { onChange(it.filter { c -> !c.isWhitespace() && !c.isISOControl() && c !in "\u200B\u200C\u200D\u2060\uFEFF" }) },
        label = { Text("Password") }, singleLine = true, modifier = modifier,
        visualTransformation = if (show) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
        trailingIcon = {
            IconButton({ show = !show }) {
                Icon(if (show) Icons.Default.VisibilityOff else Icons.Default.Visibility, if (show) "Hide password" else "Show password")
            }
        })
}

/** What to tell the user when the PBX refused the sign-in or did not answer (null = registered). */
fun signInProblem(o: SipManager.RegOutcome?, domain: String): String? = when (o) {
    is SipManager.RegOutcome.Ok -> null
    is SipManager.RegOutcome.Failed -> when (o.code) {
        401, 403, 407 -> "Wrong extension or password. Check them and try again."
        404 -> "Extension not found at $domain."
        else -> "The PBX refused the sign-in (${o.reason.ifBlank { o.code.toString() }})."
    }
    null -> "No answer from $domain. Check the company code and your internet connection."
}

@Composable
fun LoginScreen(done: () -> Unit) {
    val ctx = LocalContext.current
    var acc by remember { mutableStateOf(Account.load(ctx)) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().padding(24.dp).systemBarsPadding()) {
        Spacer(Modifier.weight(1f))
        Text("N2IT Phone", fontSize = 32.sp)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(acc.tenant, { acc = acc.copy(tenant = it) }, label = { Text("Company code") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
            supportingText = { Text(if (acc.domain.isEmpty()) "Your company code, or the full server address" else "Connects to ${acc.domain}") })
        OutlinedTextField(acc.user, { acc = acc.copy(user = it) }, label = { Text("Extension") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        PasswordField(acc.password, { acc = acc.copy(password = it) }, Modifier.fillMaxWidth())
        Spacer(Modifier.height(16.dp))
        Button(onClick = {
                busy = true; problem = null
                scope.launch {
                    val p = signInProblem(SipManager.verify(acc), acc.domain)
                    busy = false
                    if (p == null) { Account.save(ctx, acc); done() } else { problem = p; SipManager.stopRegistering() }
                }
            },
            enabled = acc.isConfigured && !busy, modifier = Modifier.fillMaxWidth()) { Text(if (busy) "Signing in…" else "Sign in") }
        problem?.let { Spacer(Modifier.height(8.dp)); Text(it, color = Red) }
        Spacer(Modifier.weight(1f))
        VersionText()
    }
}

@Composable
fun MainTabs(onSignOut: () -> Unit) {
    var tab by remember { mutableIntStateOf(2) }
    val vm by SipManager.hasVoicemail.collectAsState()
    Scaffold(bottomBar = {
        NavigationBar {
            listOf("Contacts" to Icons.Default.Contacts, "Recents" to Icons.Default.History, "Keypad" to Icons.Default.Dialpad,
                "Voicemail" to Icons.Default.Voicemail, "Settings" to Icons.Default.Settings).forEachIndexed { i, (name, icon) ->
                NavigationBarItem(selected = tab == i, onClick = { tab = i }, label = { Text(name, maxLines = 1, fontSize = 11.sp) },
                    icon = { BadgedBox(badge = { if (i == 3 && vm) Badge() }) { Icon(icon, name) } })
            }
        }
    }) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            when (tab) {
                0 -> ContactsTab()
                1 -> RecentsTab()
                2 -> KeypadTab()
                3 -> VoicemailTab()
                else -> SettingsTab(onSignOut)
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun KeypadTab() {
    var number by remember { mutableStateOf("") }
    var menu by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    val registered by SipManager.registered.collectAsState()
    Column(Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        StatusRow(); Spacer(Modifier.height(4.dp)); DndButton(); Spacer(Modifier.height(8.dp))
        // Long-press the number to paste a copied one ("+27 82 123-4567" -> "+27821234567") or copy it.
        Box(Modifier.fillMaxWidth().combinedClickable(onClick = {}, onLongClick = { menu = true }), contentAlignment = Alignment.Center) {
            Text(number.ifEmpty { " " }, fontSize = 34.sp, maxLines = 1)
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Paste") }, leadingIcon = { Icon(Icons.Default.ContentPaste, null) }, onClick = {
                    val digits = clipboard.getText()?.text.orEmpty().filter { it in "+0123456789*#" }
                    if (digits.isNotEmpty()) number = digits
                    menu = false
                })
                if (number.isNotEmpty()) DropdownMenuItem(text = { Text("Copy") }, leadingIcon = { Icon(Icons.Default.ContentCopy, null) }, onClick = {
                    clipboard.setText(AnnotatedString(number)); menu = false
                })
            }
        }
        Spacer(Modifier.height(16.dp))
        Pad { number += it }
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Spacer(Modifier.size(72.dp))
            FilledIconButton(onClick = { dial(number); number = "" }, enabled = number.isNotEmpty() && registered,
                modifier = Modifier.size(72.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Green)) {
                Icon(Icons.Default.Call, "Call", tint = Color.White)
            }
            IconButton(onClick = { number = number.dropLast(1) }, modifier = Modifier.size(72.dp)) {
                if (number.isNotEmpty()) Icon(Icons.Default.Backspace, "Delete")
            }
        }
    }
}

@Composable
fun Pad(onKey: (String) -> Unit) {
    listOf("123", "456", "789", "*0#").forEach { row ->
        Row(horizontalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.padding(vertical = 6.dp)) {
            row.forEach { k ->
                FilledTonalButton(onClick = { onKey(k.toString()) }, shape = CircleShape, modifier = Modifier.size(72.dp),
                    contentPadding = PaddingValues(0.dp)) { Text(k.toString(), fontSize = 28.sp) }
            }
        }
    }
}

@Composable
fun RecentsTab() {
    val recents by SipManager.recents.collectAsState()
    if (recents.isEmpty()) Box(Modifier.fillMaxSize(), Alignment.Center) { Text("No recent calls") }
    LazyColumn {
        items(recents) { r ->
            ListItem(
                modifier = Modifier.clickable { dial(r.number) },
                leadingContent = { Icon(if (r.incoming) Icons.Default.CallReceived else Icons.Default.CallMade, null,
                    tint = if (r.missed) Red else MaterialTheme.colorScheme.onSurfaceVariant) },
                headlineContent = { Text(r.number, color = if (r.missed) Red else Color.Unspecified) },
                supportingContent = { Text(DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(r.time))) })
        }
    }
}

data class PhoneContact(val name: String, val number: String)

private fun loadContacts(c: Context): List<PhoneContact> = try {
    val out = mutableListOf<PhoneContact>()
    c.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
        arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
        null, null, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)?.use {
        while (it.moveToNext()) out += PhoneContact(it.getString(0) ?: "", it.getString(1) ?: "")
    }
    out
} catch (e: SecurityException) { emptyList() }

/**
 * Company address book from FusionPBX > Apps > Contacts, served per tenant by the PBX
 * (`/app/n2it/contacts.php`, HTTP Basic with the extension and its SIP password; see IOS-MAC-HANDOVER.md).
 * Empty when the account isn't set up, the endpoint isn't deployed yet (404) or the request fails.
 */
private fun loadCompanyContacts(c: Context): List<PhoneContact> = try {
    val acc = Account.load(c)
    if (!acc.isConfigured) emptyList() else {
        val conn = java.net.URL("https://${acc.domain}/app/n2it/contacts.php").openConnection() as java.net.HttpURLConnection
        conn.connectTimeout = 15_000; conn.readTimeout = 15_000
        val login = android.util.Base64.encodeToString("${acc.user.trim()}:${acc.password}".toByteArray(), android.util.Base64.NO_WRAP)
        conn.setRequestProperty("Authorization", "Basic $login")
        try {
            if (conn.responseCode != 200) emptyList() else {
                val list = org.json.JSONObject(conn.inputStream.bufferedReader().readText()).getJSONArray("contacts")
                val out = mutableListOf<PhoneContact>()
                for (i in 0 until list.length()) {
                    val o = list.getJSONObject(i)
                    val nums = o.optJSONArray("numbers") ?: continue
                    for (j in 0 until nums.length()) {
                        val n = nums.getJSONObject(j).optString("number")
                        if (n.isNotBlank()) out += PhoneContact(o.optString("name"), n)
                    }
                }
                out.sortedBy { it.name.lowercase() }
            }
        } finally { conn.disconnect() }
    }
} catch (e: Exception) { emptyList() }

@Composable
fun ContactsTab() {
    val ctx = LocalContext.current
    val all = remember { loadContacts(ctx) }
    var company by remember { mutableStateOf(emptyList<PhoneContact>()) }
    LaunchedEffect(Unit) {
        company = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { loadCompanyContacts(ctx) }
        companyCache = company
    }
    var q by remember { mutableStateOf("") }
    fun matches(l: List<PhoneContact>) = l.filter { q.isBlank() || it.name.contains(q, true) || it.number.contains(q) }
    val companyList = matches(company)
    val list = matches(all)
    Column {
        OutlinedTextField(q, { q = it }, placeholder = { Text("Search") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(12.dp))
        if (all.isEmpty() && company.isEmpty()) Box(Modifier.fillMaxSize(), Alignment.Center) { Text("No contacts (allow Contacts permission)") }
        LazyColumn {
            if (companyList.isNotEmpty()) item { SectionHeader("Company") }
            items(companyList) { ContactRow(it) }
            if (company.isNotEmpty() && list.isNotEmpty()) item { SectionHeader("Phone") }
            items(list) { ContactRow(it) }
        }
    }
}

@Composable
private fun SectionHeader(title: String) =
    Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))

@Composable
private fun ContactRow(c: PhoneContact) =
    ListItem(modifier = Modifier.clickable { dial(c.number.filter { it in "+0123456789*#" }) },
        headlineContent = { Text(c.name) }, supportingContent = { Text(c.number) })

@Composable
fun VoicemailTab() {
    val ctx = LocalContext.current
    val vm by SipManager.hasVoicemail.collectAsState()
    val registered by SipManager.registered.collectAsState()
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Icon(Icons.Default.Voicemail, null, Modifier.size(56.dp))
        Spacer(Modifier.height(16.dp))
        Text(if (vm) "You have new voicemail" else "No new messages", fontSize = 20.sp)
        Spacer(Modifier.height(24.dp))
        Button(onClick = { SipManager.call(Account.load(ctx).voicemail) }, enabled = registered,
            colors = ButtonDefaults.buttonColors(containerColor = Green)) {
            Icon(Icons.Default.Call, null); Spacer(Modifier.width(8.dp)); Text("Call voicemail")
        }
    }
}

@Composable
fun SettingsTab(onSignOut: () -> Unit) {
    val ctx = LocalContext.current
    var acc by remember { mutableStateOf(Account.load(ctx)) }
    var busy by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        StatusRow(); Spacer(Modifier.height(4.dp)); DndButton(); Spacer(Modifier.height(8.dp))
        OutlinedTextField(acc.tenant, { acc = acc.copy(tenant = it) }, label = { Text("Client (e.g. n2it)") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), supportingText = { Text(acc.domain) })
        OutlinedTextField(acc.user, { acc = acc.copy(user = it) }, label = { Text("Extension") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        PasswordField(acc.password, { acc = acc.copy(password = it) }, Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(acc.port.toString(), { acc = acc.copy(port = it.toIntOrNull() ?: acc.port) }, label = { Text("Port") },
                singleLine = true, modifier = Modifier.weight(1f), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            OutlinedTextField(acc.voicemail, { acc = acc.copy(voicemail = it) }, label = { Text("Voicemail no.") },
                singleLine = true, modifier = Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 8.dp)) {
            listOf("UDP", "TCP", "TLS").forEach { t ->
                FilterChip(selected = acc.transport == t, onClick = { acc = acc.copy(transport = t) }, label = { Text(t) })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Encrypt call audio (SRTP)", Modifier.weight(1f))
            Switch(acc.srtp, { acc = acc.copy(srtp = it) })
        }
        Button(onClick = {
                busy = true; saved = null
                scope.launch {
                    val p = signInProblem(SipManager.verify(acc), acc.domain)
                    busy = false
                    if (p == null) { Account.save(ctx, acc); saved = "Saved and registered." }
                    else { saved = p + " Nothing was changed."; SipManager.configure(Account.load(ctx)) }   // keep the working account
                }
            }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(if (busy) "Checking…" else "Save & Register") }
        saved?.let { Text(it, color = if (it.startsWith("Saved")) Color.Unspecified else Red, style = MaterialTheme.typography.bodySmall) }
        HorizontalDivider(Modifier.padding(vertical = 16.dp))
        AccountsSection(onActiveChanged = { acc = it }, onNoneLeft = onSignOut)
        HorizontalDivider(Modifier.padding(vertical = 16.dp))
        EchoSection()
        Spacer(Modifier.height(16.dp))
        VersionText()
    }
}

/** Echo cancellation runs by itself (WebRTC); the background-voices filter can be switched off. */
@Composable
private fun EchoSection() {
    val echo by SipManager.echo.collectAsState()
    Text("Echo cancellation", style = MaterialTheme.typography.titleSmall)
    Text(echo, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    val gate by SipManager.backgroundFilter.collectAsState()
    Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Filter out background voices")
            Text("Keeps people talking nearby out of your calls, mostly on speaker. Turn off if the other side says your voice cuts out. Applies from the next call.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(gate, { SipManager.setBackgroundFilter(it) })
    }
}

@Composable
private fun VersionText() = Text("Version: ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.bodySmall,
    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.fillMaxWidth(),
    textAlign = androidx.compose.ui.text.style.TextAlign.Center)

/**
 * Saved accounts (e.g. a reseller testing several clients). One is active at a time: only it is registered and
 * rings; tap another to switch. Log out removes an account from this phone.
 */
@Composable
private fun AccountsSection(onActiveChanged: (Account) -> Unit, onNoneLeft: () -> Unit) {
    val ctx = LocalContext.current
    val inCall = SipManager.call.collectAsState().value != null
    var active by remember { mutableStateOf(Account.load(ctx)) }
    var others by remember { mutableStateOf(Account.others(ctx)) }
    var adding by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf<Account?>(null) }
    fun refresh() { active = Account.load(ctx); others = Account.others(ctx) }
    fun use(a: Account) { Account.activate(ctx, a); SipManager.switchAccount(a); refresh(); onActiveChanged(a) }

    Text("Accounts", style = MaterialTheme.typography.titleMedium)
    Text(if (inCall) "Finish the call to switch accounts." else "Only the active account receives calls. Tap another to switch.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    ((if (active.isConfigured) listOf(active) else emptyList()) + others).forEach { a ->
        val isActive = a.sameAs(active)
        ListItem(
            modifier = Modifier.clickable(enabled = !isActive && !inCall) { use(a) },
            leadingContent = { RadioButton(selected = isActive, onClick = if (isActive || inCall) null else ({ use(a) })) },
            headlineContent = { Text("Extension ${a.user}") },
            supportingContent = { Text(a.domain + if (isActive) " · active" else "") },
            trailingContent = { TextButton({ leaving = a }, enabled = !inCall) { Text("Log out", color = Red) } })
    }
    OutlinedButton({ adding = true }, enabled = !inCall, modifier = Modifier.fillMaxWidth()) {
        Icon(Icons.Default.PersonAdd, null); Spacer(Modifier.width(8.dp)); Text("Add account")
    }
    if (adding) AddAccountDialog(onDismiss = { adding = false }) { a -> adding = false; use(a) }
    leaving?.let { a ->
        AlertDialog(
            onDismissRequest = { leaving = null },
            title = { Text("Log out of extension ${a.user}?") },
            text = { Text("${a.domain} is removed from this phone. You can add it again later with its password.") },
            confirmButton = { TextButton({
                leaving = null
                val wasActive = a.sameAs(active)
                val next = Account.remove(ctx, a)
                if (next == null) onNoneLeft()
                else { if (wasActive) { SipManager.switchAccount(next); onActiveChanged(next) }; refresh() }
            }) { Text("Log out", color = Red) } },
            dismissButton = { TextButton({ leaving = null }) { Text("Cancel") } })
    }
}

@Composable
private fun AddAccountDialog(onDismiss: () -> Unit, onAdd: (Account) -> Unit) {
    var a by remember { mutableStateOf(Account()) }
    val ctx = LocalContext.current
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add account") },
        text = { Column {
            OutlinedTextField(a.tenant, { a = a.copy(tenant = it) }, label = { Text("Company code") }, singleLine = true,
                supportingText = { Text(if (a.domain.isEmpty()) "e.g. n2it" else "Connects to ${a.domain}") })
            OutlinedTextField(a.user, { a = a.copy(user = it) }, label = { Text("Extension") }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
            PasswordField(a.password, { a = a.copy(password = it) })
            Text("It becomes the active account; the current one stays in the list.", style = MaterialTheme.typography.bodySmall)
            problem?.let { Text(it, color = Red, style = MaterialTheme.typography.bodySmall) }
        } },
        confirmButton = { TextButton({
                val next = a.copy(tenant = a.tenant.trim(), user = a.user.trim())
                busy = true; problem = null
                scope.launch {
                    val p = signInProblem(SipManager.verify(next), next.domain)
                    busy = false
                    if (p == null) onAdd(next) else { problem = p; SipManager.configure(Account.load(ctx)) }   // back to the active one
                }
            }, enabled = a.isConfigured && !busy) { Text(if (busy) "Checking…" else "Add") } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } })
}

@Composable
fun CallScreen(call: CallInfo, onMinimise: () -> Unit) {
    val muted by SipManager.muted.collectAsState()
    var pad by remember { mutableStateOf(false) }
    var transferTo by remember { mutableStateOf<Boolean?>(null) }  // null = closed, false = blind, true = attended
    var adding by remember { mutableStateOf(false) }
    val connected = call.onHold || call.state == CallState.StreamsRunning || call.state == CallState.Connected
    val ringingIn = call.state == CallState.IncomingReceived
    val label = if (call.conference) "Conference · ${call.participants.size + 1} people" else when (call.state) {
        CallState.IncomingReceived -> "Incoming call"
        CallState.OutgoingInit, CallState.OutgoingProgress -> "Calling…"
        CallState.OutgoingRinging, CallState.OutgoingEarlyMedia -> "Ringing…"
        CallState.StreamsRunning, CallState.Connected -> "Connected"
        CallState.Paused, CallState.Pausing -> "On hold"
        else -> ""
    }
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        // Back to contacts/keypad with the call still up; the green bar (or the notification) brings it back.
        BackHandler(enabled = !ringingIn, onBack = onMinimise)
        if (!ringingIn) Row(Modifier.fillMaxWidth()) {
            IconButton(onMinimise) { Icon(Icons.Default.KeyboardArrowDown, "Minimise call") }
        }
        if (call.conference) {
            // One card per person, sharing the screen (owner 2026-10-11: one long line of numbers wrapped over itself)
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            ConferenceCards(call.participants, compact = pad, modifier = Modifier.weight(1f).fillMaxWidth())
            Spacer(Modifier.height(20.dp))
        } else {
            Spacer(Modifier.weight(1f))
            // Phone contact or company book first, then the caller ID name the PBX sent; the number underneath
            val name = rememberContactName(call.number) ?: call.name
            Text(name ?: displayNumber(call.number), fontSize = 34.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (name != null) Text(displayNumber(call.number), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.weight(1f))
        }
        // While dialling: mute and speaker/Bluetooth already, so the user can pick the car or speaker before they answer.
        if (!connected && !ringingIn) Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            FilledTonalIconToggleButton(muted, { SipManager.toggleMute() }, Modifier.size(64.dp)) { Icon(Icons.Default.MicOff, "Mute") }
            AudioRouteButton()
        }
        if (connected) {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                FilledTonalIconToggleButton(muted, { SipManager.toggleMute() }, Modifier.size(64.dp)) { Icon(Icons.Default.MicOff, "Mute") }
                AudioRouteButton()
                FilledTonalIconToggleButton(pad, { pad = it }, Modifier.size(64.dp)) { Icon(Icons.Default.Dialpad, "Keypad") }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                if (!call.conference) {
                    FilledTonalIconToggleButton(call.onHold, { SipManager.toggleHold() }, Modifier.size(64.dp)) { Icon(Icons.Default.Pause, "Hold") }
                    FilledTonalIconButton({ transferTo = false }, Modifier.size(64.dp)) { Icon(Icons.Default.PhoneForwarded, "Transfer") }
                }
                FilledTonalIconButton({ adding = true }, Modifier.size(64.dp)) { Icon(Icons.Default.PersonAdd, "Add participant") }
            }
            if (call.consulting) {
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button({ SipManager.merge() }, colors = ButtonDefaults.buttonColors(containerColor = Green)) {
                        Icon(Icons.Default.CallMerge, null); Spacer(Modifier.width(6.dp)); Text("Merge calls")
                    }
                    if (!call.conference) FilledTonalButton({ SipManager.completeTransfer() }) { Text("Complete transfer") }
                }
            }
            if (pad) { Spacer(Modifier.height(12.dp)); Pad { SipManager.sendDigit(it[0]) } }
        }
        val silenced by SipManager.silenced.collectAsState()
        if (ringingIn && !silenced) { Spacer(Modifier.height(16.dp)); TextButton({ SipManager.silence() }) { Text("Silence") } }
        Spacer(Modifier.height(32.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(56.dp)) {
            if (ringingIn) FilledIconButton({ SipManager.answer() }, Modifier.size(76.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Green)) {
                Icon(Icons.Default.Call, "Answer", tint = Color.White)
            }
            FilledIconButton({ if (ringingIn) SipManager.decline() else SipManager.hangup() }, Modifier.size(76.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Red)) {
                Icon(Icons.Default.CallEnd, "Hang up", tint = Color.White)
            }
        }
        Spacer(Modifier.height(24.dp))
    }
    if (transferTo != null) TransferDialog(
        onDismiss = { transferTo = null },
        onBlind = { SipManager.blindTransfer(it); transferTo = null },
        onConsult = { SipManager.consult(it); transferTo = null })
    val notice by SipManager.notice.collectAsState()
    val ctx = LocalContext.current
    LaunchedEffect(notice) {
        notice?.let { android.widget.Toast.makeText(ctx, it, android.widget.Toast.LENGTH_LONG).show(); SipManager.clearNotice() }
    }
    if (adding) AddParticipantDialog(call.conference, onDismiss = { adding = false }, onAdd = { SipManager.addParticipant(it); adding = false })
}

/** Conference: the space between the status line and the buttons, split evenly between the people (up to 4);
 *  with more people, or while the keypad is open, a scrolling list of short cards. */
@Composable
private fun ConferenceCards(people: List<Participant>, compact: Boolean, modifier: Modifier) {
    val split = !compact && people.size <= 4
    Column(if (split) modifier else modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        people.forEach { p ->
            key(p.id) { ParticipantCard(p, if (split) Modifier.weight(1f).fillMaxWidth() else Modifier.fillMaxWidth().height(76.dp)) }
        }
    }
}

/** Name, number, status and a hang-up for this person only. Tall cards stack it centred; short ones in a row. */
@Composable
private fun ParticipantCard(p: Participant, modifier: Modifier) {
    val name = rememberContactName(p.number) ?: p.name
    val title = name ?: displayNumber(p.number)
    val number = if (name != null) displayNumber(p.number) else null
    val (status, statusColor) = when (p.status) {
        Participant.Status.Talking -> "Talking" to Green
        Participant.Status.Ringing -> "Ringing…" to Color(0xFFE0A030)
        Participant.Status.OnHold -> "On hold" to MaterialTheme.colorScheme.onSurfaceVariant
    }
    val drop: @Composable () -> Unit = {
        FilledIconButton({ SipManager.dropParticipant(p.id) }, Modifier.size(44.dp),
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = Red)) { Icon(Icons.Default.CallEnd, "Hang up on $title", tint = Color.White) }
    }
    Surface(modifier, shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
        BoxWithConstraints(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            if (maxHeight >= 150.dp) Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Initial(title, 64.dp)
                Spacer(Modifier.height(10.dp))
                Text(title, fontSize = 22.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                number?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Text(status, color = statusColor, style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(10.dp))
                drop()
            } else Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Initial(title, 44.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row {
                        number?.let { Text("$it · ", color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, style = MaterialTheme.typography.bodySmall) }
                        Text(status, color = statusColor, maxLines = 1, style = MaterialTheme.typography.bodySmall)
                    }
                }
                Spacer(Modifier.width(8.dp))
                drop()
            }
        }
    }
}

/** Round badge with the first letter of a name, or a person icon for a bare number. */
@Composable
private fun Initial(title: String, size: androidx.compose.ui.unit.Dp) {
    Box(Modifier.size(size).background(MaterialTheme.colorScheme.primaryContainer, CircleShape), contentAlignment = Alignment.Center) {
        val letter = title.firstOrNull { it.isLetter() }?.uppercaseChar()
        if (letter != null) Text("$letter", fontSize = (size.value * 0.42f).sp, color = MaterialTheme.colorScheme.onPrimaryContainer)
        else Icon(Icons.Default.Person, null, Modifier.size(size * 0.55f), tint = MaterialTheme.colorScheme.onPrimaryContainer)
    }
}

/** South African numbers as people write them: +27735779444 / 27735779444 -> 073 577 9444. Extensions unchanged. */
fun displayNumber(n: String): String {
    val d = n.filter { it.isDigit() }
    val local = when {
        d.length == 11 && d.startsWith("27") && (n.startsWith("+") || n.startsWith("27")) -> "0" + d.drop(2)
        d.length == 10 && d.startsWith("0") && n.none { it.isLetter() } -> d
        else -> return n
    }
    return "${local.take(3)} ${local.substring(3, 6)} ${local.drop(6)}"
}

/** Name for a number: the company address book first, then the phone's contacts (looked up off the main thread). */
@Composable
private fun rememberContactName(number: String): String? {
    val ctx = LocalContext.current
    return produceState<String?>(null, number) {
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { contactName(ctx, number) }
    }.value
}
private fun contactName(c: Context, number: String): String? {
    fun key(n: String) = n.filter { it.isDigit() }.let { if (it.length == 11 && it.startsWith("27")) "0" + it.drop(2) else it }
    val k = key(number)
    if (k.isEmpty()) return null
    companyCache.firstOrNull { it.name.isNotBlank() && key(it.number) == k }?.let { return it.name }
    if (k.length < 7) return null   // extensions: only the company book knows them
    return try {
        c.contentResolver.query(android.net.Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, android.net.Uri.encode(number)),
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) { null }   // no Contacts permission
}

private fun AudioRoute.icon() = when (this) {
    AudioRoute.Earpiece -> Icons.Default.PhoneInTalk
    AudioRoute.Speaker -> Icons.Default.VolumeUp
    AudioRoute.Bluetooth -> Icons.Default.BluetoothAudio
    AudioRoute.Headset -> Icons.Default.Headset
}
private fun AudioOption.label() = when (route) {
    AudioRoute.Earpiece -> "Phone"
    AudioRoute.Speaker -> "Speaker"
    AudioRoute.Bluetooth -> name.ifBlank { "Bluetooth" }
    AudioRoute.Headset -> "Headset"
}

/**
 * Speaker button. With only the phone and its loudspeaker it simply toggles the speaker; with Bluetooth (car kit,
 * headset) or a wired headset connected it opens a menu to pick where the call is heard and spoken.
 */
@Composable
private fun AudioRouteButton() {
    val route by SipManager.audioRoute.collectAsState()
    val routes by SipManager.audioRoutes.collectAsState()
    var menu by remember { mutableStateOf(false) }
    val choice = routes.any { it.route == AudioRoute.Bluetooth || it.route == AudioRoute.Headset }
    Box {
        FilledTonalIconToggleButton(route != AudioRoute.Earpiece, {
            if (choice) menu = true
            else SipManager.setAudioRoute(if (route == AudioRoute.Speaker) AudioRoute.Earpiece else AudioRoute.Speaker)
        }, Modifier.size(64.dp)) { Icon(route.icon(), if (choice) "Audio output" else "Speaker") }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            routes.forEach { o ->
                DropdownMenuItem(text = { Text(o.label()) }, leadingIcon = { Icon(o.route.icon(), null) },
                    trailingIcon = { if (o.route == route) Icon(Icons.Default.Check, null) },
                    onClick = { SipManager.setAudioRoute(o.route); menu = false })
            }
        }
    }
}

/** The contacts the number box searches: the company address book and the phone's own. */
private class ContactBook(val company: List<PhoneContact>, val phone: List<PhoneContact>) {
    /** Who a typed or tapped number is: the contact whose whole number is the same, company address book first. */
    fun whois(target: String): PhoneContact? {
        val key = numberKey(target)
        if (key.length < 2) return null
        return (company + phone).firstOrNull { numberKey(it.number) == key }
    }
}
/** A number for comparing: digits only, and a South African 27… number written as 0… (so 082 123 4567 = +27 82 123 4567). */
private fun numberKey(n: String): String {
    val d = SipManager.cleanNumber(n).filter { it.isDigit() }
    return if (d.length == 11 && d.startsWith("27")) "0" + d.substring(2) else d
}
/** The company address book is loaded once per app run (see companyCache); the phone's contacts each time the box opens. */
@Composable
private fun rememberContactBook(): ContactBook {
    val ctx = LocalContext.current
    val phone = remember { loadContacts(ctx) }
    var company by remember { mutableStateOf(companyCache) }
    LaunchedEffect(Unit) {
        if (companyCache.isEmpty()) {
            company = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { loadCompanyContacts(ctx) }
            companyCache = company
        }
    }
    return ContactBook(company, phone)
}
/** Names a person on a button: short enough for one line. */
private fun shortLabel(s: String) = if (s.length > 18) s.take(17).trimEnd() + "…" else s

/**
 * Number box for Add participant and Transfer: type an extension or number, or search by name; the company address
 * book and the phone's contacts that match are listed under it and a tap fills in the number. Whatever is in the box,
 * a highlighted line says who it will reach (the contact's name, or "Not in your contacts" for a number nobody has
 * saved), so a typed number needs one press of the button and a tapped contact visibly changes something.
 */
@Composable
private fun NumberOrContact(book: ContactBook, target: String, onChange: (String) -> Unit) {
    val company = book.company
    val phone = book.phone
    val q = target.trim()
    val digits = q.filter { it.isDigit() }
    fun matches(c: PhoneContact) = q.isBlank() || c.name.contains(q, true) ||
        (digits.length >= 2 && c.number.filter { it.isDigit() }.contains(digits))
    val list = (company.filter(::matches).map { it to true } + phone.filter(::matches).map { it to false }).take(60)
    val number = dialable(target)
    val who = book.whois(target)
    Column {
        OutlinedTextField(target, onChange, label = { Text("Name, extension or number") }, singleLine = true,
            modifier = Modifier.fillMaxWidth())
        if (number != null) Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(8.dp),
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Person, null)
                Spacer(Modifier.width(8.dp))
                Column {
                    Text(who?.name?.ifBlank { number } ?: number, style = MaterialTheme.typography.titleSmall, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                    Text(if (who != null) number else "Not in your contacts", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        // a list that only repeats the person named above would just be a second thing to tap
        if (list.isNotEmpty() && !(who != null && list.size == 1)) LazyColumn(Modifier.heightIn(max = 260.dp).padding(top = 4.dp)) {
            items(list) { (c, isCompany) ->
                ListItem(modifier = Modifier.clickable { onChange(SipManager.cleanNumber(c.number)) },
                    leadingContent = { Icon(if (isCompany) Icons.Default.Business else Icons.Default.Person, null) },
                    headlineContent = { Text(c.name) }, supportingContent = { Text(c.number) })
            }
        }
    }
}
/** The company address book, loaded once per app run (the PBX is asked again after a restart). */
private var companyCache: List<PhoneContact> = emptyList()
/** What the Call / Transfer buttons dial: the typed number, or nothing when the box holds a name search. */
private fun dialable(target: String) = SipManager.cleanNumber(target).takeIf { n -> n.isNotBlank() && target.none { it.isLetter() } || '@' in target }

@Composable
private fun AddParticipantDialog(inConference: Boolean, onDismiss: () -> Unit, onAdd: (String) -> Unit) {
    var target by remember { mutableStateOf("") }
    val book = rememberContactBook()
    val number = dialable(target)
    val name = number?.let { book.whois(target)?.name?.ifBlank { null } ?: it }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add participant") },
        text = { Column {
            NumberOrContact(book, target) { target = it }
            Spacer(Modifier.height(8.dp))
            Text(if (inConference) "They join the conference when they answer."
                else "The current call goes on hold. Tap Merge calls once they answer.", style = MaterialTheme.typography.bodySmall)
        } },
        confirmButton = { TextButton({ number?.let(onAdd) }, enabled = number != null) {
            Text(if (name == null) (if (inConference) "Add" else "Call") else (if (inConference) "Add " else "Call ") + shortLabel(name), maxLines = 1)
        } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } })
}

@Composable
private fun TransferDialog(onDismiss: () -> Unit, onBlind: (String) -> Unit, onConsult: (String) -> Unit) {
    var target by remember { mutableStateOf("") }
    val book = rememberContactBook()
    val number = dialable(target)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Transfer to") },
        text = { NumberOrContact(book, target) { target = it } },
        confirmButton = { TextButton({ number?.let(onBlind) }, enabled = number != null) { Text("Blind") } },
        dismissButton = { Row { TextButton({ number?.let(onConsult) }, enabled = number != null) { Text("Consult first") }
            TextButton(onDismiss) { Text("Cancel") } } })
}
