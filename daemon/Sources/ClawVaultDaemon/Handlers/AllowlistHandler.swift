import Foundation

/// POST /allowlist — Modify allowlist (requires companion approval + Touch ID).
struct AllowlistHandler {
    let services: ServiceContainer
    let companionProxy: CompanionProxy
    let auditLogger: AuditLogger
    let configStore: ConfigStore

    func handle(request: HTTPRequest) async -> HTTPResponse {
        // 1. Parse the JSON body
        guard let body = request.body,
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let action = json["action"] as? String,
            let address = json["address"] as? String
        else {
            return .error(400, "Missing required fields: action (add/remove), address")
        }

        guard action == "add" || action == "remove" else {
            return .error(400, "action must be 'add' or 'remove'")
        }

        // Build a human-readable summary
        let changeSummary = action == "add"
            ? "Add \(address) to allowlist"
            : "Remove \(address) from allowlist"

        // 2. Request admin approval via companion (Touch ID + confirmation dialog)
        do {
            let approved = try await companionProxy.requestAdminApproval(summary: changeSummary)
            if !approved {
                await auditLogger.log(
                    action: "allowlist_update",
                    target: address,
                    decision: "denied",
                    reason: "User denied via companion app"
                )
                return .error(403, "Allowlist update denied by user")
            }
        } catch {
            await auditLogger.log(
                action: "allowlist_update",
                target: address,
                decision: "denied",
                reason: "Companion unreachable: \(error.localizedDescription)"
            )
            return .error(503, error.localizedDescription)
        }

        // 3. Apply changes to policy engine
        if action == "add" {
            await services.policyEngine.addToAllowlist(address)
        } else {
            await services.policyEngine.removeFromAllowlist(address)
        }

        // 4. Persist allowlist to config
        let currentAllowlist = await services.policyEngine.currentAllowlist
        do {
            try configStore.update { cfg in
                cfg.allowlistedAddresses = Array(currentAllowlist)
            }
        } catch {
            await auditLogger.log(
                action: "allowlist_update",
                target: address,
                decision: "warning",
                reason: "Failed to persist allowlist: \(error.localizedDescription)"
            )
        }

        await auditLogger.log(
            action: "allowlist_update",
            target: address,
            decision: "approved",
            reason: changeSummary
        )

        return .json(200, [
            "status": "updated",
            "action": action,
            "address": address,
        ])
    }
}
