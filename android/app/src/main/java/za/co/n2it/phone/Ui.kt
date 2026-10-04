package za.co.n2it.phone

import android.content.Context
import android.provider.ContactsContract
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.text.DateFormat
import java.util.Date

private val Green = Color(0xFF2E9E4F)
private val Red = Color(0xFFD64545)

@Composable
fun App(onSignedIn: () -> Unit, onSignedOut: () -> Unit) {
    val ctx = LocalContext.current
    var loggedIn by remember { mutableStateOf(Account.load(ctx).isConfigured) }
    val call by SipManager.call.collectAsState()

    if (call != null) { CallScreen(call!!); return }
    if (!loggedIn) {
        LoginScreen { loggedIn = true; onSignedIn() }
    } else {
        MainTabs(onSignOut = { SipManager.signOut(ctx); onSignedOut(); loggedIn = false })
    }
}

@Composable
fun StatusRow() {
    val ok by SipManager.registered.collectAsState()
    val status by SipManager.status.collectAsState()
    Row(verticalAlignment = Alignment.CenterVertically) {
        Surface(color = if (ok) Green else Red, shape = CircleShape, modifier = Modifier.size(10.dp)) {}
        Spacer(Modifier.width(6.dp)); Text(status, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
fun LoginScreen(done: () -> Unit) {
    val ctx = LocalContext.current
    var acc by remember { mutableStateOf(Account.load(ctx)) }
    Column(Modifier.fillMaxSize().padding(24.dp).systemBarsPadding(), verticalArrangement = Arrangement.Center) {
        Text("N2IT Phone", fontSize = 32.sp)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(acc.tenant, { acc = acc.copy(tenant = it) }, label = { Text("Company code") },
            singleLine = true, modifier = Modifier.fillMaxWidth(),
            supportingText = { Text(if (acc.domain.isEmpty()) "Enter your company code" else "Connects to ${acc.domain}") })
        OutlinedTextField(acc.user, { acc = acc.copy(user = it) }, label = { Text("Extension") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        OutlinedTextField(acc.password, { acc = acc.copy(password = it) }, label = { Text("Password") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), visualTransformation = PasswordVisualTransformation())
        Spacer(Modifier.height(16.dp))
        Button(onClick = { Account.save(ctx, acc); SipManager.configure(acc); done() },
            enabled = acc.isConfigured, modifier = Modifier.fillMaxWidth()) { Text("Sign in") }
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

@Composable
fun KeypadTab() {
    var number by remember { mutableStateOf("") }
    val registered by SipManager.registered.collectAsState()
    Column(Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        StatusRow(); Spacer(Modifier.height(16.dp))
        Text(number.ifEmpty { " " }, fontSize = 34.sp, maxLines = 1)
        Spacer(Modifier.height(16.dp))
        Pad { number += it }
        Spacer(Modifier.height(16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            Spacer(Modifier.size(72.dp))
            FilledIconButton(onClick = { SipManager.call(number); number = "" }, enabled = number.isNotEmpty() && registered,
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
                modifier = Modifier.clickable { SipManager.call(r.number) },
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

@Composable
fun ContactsTab() {
    val ctx = LocalContext.current
    val all = remember { loadContacts(ctx) }
    var q by remember { mutableStateOf("") }
    val list = all.filter { q.isBlank() || it.name.contains(q, true) || it.number.contains(q) }
    Column {
        OutlinedTextField(q, { q = it }, placeholder = { Text("Search") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(12.dp))
        if (all.isEmpty()) Box(Modifier.fillMaxSize(), Alignment.Center) { Text("No contacts (allow Contacts permission)") }
        LazyColumn {
            items(list) { c ->
                ListItem(modifier = Modifier.clickable { SipManager.call(c.number.filter { it in "+0123456789*#" }) },
                    headlineContent = { Text(c.name) }, supportingContent = { Text(c.number) })
            }
        }
    }
}

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
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        StatusRow(); Spacer(Modifier.height(12.dp))
        OutlinedTextField(acc.tenant, { acc = acc.copy(tenant = it) }, label = { Text("Client (e.g. n2it)") },
            singleLine = true, modifier = Modifier.fillMaxWidth(), supportingText = { Text(acc.domain) })
        OutlinedTextField(acc.user, { acc = acc.copy(user = it) }, label = { Text("Extension") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(acc.password, { acc = acc.copy(password = it) }, label = { Text("Password") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
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
        Button(onClick = { Account.save(ctx, acc); SipManager.configure(acc) }, modifier = Modifier.fillMaxWidth()) { Text("Save & Register") }
        TextButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) { Text("Sign out", color = Red) }
    }
}

@Composable
fun CallScreen(call: CallInfo) {
    val muted by SipManager.muted.collectAsState()
    val speaker by SipManager.speaker.collectAsState()
    var pad by remember { mutableStateOf(false) }
    val connected = call.state == org.linphone.core.Call.State.StreamsRunning || call.state == org.linphone.core.Call.State.Connected
    val ringingIn = call.state == org.linphone.core.Call.State.IncomingReceived
    val label = when (call.state) {
        org.linphone.core.Call.State.IncomingReceived -> "Incoming call"
        org.linphone.core.Call.State.OutgoingInit, org.linphone.core.Call.State.OutgoingProgress -> "Calling…"
        org.linphone.core.Call.State.OutgoingRinging, org.linphone.core.Call.State.OutgoingEarlyMedia -> "Ringing…"
        org.linphone.core.Call.State.StreamsRunning, org.linphone.core.Call.State.Connected -> "Connected"
        else -> ""
    }
    Column(Modifier.fillMaxSize().systemBarsPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Text(call.number, fontSize = 34.sp); Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        if (connected) {
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                FilledTonalIconToggleButton(muted, { SipManager.toggleMute() }, Modifier.size(64.dp)) { Icon(Icons.Default.MicOff, "Mute") }
                FilledTonalIconToggleButton(speaker, { SipManager.toggleSpeaker() }, Modifier.size(64.dp)) { Icon(Icons.Default.VolumeUp, "Speaker") }
                FilledTonalIconToggleButton(pad, { pad = it }, Modifier.size(64.dp)) { Icon(Icons.Default.Dialpad, "Keypad") }
            }
            if (pad) { Spacer(Modifier.height(12.dp)); Pad { SipManager.sendDigit(it[0]) } }
        }
        Spacer(Modifier.height(32.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(56.dp)) {
            if (ringingIn) FilledIconButton({ SipManager.answer() }, Modifier.size(76.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Green)) {
                Icon(Icons.Default.Call, "Answer", tint = Color.White)
            }
            FilledIconButton({ SipManager.hangup() }, Modifier.size(76.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Red)) {
                Icon(Icons.Default.CallEnd, "Hang up", tint = Color.White)
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}
