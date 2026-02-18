import Foundation
import UserNotifications

/// Wrapper for UNUserNotificationCenter — used by companion to manage notification categories.
enum NotificationManager {
    static let approvalCategory = "CLAWVAULT_APPROVAL"

    /// Register notification categories for actionable notifications.
    static func registerCategories() {
        let category = UNNotificationCategory(
            identifier: approvalCategory,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
