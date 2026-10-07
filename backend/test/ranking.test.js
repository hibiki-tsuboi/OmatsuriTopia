import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker, { RULES, weekFor, validateRound } from '../src/index.js';

function environment() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../migrations/0001_ranking.sql', import.meta.url), 'utf8'));
  const prepare = sql => {
    let params = [];
    return {
      bind(...args) { params = args; return this; },
      async first() { return sqlite.prepare(sql).get(...params) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...params) }; },
      async run() { return { meta: sqlite.prepare(sql).run(...params) }; }
    };
  };
  const env = {
    DB: { prepare, async batch(statements) {
      sqlite.exec('BEGIN');
      try { const results = []; for (const s of statements) results.push(await s.run()); sqlite.exec('COMMIT'); return results; }
      catch (e) { sqlite.exec('ROLLBACK'); throw e; }
    } },
    REQUEST_LIMIT: { limit: async () => ({ success: true }) },
    REGISTER_LIMIT: { limit: async () => ({ success: true }) }
  };
  const call = (path, method = 'GET', token = null, body = undefined) => worker.fetch(new Request('https://example.com' + path, {
    method, headers: { ...(token ? { authorization: 'Bearer ' + token } : {}), 'content-type': 'application/json' },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  }), env);
  return { sqlite, env, call };
}
const token = 'a'.repeat(64);
const other = 'b'.repeat(64);
const valid = (points = 50) => ({ rules: RULES, elapsedMs: 10000, shots: Array.from({ length: 10 }, (_, i) => ({ offsetMs: (i + 1) * 1000, points })) });
async function register(call, key = token) { const r = await call('/v1/players', 'POST', key); assert.ok(r.ok); return r.json(); }
async function start(call, key = token) { const r = await call('/v1/rounds', 'POST', key, { rules: RULES }); assert.equal(r.status, 201); return r.json(); }

test('JST week changes exactly at Monday midnight including year boundary', () => {
  assert.equal(weekFor(Date.parse('2026-10-04T14:59:59Z')), '2026-09-28');
  assert.equal(weekFor(Date.parse('2026-10-04T15:00:00Z')), '2026-10-05');
  assert.equal(weekFor(Date.parse('2027-01-01T00:00:00Z')), '2026-12-28');
});

test('score derives from legal shots; malformed, impossible and unfinished games are rejected', () => {
  assert.deepEqual(validateRound(valid()), { score: 500, hits: 10 });
  assert.deepEqual(validateRound({ rules: RULES, elapsedMs: 60000, shots: [] }), { score: 0, hits: 0 });
  for (const body of [
    { ...valid(), rules: 'old' }, { ...valid(), elapsedMs: -1 }, { ...valid(), elapsedMs: 60001 },
    { ...valid(), shots: [] }, { ...valid(), shots: Array(11).fill({ offsetMs: 1, points: 20 }) },
    { ...valid(), shots: Array(10).fill({ offsetMs: 1000, points: 20 }) },
    { ...valid(), shots: valid().shots.map(s => ({ ...s, points: 999 })) },
    { ...valid(), elapsedMs: 9500 }, { ...valid(), elapsedMs: 15000 }
  ]) assert.throws(() => validateRound(body));
});

test('registration is idempotent and requires a strong bearer token', async () => {
  const { call, sqlite } = environment();
  assert.equal((await call('/v1/players', 'POST')).status, 401);
  assert.equal((await call('/v1/players', 'POST', 'weak')).status, 401);
  const a = await register(call); const b = await register(call);
  assert.deepEqual(a, b);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 1);
  assert.ok(!JSON.stringify(a).includes(token));
});

test('completed scores are idempotent, immutable and owned by authenticated player', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, sqlite } = environment();
  await register(call); await register(call, other);
  const round = await start(call);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', other, valid())).status, 404);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid())).status, 400);
  t.mock.timers.tick(10000);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid())).status, 200);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid())).status, 200);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid(100))).status, 409);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM weekly_bests').get().n, 1);
  const ranking = await (await call('/v1/leaderboard', 'GET', token)).json();
  assert.equal(ranking.me.rank, 1); assert.equal(ranking.me.score, 500);
  assert.equal(ranking.entries[0].isMe, true);
  assert.equal('id' in ranking.entries[0], false);
});

test('weekly best never regresses and faster equal scores win; exact ties share rank', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call } = environment();
  await register(call); await register(call, other);
  for (const [key, points, duration] of [[token, 100, 10000], [token, 50, 10000], [token, 100, 9000], [other, 100, 9000]]) {
    const r = await start(call, key); t.mock.timers.tick(10000);
    const body = valid(points); body.elapsedMs = duration;
    body.shots = body.shots.map((s, i) => ({ ...s, offsetMs: (i + 1) * duration / 10 }));
    assert.equal((await call(`/v1/rounds/${r.id}/score`, 'POST', key, body)).status, 200);
  }
  const board = await (await call('/v1/leaderboard', 'GET', token)).json();
  assert.equal(board.me.score, 1000); assert.equal(board.me.elapsedMs, 9000);
  assert.deepEqual(board.entries.map(e => e.rank), [1, 1]);
});

