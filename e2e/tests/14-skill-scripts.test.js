import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import path from 'node:path';

const execFileAsync = promisify(execFile);
const SKILL_DIR = process.env.CLAWVAULT_SKILL_DIR;

describe('14 — Skill Script Integration', () => {
  it('skill directory exists', () => {
    assert.ok(SKILL_DIR, 'CLAWVAULT_SKILL_DIR env var required');
    assert.ok(existsSync(SKILL_DIR), `Skill dir not found: ${SKILL_DIR}`);
  });

  it('node_modules exist (viem installed)', () => {
    const viemPath = path.join(SKILL_DIR, 'node_modules', 'viem');
    assert.ok(
      existsSync(viemPath),
      'viem not installed. Run: cd skill && npm install'
    );
  });

  it('status.js runs and shows daemon status', async () => {
    // Note: wallet is frozen from test 12, so status may reflect that
    try {
      const { stdout, stderr } = await execFileAsync(
        'node',
        [path.join(SKILL_DIR, 'scripts', 'status.js')],
        {
          env: { ...process.env, CLAWVAULT_SOCKET: process.env.CLAWVAULT_SOCKET },
          timeout: 15000,
        }
      );

      const output = stdout + stderr;
      assert.ok(
        output.includes('Daemon:') || output.includes('ok'),
        `status.js should show daemon status. Output: ${output}`
      );

      console.log(`    status.js output:\n${stdout.trim().split('\n').map(l => '      ' + l).join('\n')}`);
    } catch (err) {
      // status.js may exit(1) if wallet is frozen — that's expected after test 12
      if (err.stdout && err.stdout.includes('Daemon:')) {
        console.log(`    status.js output (non-zero exit): ${err.stdout.trim()}`);
      } else {
        throw err;
      }
    }
  });

  it('balance.js runs with wallet address', async () => {
    // balance.js is read-only (no daemon needed), just verifies the script runs
    const { readFile } = await import('node:fs/promises');
    const STATE_FILE = new URL('../.test-state.json', import.meta.url);

    let walletAddress;
    try {
      const state = JSON.parse(await readFile(STATE_FILE, 'utf-8'));
      walletAddress = state.walletAddress;
    } catch {
      console.log('    Skipping — no wallet address from prior test');
      return;
    }

    assert.ok(walletAddress, 'No wallet address');

    const { stdout } = await execFileAsync(
      'node',
      [path.join(SKILL_DIR, 'scripts', 'balance.js'), walletAddress, '8453'],
      {
        env: { ...process.env },
        timeout: 30000,
      }
    );

    assert.ok(
      stdout.includes('ETH') || stdout.includes('Base'),
      `balance.js should show ETH balance. Output: ${stdout}`
    );

    console.log(`    balance.js output:\n${stdout.trim().split('\n').map(l => '      ' + l).join('\n')}`);
  });
});
