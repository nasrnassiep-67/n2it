import SwiftUI
import Contacts

struct PhoneContact: Identifiable {
    let id: String
    let name: String
    let numbers: [String]
}

/// Company address book from FusionPBX > Apps > Contacts, served per tenant by the PBX
/// (`/app/n2it/contacts.php`, HTTP Basic with the extension and its SIP password; see IOS-MAC-HANDOVER.md).
private struct PbxContacts: Decodable {
    struct Contact: Decodable {
        struct Number: Decodable { let label: String?; let number: String }
        let name: String
        let numbers: [Number]
    }
    struct Ext: Decodable { let number: String }
    let contacts: [Contact]
    let extensions: [Ext]?
    /// The company's outbound route patterns (PBX since 2026-10-22); nil from an older PBX.
    let dial_patterns: [String]?
}

/// What the company's PBX can dial (owner 2026-10-22: show only contact numbers it can dial): its outbound route
/// patterns plus its extensions. A number with letters (0800-FLOWERS, "ext 12") is never shown: cleaning would turn it
/// into a different number. Without rules (PBX not answered, older PBX) everything else is shown.
struct DialRules {
    let patterns: [NSRegularExpression]
    let extensions: Set<String>

    static func hasLetters(_ raw: String) -> Bool { raw.contains { $0.isLetter } && !raw.contains("@") }
    static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.contains("@") { return t.filter { !$0.isWhitespace } }
        let allowed = Set("+0123456789*#")
        return String(t.filter { allowed.contains($0) })
    }
    func canDial(_ raw: String) -> Bool {
        if DialRules.hasLetters(raw) { return false }
        let n = DialRules.clean(raw)
        if n.isEmpty { return false }
        if n.contains("@") || extensions.contains(n) { return true }
        let range = NSRange(n.startIndex..., in: n)
        return patterns.contains { $0.firstMatch(in: n, range: range) != nil }
    }
}

@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [PhoneContact] = []
    @Published var company: [PhoneContact] = []
    @Published var denied = false
    private var rules: DialRules?

    func load() async {
        async let pbx = loadCompany()
        let phone = await loadPhone()
        let comp = await pbx
        SipManager.shared.learnNames(comp + phone)   // names on incoming calls and in Recents (all numbers)
        company = dialable(comp)
        contacts = dialable(phone)
    }

    /// Only the numbers the company's PBX can dial; a contact left with none is not listed.
    private func dialable(_ list: [PhoneContact]) -> [PhoneContact] {
        list.compactMap { c in
            let nums = c.numbers.filter { rules?.canDial($0) ?? !DialRules.hasLetters($0) }
            return nums.isEmpty ? nil : PhoneContact(id: c.id, name: c.name, numbers: nums)
        }
    }

    /// Empty when the account isn't set up, the endpoint isn't deployed yet (404) or the request fails.
    private func loadCompany() async -> [PhoneContact] {
        let acc = Account.load()
        guard acc.isConfigured, let url = URL(string: "https://\(acc.domain)/app/n2it/contacts.php") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 15)
        let login = Data("\(acc.user):\(acc.password)".utf8).base64EncodedString()
        req.setValue("Basic \(login)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(PbxContacts.self, from: data) else { return [] }
        if let pats = list.dial_patterns {
            rules = DialRules(patterns: pats.compactMap { try? NSRegularExpression(pattern: $0) },
                              extensions: Set((list.extensions ?? []).map(\.number)))
        }
        return list.contacts.enumerated().compactMap { i, c in
            let nums = c.numbers.map(\.number).filter { !$0.isEmpty }
            return nums.isEmpty ? nil : PhoneContact(id: "pbx-\(i)", name: c.name, numbers: nums)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadPhone() async -> [PhoneContact] {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { denied = true; return [] }
        denied = false
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let req = CNContactFetchRequest(keysToFetch: keys)
        req.sortOrder = .givenName
        var out: [PhoneContact] = []
        try? store.enumerateContacts(with: req) { c, _ in
            let nums = c.phoneNumbers.map { $0.value.stringValue }
            guard !nums.isEmpty else { return }
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            out.append(PhoneContact(id: c.identifier, name: name.isEmpty ? c.organizationName : name, numbers: nums))
        }
        return out
    }
}

struct ContactsView: View {
    @EnvironmentObject var sip: SipManager
    @StateObject private var store = ContactsStore()
    @State private var query = ""
    @State private var picking: PhoneContact?

    private func matches(_ list: [PhoneContact]) -> [PhoneContact] {
        query.isEmpty ? list
            : list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.numbers.contains { $0.contains(query) } }
    }

    var body: some View {
        NavigationStack {
            List {
                let company = matches(store.company)
                if !company.isEmpty {
                    Section("Company") { ForEach(company) { row($0) } }
                }
                let phone = matches(store.contacts)
                if !phone.isEmpty {
                    Section(store.company.isEmpty ? "" : "Phone") { ForEach(phone) { row($0) } }
                }
            }
            .overlay {
                if store.company.isEmpty && store.denied {
                    Text("Allow Contacts access in Settings to dial from your contacts.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
                } else if store.company.isEmpty && store.contacts.isEmpty { Text("No contacts").foregroundStyle(.secondary) }
            }
            .searchable(text: $query)
            .navigationTitle("Contacts")
            .confirmationDialog("Call", isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                                presenting: picking) { c in
                ForEach(c.numbers, id: \.self) { n in Button(n) { dial(n) } }
            }
            .task { await store.load() }
            .refreshable { await store.load() }
        }
    }

    private func row(_ c: PhoneContact) -> some View {
        Button { c.numbers.count == 1 ? dial(c.numbers[0]) : (picking = c) } label: {
            VStack(alignment: .leading) {
                Text(c.name).foregroundStyle(.primary)
                Text(c.numbers.first ?? "").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Strip spaces, dashes and brackets; turn +27... into 0... style is left to the PBX dial plan.
    private func dial(_ raw: String) {
        let allowed = Set("+0123456789*#")
        sip.call(String(raw.filter { allowed.contains($0) }))
    }
}
