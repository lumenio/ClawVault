import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { client, prompt, waitFor } from '../lib/test-client.js';
import { getBalance, getCode, sendETH } from '../lib/chain-helpers.js';

const CHAIN_ID = parseInt(process.env.CLAWVAULT_CHAIN_ID || '8453', 10);
const STATE_FILE = new URL('../.test-state.json', import.meta.url);

describe('03 — Fund & Deploy Wallet', () => {
  let walletAddress;

  it('loads wallet address from prior test', async () => {
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    walletAddress = state.walletAddress;
    assert.ok(walletAddress, 'walletAddress should be set by test 02');
  });

  it('wallet is funded (manual or automated)', async () => {
    // Try automated funding first via CLAWVAULT_FUNDER_KEY
    if (process.env.CLAWVAULT_FUNDER_KEY) {
      console.log('    Funding wallet via CLAWVAULT_FUNDER_KEY...');
      const txHash = await sendETH(walletAddress, '0.01', CHAIN_ID);
      console.log(`    Funded: ${txHash}`);
    } else {
      // Interactive: prompt user to fund
      console.log('');
      console.log(
        `    ** Please fund ${walletAddress} with ≥0.01 ETH + 5 USDC on Base **`
      );
      await prompt('    ** Press Enter when funded ** ');
    }

    // Verify balance
    const balance = await waitFor(
      async () => {
        const bal = await getBalance(walletAddress, CHAIN_ID);
        return bal >= 5_000_000_000_000_000n ? bal : null; // ≥0.005 ETH
      },
      60000,
      3000
    );
    assert.ok(balance >= 5_000_000_000_000_000n, 'Wallet needs ≥0.005 ETH');
    console.log(`    Balance: ${Number(balance) / 1e18} ETH`);
  });

  it('POST /setup/deploy deploys wallet on-chain', async () => {
    const res = await client.deploy();

    assert.equal(
      res.status,
      200,
      `Deploy failed: ${JSON.stringify(res.data)}`
    );
    assert.ok(res.data.userOpHash, 'Expected userOpHash');
    assert.equal(res.data.walletAddress?.toLowerCase(), walletAddress.toLowerCase());

    console.log(`    UserOp hash: ${res.data.userOpHash}`);

    // Persist deploy hash
    const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
    state.deployHash = res.data.userOpHash;
    await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
  });

  it('wallet has code on-chain (deployed)', async () => {
    // Wait for deployment to propagate
    const code = await waitFor(
      async () => {
        const c = await getCode(walletAddress, CHAIN_ID);
        return c && c !== '0x' && c.length > 2 ? c : null;
      },
      120000,
      5000
    );
    assert.ok(code && code !== '0x', 'Wallet should have code after deployment');
    console.log(`    Contract code: ${code.substring(0, 20)}... (${(code.length - 2) / 2} bytes)`);
  });
});
