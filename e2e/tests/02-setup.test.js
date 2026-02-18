import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { writeFile, readFile } from 'node:fs/promises';
import { client } from '../lib/test-client.js';

const FACTORY = process.env.CLAWVAULT_FACTORY;
const RECOVERY = process.env.CLAWVAULT_RECOVERY;
const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);

// Store wallet address for subsequent tests
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

describe('02 — Wallet Setup', () => {
  it('POST /setup configures wallet and returns counterfactual address', async () => {
    assert.ok(FACTORY, 'CLAWVAULT_FACTORY env var required');
    assert.ok(RECOVERY, 'CLAWVAULT_RECOVERY env var required');

    const res = await client.setup({
      chainId: CHAIN_ID,
      profile: 'balanced',
      recoveryAddress: RECOVERY,
      factoryAddress: FACTORY,
    });

    assert.equal(res.status, 200, `Setup failed: ${JSON.stringify(res.data)}`);
    assert.ok(res.data.walletAddress, 'Expected walletAddress');
    assert.ok(
      res.data.walletAddress.startsWith('0x'),
      'walletAddress should be hex'
    );
    assert.equal(res.data.chainId, CHAIN_ID);
    assert.equal(res.data.profile, 'balanced');

    // Persist wallet address for subsequent tests
    const state = { walletAddress: res.data.walletAddress };
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));

    console.log(`    Wallet address: ${res.data.walletAddress}`);
    console.log(`    Precompile: ${res.data.precompileAvailable}`);
  });

  it('GET /address returns the configured wallet', async () => {
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    const res = await client.address();

    assert.equal(res.status, 200);
    assert.equal(
      res.data.walletAddress?.toLowerCase(),
      state.walletAddress.toLowerCase()
    );
  });
});
