import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { client, prompt } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

describe('08 — Approval Flow (complete over-limit tx)', () => {
  it('re-submits the over-limit tx with approval code', async () => {
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    const pending = state.pendingOverLimit;
    assert.ok(pending, 'No pending over-limit tx — run test 07 first');

    // Get approval code from user (displayed in companion menu bar)
    const code = await prompt('    ** Enter the 8-digit approval code: ');
    assert.ok(code && code.length >= 6, 'Approval code seems too short');

    const res = await client.sign({
      target: pending.target,
      calldata: '0x',
      value: pending.value,
      chainHint: CHAIN_ID.toString(),
      approvalCode: code,
    });

    assert.equal(
      res.status,
      200,
      `Approval sign failed: ${JSON.stringify(res.data)}`
    );
    assert.ok(res.data.userOpHash, 'Expected userOpHash');

    console.log(`    UserOp hash: ${res.data.userOpHash}`);

    state.approvedOverLimitHash = res.data.userOpHash;
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
  });
});
