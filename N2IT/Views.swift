import SwiftUI

struct RootView: View {
    @EnvironmentObject var sip: SipManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var loggedIn = Account.load().isConfigured
    @State private var tab = Screenshots.tab

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
        }.onChange(of: scenePhase) { sip.appPhase($0) }
        .onChange(of: sip.loginRefused) { if $0 { loggedIn = false } }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            ContactsView().tabItem { Label("Contacts", systemImage: "person.crop.circle") }.tag(0)
            RecentsView().tabItem { Label("Recents", systemImage: "clock") }.tag(1)
            KeypadView().tabItem { Label("Keypad", systemImage: "circle.grid.3x3.fill") }.tag(2)
            VoicemailView().tabItem { Label("Voicemail", systemImage: "recordingtape") }
                .badge(sip.hasVoicemail ? max(sip.newVoicemails, 1) : 0).tag(3)
            SettingsView(onSignOut: { loggedIn = false }).tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
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
    @EnvironmentObject var sip: SipManager
    @State private var taps = 0
    var body: some View {
        HStack {
            Text("Version: \(SipManager.appVersion)" + (sip.tester ? " · tester tools on" : ""))
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        // 7 taps turn the tester tools on or off (Last call problem, the call screen's audio line)
        .onTapGesture { taps += 1; if taps >= 7 { taps = 0; sip.tester.toggle() } }
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
                            Text(r.name ?? r.number).foregroundStyle(r.missed ? .red : .primary)
                            if r.name != nil { Text(r.number).font(.caption).foregroundStyle(.secondary) }
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

/// Conference: the space above the buttons split evenly between the people (up to 4); with more people, or while
/// the keypad is open, a scrolling list of short cards. Port of Android's ConferenceCards.
struct ConferenceCards: View {
    let people: [Participant]
    let compact: Bool

    var body: some View {
        if !compact && people.count <= 4 {
            VStack(spacing: 10) {
                ForEach(people) { ParticipantCard(p: $0, tall: true).frame(maxHeight: .infinity) }
            }.padding(.horizontal)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(people) { ParticipantCard(p: $0, tall: false).frame(height: 76) }
                }.padding(.horizontal)
            }
        }
    }
}

/// Name, number, status and a hang-up for this person only. Tall cards stack it centred; short ones in a row.
struct ParticipantCard: View {
    @EnvironmentObject var sip: SipManager
    let p: Participant
    let tall: Bool

    private var name: String? { sip.name(for: p.number) ?? p.name }
    private var title: String { name ?? p.number }
    private var status: (String, Color) {
        switch p.status {
        case .talking: return ("Talking", .green)
        case .ringing: return ("Ringing…", Color(red: 0xE0 / 255, green: 0xA0 / 255, blue: 0x30 / 255))
        case .onHold: return ("On hold", .secondary)
        }
    }

