---
name: clawvault
description: Secure crypto wallet for OpenClaw with Secure Enclave signing and policy-gated approvals.
metadata: {"openclaw":{"displayName":"ClawVault","source":"https://github.com/lumenio/ClawVault/tree/main/skill","homepage":"https://github.com/lumenio/ClawVault","requires":{"bins":["ClawVaultDaemon"]},"install":[{"kind":"download","label":"Install ClawVault Daemon (macOS pkg)","url":"https://github.com/lumenio/ClawVault/releases/download/v0.1.0/ClawVaultDaemon.pkg","os":"darwin"},{"kind":"download","label":"Download ClawVault Companion (macOS app zip)","url":"https://github.com/lumenio/ClawVault/releases/download/v0.1.0/ClawVaultCompanion.app.zip","os":"darwin"}]}}
---

# ClawVault — Crypto Wallet Skill

Secure crypto wallet for OpenClaw agents. Hardware-isolated keys (Apple Secure Enclave), on-chain spending caps, ERC-4337 smart wallet.

## Commands

| Command | What it does | Requires daemon? |
|---------|-------------|------------------|
| `send <to> <amount> [token] [chainId]` | Send ETH or USDC | Yes |
| `swap <amountETH> [tokenOut] [chainId]` | Swap ETH for tokens via Uniswap | Yes |
| `balance <address> [chainId]` | Check ETH and stablecoin balances | No (read-only) |
| `capabilities` | Show current limits, budgets, gas status | Yes |
| `decode <target> <calldata> <value>` | Decode a tx intent into human-readable summary | Yes |
| `panic` | Emergency freeze — instant, no Touch ID | Yes |
| `status` | Check daemon health and wallet info | Yes |
| `identity [query\|register]` | ERC-8004 identity operations | Partially |
| `setup` | Run setup wizard, show wallet status and config | Yes |
| `policy` | Show current spending policy | Yes |
| `policy update '<json>'` | Update spending policy (Touch ID required) | Yes |
| `allowlist <add\|remove> <address> [label]` | Add or remove address from allowlist (Touch ID required) | Yes |
| `audit-log` | Show the daemon audit log | Yes |

## Security Model

- **The skill is untrusted.** It only builds intents: `{target, calldata, value}`.
- The skill NEVER sets nonce, gas, chainId, fees, or signatures.
- The signing daemon (local macOS process) enforces all policy.
- Transactions within policy limits execute automatically (autopilot).
- Transactions that exceed limits or use unknown calldata require human approval via 8-digit code.
- Token approvals (`approve`, `permit`, etc.) ALWAYS require explicit approval.

## What requires approval?

- Transfers over per-tx or daily spending caps
- Transfers to non-allowlisted addresses
- Token approvals (approve, permit, setApprovalForAll)
- Unknown calldata (default-deny policy)
- Swaps above slippage limits

## What works on autopilot?

- ETH and USDC transfers within limits to allowlisted addresses
- Swaps on allowlisted DEXes (Uniswap) within slippage limits
- DeFi deposits/withdrawals on allowlisted protocols (Aave)
- Balance checks, status queries, decode requests

## Setup

1. Install ClawVault from ClawHub (macOS install entries provide daemon + companion downloads)
2. Run `clawvault setup` to auto-start daemon/companion and verify wallet status
3. If setup reports missing local components, install `ClawVaultDaemon.pkg` and `ClawVaultCompanion.app` from the release assets
4. Fund the wallet address with ETH on your chosen chain
5. Start transacting

## Error Handling

- If the daemon is not running, all signing commands will fail with a clear error
- If gas is low, the daemon will refuse transactions — fund the wallet with more ETH
- If the wallet is frozen, no outbound transactions are possible until unfrozen (requires Touch ID + 10min delay)
- Rate-limited by Pimlico? The daemon uses exponential backoff automatically

## Approval Flow

When a transaction exceeds policy limits or uses unknown calldata, the daemon
returns HTTP 202 with a reason, summary, and expiration. The agent should:

1. Present the approval reason and summary to the user.
2. Ask the user for the 8-digit approval code (displayed by the daemon's native macOS dialog).
3. Re-call `/sign` with the same intent plus the `approvalCode` field to confirm.

No separate approval script is needed -- the same `send` or `swap` command is
re-invoked with the approval code passed through the daemon.

## Chains

- Ethereum Mainnet (chainId 1)
- Base (chainId 8453)
