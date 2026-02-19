import Foundation

// MARK: - Daemon → Companion Callback Protocol

/// Protocol for daemon to call back into the companion app.
/// The companion exports this interface on its XPC connection.
@objc protocol CompanionCallbackProtocol {
    /// Request admin approval (Touch ID + confirmation dialog).
    /// The companion shows a SwiftUI sheet with the summary and prompts for biometric auth.
    /// - Parameters:
    ///   - summary: Human-readable description of the action requiring approval.
    ///   - reply: `true` if user approved (Touch ID succeeded), `false` if denied or cancelled.
    func requestAdminApproval(summary: String, reply: @escaping (Bool) -> Void)

    /// Post an approval notification to the companion UI.
    /// The companion stores the approval in its pending list (always visible in menu bar)
    /// and attempts a macOS notification (best-effort).
    /// - Parameters:
    ///   - code: The 8-digit approval code.
    ///   - summary: Human-readable transaction summary.
    ///   - hashPrefix: First 18 chars of the approval hash hex.
    ///   - expiresIn: Seconds until expiry.
    ///   - reply: `true` if companion accepted and stored the approval, `false` on error.
    func postApprovalNotification(
        code: String,
        summary: String,
        hashPrefix: String,
        expiresIn: Int,
        reply: @escaping (Bool) -> Void
    )
}

// MARK: - Companion → Daemon Protocol

/// Protocol for the companion app to call into the daemon.
/// The daemon implements this interface on its XPC listener.
@objc protocol DaemonXPCProtocol {
    /// List all pending approval requests.
    /// Used by the companion to populate its menu bar pending approvals dropdown.
    /// Daemon is the source of truth — companion restart doesn't lose codes.
    func listPendingApprovals(reply: @escaping ([PendingApprovalInfo]) -> Void)

    /// Ping the daemon to check connectivity.
    func ping(reply: @escaping (Bool) -> Void)
}

// MARK: - PendingApprovalInfo (NSSecureCoding for XPC transport)

/// Represents a pending approval request, transported over XPC.
/// Uses NSObject + NSSecureCoding with primitive-typed properties
/// to avoid fragile [String: Any] bridging.
class PendingApprovalInfo: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    @objc let code: String
    @objc let summary: String
    @objc let hashPrefix: String
    @objc let expiresAt: Date

    init(code: String, summary: String, hashPrefix: String, expiresAt: Date) {
        self.code = code
        self.summary = summary
        self.hashPrefix = hashPrefix
        self.expiresAt = expiresAt
        super.init()
    }

    required init?(coder: NSCoder) {
        guard let code = coder.decodeObject(of: NSString.self, forKey: "code") as String?,
              let summary = coder.decodeObject(of: NSString.self, forKey: "summary") as String?,
              let hashPrefix = coder.decodeObject(of: NSString.self, forKey: "hashPrefix") as String?,
              let expiresAt = coder.decodeObject(of: NSDate.self, forKey: "expiresAt") as Date?
        else {
            return nil
        }
        self.code = code
        self.summary = summary
        self.hashPrefix = hashPrefix
        self.expiresAt = expiresAt
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(code as NSString, forKey: "code")
        coder.encode(summary as NSString, forKey: "summary")
        coder.encode(hashPrefix as NSString, forKey: "hashPrefix")
        coder.encode(expiresAt as NSDate, forKey: "expiresAt")
    }
}
