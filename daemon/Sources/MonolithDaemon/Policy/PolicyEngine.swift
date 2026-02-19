import Foundation

/// Core policy engine — default-deny, gates every signing request.
/// This is the primary defense against prompt injection.
actor PolicyEngine {
    private var profile: SecurityProfile
    private let protocolRegistry: ProtocolRegistry
    private let stablecoinRegistry: StablecoinRegistry
    private let spendingTracker: SpendingTracker
    private let chainClient: ChainClient?
    private let chainId: UInt64
    private var allowlistedAddresses: Set<String>
    private var frozen: Bool
    private var walletAddress: String?

    enum Decision {
        case allow
        case requireApproval(String)
        case deny(String)
    }

    init(
        profile: SecurityProfile,
        protocolRegistry: ProtocolRegistry,
        stablecoinRegistry: StablecoinRegistry,
        allowlistedAddresses: Set<String> = [],
        frozen: Bool = false,
        chainClient: ChainClient? = nil,
        chainId: UInt64 = 8453,
        walletAddress: String? = nil
    ) {
        self.profile = profile
        self.protocolRegistry = protocolRegistry
        self.stablecoinRegistry = stablecoinRegistry
        self.spendingTracker = SpendingTracker()
        self.allowlistedAddresses = allowlistedAddresses
        self.frozen = frozen
        self.chainClient = chainClient
        self.chainId = chainId
        self.walletAddress = walletAddress
    }

    /// Evaluate an intent against the policy.
    func evaluate(
        target: String,
        calldata: Data,
        value: UInt64,
        chainId: UInt64
    ) async -> Decision {
        // 1. Frozen check
        if frozen {
            return .deny("Wallet is frozen")
        }

        // 2. Blocked selectors ALWAYS require approval
        if SelectorBlocklist.isCalldataBlocked(calldata) {
            return .requireApproval("Blocked selector detected — requires explicit approval")
        }

        // 3. Decode the intent
        let decoded = CalldataDecoder.decode(
            calldata: calldata,
            target: target,
            value: value,
            chainId: chainId,
            stablecoinRegistry: stablecoinRegistry,
            protocolRegistry: protocolRegistry
        )

        // 4. Unknown calldata → require approval (default-deny)
        if !decoded.isKnown {
            return .requireApproval("Unknown calldata: \(decoded.summary)")
        }

        // 5. Determine amounts for spending check
        let ethAmount = value
        var stablecoinAmount: UInt64 = 0

        // ERC-20 transfer to stablecoin
        if calldata.count >= 68 {
            let selector = calldata.prefix(4).map { String(format: "%02x", $0) }.joined()
            if selector == "a9059cbb" {
                let amountBytes = calldata[36..<68]
                stablecoinAmount = CalldataDecoder.dataToUInt64(Data(amountBytes))

                if !stablecoinRegistry.isStablecoin(chainId: chainId, address: target) {
                    // Unknown token transfer — require approval
                    return .requireApproval("Unknown token transfer requires approval")
                }
            }
        }

        // 6. Check if target is a known DeFi protocol
        if calldata.count >= 4 {
            let selector =
                "0x" + calldata.prefix(4).map { String(format: "%02x", $0) }.joined()
            if protocolRegistry.isAllowed(chainId: chainId, target: target, selector: selector) {
                // Slippage enforcement for swap operations (§6.4)
                let selectorHex = calldata.prefix(4).map { String(format: "%02x", $0) }.joined()
                if selectorHex == "3593564c" { // Uniswap Universal Router execute()
                    // Validate swap safety before slippage check
                    if let swapParams = CalldataDecoder.extractSwapParams(calldata) {
                        // Validate recipient is MSG_SENDER (0x0..0001) or the wallet address
                        let recipientLower = swapParams.recipient.lowercased()
                        let msgSender = "0x0000000000000000000000000000000000000001"
                        let walletLower = walletAddress?.lowercased() ?? ""
                        if recipientLower != msgSender && recipientLower != walletLower {
                            return .requireApproval("Swap recipient is not the wallet — possible output diversion")
                        }

                        // Validate command set: only WRAP_ETH (0x0b) and V3_SWAP_EXACT_IN (0x00) allowed
                        let allowedCommands: Set<UInt8> = [0x00, 0x0b] // V3_SWAP_EXACT_IN, WRAP_ETH
                        let disallowedCommands = swapParams.commands.filter { !allowedCommands.contains($0) }
                        if !disallowedCommands.isEmpty {
                            let hexCmds = disallowedCommands.map { String(format: "0x%02x", $0) }.joined(separator: ", ")
                            return .requireApproval("Swap contains disallowed commands [\(hexCmds)] — approval required")
                        }

                        // Validate payerIsUser consistency
                        let hasWrapEth = swapParams.commands.contains(0x0b)
                        if hasWrapEth && swapParams.payerIsUser {
                            // ETH→token swap: router has WETH from WRAP_ETH, payerIsUser should be false
                            return .requireApproval("ETH swap with payerIsUser=true — unexpected, approval required")
                        }
                        if !hasWrapEth && !swapParams.payerIsUser {
                            // Token→token swap: payerIsUser should be true (wallet pays directly)
                            return .requireApproval("Token swap with payerIsUser=false — unexpected, approval required")
                        }
                    }

                    let slippageResult = await verifySwapSlippage(calldata)
                    switch slippageResult {
                    case .cannotDecode:
                        return .requireApproval("Cannot decode swap calldata — approval required")
                    case .noQuoter:
                        return .requireApproval("Cannot verify slippage (no Quoter) — approval required")
                    case .multiHop:
                        return .requireApproval("Multi-hop swap — cannot verify slippage")
                    case .exceedsLimit(let actualBps):
                        let slippagePct = String(format: "%.1f", Double(actualBps) / 100.0)
                        let limitPct = String(format: "%.1f", Double(profile.maxSlippageBps) / 100.0)
                        return .requireApproval("Slippage \(slippagePct)% exceeds limit \(limitPct)%")
                    case .withinLimits:
                        break // proceed to spending check
                    }
                }

                // DeFi autopilot action — check spending limits
                let spendResult = await spendingTracker.check(
                    ethAmount: ethAmount,
                    stablecoinAmount: stablecoinAmount,
                    profile: profile
                )
                switch spendResult {
                case .allowed:
                    return .allow
                case .denied(let reason):
                    return .requireApproval("Spending limit: \(reason)")
                }
            }
        }

        // 7. Native ETH transfer or stablecoin transfer to allowlisted address
        // For ERC-20 transfers, check the decoded recipient (not target, which is the token contract)
        let isERC20Transfer = calldata.count >= 68
            && calldata.prefix(4).map { String(format: "%02x", $0) }.joined() == "a9059cbb"
        let checkAddress: String
        if isERC20Transfer {
            // Extract recipient from calldata[16..<36] (skip 4 selector + 12 zero-padding)
            let recipientBytes = calldata[16..<36]
            checkAddress = ("0x" + recipientBytes.map { String(format: "%02x", $0) }.joined()).lowercased()
        } else {
            checkAddress = target.lowercased()
        }
        let isAllowlisted = allowlistedAddresses.contains(checkAddress)

        if calldata.isEmpty || isERC20Transfer {
            // Simple transfer — check spending limits
            let spendResult = await spendingTracker.check(
                ethAmount: ethAmount,
                stablecoinAmount: stablecoinAmount,
                profile: profile
            )
            switch spendResult {
            case .allowed:
                if isAllowlisted || (ethAmount == 0 && stablecoinAmount == 0) {
                    return .allow
                }
                // Non-allowlisted address — require approval for non-trivial amounts
                return .requireApproval("Transfer to non-allowlisted address")
            case .denied(let reason):
                return .requireApproval("Spending limit: \(reason)")
            }
        }

        // 8. Anything else — require approval
        return .requireApproval("Action requires approval: \(decoded.summary)")
    }

    /// Record a completed transaction.
    func recordTransaction(ethAmount: UInt64, stablecoinAmount: UInt64) async {
        await spendingTracker.record(ethAmount: ethAmount, stablecoinAmount: stablecoinAmount)
    }

    /// Get remaining budgets.
    func remainingBudgets() async -> (ethRemaining: UInt64, stablecoinRemaining: UInt64) {
        await spendingTracker.remainingBudgets(profile: profile)
    }

    /// Freeze the policy engine (blocks all signing).
    func freeze() {
        frozen = true
    }

    /// Unfreeze the policy engine.
    func unfreeze() {
        frozen = false
    }

    var isFrozen: Bool { frozen }

    /// Add address to allowlist.
    func addToAllowlist(_ address: String) {
        allowlistedAddresses.insert(address.lowercased())
    }

    /// Remove address from allowlist.
    func removeFromAllowlist(_ address: String) {
        allowlistedAddresses.remove(address.lowercased())
    }

    /// Get profile info.
    var profileName: String { profile.name }
    var maxSlippageBps: Int { profile.maxSlippageBps }

    /// Get the set of allowlisted addresses.
    var currentAllowlist: Set<String> { allowlistedAddresses }

    /// Update the active security profile (called by PolicyHandler after Touch ID).
    func updateProfile(_ newProfile: SecurityProfile) {
        self.profile = newProfile
    }

    // MARK: - Slippage Verification

    private enum SlippageResult {
        case withinLimits
        case exceedsLimit(Int)   // actual slippage in bps
        case cannotDecode
        case noQuoter
        case multiHop
    }

    /// Verify swap slippage by decoding calldata and querying the Uniswap Quoter.
    private func verifySwapSlippage(_ calldata: Data) async -> SlippageResult {
        // 1. Decode Universal Router calldata to extract swap params
        guard let swapParams = CalldataDecoder.extractSwapParams(calldata) else {
            return .cannotDecode
        }

        // 2. Multi-hop swaps require approval (too complex to verify in MVP)
        if swapParams.isMultiHop {
            return .multiHop
        }

        // 3. Query QuoterV2 for a fresh market quote
        guard let client = chainClient else {
            return .noQuoter
        }

        do {
            let quotedOutput = try await client.quoteExactInputSingle(
                chainId: chainId,
                tokenIn: swapParams.tokenIn,
                tokenOut: swapParams.tokenOut,
                amountIn: swapParams.amountIn,
                fee: swapParams.fee
            )

            guard quotedOutput > 0 else { return .cannotDecode }

            // 4. Compute actual slippage: (quote - amountOutMin) / quote * 10000
            if swapParams.amountOutMin > quotedOutput {
                // amountOutMin is above quote — no slippage concern
                return .withinLimits
            }

            let slippageBps = Int((quotedOutput - swapParams.amountOutMin) * 10000 / quotedOutput)

            if slippageBps > profile.maxSlippageBps {
                return .exceedsLimit(slippageBps)
            }

            return .withinLimits
        } catch {
            // Quoter call failed — safe default-deny
            return .noQuoter
        }
    }
}
