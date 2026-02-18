import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

describe('13 — Audit Log', () => {
  it('GET /audit-log returns entries from prior tests', async () => {
    const res = await client.auditLog();

    assert.equal(
      res.status,
      200,
      `Audit log failed: ${JSON.stringify(res.data)}`
    );
    assert.ok(Array.isArray(res.data.entries), 'Expected entries array');
    assert.ok(
      res.data.entries.length > 0,
      'Expected at least one audit log entry from prior tests'
    );

    console.log(`    Total entries: ${res.data.entries.length}`);

    // Verify expected actions are present
    const actions = res.data.entries.map((e) => e.action);
    const expectedActions = ['setup', 'deploy'];

    for (const expected of expectedActions) {
      assert.ok(
        actions.includes(expected),
        `Expected action "${expected}" in audit log. Found: ${[...new Set(actions)].join(', ')}`
      );
    }

    // Should have a panic entry from test 12
    assert.ok(
      actions.includes('panic') || actions.includes('freeze'),
      'Expected panic/freeze entry in audit log'
    );

    console.log(`    Actions: ${[...new Set(actions)].join(', ')}`);
  });

  it('audit entries have timestamps', async () => {
    const res = await client.auditLog();
    const entries = res.data.entries;

    for (const entry of entries) {
      assert.ok(entry.timestamp, `Entry missing timestamp: ${JSON.stringify(entry)}`);
    }
  });

  it('audit entries for sign operations include target', async () => {
    const res = await client.auditLog();
    const signEntries = res.data.entries.filter(
      (e) => e.action === 'sign' || e.action === 'deploy'
    );

    for (const entry of signEntries) {
      assert.ok(
        entry.target,
        `Sign/deploy entry missing target: ${JSON.stringify(entry)}`
      );
    }
  });
});
