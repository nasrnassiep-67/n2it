import Foundation

/// App Store screenshots (debug builds only): launched with `-screenshots` the app shows a signed-in demo extension
/// with sample contacts and recents and never contacts a PBX; `-screenshotTab <0-4>` picks the tab and
/// `-screenshotCall` also opens the call screen.
enum Screenshots {
    #if DEBUG
    static let on = ProcessInfo.processInfo.arguments.contains("-screenshots")
    #else
    static let on = false
    #endif

    /// Tab to open on (0 Contacts … 4 Settings); always Contacts outside screenshot mode.
    static var tab: Int {
        guard on else { return 0 }
        return UserDefaults.standard.integer(forKey: "screenshotTab")   // -screenshotTab 2 on the command line
    }

    static let account = Account(tenant: "demo", user: "1001", password: "demo", port: 5061, transport: .tls,
                                 voicemailNumber: "*97", srtp: true)

    static let company = [
        PhoneContact(id: "c1", name: "Reception", numbers: ["1000"]),
        PhoneContact(id: "c2", name: "Sales", numbers: ["1002"]),
        PhoneContact(id: "c3", name: "Support", numbers: ["1003"]),
        PhoneContact(id: "c4", name: "Accounts", numbers: ["1004"]),
        PhoneContact(id: "c5", name: "Warehouse", numbers: ["1005"]),
    ]

    static let phone = [
        PhoneContact(id: "p1", name: "Aisha Patel", numbers: ["0825550142"]),
        PhoneContact(id: "p2", name: "Ben Smith", numbers: ["0215550178"]),
        PhoneContact(id: "p3", name: "Carla Mendes", numbers: ["0835550111"]),
        PhoneContact(id: "p4", name: "David Nkosi", numbers: ["0115550190"]),
        PhoneContact(id: "p5", name: "Emma Botha", numbers: ["0725550163"]),
        PhoneContact(id: "p6", name: "Faith Mokoena", numbers: ["0315550124"]),
    ]

    static func fill(_ sip: SipManager) {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        sip.recents = [
            RecentCall(number: "1002", date: ago(12), incoming: true, missed: false, name: "Sales"),
            RecentCall(number: "0825550142", date: ago(48), incoming: false, missed: false, name: "Aisha Patel"),
            RecentCall(number: "0215550178", date: ago(95), incoming: true, missed: true, name: "Ben Smith"),
            RecentCall(number: "1003", date: ago(180), incoming: false, missed: false, name: "Support"),
            RecentCall(number: "0115550190", date: ago(60 * 26), incoming: true, missed: false, name: "David Nkosi"),
            RecentCall(number: "1000", date: ago(60 * 30), incoming: false, missed: false, name: "Reception"),
        ]
        sip.registered = true
        sip.registration = "Registered"
        sip.newVoicemails = 2; sip.hasVoicemail = true
        if ProcessInfo.processInfo.arguments.contains("-screenshotCall") {
            sip.activeCall = CallInfo(number: "0825550142", state: .StreamsRunning, incoming: false, name: "Aisha Patel")
        }
    }
}
