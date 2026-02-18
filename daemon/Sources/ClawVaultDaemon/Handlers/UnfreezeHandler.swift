import Foundation

/// POST /unfreeze — Unfreeze the wallet locally after on-chain unfreeze is confirmed.
/// Requires: config.frozen == true, on-chain wallet.frozen() == false, companion approval + Touch ID.
///
/// The /unfreeze endpoint clears local freeze state only, after verifying on-chain frozen() == false.
/// On-chain unfreeze is performed externally by the recovery address (EOA) calling
/// requestUnfreeze() + finalizeUnfreeze() via a normal transaction — NOT via a UserOp from the daemon.
struct UnfreezeHandler {
    let services: ServiceContainer
    let companionProxy: CompanionProxy
    let auditLogger: AuditLogger
    let configStore: ConfigStore

    func handle(request: HTTPRequest) async -> HTTPResponse {
        let config = configStore.read()

        // 1. Must be frozen locally
        guard config.frozen else {
            return .error(400, "Wallet is not frozen")
        }

        guard let walletAddress = config.walletAddress else {
            return .error(503, "Wallet not deployed yet")
        }

        // 2. Verify on-chain frozen() == false via eth_call
        // frozen() selector = 0x054f7d9c
        let frozenOnChain: Bool
        do {
            let result = try await services.chainClient.ethCall(to: walletAddress, data: "0x054f7d9c")
            // Result is a bool (32 bytes), last byte is 0 (false) or 1 (true)
            if let resultData = SignatureUtils.fromHex(result), resultData.count >= 32 {
                frozenOnChain = resultData[31] != 0
            } else {
                frozenOnChain = true // Assume frozen if we can't read
            }
        } catch {
            return .error(500, "Failed to check on-chain freeze status: \(error.localizedDescription)")
        }

        if frozenOnChain {
            return .json(409, [
                "status": "still_frozen_on_chain",
                "message": "Wallet is still frozen on-chain. The recovery address must call requestUnfreeze() and then finalizeUnfreeze() after the 10-minute delay.",
                "recoveryAddress": config.recoveryAddress ?? "unknown",
            ])
        }

        // 3. Request admin approval via companion (Touch ID + confirmation dialog)
        do {
            let approved = try await companionProxy.requestAdminApproval(
                summary: "The wallet has been unfrozen on-chain. Confirm to unfreeze the daemon locally and resume signing."
            )
            if !approved {
                await auditLogger.log(
                    action: "unfreeze",
                    decision: "denied",
                    reason: "User denied via companion app"
                )
                return .error(403, "Unfreeze denied by user")
            }
        } catch {
            await auditLogger.log(
                action: "unfreeze",
                decision: "denied",
                reason: "Companion unreachable: \(error.localizedDescription)"
            )
            return .error(503, error.localizedDescription)
        }

        // 4. Unfreeze locally
        await services.policyEngine.unfreeze()
        do {
            try configStore.update { $0.frozen = false }
        } catch {
            await auditLogger.log(
                action: "unfreeze",
                decision: "warning",
                reason: "Failed to persist unfrozen state: \(error.localizedDescription)"
            )
        }

        await auditLogger.log(
            action: "unfreeze",
            decision: "approved",
            reason: "Wallet unfrozen locally after on-chain confirmation + Touch ID"
        )

        return .json(200, [
            "status": "unfrozen",
            "message": "Wallet is unfrozen. Signing is now enabled.",
        ])
    }
}