    var body: some View {
        // Only the operator removes people; anyone can still cancel a call of their own that is ringing or on hold
        let drop = Group {
            if sip.roomOperator || p.status != .talking {
                Button { sip.dropParticipant(p.id) } label: {
                    Image(systemName: "phone.down.fill").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.red).clipShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Hang up on \(title)")
            }
        }
        let initial = Text(String(title.first(where: { $0.isLetter || $0.isNumber }) ?? "?").uppercased())
        Group {
            if tall {
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 6) {
                        initial.font(.title).frame(width: 64, height: 64).background(Color.accentColor.opacity(0.2)).clipShape(Circle())
                        Text(title).font(.title2).lineLimit(1)
                        if name != nil { Text(p.number).foregroundStyle(.secondary) }
                        Text(status.0).font(.subheadline.weight(.semibold)).foregroundStyle(status.1)
                        drop.padding(.top, 4)
                    }
                    row(initial: initial, drop: drop)
                }
            } else {
                row(initial: initial, drop: drop)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func row(initial: Text, drop: some View) -> some View {
        HStack(spacing: 12) {
            initial.font(.headline).frame(width: 44, height: 44).background(Color.accentColor.opacity(0.2)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                HStack(spacing: 0) {
                    if name != nil { Text(p.number + " · ").foregroundStyle(.secondary) }
                    Text(status.0).foregroundStyle(status.1)
                }.font(.caption).lineLimit(1)
            }
            Spacer()
            drop
        }
    }
}

struct CallView: View {
    @EnvironmentObject var sip: SipManager
    @State private var showPad = false
    @State private var dtmf = ""
    @State private var showTransfer = false
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 28) {
            if sip.inConference {
                // One card per person, sharing the space above the buttons (as Android; a single line of names was hard to read)
                VStack(spacing: 12) {
                    Text(label).foregroundStyle(.secondary).padding(.top, 16)
                    if let n = sip.notice { Text(n).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal) }
                    ConferenceCards(people: sip.participants, compact: showPad)
                }
            } else {
                Spacer()
                Text(sip.activeCall?.name ?? sip.activeCall?.number ?? "").font(.largeTitle).multilineTextAlignment(.center)
                if let name = sip.activeCall?.name, name != sip.activeCall?.number {
                    Text(sip.activeCall?.number ?? "").font(.title3).foregroundStyle(.secondary)
                }
                Text(label).foregroundStyle(.secondary)
                if sip.tester, let d = sip.audioDiag { Text(d).font(.caption2.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal) }
                if let n = sip.notice { Text(n).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal) }
                Spacer()
            }
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
                // Hidden while the keypad is open, so the hang-up button stays on screen
                if !showPad {
                    HStack(spacing: 40) {
                        if !sip.inConference {
                            toggle("pause.fill", on: sip.onHold) { sip.toggleHold() }
                            toggle("phone.arrow.right", on: false) { showTransfer = true }
                        }
                        toggle("person.badge.plus", on: false) { showAdd = true }
                    }
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
                    // One block with tight rows: as separate items each row took the screen's 28 pt gap and the pad
                    // pushed the hang-up button off the bottom
                    VStack(spacing: 10) {
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
            }
            HStack(spacing: 60) {
                if ringingIn {
                    round("phone.fill", .green) { sip.answer() }
                }
                round("phone.down.fill", .red) { sip.hangup() }
            }
            Spacer().frame(height: 40)
        }.frame(maxWidth: .infinity).background(Color(.systemBackground))
        .onAppear { if Screenshots.pickerText != nil { showAdd = true } }
        // Pick from company and phone contacts, or type a number; a line names who it reaches (as Android 0.2.13)
        .sheet(isPresented: $showTransfer) {
            NumberPicker(mode: .transfer, onAdd: { _ in },
                         onTransfer: { n, consult in consult ? sip.consult(n) : sip.blindTransfer(n) })
        }
        .sheet(isPresented: $showAdd) {
            NumberPicker(mode: .add(inConference: sip.inConference), onAdd: { sip.addParticipant($0) },
                         onTransfer: { _, _ in })
        }
    }

    private var connected: Bool { sip.onHold || sip.activeCall?.state == .StreamsRunning || sip.activeCall?.state == .Connected }
    private var ringingIn: Bool { sip.activeCall?.state == .IncomingReceived }
    private var label: String {
        if sip.inConference { return "Conference · \(sip.roomCount ?? sip.participants.count + 1) people" }
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
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") { StatusDot(); DndButton() }
                Section(header: Text("SIP account"), footer: Text(acc.tenant)) {
                    TextField("Company code", text: $acc.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $acc.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasswordField(text: $acc.password)
                    TextField("Voicemail number", text: $acc.voicemailNumber).keyboardType(.numbersAndPunctuation)
                }
                Section(header: Text("Audio"), footer: Text("Takes effect from the next call.")) {
                    Toggle("Filter out background voices", isOn: Binding(get: { sip.backgroundFilter }, set: { sip.backgroundFilter = $0 }))
                }
                if sip.tester, let problem = sip.lastProblem {
                    Section("Last call problem") {
                        Text(problem).font(.caption2.monospaced()).lineLimit(8)
                        Button("Copy details") { UIPasteboard.general.string = problem }
                    }
                }
                SignInStatus(checking: checking, problem: problem)
                Button("Save & Register") {
                    checking = true; problem = nil
                    let previous = Account.load()
                    Task {
                        problem = await sip.signInProblem(acc, previous: previous)
                        checking = false
                        if problem == nil { acc.save(); PushManager.shared.uploadToken() }
                    }
                }.disabled(!acc.isConfigured || checking)
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
                        Text(a.tenant + (isActive ? " · active" : "")).font(.caption).foregroundStyle(.secondary)
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
        .sheet(isPresented: $adding) { AddAccountView { a in adding = false; use(a) }.environmentObject(sip) }
        .alert("Log out of extension \(leaving?.user ?? "")?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
               presenting: leaving) { a in
            Button("Log out", role: .destructive) {
                leaving = nil
                if sip.logOut(a) { refresh(); onActiveChanged(active) } else { onNoneLeft() }
            }
            Button("Cancel", role: .cancel) { leaving = nil }
        } message: { a in
            Text("\(a.tenant) is removed from this phone. You can add it again later with its password.")
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
    @EnvironmentObject var sip: SipManager
    @State private var a = Account.blank
    @State private var checking = false
    @State private var problem: String?
    var onAdd: (Account) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Your company code (e.g. yourcompany)"
                                     + "\nIt becomes the active account; the current one stays in the list.")) {
                    TextField("Company code", text: $a.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $a.user).keyboardType(.numberPad)
                    PasswordField(text: $a.password)
                }
                SignInStatus(checking: checking, problem: problem)
            }
            .navigationTitle("Add account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(checking ? "Checking…" : "Add") {
                        a.tenant = a.tenant.trimmingCharacters(in: .whitespacesAndNewlines)
                        a.user = a.user.trimmingCharacters(in: .whitespacesAndNewlines)
                        checking = true; problem = nil
                        let previous = Account.load()
                        Task {
                            problem = await sip.signInProblem(a, previous: previous)
                            checking = false
                            if problem == nil { onAdd(a) }
                        }
                    }.disabled(!a.isConfigured || checking)
                }
            }
        }
    }
}

