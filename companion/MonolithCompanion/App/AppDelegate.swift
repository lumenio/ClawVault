import Foundation
import SwiftUI
import UserNotifications

/// Application delegate — manages XPC connection lifecycle and notification setup.
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let xpcClient = CompanionXPCClient()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission
        Task {
            do {
                try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("[Companion] Notification permission denied: \(error)")
            }
        }

        // Connect to daemon
        xpcClient.connect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        xpcClient.disconnect()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
