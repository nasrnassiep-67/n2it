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
    let contacts: [Contact]
}

@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [PhoneContact] = []
    @Published var company: [PhoneContact] = []
    @Published var denied = false

    func load() async {
        async let pbx = loadCompany()
        await loadPhone()
        company = await pbx
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
        return list.contacts.enumerated().compactMap { i, c in
            let nums = c.numbers.map(\.number).filter { !$0.isEmpty }
            return nums.isEmpty ? nil : PhoneContact(id: "pbx-\(i)", name: c.name, numbers: nums)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadPhone() async {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { denied = true; return }
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
        contacts = out
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