/// A real password box: no autocorrect, suggestions or capitals, an eye to show what was typed, and spaces / zero-width
/// characters dropped from what is pasted (Android 0.2.14: a pasted password reached the PBX changed).
struct PasswordField: View {
    @Binding var text: String
    @State private var shown = false
    private static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]
    static func clean(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { !invisible.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }))
    }

    var body: some View {
        let b = Binding(get: { text }, set: { text = Self.clean($0) })
        HStack {
            Group {
                if shown { TextField("Password", text: b) } else { SecureField("Password", text: b) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.password)
            Button { shown.toggle() } label: { Image(systemName: shown ? "eye.slash" : "eye").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).accessibilityLabel(shown ? "Hide password" : "Show password")
        }
    }
}

/// "Checking…" while the sign-in check runs, else the refusal in red.
struct SignInStatus: View {
    let checking: Bool
    let problem: String?
    var body: some View {
        if checking { HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) } }
        else if let problem { Text(problem).foregroundStyle(.red) }
    }
}

/// Novamo brand navy: the sign-in screen stays this colour in light and dark mode alike (as Android).
private let novamoNavy = Color(red: 10 / 255, green: 35 / 255, blue: 66 / 255)

struct LoginView: View {
    @EnvironmentObject var sip: SipManager
    @State private var acc = Account.load()
    @State private var checking = false
    @State private var problem: String?
    var done: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
                    VStack(spacing: 14) {
                        Image("NovamoLogo").resizable().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .accessibilityHidden(true)
                        Text("Novamo").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    }
                    card
                    Spacer(minLength: 0)
                    Link("support@novamo.co.za", destination: URL(string: "mailto:support@novamo.co.za")!)
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                    VersionText().environment(\.colorScheme, .dark)
                }
                .padding(24)
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(novamoNavy.ignoresSafeArea())
        .onAppear {
            if sip.loginRefused { acc.password = ""; problem = "Wrong extension or password. Sign in again." }
        }
    }

    /// The form: always a white card with dark text, whatever the phone's appearance.
    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Company code", text: $acc.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Your company code")
                .font(.footnote).foregroundStyle(.secondary)
            Divider()
            TextField("Extension", text: $acc.user).textInputAutocapitalization(.never).autocorrectionDisabled()
            Divider()
            PasswordField(text: $acc.password)
            Divider()
            SignInStatus(checking: checking, problem: problem)
            Button {
                checking = true; problem = nil
                Task {
                    problem = await sip.signInProblem(acc, previous: nil)
                    checking = false
                    if problem == nil { acc.save(); PushManager.shared.uploadToken(); sip.loginRefused = false; done() }
                }
            } label: {
                Text(checking ? "Signing in…" : "Sign in").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(novamoNavy)
            .disabled(!acc.isConfigured || checking)
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}
