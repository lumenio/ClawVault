import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const BASE_RPC = 'https://mainnet.base.org';
const ETH_RPC = 'https://cloudflare-eth.com';

/**
 * On-chain verification helpers using Foundry's `cast` CLI.
 * All functions target a specific chain via RPC URL.
 */

function rpcURL(chainId = 8453) {
  return chainId === 1 ? ETH_RPC : BASE_RPC;
}

/**
 * Get native ETH balance in wei.
 * @param {string} address
 * @param {number} chainId
 * @returns {Promise<bigint>}
 */
export async function getBalance(address, chainId = 8453) {
  const { stdout } = await execFileAsync('cast', [
    'balance',
    address,
    '--rpc-url',
    rpcURL(chainId),
  ]);
  return BigInt(stdout.trim());
}

/**
 * Get deployed contract code. Returns '0x' if no code (EOA).
 * @param {string} address
 * @param {number} chainId
 * @returns {Promise<string>}
 */
export async function getCode(address, chainId = 8453) {
  const { stdout } = await execFileAsync('cast', [
    'code',
    address,
    '--rpc-url',
    rpcURL(chainId),
  ]);
  return stdout.trim();
}

/**
 * Call ERC-20 balanceOf.
 * @param {string} token - Token contract address.
 * @param {string} account - Address to check.
 * @param {number} chainId
 * @returns {Promise<bigint>}
 */
export async function callERC20BalanceOf(token, account, chainId = 8453) {
  const { stdout } = await execFileAsync('cast', [
    'call',
    token,
    'balanceOf(address)(uint256)',
    account,
    '--rpc-url',
    rpcURL(chainId),
  ]);
  return BigInt(stdout.trim());
}

/**
 * Wait for a transaction to be mined and return the receipt.
 * Polls `cast receipt` with retries.
 * @param {string} txHash
 * @param {number} chainId
 * @param {number} timeoutMs
 * @returns {Promise<{status: string, blockNumber: string, gasUsed: string}>}
 */
export async function waitForTx(txHash, chainId = 8453, timeoutMs = 120000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const { stdout } = await execFileAsync('cast', [
        'receipt',
        txHash,
        '--json',
        '--rpc-url',
        rpcURL(chainId),
      ]);
      const receipt = JSON.parse(stdout);
      if (receipt.status) {
        return {
          status: receipt.status,
          blockNumber: receipt.blockNumber,
          gasUsed: receipt.gasUsed,
        };
      }
    } catch {
      // Transaction not yet mined — keep polling
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error(`Transaction ${txHash} not mined within ${timeoutMs}ms`);
}

/**
 * Get the current block number.
 * @param {number} chainId
 * @returns {Promise<bigint>}
 */
export async function getBlockNumber(chainId = 8453) {
  const { stdout } = await execFileAsync('cast', [
    'block-number',
    '--rpc-url',
    rpcURL(chainId),
  ]);
  return BigInt(stdout.trim());
}

/**
 * Send ETH from a local account (requires private key in env).
 * Used for funding the test wallet.
 * @param {string} to
 * @param {string} valueEth - e.g., "0.01"
 * @param {number} chainId
 * @returns {Promise<string>} Transaction hash
 */
export async function sendETH(to, valueEth, chainId = 8453) {
  const privateKey = process.env.CLAWVAULT_FUNDER_KEY;
  if (!privateKey) {
    throw new Error(
      'CLAWVAULT_FUNDER_KEY env var required for funding operations'
    );
  }
  const { stdout } = await execFileAsync('cast', [
    'send',
    to,
    '--value',
    `${valueEth}ether`,
    '--private-key',
    privateKey,
    '--rpc-url',
    rpcURL(chainId),
    '--json',
  ]);
  const result = JSON.parse(stdout);
  return result.transactionHash;
}
