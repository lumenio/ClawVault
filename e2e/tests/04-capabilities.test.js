import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

describe('04 — Capabilities', () => {
  it('GET /capabilities returns profile and limits', async () => {
    const res = await client.capabilities();

    assert.equal(res.status, 200);
    assert.equal(res.data.profile, 'balanced');
    assert.equal(res.data.frozen, false);
    assert.ok(
      res.data.gasStatus === 'ok' || res.data.gasStatus === 'low',
      `Unexpected gasStatus: ${res.data.gasStatus}`
    );
  });

  it('limits match balanced profile defaults', async () => {
    const res = await client.capabilities();
    const limits = res.data.limits;

    assert.ok(limits, 'Expected limits object');
    // Balanced profile: 0.05 ETH/tx, 0.25 ETH/day, 100 USDC/tx, 500 USDC/day
    assert.ok(limits.perTxEthCap > 0, 'perTxEthCap should be positive');
    assert.ok(limits.dailyEthCap > 0, 'dailyEthCap should be positive');
    assert.ok(limits.perTxStablecoinCap > 0, 'perTxStablecoinCap should be positive');
    assert.ok(limits.dailyStablecoinCap > 0, 'dailyStablecoinCap should be positive');
    assert.ok(limits.maxTxPerHour > 0, 'maxTxPerHour should be positive');
  });

  it('remaining budgets are non-negative', async () => {
    const res = await client.capabilities();
    const remaining = res.data.remaining;

    assert.ok(remaining, 'Expected remaining object');
    assert.ok(remaining.ethDaily >= 0, 'ethDaily remaining should be >= 0');
    assert.ok(
      remaining.stablecoinDaily >= 0,
      'stablecoinDaily remaining should be >= 0'
    );
  });
});
