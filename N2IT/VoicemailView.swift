import SwiftUI

struct VoicemailView: View {
    @EnvironmentObject var sip: SipManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "recordingtape").font(.system(size: 56)).foregroundStyle(.secondary)
                if sip.newVoicemails > 0 {
                    Text("\(sip.newVoicemails) new message\(sip.newVoicemails == 1 ? "" : "s")").font(.title2)
                } else {
                    Text("No new messages").font(.title2).foregroundStyle(.secondary)
                }
                if sip.oldVoicemails > 0 { Text("\(sip.oldVoicemails) saved").foregroundStyle(.secondary) }
                Button {
                    sip.call(Account.load().voicemailNumber)
                } label: {
                    Label("Call voicemail", systemImage: "phone.fill").frame(maxWidth: 260).padding()
                        .background(Color.green).foregroundStyle(.white).clipShape(Capsule())
                }
                .disabled(!sip.registered)
            }
            .navigationTitle("Voicemail")
        }
    }
}
