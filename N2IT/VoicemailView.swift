import SwiftUI

struct VoicemailView: View {
    @EnvironmentObject var sip: SipManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "recordingtape").font(.system(size: 56)).foregroundStyle(.secondary)
                if sip.hasVoicemail {
                    Text(sip.newVoicemails > 0 ? "\(sip.newVoicemails) new message\(sip.newVoicemails == 1 ? "" : "s")" : "You have new voicemail").font(.title2)
                } else {
                    Text("No new messages").font(.title2).foregroundStyle(.secondary)
                }
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
