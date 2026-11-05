import SwiftUI

@main struct ElunoApp: App {
    @StateObject private var store = ElunoStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ElunoView(store: store)
                .tint(Color(red: 0.09, green: 0.38, blue: 0.30))
                .onOpenURL { store.scanned($0.absoluteString) }
                .onChange(of: scenePhase) { phase in
                    // Only leaving the foreground pauses work. A permission alert, Control Center or an
                    // iPad window resize makes the scene inactive for a moment, and must not cancel transfers.
                    if phase == .active {
                        store.foreground(true)
                    } else if phase == .background {
                        store.foreground(false)
                    }
                }
        }
    }
}
