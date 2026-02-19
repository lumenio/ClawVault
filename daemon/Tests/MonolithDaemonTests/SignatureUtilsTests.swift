import Foundation
import XCTest

@testable import MonolithDaemon

final class SignatureUtilsTests: XCTestCase {
    func testHexRoundtrip() {
        let original = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let hex = SignatureUtils.toHex(original)
        XCTAssertEqual(hex, "0xdeadbeef")
        XCTAssertEqual(SignatureUtils.fromHex(hex), original)
    }

    func testFromHexPrefix() {
        let a = SignatureUtils.fromHex("0xabcd")
        let b = SignatureUtils.fromHex("abcd")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, Data([0xAB, 0xCD]))
    }

    func testLowSAlreadyNormalized() {
        var sig = Data(count: 64)
        sig[63] = 1; sig[31] = 1
        XCTAssertEqual(SignatureUtils.normalizeSignature(sig), sig)
    }

    func testHighSNormalized() {
        var sig = Data(count: 64)
        sig[31] = 1
        let nDiv2 = SignatureUtils.p256NDiv2
        for i in 0..<32 { sig[32 + i] = nDiv2[i] }
        sig[63] &+= 1
        let normalized = SignatureUtils.normalizeSignature(sig)
        let normalizedS = Array(normalized[32..<64])
        XCTAssertTrue(SignatureUtils.compareUInt256(normalizedS, nDiv2) <= 0)
    }

    func testCompareOrdering() {
        var a = [UInt8](repeating: 0, count: 32)
        var b = [UInt8](repeating: 0, count: 32)
        a[31] = 1; b[31] = 2
        XCTAssertTrue(SignatureUtils.compareUInt256(a, b) < 0)
        a[31] = 2
        XCTAssertEqual(SignatureUtils.compareUInt256(a, b), 0)
        a[31] = 3
        XCTAssertTrue(SignatureUtils.compareUInt256(a, b) > 0)
    }

    func testSubtraction() {
        var a = [UInt8](repeating: 0, count: 32)
        var b = [UInt8](repeating: 0, count: 32)
        a[31] = 10; b[31] = 3
        XCTAssertEqual(SignatureUtils.subtractUInt256(a, b)[31], 7)
    }

    func testNormalizeWrongLength() {
        let short = Data([1, 2, 3])
        XCTAssertEqual(SignatureUtils.normalizeSignature(short), short)
    }
}
