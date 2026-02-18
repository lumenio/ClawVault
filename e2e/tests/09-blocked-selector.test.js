import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);

// Base USDC address
const BASE_USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';

// Blocked selectors from CLAUDE.md invariant #6
const BLOCKED_SELECTORS = {
  'approve(address,uint256)': '0x095ea7b3',
  'increaseAllowance(address,uint256)': '0x39509351',
  'setApprovalForAll(address,bool)': '0xa22cb465',
  // EIP-2612 permit
  'permit(address,address,uint256,uint256,uint8,bytes32,bytes32)': '0xd505accf',
};

describe('09 — Blocked Selectors', () => {
  for (const [name, selector] of Object.entries(BLOCKED_SELECTORS)) {
    it(`${name} requires approval (selector: ${selector})`, async () => {
      // Build minimal calldata with the blocked selector + dummy args
      const dummyArgs = '0'.repeat(128); // 2 x 32-byte zero words
      const calldata = selector + dummyArgs;

      const res = await client.sign({
        target: BASE_USDC,
        calldata,
        value: '0',
        chainHint: CHAIN_ID.toString(),
      });

      assert.equal(
        res.status,
        202,
        `Expected 202 for ${name}, got ${res.status}: ${JSON.stringify(res.data)}`
      );
      assert.ok(
        res.data.status === 'approval_required',
        `Expected approval_required for ${name}`
      );
      console.log(`    ${name}: approval_required (${res.data.reason})`);
    });
  }
});
