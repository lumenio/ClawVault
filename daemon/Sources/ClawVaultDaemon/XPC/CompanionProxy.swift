import Foundation

/// Actor wrapping the companion app's XPC callback proxy.
/// Provides async wrappers for daemon → companion calls.
/// Throws `CompanionError.unreachable` if no companion is connected (fail closed).
actor CompanionProxy {
    private var proxy: CompanionCallbackProtocol?

    /// Store the companion's callback proxy (called when companion connects via XPC).
    nonisolated func setProxy(_ proxy: CompanionCallbackProtocol) {
        Task { await _setProxy(proxy) }
    }

    /// Clear the stored proxy (called on connection interruption/invalidation).
    nonisolated func clearProxy() {
        Task { await _clearProxy() }
    }

    /// Whether a companion is currently connected.
    var isConnected: Bool {
        proxy != nil
    }

    // MARK: - Async wrappers

    /// Request admin approval via the companion (Touch ID + confirmation dialog).
    /// - Parameter summary: Human-readable description of the action.
    /// - Returns: `true` if user approved, `false` if denied.
    /// - Throws: `CompanionError.unreachable` if companion is not connected.
    func requestAdminApproval(summary: String) async throws -> Bool {
        guard let proxy = proxy else {
            throw CompanionError.unreachable
        }
        return try await withCheckedThrowingContinuation { continuation in
            proxy.requestAdminApproval(summary: summary) { approved in
                continuation.resume(returning: approved)
            }
        }
    }

    /// Post an approval notification to the companion.
    /// Returns `true` if the companion accepted and stored the approval in its UI.
    /// - Throws: `CompanionError.unreachable` if companion is not connected.
    func postApprovalNotification(
        code: String,
        summary: String,
        hashPrefix: String,
        expiresIn: Int
    ) async throws -> Bool {
        guard let proxy = proxy else {
            throw CompanionError.unreachable
        }
        return try await withCheckedThrowingContinuation { continuation in
            proxy.postApprovalNotification(
                code: code,
                summary: summary,
                hashPrefix: hashPrefix,
                expiresIn: expiresIn
            ) { stored in
                continuation.resume(returning: stored)
            }
        }
    }

    // MARK: - Private

    private func _setProxy(_ proxy: CompanionCallbackProtocol) {
        self.proxy = proxy
    }

    private func _clearProxy() {
        self.proxy = nil
    }
}

// MARK: - CompanionError

enum CompanionError: Error, CustomStringConvertible {
    case unreachable

    var description: String {
        switch self {
        case .unreachable:
            return "Companion app required for approvals — please start ClawVault.app"
        }
    }
}
