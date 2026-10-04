import SwiftUI

@main
struct N2ITApp: App {
    @StateObject private var sip = SipManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sip)
                .fullScreenCover(isPresented: .constant(sip.activeCall != nil)) {
                    CallView().environmentObject(sip)
                }
        }
    }
}
