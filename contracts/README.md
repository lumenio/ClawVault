# Monolith Contracts

ERC-4337 smart wallet with P-256 signature verification, on-chain spending caps, and recovery module.

## Contracts

| Contract | Description |
|---|---|
| `MonolithWallet.sol` | Core wallet. Single P-256 owner, `validateUserOp` with precompile/fallback sig verification, daily spending caps, freeze/recovery. |
| `MonolithFactory.sol` | CREATE2 deterministic deployment. ERC-4337 `initCode` compatible. |
| `P256Verifier.sol` | Wrapper that tries the precompile at `0x100` first (EIP-7951 / RIP-7212), falls back to Daimo's `P256Verifier`. |

## Build

```bash
forge build
```

## Test

```bash
forge test          # 48 tests
forge test -vvv     # verbose
forge test --match-test test_SpendingCap  # run specific tests
```

## Dependencies

Installed via `forge install`:

- `eth-infinitism/account-abstraction` -- ERC-4337 v0.7 EntryPoint interfaces
- `daimo-eth/p256-verifier` -- P-256 signature verification fallback
- `OpenZeppelin/openzeppelin-contracts` -- Utilities
- `foundry-rs/forge-std` -- Test framework

## Key Design Decisions

- **Raw r||s signatures** (64 bytes) -- no DER encoding
- **Low-S enforced on-chain** -- rejects signatures where `s > n/2`
- **No paymasters** -- `paymasterAndData` must always be empty
- **Spending caps track both `transfer()` and `transferFrom()`** -- prevents bypass via transferFrom
- **Stablecoins by (chainId, address)** -- never by symbol string
- **Recovery auto-freezes** -- key rotation triggers immediate freeze + 48h timelock
