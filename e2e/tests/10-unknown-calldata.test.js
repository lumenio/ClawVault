import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);

describe('10 — Unknown Calldata (default-deny)', () => {
  it('random calldata to unknown contract requires approval', async () => {
    // Some random address and calldata — default-deny should trigger
    const randomTarget = '0x1234567890abcdef1234567890abcdef12345678';
    const randomCalldata = '0xdeadbeef' + '00'.repeat(64);

    const res = await client.sign({
      target: randomTarget,
      calldata: randomCalldata,
      value: '0',
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(
      res.status,
      202,
      `Expected 202 for unknown calldata, got ${res.status}: ${JSON.stringify(res.data)}`
    );
    assert.ok(
      res.data.status === 'approval_required',
      'Default-deny should require approval for unknown calldata'
    );

    console.log(`    Reason: ${res.data.reason}`);
  });

  it('random calldata to known token requires approval', async () => {
    // Unknown selector on USDC contract
    const BASE_USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
    const unknownSelector = '0xffffffff' + '00'.repeat(32);

    const res = await client.sign({
      target: BASE_USDC,
      calldata: unknownSelector,
      value: '0',
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(
      res.status,
      202,
      `Expected 202, got ${res.status}: ${JSON.stringify(res.data)}`
    );
    console.log(`    Reason: ${res.data.reason}`);
  });
});
