import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);

describe('12 — Panic / Freeze', () => {
  it('POST /panic freezes the wallet instantly (no Touch ID)', async () => {
    const res = await client.panic();

    assert.equal(
      res.status,
      200,
      `Panic failed: ${JSON.stringify(res.data)}`
    );
    console.log(`    Panic response: ${JSON.stringify(res.data)}`);
  });

  it('GET /capabilities shows frozen=true', async () => {
    const res = await client.capabilities();

    assert.equal(res.status, 200);
    assert.equal(
      res.data.frozen,
      true,
      'Wallet should be frozen after panic'
    );

    console.log(`    frozen: ${res.data.frozen}`);
  });

  it('POST /sign returns 409 when frozen', async () => {
    const res = await client.sign({
      target: process.env.CLAWVAULT_RECOVERY,
      calldata: '0x',
      value: '100000000000000',
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(
      res.status,
      409,
      `Expected 409 Conflict (frozen), got ${res.status}: ${JSON.stringify(res.data)}`
    );

    console.log(`    Sign while frozen: ${res.status} ${res.data?.error || ''}`);
  });

  it('POST /panic is idempotent (already frozen)', async () => {
    const res = await client.panic();

    // Should succeed or already-frozen — not error
    assert.ok(
      res.status === 200 || res.status === 409,
      `Expected 200 or 409, got ${res.status}`
    );
  });
});
