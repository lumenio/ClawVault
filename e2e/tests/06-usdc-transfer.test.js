import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

// Base USDC contract address (identified by chainId + address, not symbol)
const BASE_USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';

// 1 USDC = 1_000_000 (6 decimals) — well within balanced profile's 100 USDC/tx cap
const AMOUNT_RAW = '1000000';

// ERC-20 transfer(address,uint256) selector = 0xa9059cbb
function encodeTransfer(to, amount) {
  const toClean = to.replace('0x', '').toLowerCase().padStart(64, '0');
  const amountHex = BigInt(amount).toString(16).padStart(64, '0');
  return '0xa9059cbb' + toClean + amountHex;
}

describe('06 — USDC Transfer (within policy)', () => {
  it('sends 1 USDC via ERC-20 transfer', async () => {
    const recipientAddress = process.env.CLAWVAULT_RECOVERY;
    assert.ok(recipientAddress, 'CLAWVAULT_RECOVERY required as recipient');

    const calldata = encodeTransfer(recipientAddress, AMOUNT_RAW);

    const res = await client.sign({
      target: BASE_USDC,
      calldata,
      value: '0',
      chainHint: CHAIN_ID.toString(),
    });

    if (res.status === 202) {
      console.log('    USDC transfer requires approval');
      console.log(`    Reason: ${res.data.reason}`);
      const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
      state.pendingUsdcTransfer = res.data;
      await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
      return;
    }

    assert.equal(
      res.status,
      200,
      `Sign failed: ${JSON.stringify(res.data)}`
    );
    assert.ok(res.data.userOpHash, 'Expected userOpHash');

    console.log(`    UserOp hash: ${res.data.userOpHash}`);

    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    state.usdcTransferHash = res.data.userOpHash;
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
  });
});
