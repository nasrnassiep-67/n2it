import SwiftUI
import Contacts

struct PhoneContact: Identifiable {
    let id: String
    let name: String
    let numbers: [String]
}

@MainActor
final class ContactsStore: ObservableObject {
    @Published var contacts: [PhoneContact] = []
    @Published var denied = false

    func load() async {
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

    private var filtered: [PhoneContact] {
        query.isEmpty ? store.contacts
            : store.contacts.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.numbers.contains { $0.contains(query) } }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { c in
                Button { c.numbers.count == 1 ? dial(c.numbers[0]) : (picking = c) } label: {
                    VStack(alignment: .leading) {
                        Text(c.name).foregroundStyle(.primary)
                        Text(c.numbers.first ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if store.denied {
                    Text("Allow Contacts access in Settings to dial from your contacts.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding()
                } else if store.contacts.isEmpty { Text("No contacts").foregroundStyle(.secondary) }
            }
            .searchable(text: $query)
            .navigationTitle("Contacts")
            .confirmationDialog("Call", isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                                presenting: picking) { c in
                ForEach(c.numbers, id: \.self) { n in Button(n) { dial(n) } }
            }
            .task { await store.load() }
        }
    }

    /// Strip spaces, dashes and brackets; turn +27... into 0... style is left to the PBX dial plan.
    private func dial(_ raw: String) {
        let allowed = Set("+0123456789*#")
        sip.call(String(raw.filter { allowed.contains($0) }))
    }
}