test('expired and superseded rounds reject new scores, accepted retries survive expiry', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call } = environment(); await register(call);
  const a = await start(call);
  assert.equal((await call('/v1/rounds', 'POST', token, { rules: RULES })).status, 429);
  t.mock.timers.tick(5000); const b = await start(call);
  t.mock.timers.tick(10000);
  assert.equal((await call(`/v1/rounds/${a.id}/score`, 'POST', token, valid())).status, 410);
  assert.equal((await call(`/v1/rounds/${b.id}/score`, 'POST', token, valid())).status, 200);
  t.mock.timers.tick(600001);
  assert.equal((await call(`/v1/rounds/${b.id}/score`, 'POST', token, valid())).status, 200);
  const c = await start(call); t.mock.timers.tick(600001);
  assert.equal((await call(`/v1/rounds/${c.id}/score`, 'POST', token, valid())).status, 410);
});

test('Sunday round belongs to start week even when submitted on Monday', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-04T14:59:55Z') });
  const { call, sqlite } = environment(); await register(call); const round = await start(call);
  t.mock.timers.tick(10000);
  assert.equal((await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid())).status, 200);
  assert.equal(sqlite.prepare('SELECT week FROM weekly_bests').get().week, '2026-09-28');
  assert.deepEqual((await (await call('/v1/leaderboard')).json()).entries, []);
});

test('own rank is available below the top 100 and guest views omit ownership', async () => {
  const { call, sqlite } = environment(); const me = await register(call);
  const insertPlayer = sqlite.prepare('INSERT INTO players(id,token_hash,name,created_at) VALUES(?,?,?,?)');
  const insertBest = sqlite.prepare('INSERT INTO weekly_bests VALUES(?,?,?,?,?,?,?)');
  for (let i = 0; i < 105; i++) {
    insertPlayer.run(String(i), String(i), 'player' + i, Date.now());
    insertBest.run(String(i), weekFor(Date.now()), RULES, 1000 + i, 10000, 10, Date.now());
  }
  insertBest.run(me.id, weekFor(Date.now()), RULES, 500, 10000, 10, Date.now());
  const board = await (await call('/v1/leaderboard', 'GET', token)).json();
  assert.equal(board.entries.length, 100); assert.equal(board.me.rank, 106);
  const guest = await (await call('/v1/leaderboard')).json();
  assert.equal(guest.me, null); assert.ok(guest.entries.every(e => !e.isMe));
});

test('deletion removes player, sessions and best scores, but not another player', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, sqlite } = environment(); await register(call); await register(call, other);
  const r = await start(call); t.mock.timers.tick(10000);
  await call(`/v1/rounds/${r.id}/score`, 'POST', token, valid());
  assert.equal((await call('/v1/player', 'DELETE', token)).status, 204);
  for (const table of ['rounds', 'weekly_bests']) assert.equal(sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 1);
  assert.equal((await call('/v1/rounds', 'POST', token, { rules: RULES })).status, 401);
});

test('rate limits, oversized bodies and malformed JSON are handled', async () => {
  const { call, env } = environment(); await register(call);
  assert.equal((await call('/v1/rounds', 'POST', token, { padding: 'x'.repeat(17000) })).status, 413);
  const response = await worker.fetch(new Request('https://example.com/v1/rounds', { method: 'POST',
    headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json' }, body: '{' }), env);
  assert.equal(response.status, 400);
  env.REQUEST_LIMIT.limit = async () => ({ success: false });
  assert.equal((await call('/v1/leaderboard')).status, 429);
});

test('registration throttling preserves retries for an existing identity', async () => {
  const { call, env } = environment();
  const profile = await register(call);
  env.REGISTER_LIMIT.limit = async () => ({ success: false });
  assert.deepEqual(await (await call('/v1/players', 'POST', token)).json(), profile);
  assert.equal((await call('/v1/players', 'POST', other)).status, 429);
});

test('scheduled cleanup respects recent records and removes expired data', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  const profile = await register(call);
  const round = await start(call); t.mock.timers.tick(10000);
  await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid());
  await worker.scheduled({}, env);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM rounds').get().n, 1);
  t.mock.timers.tick(2 * 86400000);
  await worker.scheduled({}, env);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM rounds').get().n, 0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM weekly_bests').get().n, 1);
  t.mock.timers.tick(100 * 86400000);
  await worker.scheduled({}, env);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM weekly_bests').get().n, 0);
  assert.equal(sqlite.prepare('SELECT id FROM players').get().id, profile.id);
  t.mock.timers.tick(365 * 86400000);
  await worker.scheduled({}, env);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 0);
});
