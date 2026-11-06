import SwiftUI

/// Number box for Add participant and Transfer (port of Android 0.2.5 / 0.2.13 NumberOrContact): type an extension
/// or number, or search by name; matching company and phone contacts are listed under it and a tap fills in the
/// number. Whatever is in the box, a highlighted line says who it will reach (the contact's name, or "Not in your
/// contacts"), and the button names them. Still two steps on purpose (pick, then press the button): one tap must not
/// call or add the wrong person into a live conference.
struct NumberPicker: View {
    enum Mode { case add(inConference: Bool), transfer }
    let mode: Mode
    /// Add: the number. Transfer: the number and whether to consult first.
    let onAdd: (String) -> Void
    let onTransfer: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ContactsStore.shared
    @State private var target = ""
    @FocusState private var focused: Bool

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let number: String
        let company: Bool
    }

    private var entries: [Entry] {
        store.company.flatMap { c in c.numbers.map { Entry(id: "c\(c.id)\($0)", name: c.name, number: $0, company: true) } } +
        store.contacts.flatMap { c in c.numbers.map { Entry(id: "p\(c.id)\($0)", name: c.name, number: $0, company: false) } }
    }

    /// What the buttons dial: the typed number, or nothing while the box holds a name search.
    private var number: String? {
        let n = DialRules.clean(target)
        if target.contains("@") { return n.isEmpty ? nil : n }
        return !n.isEmpty && !target.contains(where: \.isLetter) ? n : nil
    }

    /// The contact the number in the box reaches (same matching as caller names: last 9 digits).
    private var who: Entry? {
        guard let n = number else { return nil }
        let key = SipManager.numberKey(n)
        guard !key.isEmpty else { return nil }
        return entries.first { SipManager.numberKey($0.number) == key }
    }

    private var matches: [Entry] {
        let q = target.trimmingCharacters(in: .whitespaces)
        let digits = q.filter(\.isNumber)
        return Array(entries.filter { e in
            q.isEmpty || e.name.localizedCaseInsensitiveContains(q) ||
            (digits.count >= 2 && e.number.filter(\.isNumber).contains(digits))
        }.prefix(60))
    }

    private var title: String {
        if case .transfer = mode { return "Transfer to" }
        return "Add participant"
    }

    private func short(_ s: String) -> String { s.count > 18 ? String(s.prefix(17)).trimmingCharacters(in: .whitespaces) + "…" : s }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name, extension or number", text: $target)
                        .keyboardType(.namePhonePad).textContentType(.none).autocorrectionDisabled()
                        .textInputAutocapitalization(.never).focused($focused)
                    if let n = number {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(who?.name.isEmpty == false ? who!.name : n).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(who != nil ? n : "Not in your contacts").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.accentColor.opacity(0.15))
                    }
                } footer: {
                    if case .add(let conf) = mode {
                        Text(conf ? "They join the conference when they answer."
                                  : "The current call goes on hold. Tap Merge calls once they answer.")
                    }
                }
                Section { buttons }
                // A list that only repeats the person named above would just be a second thing to tap
                let list = matches
                if !list.isEmpty && !(who != nil && list.count == 1) {
                    Section("Contacts") {
                        ForEach(list) { e in
                            Button { target = DialRules.clean(e.number) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: e.company ? "building.2" : "person").frame(width: 22).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.name).foregroundStyle(.primary)
                                        Text(e.number).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.contentShape(Rectangle())
                            }.tint(.primary)
                        }
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { if let t = Screenshots.pickerText { target = t }; focused = Screenshots.pickerText == nil; if store.company.isEmpty && store.contacts.isEmpty { await store.load() } }
        }
    }

    @ViewBuilder private var buttons: some View {
        let label = who.map { $0.name.isEmpty ? nil : short($0.name) } ?? number.map(short)
        switch mode {
        case .add(let conf):
            Button {
                if let n = number { onAdd(n); dismiss() }
            } label: {
                Label((conf ? "Add" : "Call") + (label.map { " " + $0 } ?? ""), systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(number == nil)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        case .transfer:
            HStack(spacing: 12) {
                Button { if let n = number { onTransfer(n, false); dismiss() } } label: {
                    Text("Blind").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button { if let n = number { onTransfer(n, true); dismiss() } } label: {
                    Text("Consult first").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }.disabled(number == nil)
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }
}
