import SwiftUI

struct RootView: View {
    @EnvironmentObject var sip: SipManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var loggedIn = Account.load().isConfigured

    var body: some View {
        Group {
            if !loggedIn {
                LoginView { loggedIn = true }
            } else {
                VStack(spacing: 0) {
                    DndBanner()
                    tabs
                }
            }
        }.onChange(of: scenePhase) { if $0 == .active { sip.checkDnd() } }
    }

    private var tabs: some View {
        TabView {
            ContactsView().tabItem { Label("Contacts", systemImage: "person.crop.circle") }
            RecentsView().tabItem { Label("Recents", systemImage: "clock") }
            KeypadView().tabItem { Label("Keypad", systemImage: "circle.grid.3x3.fill") }
            VoicemailView().tabItem { Label("Voicemail", systemImage: "recordingtape") }
                .badge(sip.hasVoicemail ? max(sip.newVoicemails, 1) : 0)
            SettingsView(onSignOut: { loggedIn = false }).tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct StatusDot: View {
    @EnvironmentObject var sip: SipManager
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(!sip.registered ? .red : sip.dndUntil != nil ? Color.dndOrange : .green).frame(width: 10, height: 10)
            Text(sip.registered && sip.dndUntil != nil ? "Do Not Disturb" : sip.registration).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    static let dndOrange = Color(red: 0xE6 / 255, green: 0x51 / 255, blue: 0)
}

private let dndTime: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm")
    return f
}()

/// Orange banner on every screen while DND is on, so it can't be forgotten.
struct DndBanner: View {
    @EnvironmentObject var sip: SipManager
    var body: some View {
        if let until = sip.dndUntil {
            HStack(spacing: 10) {
                Image(systemName: "minus.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("DND enabled. Please disable DND to receive calls.").font(.subheadline)
                    Text("Until \(dndTime.string(from: until))").font(.caption)
                }
                Spacer()
                Button("Turn off") { sip.setDnd(nil) }.font(.subheadline.bold())
            }
            .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity).background(Color.dndOrange)
        }
    }
}

/// DND button: always with an end time, from 1 hour up to 2 weeks.
struct DndButton: View {
    @EnvironmentObject var sip: SipManager
    @State private var choosing = false
    @State private var picking = false
    @State private var picked = Date().addingTimeInterval(3600)

    var body: some View {
        let on = sip.dndUntil != nil
        Button { choosing = true } label: {
            Label(sip.dndUntil.map { "DND until \(dndTime.string(from: $0))" } ?? "Do Not Disturb", systemImage: "minus.circle.fill")
                .font(.footnote).padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? .white : .primary)
                .background(on ? Color.dndOrange : Color(.secondarySystemBackground)).clipShape(Capsule())
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Do Not Disturb", isPresented: $choosing, titleVisibility: .visible) {
            Button("1 hour") { set(hours: 1) }
            Button("2 hours") { set(hours: 2) }
            Button("4 hours") { set(hours: 4) }
            Button("Until \(dndTime.string(from: morning))") { sip.setDnd(morning) }
            Button("Choose date and time…") { picked = Date().addingTimeInterval(3600); picking = true }
            if on { Button("Turn off now", role: .destructive) { sip.setDnd(nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Calls to this app go to voicemail until the time you choose. Other phones on your extension still ring.")
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                Form {
                    DatePicker("Until", selection: $picked,
                               in: Date()...Date().addingTimeInterval(SipManager.maxDnd))
                        .datePickerStyle(.graphical)
                    Text("At most 2 weeks from now.").font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle("Do Not Disturb").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Turn on") { sip.setDnd(picked); picking = false } }
                }
            }
        }
    }

    private func set(hours: Double) { sip.setDnd(Date().addingTimeInterval(hours * 3600)) }

    /// Next 08:00 (today if it's still early, otherwise tomorrow).
    private var morning: Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        return today > Date() ? today : cal.date(byAdding: .day, value: 1, to: today)!
    }
}

struct VersionText: View {
    var body: some View {
        HStack {
            Text("Version: \(SipManager.appVersion)").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
    }
}

struct KeypadView: View {
    @EnvironmentObject var sip: SipManager
    @State private var number = ""
    private let keys = [["1","2","3"],["4","5","6"],["7","8","9"],["*","0","#"]]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) { StatusDot(); DndButton() }
            Text(number.isEmpty ? " " : number).font(.system(size: 36, weight: .light)).lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .contextMenu {
                    Button { paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    if !number.isEmpty {
                        Button { UIPasteboard.general.string = number } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
                }
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.self) { k in
                        Button { number += k } label: {
                            Text(k).font(.system(size: 32)).frame(width: 78, height: 78)
                                .background(Color(.secondarySystemBackground)).clipShape(Circle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 24) {
                Color.clear.frame(width: 78, height: 78)
                Button { sip.call(number); number = "" } label: {
                    Image(systemName: "phone.fill").font(.title).foregroundStyle(.white)
                        .frame(width: 78, height: 78).background(Color.green).clipShape(Circle())
                }.disabled(number.isEmpty)
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left").font(.title2).frame(width: 78, height: 78)
                }.opacity(number.isEmpty ? 0 : 1)
            }
        }.padding()
    }

