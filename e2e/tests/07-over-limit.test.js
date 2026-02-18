import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

// 0.06 ETH — exceeds balanced profile's 0.05 ETH/tx cap
const OVER_LIMIT_WEI = '60000000000000000';

describe('07 — Over-Limit Transaction (approval required)', () => {
  it('POST /sign with amount exceeding per-tx cap returns 202', async () => {
    const recipientAddress = process.env.CLAWVAULT_RECOVERY;
    assert.ok(recipientAddress, 'CLAWVAULT_RECOVERY required');

    const res = await client.sign({
      target: recipientAddress,
      calldata: '0x',
      value: OVER_LIMIT_WEI,
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(
      res.status,
      202,
      `Expected 202 approval_required, got ${res.status}: ${JSON.stringify(res.data)}`
    );
    assert.ok(
      res.data.status === 'approval_required',
      `Expected status approval_required, got: ${res.data.status}`
    );
    assert.ok(res.data.reason, 'Expected reason');
    assert.ok(res.data.hashPrefix, 'Expected hashPrefix for approval matching');
    assert.ok(res.data.expiresIn > 0, 'Expected positive expiresIn');

    console.log(`    Reason: ${res.data.reason}`);
    console.log(`    Hash prefix: ${res.data.hashPrefix}`);
    console.log(`    Expires in: ${res.data.expiresIn}s`);

    // Save the pending approval details for test 08
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    state.pendingOverLimit = {
      target: recipientAddress,
      value: OVER_LIMIT_WEI,
      hashPrefix: res.data.hashPrefix,
      expiresIn: res.data.expiresIn,
    };
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));

    console.log('');
    console.log(
      '    ** Read the 8-digit approval code from the ClawVault companion menu bar **'
    );
  });
});
