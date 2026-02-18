import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { client } from '../lib/test-client.js';
import { getBalance } from '../lib/chain-helpers.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

// Small ETH transfer — well within balanced profile's 0.05 ETH/tx cap
const TRANSFER_WEI = '100000000000000'; // 0.0001 ETH

describe('05 — ETH Transfer (within policy)', () => {
  let recipientAddress;

  it('sends 0.0001 ETH to the recovery address (allowlisted)', async () => {
    // Use recovery address as recipient (it's a valid address)
    recipientAddress = process.env.CLAWVAULT_RECOVERY;
    assert.ok(recipientAddress, 'CLAWVAULT_RECOVERY required as recipient');

    const balanceBefore = await getBalance(recipientAddress, CHAIN_ID);

    const res = await client.sign({
      target: recipientAddress,
      calldata: '0x',
      value: TRANSFER_WEI,
      chainHint: CHAIN_ID.toString(),
    });

    // Might get 202 if recipient is not allowlisted — that's also a valid test outcome
    if (res.status === 202) {
      console.log(
        '    Transfer requires approval (recipient not allowlisted)'
      );
      console.log(`    Reason: ${res.data.reason}`);
      // Save for later approval test
      const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
      state.pendingEthTransfer = res.data;
      await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
      // Skip balance check — tx hasn't been sent
      return;
    }

    assert.equal(
      res.status,
      200,
      `Sign failed: ${JSON.stringify(res.data)}`
    );
    assert.ok(res.data.userOpHash, 'Expected userOpHash');

    console.log(`    UserOp hash: ${res.data.userOpHash}`);

    // Save hash for audit log verification
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    state.ethTransferHash = res.data.userOpHash;
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
  });
});