    /// Paste a copied number, keeping only dialable characters ("+27 82 123-4567" -> "+27821234567").
    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        let digits = text.filter { "+0123456789*#".contains($0) }
        if !digits.isEmpty { number = digits }
    }
}

struct RecentsView: View {
    @EnvironmentObject var sip: SipManager
    var body: some View {
        NavigationStack {
            List(sip.recents) { r in
                Button { sip.call(r.number) } label: {
                    HStack {
                        Image(systemName: r.incoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                            .foregroundStyle(r.missed ? .red : .secondary)
                        VStack(alignment: .leading) {
                            Text(r.number).foregroundStyle(r.missed ? .red : .primary)
                            Text(r.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay { if sip.recents.isEmpty { Text("No recent calls").foregroundStyle(.secondary) } }
            .navigationTitle("Recents")
        }
    }
}

struct CallView: View {
    @EnvironmentObject var sip: SipManager
    @State private var showPad = false
    @State private var dtmf = ""
    @State private var showTransfer = false
    @State private var showAdd = false
    @State private var target = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(sip.activeCall?.number ?? "").font(.largeTitle)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            // While dialling: mute and the audio button already, so the user can pick the car or speaker before they answer.
            if !connected && !ringingIn {
                HStack(spacing: 40) {
                    toggle("mic.slash.fill", on: sip.muted) { sip.toggleMute() }
                    audioButton
                }
            }
            if connected {
                HStack(spacing: 40) {
                    toggle("mic.slash.fill", on: sip.muted) { sip.toggleMute() }
                    audioButton
                    toggle("circle.grid.3x3.fill", on: showPad) { showPad.toggle() }
                }
                HStack(spacing: 40) {
                    if !sip.inConference {
                        toggle("pause.fill", on: sip.onHold) { sip.toggleHold() }
                        toggle("phone.arrow.right", on: false) { showTransfer = true }
                    }
                    toggle("person.badge.plus", on: false) { showAdd = true }
                }
                if sip.consulting {
                    HStack(spacing: 12) {
                        Button { sip.merge() } label: { Label("Merge calls", systemImage: "arrow.triangle.merge") }
                            .buttonStyle(.borderedProminent).tint(.green)
                        if !sip.inConference {
                            Button("Complete transfer") { sip.completeTransfer() }.buttonStyle(.bordered)
                        }
                    }
                }
                if showPad {
                    Text(dtmf).font(.title3).frame(height: 24)
                    ForEach([["1","2","3"],["4","5","6"],["7","8","9"],["*","0","#"]], id: \.self) { row in
                        HStack(spacing: 20) {
                            ForEach(row, id: \.self) { k in
                                Button { dtmf += k; sip.sendDigit(Character(k)) } label: {
                                    Text(k).font(.title2).frame(width: 56, height: 56)
                                        .background(Color(.secondarySystemBackground)).clipShape(Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 60) {
                if ringingIn {
                    round("phone.fill", .green) { sip.answer() }
                }
                round("phone.down.fill", .red) { sip.hangup() }
            }
            Spacer().frame(height: 40)
        }.frame(maxWidth: .infinity).background(Color(.systemBackground))
        .alert("Transfer to", isPresented: $showTransfer) {
            TextField("Extension or number", text: $target).keyboardType(.phonePad)
            Button("Blind") { sip.blindTransfer(target); target = "" }
            Button("Consult first") { sip.consult(target); target = "" }
            Button("Cancel", role: .cancel) { target = "" }
        }
        .alert("Add participant", isPresented: $showAdd) {
            TextField("Extension or number", text: $target).keyboardType(.phonePad)
            Button("Call") { sip.addParticipant(target); target = "" }
            Button("Cancel", role: .cancel) { target = "" }
        } message: {
            Text(sip.inConference ? "They join the conference when they answer."
                 : "The current call goes on hold. Tap Merge calls once they answer.")
        }
    }

    private var connected: Bool { sip.onHold || sip.activeCall?.state == .StreamsRunning || sip.activeCall?.state == .Connected }
    private var ringingIn: Bool { sip.activeCall?.state == .IncomingReceived }
    private var label: String {
        if sip.inConference { return "Conference · \(sip.participants.count + 1) people" }
        switch sip.activeCall?.state {
        case .IncomingReceived: return "Incoming call"
        case .OutgoingProgress, .OutgoingInit: return "Calling…"
        case .OutgoingRinging, .OutgoingEarlyMedia: return "Ringing…"
        case .StreamsRunning, .Connected: return "Connected"
        case .Paused, .Pausing: return "On hold"
        default: return ""
        }
    }

    /// Speaker on/off; with Bluetooth (car kit, headset) or a wired headset connected it opens a menu to pick
    /// where the call is heard and spoken.
    @ViewBuilder private var audioButton: some View {
        let route = sip.audioRoute?.route ?? .iPhone
        if sip.audioRoutes.contains(where: { $0.route == .bluetooth || $0.route == .headset }) {
            Menu {
                Picker("Audio", selection: Binding(get: { sip.audioRoute?.id ?? "" }, set: { sip.setAudioRoute($0) })) {
                    ForEach(sip.audioRoutes) { Label($0.name, systemImage: $0.route.icon).tag($0.id) }
                }.pickerStyle(.inline)
            } label: { circle(route.icon, on: route != .iPhone) }
        } else {
            toggle("speaker.wave.3.fill", on: route == .speaker) { sip.toggleSpeaker() }
        }
    }

    private func round(_ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title).foregroundStyle(.white)
                .frame(width: 76, height: 76).background(color).clipShape(Circle())
        }
    }
    private func toggle(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { circle(icon, on: on) }
    }
    private func circle(_ icon: String, on: Bool) -> some View {
        Image(systemName: icon).font(.title2).frame(width: 64, height: 64)
            .foregroundStyle(on ? Color(.systemBackground) : .primary)
            .background(on ? Color.primary : Color(.secondarySystemBackground)).clipShape(Circle())
    }
}

struct SettingsView: View {
    @EnvironmentObject var sip: SipManager
    var onSignOut: () -> Void
    @State private var acc = Account.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") { StatusDot(); DndButton() }
                Section(header: Text("SIP account"), footer: Text(acc.domain)) {
                    TextField("Client (e.g. n2it)", text: $acc.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $acc.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $acc.password)
                    TextField("Port", value: $acc.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                    TextField("Voicemail number", text: $acc.voicemailNumber).keyboardType(.numbersAndPunctuation)
                    Picker("Transport", selection: $acc.transport) {
                        ForEach(SipTransport.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Encrypt call audio (SRTP)", isOn: $acc.srtp)
                }
                Button("Save & Register") { acc.save(); sip.configure(acc); PushManager.shared.uploadToken() }
                AccountsSection(onActiveChanged: { acc = $0 }, onNoneLeft: onSignOut)
                Section { VersionText() }.listRowBackground(Color.clear)
            }.navigationTitle("Settings")
        }
    }
}

/// Saved accounts (e.g. a reseller testing several clients). One is active at a time: only it is registered and
/// rings; tap another to switch. Log out removes an account from this phone.
struct AccountsSection: View {
    @EnvironmentObject var sip: SipManager
    var onActiveChanged: (Account) -> Void
    var onNoneLeft: () -> Void
    @State private var active = Account.load()
    @State private var others = Account.others()
    @State private var adding = false
    @State private var leaving: Account?

    private var inCall: Bool { sip.activeCall != nil }
    private var list: [Account] { (active.isConfigured ? [active] : []) + others }

    var body: some View {
        Section(header: Text("Accounts"),
                footer: Text(inCall ? "Finish the call to switch accounts." : "Only the active account receives calls. Tap another to switch.")) {
            ForEach(list, id: \.key) { a in
                let isActive = a.sameAs(active)
                HStack {
                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text("Extension \(a.user)")
                        Text(a.domain + (isActive ? " · active" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Log out", role: .destructive) { leaving = a }.buttonStyle(.borderless).disabled(inCall)
                }
                .contentShape(Rectangle())
                .onTapGesture { if !isActive && !inCall { use(a) } }
            }
            Button { adding = true } label: { Label("Add account", systemImage: "person.badge.plus") }.disabled(inCall)
        }
        .onAppear(perform: refresh)
        .sheet(isPresented: $adding) { AddAccountView { a in adding = false; use(a) } }
        .alert("Log out of extension \(leaving?.user ?? "")?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
               presenting: leaving) { a in
            Button("Log out", role: .destructive) {
                leaving = nil
                if sip.logOut(a) { refresh(); onActiveChanged(active) } else { onNoneLeft() }
            }
            Button("Cancel", role: .cancel) { leaving = nil }
        } message: { a in
            Text("\(a.domain) is removed from this phone. You can add it again later with its password.")
        }
    }

    private func refresh() { active = Account.load(); others = Account.others() }

    private func use(_ a: Account) {
        let previous = Account.load()
        Account.activate(a)
        sip.switchAccount(to: a, from: previous)
        refresh()
        onActiveChanged(active)
    }
}

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var a = Account.blank
    var onAdd: (Account) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text((a.domain.isEmpty ? "e.g. n2it" : "Connects to \(a.domain)")
                                     + "\nIt becomes the active account; the current one stays in the list.")) {
                    TextField("Company code", text: $a.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $a.user).keyboardType(.numberPad)
                    SecureField("Password", text: $a.password)
                }
            }
            .navigationTitle("Add account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        a.tenant = a.tenant.trimmingCharacters(in: .whitespacesAndNewlines)
                        a.user = a.user.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(a)
                    }.disabled(!a.isConfigured)
                }
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var sip: SipManager
    @State private var acc = Account.load()
    var done: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Sign in"), footer: Text(acc.domain.isEmpty ? "Enter your company code" : "Connects to \(acc.domain)")) {
                    TextField("Company code", text: $acc.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $acc.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $acc.password)
                }
                Button("Sign in") { acc.save(); sip.configure(acc); PushManager.shared.uploadToken(); done() }.disabled(!acc.isConfigured)
                Section { VersionText() }.listRowBackground(Color.clear)
            }.navigationTitle("N2IT Phone")
        }
    }
}
