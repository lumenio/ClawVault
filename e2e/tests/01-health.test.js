import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { client } from '../lib/test-client.js';

describe('01 — Health Check', () => {
  it('GET /health returns 200 with status ok', async () => {
    const res = await client.health();
    assert.equal(res.status, 200);
    assert.equal(res.data.status, 'ok');
  });

  it('response includes version string', async () => {
    const res = await client.health();
    assert.ok(res.data.version, 'Expected version field');
  });
});
