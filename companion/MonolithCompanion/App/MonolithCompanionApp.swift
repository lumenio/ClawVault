import SwiftUI

/// Monolith Companion — menu bar app for Touch ID approvals and notifications.
/// LSUIElement = YES (no dock icon, menu bar only).
/// Connects to daemon via XPC Mach service, exports CompanionCallbackProtocol.
@main
struct MonolithCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Monolith", systemImage: "lock.shield") {
            MenuBarView(xpcClient: appDelegate.xpcClient)
        }
    }
}
