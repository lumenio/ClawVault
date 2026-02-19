import CryptoKit
import Foundation

/// Monolith Signing Daemon
/// macOS background service that manages Secure Enclave keys, enforces spending policy,
/// and constructs/signs ERC-4337 UserOperations.

@main
struct MonolithDaemon {
    static func main() async {
        print("[Monolith] Starting daemon v0.2.0")

        // Ensure config directory exists
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: DaemonConfig.configDir.path) {
                try fm.createDirectory(at: DaemonConfig.configDir, withIntermediateDirectories: true)
                try fm.setAttributes(
                    [.posixPermissions: 0o700], ofItemAtPath: DaemonConfig.configDir.path)
            }
        } catch {
            print("[Monolith] ERROR: Failed to create config directory: \(error)")
            return
        }

        // ──────────────────────────────────────────────────────────────────────
        // 1. Initialize Secure Enclave (must happen before config verification)
        // ──────────────────────────────────────────────────────────────────────
        let seManager = SecureEnclaveManager()
        do {
            try await seManager.initialize()
            let pubKey = try await seManager.signingPublicKey()
            print(
                "[Monolith] Secure Enclave initialized. Signing key: \(SignatureUtils.toHex(pubKey.x).prefix(18))..."
            )
        } catch {
            print("[Monolith] ERROR: Secure Enclave not available: \(error)")
            print("[Monolith] Running in degraded mode (no signing capability)")
        }

        // ──────────────────────────────────────────────────────────────────────
        // 2. Load + verify config integrity (SE must be initialized first)
        // ──────────────────────────────────────────────────────────────────────
        let configStore: ConfigStore
        var safeMode = false
        do {
            let signingKey = try await seManager.signingKeyForConfig()
            let publicKey = signingKey.publicKey

            if let verified = DaemonConfig.loadVerified(publicKey: publicKey) {
                // Config signature valid
                configStore = ConfigStore(verified)
                configStore.setSigner(signingKey)
                print("[Monolith] Config integrity verified")
            } else if fm.fileExists(atPath: DaemonConfig.configPath.path) {
                // Config exists but verification failed — check if it's a first-time migration
                // (no .sig file yet = legacy config, not tampered)
                if !fm.fileExists(atPath: DaemonConfig.configSigPath.path) {
                    // Legacy config without signature — migrate by signing it
                    let config = (try? DaemonConfig.load()) ?? DaemonConfig.defaultConfig()
                    try config.save(signer: signingKey)
                    configStore = ConfigStore(config)
                    configStore.setSigner(signingKey)
                    print("[Monolith] Migrated legacy config — now signed")
                } else {
                    // Signature file exists but verification failed → tampered
                    print("[Monolith] WARNING: Config integrity check failed — starting in safe mode")
                    safeMode = true
                    var safeModeConfig = DaemonConfig.defaultConfig()
                    safeModeConfig.frozen = true
                    try safeModeConfig.save(signer: signingKey)
                    configStore = ConfigStore(safeModeConfig)
                    configStore.setSigner(signingKey)
                }
            } else {
                // First run — create default config and sign it
                let config = DaemonConfig.defaultConfig()
                try config.save(signer: signingKey)
                configStore = ConfigStore(config)
                configStore.setSigner(signingKey)
                print("[Monolith] Created default config (first run)")
            }
        } catch {
            print("[Monolith] ERROR: Failed to initialize config: \(error)")
            // Fallback: load or create without signing
            let config = (try? DaemonConfig.load()) ?? DaemonConfig.defaultConfig()
            try? config.save()
            configStore = ConfigStore(config)
        }

        if safeMode {
            print("[Monolith] SAFE MODE: frozen=true, default-deny. Companion admin approval required to reset.")
        }

        // ──────────────────────────────────────────────────────────────────────
        // 3. Initialize chain clients, policy engine, services
        // ──────────────────────────────────────────────────────────────────────
        var config = configStore.read()

        guard let chainConfig = ChainConfig.forChain(config.homeChainId) else {
            print("[Monolith] ERROR: Unknown chain ID \(config.homeChainId)")
            return
        }

        let chainClient = ChainClient(rpcURL: chainConfig.rpcURL)
        let bundlerURL = config.customBundlerURL ?? chainConfig.bundlerURL
        let bundlerClient = BundlerClient(bundlerURL: bundlerURL)

        // Probe P-256 precompile at 0x100 and cache result
        if config.precompileAvailable == nil {
            let precompileAvailable = await PrecompileProbe.probe(chainClient: chainClient)
            try? configStore.update { $0.precompileAvailable = precompileAvailable }
            config = configStore.read()
            print("[Monolith] Precompile probe: \(precompileAvailable ? "available" : "not available")")
        }

        // Initialize policy engine with overrides applied
        let baseProfile = SecurityProfile.forName(config.activeProfile) ?? .balanced
        let effectiveProfile = baseProfile.withOverrides(
            perTxStablecoinCap: config.customPerTxStablecoinCap,
            dailyStablecoinCap: config.customDailyStablecoinCap,
            perTxEthCap: config.customPerTxEthCap,
            dailyEthCap: config.customDailyEthCap,
            maxTxPerHour: config.customMaxTxPerHour,
            maxSlippageBps: config.customMaxSlippageBps
        )
        let stablecoinRegistry = StablecoinRegistry()
        let protocolRegistry = ProtocolRegistry(profile: config.activeProfile)
        let persistedAllowlist = Set((config.allowlistedAddresses ?? []).map { $0.lowercased() })
        let policyEngine = PolicyEngine(
            profile: effectiveProfile,
            protocolRegistry: protocolRegistry,
            stablecoinRegistry: stablecoinRegistry,
            allowlistedAddresses: persistedAllowlist,
            frozen: config.frozen,
            chainClient: chainClient,
            chainId: config.homeChainId,
            walletAddress: config.walletAddress
        )

        let userOpBuilder = UserOpBuilder(
            chainClient: chainClient,
            bundlerClient: bundlerClient,
            entryPoint: config.entryPointAddress,
            chainId: config.homeChainId
        )
        let approvalManager = ApprovalManager()
        let auditLogger = AuditLogger()

        let services = ServiceContainer(
            chainClient: chainClient,
            bundlerClient: bundlerClient,
            userOpBuilder: userOpBuilder,
            policyEngine: policyEngine,
            protocolRegistry: protocolRegistry,
            stablecoinRegistry: stablecoinRegistry
        )

        // ──────────────────────────────────────────────────────────────────────
        // 4. Run initial freeze sync BEFORE accepting connections
        // ──────────────────────────────────────────────────────────────────────
        let freezeSyncService = FreezeSyncService(
            services: services,
            configStore: configStore,
            auditLogger: auditLogger
        )
        await freezeSyncService.syncOnce()

        // ──────────────────────────────────────────────────────────────────────
        // 5. Create XPC service + CompanionProxy, start XPC listener
        // ──────────────────────────────────────────────────────────────────────
        let xpcService = DaemonXPCService(approvalManager: approvalManager)
        let companionProxy = xpcService.companionProxy
        xpcService.start()

        // ──────────────────────────────────────────────────────────────────────
        // 6. Set up router — pass companionProxy to handlers that need it
        // ──────────────────────────────────────────────────────────────────────
        let router = RequestRouter()

        // Health — no auth
        router.register("GET", "/health") { req in
            await HealthHandler.handle(request: req)
        }

        // Address
        let addressHandler = AddressHandler(configStore: configStore, seManager: seManager)
        router.register("GET", "/address") { req in
            await addressHandler.handle(request: req)
        }

        // Capabilities
        let capsHandler = CapabilitiesHandler(
            configStore: configStore,
            services: services
        )
        router.register("GET", "/capabilities") { req in
            await capsHandler.handle(request: req)
        }

        // Decode
        let decodeHandler = DecodeHandler(
            configStore: configStore,
            services: services
        )
        router.register("POST", "/decode") { req in
            await decodeHandler.handle(request: req)
        }

        // Sign — uses companionProxy for approval notifications
        let signHandler = SignHandler(
            services: services,
            seManager: seManager,
            approvalManager: approvalManager,
            auditLogger: auditLogger,
            configStore: configStore,
            companionProxy: companionProxy
        )
        router.register("POST", "/sign") { req in
            await signHandler.handle(request: req)
        }

        // Policy — uses companionProxy instead of seManager for admin approval
        let policyHandler = PolicyHandler(
            configStore: configStore,
            services: services,
            companionProxy: companionProxy,
            auditLogger: auditLogger
        )
        router.register("GET", "/policy") { req in
            await policyHandler.handleGet(request: req)
        }
        router.register("POST", "/policy/update") { req in
            await policyHandler.handleUpdate(request: req)
        }

        // Setup
        let setupHandler = SetupHandler(
            seManager: seManager,
            services: services,
            auditLogger: auditLogger,
            configStore: configStore
        )
        router.register("POST", "/setup") { req in
            await setupHandler.handleSetup(request: req)
        }
        router.register("POST", "/setup/deploy") { req in
            await setupHandler.handleDeploy(request: req)
        }

        // Allowlist — uses companionProxy instead of seManager for admin approval
        let allowlistHandler = AllowlistHandler(
            services: services,
            companionProxy: companionProxy,
            auditLogger: auditLogger,
            configStore: configStore
        )
        router.register("POST", "/allowlist") { req in
            await allowlistHandler.handle(request: req)
        }

        // Panic
        let panicHandler = PanicHandler(
            services: services,
            auditLogger: auditLogger,
            seManager: seManager,
            configStore: configStore
        )
        router.register("POST", "/panic") { req in
            await panicHandler.handle(request: req)
        }

        // Unfreeze — uses companionProxy instead of seManager for admin approval
        let unfreezeHandler = UnfreezeHandler(
            services: services,
            companionProxy: companionProxy,
            auditLogger: auditLogger,
            configStore: configStore
        )
        router.register("POST", "/unfreeze") { req in
            await unfreezeHandler.handle(request: req)
        }

        // Audit log
        let auditLogHandler = AuditLogHandler(auditLogger: auditLogger)
        router.register("GET", "/audit-log") { req in
            await auditLogHandler.handle(request: req)
        }

        // ──────────────────────────────────────────────────────────────────────
        // 7. Start socket server + accept loop
        // ──────────────────────────────────────────────────────────────────────
        let server = SocketServer(socketPath: DaemonConfig.socketPath, router: router)
        do {
            try await server.start()
            print("[Monolith] Listening on \(DaemonConfig.socketPath)")
            print(
                "[Monolith] Profile: \(config.activeProfile), Chain: \(config.homeChainId)"
            )

            // ──────────────────────────────────────────────────────────────────
            // 8. Start periodic freeze sync (detached task, every 60s)
            // ──────────────────────────────────────────────────────────────────
            Task.detached {
                await freezeSyncService.startPeriodicSync()
            }

            // Accept connections forever
            await server.acceptLoop()
        } catch {
            print("[Monolith] ERROR: Failed to start server: \(error)")
        }
    }
}
