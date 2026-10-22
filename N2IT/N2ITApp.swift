import SwiftUI

@main
struct N2ITApp: App {
    @StateObject private var sip = SipManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sip)
                // "Call failed: Busy" and the like, once the call screen is gone (during a call the call screen shows it)
                .alert("N2IT Phone", isPresented: Binding(get: { sip.notice != nil && sip.activeCall == nil },
                                                          set: { if !$0 { sip.notice = nil } }),
                       actions: { Button("OK") {} }, message: { Text(sip.notice ?? "") })
                .fullScreenCover(isPresented: .constant(sip.activeCall != nil)) {
                    CallView().environmentObject(sip)
                }
        }
    }
}
