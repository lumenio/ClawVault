import Foundation

/// View model for a pending approval displayed in the companion menu bar.
struct PendingApproval: Identifiable {
    let id = UUID()
    let code: String
    let summary: String
    let hashPrefix: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var timeRemaining: String {
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining <= 0 { return "expired" }
        return "\(Int(remaining))s"
    }
}

/// Represents an in-flight admin approval request from the daemon.
/// Triggers a SwiftUI sheet with Touch ID in the companion.
class AdminApprovalRequest: Identifiable, ObservableObject {
    let id = UUID()
    let summary: String
    let completion: (Bool) -> Void

    init(summary: String, completion: @escaping (Bool) -> Void) {
        self.summary = summary
        self.completion = completion
    }
}
