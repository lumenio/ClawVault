import Foundation
import XCTest

@testable import ClawVaultDaemon

final class CalldataDecoderTests: XCTestCase {
    let stableRegistry = StablecoinRegistry()
    let protocolRegistry = ProtocolRegistry(profile: "balanced")

    func testDecodeNativeTransfer() {
        let decoded = CalldataDecoder.decode(
            calldata: Data(), target: "0xCAFE0000000000000000000000000000CAFECAFE",
            value: 50_000_000_000_000_000, chainId: 1,
            stablecoinRegistry: stableRegistry, protocolRegistry: protocolRegistry
        )
        XCTAssertEqual(decoded.action, "Transfer")
        XCTAssertTrue(decoded.summary.contains("ETH"))
        XCTAssertTrue(decoded.isKnown)
    }

    func testDecodeUnknown() {
        let calldata = Data([0xDE, 0xAD, 0xBE, 0xEF]) + Data(count: 32)
        let decoded = CalldataDecoder.decode(
            calldata: calldata, target: "0x1234567890abcdef1234567890abcdef12345678",
            value: 0, chainId: 1,
            stablecoinRegistry: stableRegistry, protocolRegistry: protocolRegistry
        )
        XCTAssertEqual(decoded.action, "Unknown")
        XCTAssertFalse(decoded.isKnown)
        XCTAssertTrue(decoded.summary.contains("deadbeef"))
    }

    func testShortenAddress() {
        XCTAssertEqual(CalldataDecoder.shortenAddress("0x1234567890abcdef1234567890abcdef12345678"), "0x1234…5678")
    }

    func testFormatWei() {
        XCTAssertEqual(CalldataDecoder.formatWei(50_000_000_000_000_000), "0.0500")
    }

    func testFormatUSDC() {
        XCTAssertEqual(CalldataDecoder.formatUSDC(100_000_000), "100.00")
    }
}
