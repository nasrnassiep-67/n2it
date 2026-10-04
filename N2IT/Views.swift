import SwiftUI

struct RootView: View {
    @EnvironmentObject var sip: SipManager
    @State private var loggedIn = Account.load().isConfigured

    var body: some View {
        if !loggedIn {
            LoginView { loggedIn = true }
        } else { tabs }
    }

    private var tabs: some View {
        TabView {
            ContactsView().tabItem { Label("Contacts", systemImage: "person.crop.circle") }
            RecentsView().tabItem { Label("Recents", systemImage: "clock") }
            KeypadView().tabItem { Label("Keypad", systemImage: "circle.grid.3x3.fill") }
            VoicemailView().tabItem { Label("Voicemail", systemImage: "recordingtape") }
                .badge(sip.newVoicemails)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct StatusDot: View {
    @EnvironmentObject var sip: SipManager
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(sip.registered ? .green : .red).frame(width: 10, height: 10)
            Text(sip.registration).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct KeypadView: View {
    @EnvironmentObject var sip: SipManager
    @State private var number = ""
    private let keys = [["1","2","3"],["4","5","6"],["7","8","9"],["*","0","#"]]

    var body: some View {
        VStack(spacing: 18) {
            StatusDot()
            Text(number.isEmpty ? " " : number).font(.system(size: 36, weight: .light)).lineLimit(1).minimumScaleFactor(0.5)
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

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(sip.activeCall?.number ?? "").font(.largeTitle)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if connected {
                HStack(spacing: 40) {
                    toggle("mic.slash.fill", on: sip.muted) { sip.toggleMute() }
                    toggle("speaker.wave.3.fill", on: sip.speaker) { sip.toggleSpeaker() }
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
    }

    private var connected: Bool { sip.activeCall?.state == .StreamsRunning || sip.activeCall?.state == .Connected }
    private var ringingIn: Bool { sip.activeCall?.state == .IncomingReceived }
    private var label: String {
        switch sip.activeCall?.state {
        case .IncomingReceived: return "Incoming call"
        case .OutgoingProgress, .OutgoingInit: return "Calling…"
        case .OutgoingRinging, .OutgoingEarlyMedia: return "Ringing…"
        case .StreamsRunning, .Connected: return "Connected"
        default: return ""
        }
    }

    private func round(_ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title).foregroundStyle(.white)
                .frame(width: 76, height: 76).background(color).clipShape(Circle())
        }
    }
    private func toggle(_ icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2).frame(width: 64, height: 64)
                .foregroundStyle(on ? Color(.systemBackground) : .primary)
                .background(on ? Color.primary : Color(.secondarySystemBackground)).clipShape(Circle())
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var sip: SipManager
    @State private var acc = Account.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") { StatusDot() }
                Section(header: Text("SIP account"), footer: Text(acc.domain)) {
                    TextField("Client (e.g. n2it)", text: $acc.tenant).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Extension", text: $acc.user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $acc.password)
                    TextField("Port", value: $acc.port, format: .number.grouping(.never)).keyboardType(.numberPad)
                    TextField("Voicemail number", text: $acc.voicemailNumber).keyboardType(.numbersAndPunctuation)
                    Picker("Transport", selection: $acc.transport) {
                        ForEach(SipTransport.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Button("Save & Register") { acc.save(); sip.configure(acc); PushManager.shared.uploadToken() }
            }.navigationTitle("Settings")
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
            }.navigationTitle("N2IT Phone")
        }
    }
}
