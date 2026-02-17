import Foundation
import XCTest

@testable import ClawVaultDaemon

final class UserOpHashTests: XCTestCase {
    func testKeccak256Empty() {
        let hex = SignatureUtils.toHex(Keccak256.hash(Data()))
        XCTAssertEqual(hex, "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    }

    func testKeccak256Hello() {
        let hex = SignatureUtils.toHex(Keccak256.hash("hello".data(using: .utf8)!))
        XCTAssertEqual(hex, "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8")
    }

    func testPadAddress() {
        let padded = UserOpHash.padAddress("0xCAFE")
        XCTAssertEqual(padded.count, 32)
        XCTAssertEqual(padded[30], 0xCA)
        XCTAssertEqual(padded[31], 0xFE)
    }

    func testPadUint256() {
        let padded = UserOpHash.padUint256(UInt64(256))
        XCTAssertEqual(padded.count, 32)
        XCTAssertEqual(padded[30], 0x01)
        XCTAssertEqual(padded[31], 0x00)
    }

    func testComputeHashLength() {
        let hash = UserOpHash.compute(
            sender: "0x1234567890abcdef1234567890abcdef12345678",
            nonce: Data(count: 32), initCode: Data(),
            callData: Data([0xb6, 0x1d, 0x27, 0xf6]),
            accountGasLimits: Data(count: 32), preVerificationGas: Data(count: 32),
            gasFees: Data(count: 32), paymasterAndData: Data(),
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 1
        )
        XCTAssertEqual(hash.count, 32)
    }

    func testDeterministic() {
        let compute = {
            UserOpHash.compute(
                sender: "0xABCD", nonce: Data(count: 32), initCode: Data(),
                callData: Data([0x01]), accountGasLimits: Data(count: 32),
                preVerificationGas: Data(count: 32), gasFees: Data(count: 32),
                paymasterAndData: Data(),
                entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 8453
            )
        }
        XCTAssertEqual(compute(), compute())
    }

    func testDifferentChainId() {
        let h1 = UserOpHash.compute(
            sender: "0xABCD", nonce: Data(count: 32), initCode: Data(),
            callData: Data([0x01]), accountGasLimits: Data(count: 32),
            preVerificationGas: Data(count: 32), gasFees: Data(count: 32),
            paymasterAndData: Data(),
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 1
        )
        let h2 = UserOpHash.compute(
            sender: "0xABCD", nonce: Data(count: 32), initCode: Data(),
            callData: Data([0x01]), accountGasLimits: Data(count: 32),
            preVerificationGas: Data(count: 32), gasFees: Data(count: 32),
            paymasterAndData: Data(),
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 8453
        )
        XCTAssertNotEqual(h1, h2)
    }

    func testDifferentEntryPoint() {
        let h1 = UserOpHash.compute(
            sender: "0xABCD", nonce: Data(count: 32), initCode: Data(),
            callData: Data([0x01]), accountGasLimits: Data(count: 32),
            preVerificationGas: Data(count: 32), gasFees: Data(count: 32),
            paymasterAndData: Data(),
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 1
        )
        let h2 = UserOpHash.compute(
            sender: "0xABCD", nonce: Data(count: 32), initCode: Data(),
            callData: Data([0x01]), accountGasLimits: Data(count: 32),
            preVerificationGas: Data(count: 32), gasFees: Data(count: 32),
            paymasterAndData: Data(),
            entryPoint: "0x000000000000000000000000000000000000DEAD", chainId: 1
        )
        XCTAssertNotEqual(h1, h2)
    }

    // MARK: - EIP-712 Structure Verification

    func testPackedUserOpTypehashIsCorrect() {
        let typeString = "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
        let expected = Keccak256.hash(typeString.data(using: .utf8)!)
        XCTAssertEqual(UserOpHash.packedUserOpTypehash, expected)
    }

    func testEip712DomainTypehashIsCorrect() {
        let typeString = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        let expected = Keccak256.hash(typeString.data(using: .utf8)!)
        XCTAssertEqual(UserOpHash.eip712DomainTypehash, expected)
    }

    func testNameHashIsCorrect() {
        let expected = Keccak256.hash("ERC4337".data(using: .utf8)!)
        XCTAssertEqual(UserOpHash.nameHash, expected)
    }

    func testVersionHashIsCorrect() {
        let expected = Keccak256.hash("1".data(using: .utf8)!)
        XCTAssertEqual(UserOpHash.versionHash, expected)
    }

    func testEip712PrefixPresent() {
        let hash = UserOpHash.compute(
            sender: "0x1234567890abcdef1234567890abcdef12345678",
            nonce: Data(count: 32), initCode: Data(),
            callData: Data([0xb6, 0x1d, 0x27, 0xf6]),
            accountGasLimits: Data(count: 32), preVerificationGas: Data(count: 32),
            gasFees: Data(count: 32), paymasterAndData: Data(),
            entryPoint: "0x0000000071727De22E5E9d8BAf0edAc6f37da032", chainId: 1
        )

        let structHash = Keccak256.hash(
            UserOpHash.packedUserOpTypehash
            + UserOpHash.padAddress("0x1234567890abcdef1234567890abcdef12345678")
            + UserOpHash.padUint256(Data(count: 32))
            + Keccak256.hash(Data())
            + Keccak256.hash(Data([0xb6, 0x1d, 0x27, 0xf6]))
            + UserOpHash.padBytes32(Data(count: 32))
            + UserOpHash.padUint256(Data(count: 32))
            + UserOpHash.padBytes32(Data(count: 32))
            + Keccak256.hash(Data())
        )
        let domainSep = Keccak256.hash(
            UserOpHash.eip712DomainTypehash
            + UserOpHash.nameHash
            + UserOpHash.versionHash
            + UserOpHash.padUint256(UInt64(1))
            + UserOpHash.padAddress("0x0000000071727De22E5E9d8BAf0edAc6f37da032")
        )
        let withoutPrefix = Keccak256.hash(domainSep + structHash)
        XCTAssertNotEqual(hash, withoutPrefix)

        var message = Data([0x19, 0x01])
        message.append(domainSep)
        message.append(structHash)
        let expectedHash = Keccak256.hash(message)
        XCTAssertEqual(hash, expectedHash)
    }
}
