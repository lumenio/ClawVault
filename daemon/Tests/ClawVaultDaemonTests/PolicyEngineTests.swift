import Foundation
import XCTest

@testable import ClawVaultDaemon

final class PolicyEngineTests: XCTestCase {
    func makeEngine(profile: String = "balanced", frozen: Bool = false) -> PolicyEngine {
        PolicyEngine(
            profile: SecurityProfile.forName(profile) ?? .balanced,
            protocolRegistry: ProtocolRegistry(profile: "balanced"),
            stablecoinRegistry: StablecoinRegistry(),
            frozen: frozen
        )
    }

    func testFrozenDeniesAll() async throws {
        let engine = makeEngine(frozen: true)
        let decision = await engine.evaluate(target: "0xCAFE", calldata: Data(), value: 1000, chainId: 8453)
        guard case .deny(let reason) = decision else { XCTFail("Expected deny"); return }
        XCTAssertTrue(reason.contains("frozen"))
    }

    func testBlockedSelectorRequiresApproval() async throws {
        let engine = makeEngine()
        let calldata = Data([0x09, 0x5e, 0xa7, 0xb3]) + Data(count: 64)
        let decision = await engine.evaluate(target: "0xA0b86991", calldata: calldata, value: 0, chainId: 1)
        guard case .requireApproval(let reason) = decision else { XCTFail("Expected requireApproval"); return }
        XCTAssertTrue(reason.contains("Blocked selector"))
    }

    func testUnknownCalldataRequiresApproval() async throws {
        let engine = makeEngine()
        let calldata = Data([0xDE, 0xAD, 0xBE, 0xEF]) + Data(count: 32)
        let decision = await engine.evaluate(target: "0x1234", calldata: calldata, value: 0, chainId: 8453)
        guard case .requireApproval(let reason) = decision else { XCTFail("Expected requireApproval"); return }
        XCTAssertTrue(reason.contains("Unknown"))
    }

    func testFreezeUnfreeze() async throws {
        let engine = makeEngine()
        await engine.freeze()
        let frozen = await engine.isFrozen
        XCTAssertTrue(frozen)
        await engine.unfreeze()
        let unfrozen = await engine.isFrozen
        XCTAssertFalse(unfrozen)
    }
}
