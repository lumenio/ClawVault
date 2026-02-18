import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const BASE_USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const RECIPIENT = process.env.CLAWVAULT_RECOVERY;

// ERC-20 transfer(address,uint256) calldata for 5 USDC
function encodeTransfer(to, amount) {
  const toClean = to.replace('0x', '').toLowerCase().padStart(64, '0');
  const amountHex = BigInt(amount).toString(16).padStart(64, '0');
  return '0xa9059cbb' + toClean + amountHex;
}

describe('11 — Decode Intent', () => {
  it('POST /decode returns human-readable summary for ETH transfer', async () => {
    const res = await client.decode({
      target: RECIPIENT,
      calldata: '0x',
      value: '100000000000000', // 0.0001 ETH
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(res.status, 200, `Decode failed: ${JSON.stringify(res.data)}`);
    assert.ok(res.data.summary, 'Expected summary field');
    assert.ok(
      res.data.summary.toLowerCase().includes('eth') ||
        res.data.summary.toLowerCase().includes('transfer'),
      `Summary should mention ETH or transfer: "${res.data.summary}"`
    );

    console.log(`    ETH transfer: ${res.data.summary}`);
  });

  it('POST /decode returns summary for USDC transfer', async () => {
    const calldata = encodeTransfer(RECIPIENT, '5000000'); // 5 USDC

    const res = await client.decode({
      target: BASE_USDC,
      calldata,
      value: '0',
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(res.status, 200, `Decode failed: ${JSON.stringify(res.data)}`);
    assert.ok(res.data.summary, 'Expected summary field');

    console.log(`    USDC transfer: ${res.data.summary}`);
  });

  it('POST /decode handles unknown calldata gracefully', async () => {
    const res = await client.decode({
      target: '0x1234567890abcdef1234567890abcdef12345678',
      calldata: '0xdeadbeef' + '00'.repeat(32),
      value: '0',
      chainHint: CHAIN_ID.toString(),
    });

    assert.equal(res.status, 200, `Decode failed: ${JSON.stringify(res.data)}`);
    assert.ok(res.data.summary, 'Expected summary even for unknown calldata');

    console.log(`    Unknown calldata: ${res.data.summary}`);
  });
});
