import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout } from 'node:timers/promises';

const base = process.argv[2] || 'http://localhost:8787';
const token = randomBytes(32).toString('hex');
const otherToken = randomBytes(32).toString('hex');
const request = (path, method = 'GET', body = undefined, key = token) => fetch(base + path, {
  method, headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
  ...(body ? { body: JSON.stringify(body) } : {})
});
const registered = [];
try {
  const profiles = [];
  for (const key of [token, otherToken]) {
    const response = await request('/v1/players', 'POST', undefined, key);
    assert.equal(response.status, 201);
    registered.push(key);
    profiles.push(await response.json());
  }
  assert.notEqual(profiles[0].name, profiles[1].name);
  assert.notEqual(profiles[0].id, profiles[1].id);
  const repeated = await request('/v1/players', 'POST');
  assert.equal(repeated.status, 200);
  assert.deepEqual(await repeated.json(), profiles[0]);
  let best = 0;
  for (const points of [0, 20, 0]) {
    const start = await request('/v1/rounds', 'POST', { rules: 'festival-60-v1' });
    assert.equal(start.status, 201);
    const round = await start.json();
    await setTimeout(5600);
    const body = { rules: 'festival-60-v1', elapsedMs: 5500,
      shots: Array.from({ length: 10 }, (_, i) => ({ offsetMs: 1000 + i * 500, points: i === 0 ? points : 0 })) };
    const submitted = await request(`/v1/rounds/${round.id}/score`, 'POST', body);
    assert.equal(submitted.status, 200, await submitted.text());
    assert.equal((await request(`/v1/rounds/${round.id}/score`, 'POST', body)).status, 200);
    best = Math.max(best, points);
    for (const path of ['/v1/leaderboard', '/v1/leaderboard/all-time']) {
      const board = await (await request(path)).json();
      assert.ok(board.entries.every(row => row.score > 0));
      if (best > 0) {
        assert.equal(board.me.score, best);
        assert.ok(board.me.rank >= 1);
      } else {
        assert.equal(board.me, null);
        assert.ok(board.entries.every(row => !row.isMe));
      }
    }
  }
  console.log('PASS: unique names, idempotent registration, zero-score exclusion, positive ranking, best preservation, retries');
} finally {
  for (const key of registered) {
    const deleted = await request('/v1/player', 'DELETE', undefined, key);
    assert.equal(deleted.status, 204);
    assert.equal((await request('/v1/leaderboard/all-time', 'GET', undefined, key)).status, 401);
    console.log('PASS: deleted the temporary test player and its scores');
  }
}
