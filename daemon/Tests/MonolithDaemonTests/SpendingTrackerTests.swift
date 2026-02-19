import Foundation
import XCTest

@testable import MonolithDaemon

final class SpendingTrackerTests: XCTestCase {
    func testAllowWithinLimits() async throws {
        let tracker = SpendingTracker()
        let result = await tracker.check(ethAmount: 10_000_000_000_000_000, stablecoinAmount: 0, profile: .balanced)
        guard case .allowed = result else { XCTFail("Expected allowed"); return }
    }

    func testDenyOverPerTxCap() async throws {
        let tracker = SpendingTracker()
        let result = await tracker.check(ethAmount: 100_000_000_000_000_000, stablecoinAmount: 0, profile: .balanced)
        guard case .denied(let reason) = result else { XCTFail("Expected denied"); return }
        XCTAssertTrue(reason.contains("per-tx cap"))
    }

    func testDenyOverStablecoinCap() async throws {
        let tracker = SpendingTracker()
        let result = await tracker.check(ethAmount: 0, stablecoinAmount: 200_000_000, profile: .balanced)
        guard case .denied(let reason) = result else { XCTFail("Expected denied"); return }
        XCTAssertTrue(reason.contains("per-tx cap"))
    }

    func testDailyCapAccumulation() async throws {
        let tracker = SpendingTracker()
        // Initialize currentDay via a check so record() accumulation isn't wiped
        _ = await tracker.check(ethAmount: 0, stablecoinAmount: 0, profile: .balanced)
        // Record spending directly to avoid cooldown interference
        for _ in 0..<6 {
            await tracker.record(ethAmount: 40_000_000_000_000_000, stablecoinAmount: 0)
        }
        // 6 × 0.04 = 0.24 ETH recorded; daily cap is 0.25 ETH
        // Next 0.04 would push to 0.28 > 0.25, so should be denied
        let result = await tracker.check(ethAmount: 40_000_000_000_000_000, stablecoinAmount: 0, profile: .balanced)
        guard case .denied(let reason) = result else { XCTFail("Expected denied"); return }
        XCTAssertTrue(reason.contains("Daily ETH cap"))
    }

    func testRemainingBudgets() async throws {
        let tracker = SpendingTracker()
        await tracker.record(ethAmount: 100_000_000_000_000_000, stablecoinAmount: 0)
        let budgets = await tracker.remainingBudgets(profile: .balanced)
        XCTAssertEqual(budgets.ethRemaining, 150_000_000_000_000_000)
    }
}
