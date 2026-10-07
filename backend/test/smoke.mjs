import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout } from 'node:timers/promises';

const base = process.argv[2] || 'http://localhost:8787';
const token = randomBytes(32).toString('hex');
const request = (path, method = 'GET', body = undefined) => fetch(base + path, {
  method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
  ...(body ? { body: JSON.stringify(body) } : {})
});
let registered = false;
try {
  const profile = await request('/v1/players', 'POST');
  assert.ok(profile.ok, `Registration failed: ${profile.status} ${await profile.text()}`);
  registered = true;
  const start = await request('/v1/rounds', 'POST', { rules: 'festival-60-v1' });
  assert.equal(start.status, 201);
  const round = await start.json();
  await setTimeout(5600);
  const body = { rules: 'festival-60-v1', elapsedMs: 5500,
    shots: Array.from({ length: 10 }, (_, i) => ({ offsetMs: 1000 + i * 500, points: 0 })) };
  const submitted = await request(`/v1/rounds/${round.id}/score`, 'POST', body);
  assert.equal(submitted.status, 200, await submitted.text());
  assert.equal((await request(`/v1/rounds/${round.id}/score`, 'POST', body)).status, 200);
  const board = await (await request('/v1/leaderboard')).json();
  assert.equal(board.me.score, 0);
  assert.ok(board.entries.some(row => row.isMe));
  console.log('PASS: registration, session, submission, retry, weekly ranking');
} finally {
  if (registered) {
    const deleted = await request('/v1/player', 'DELETE');
    assert.equal(deleted.status, 204);
    assert.equal((await request('/v1/leaderboard')).status, 401);
    console.log('PASS: deleted the temporary test player and its scores');
  }
}
