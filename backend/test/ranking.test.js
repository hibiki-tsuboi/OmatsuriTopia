import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import worker, { RULES, weekFor, validateRound } from '../src/index.js';

const migrationsURL = new URL('../migrations/', import.meta.url);
const migrations = readdirSync(migrationsURL).filter(name => name.endsWith('.sql')).sort();
function migrate(sqlite, name) {
  sqlite.exec('BEGIN');
  try {
    sqlite.exec(readFileSync(new URL(name, migrationsURL), 'utf8'));
    sqlite.exec('COMMIT');
  } catch (error) { sqlite.exec('ROLLBACK'); throw error; }
}
function environment({ legacy = false } = {}) {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('PRAGMA foreign_keys = ON');
  for (const name of legacy ? migrations.slice(0, 1) : migrations) migrate(sqlite, name);
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
  const call = (path, method = 'GET', token = null, body = undefined, headers = {}) => worker.fetch(new Request('https://example.com' + path, {
    method, headers: { ...(token ? { authorization: 'Bearer ' + token } : {}), 'content-type': 'application/json', ...headers },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {})
  }), env);
  return { sqlite, env, call };
}
const token = 'a'.repeat(64);
const other = 'b'.repeat(64);
const allTimePath = '/v1/leaderboard/all-time';
const valid = (points = 50) => ({ rules: RULES, elapsedMs: 10000, shots: Array.from({ length: 10 }, (_, i) => ({ offsetMs: (i + 1) * 1000, points })) });
async function register(call, key = token) { const r = await call('/v1/players', 'POST', key); assert.ok(r.ok); return r.json(); }
async function start(call, key = token) { const r = await call('/v1/rounds', 'POST', key, { rules: RULES }); assert.equal(r.status, 201); return r.json(); }

function countingRequestLimit() {
  const counts = new Map();
  return { async limit({ key }) {
    const windowKey = `${Math.floor(Date.now() / 60000)}:${key}`;
    const count = (counts.get(windowKey) ?? 0) + 1;
    counts.set(windowKey, count);
    return { success: count <= 120 };
  } };
}

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

test('duplicate generated names are retried without replacing the existing player', async t => {
  const { call, sqlite } = environment();
  const values = [7, 7, 8];
  t.mock.method(crypto, 'getRandomValues', bytes => { bytes.set([0, 0, values.shift()]); return bytes; });
  const first = await register(call);
  const second = await register(call, other);
  assert.equal(first.name, '金色のきつね0007');
  assert.equal(second.name, '金色のきつね0008');
  assert.notEqual(first.id, second.id);
  assert.equal(values.length, 0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 2);
  assert.deepEqual(await register(call), first);
  assert.deepEqual(await register(call, other), second);
});

test('concurrent registrations with the same name receive distinct names', async t => {
  const { call, sqlite } = environment();
  const values = [42, 42, 43];
  t.mock.method(crypto, 'getRandomValues', bytes => { bytes.set([1, 1, values.shift()]); return bytes; });
  const profiles = await Promise.all([register(call), register(call, other)]);
  assert.equal(new Set(profiles.map(profile => profile.id)).size, 2);
  assert.deepEqual(profiles.map(profile => profile.name).sort(), ['星空のたぬき0042', '星空のたぬき0043']);
  assert.equal(sqlite.prepare('SELECT COUNT(DISTINCT name) AS n FROM players').get().n, 2);
});

test('concurrent registration retries of one identity return the same player', async t => {
  const { call, sqlite } = environment();
  let suffix = 0;
  t.mock.method(crypto, 'getRandomValues', bytes => { bytes.set([0, 0, suffix++]); return bytes; });
  const profiles = await Promise.all(Array.from({ length: 5 }, () => register(call)));
  assert.ok(profiles.every(profile => profile.id === profiles[0].id && profile.name === profiles[0].name));
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 1);
});

test('name collisions stop after bounded retries and a later retry can succeed', async t => {
  const { call, sqlite } = environment();
  const random = t.mock.method(crypto, 'getRandomValues', bytes => { bytes.fill(0); return bytes; });
  const first = await register(call);
  random.mock.resetCalls();
  const failed = await call('/v1/players', 'POST', other);
  assert.equal(failed.status, 503);
  assert.match((await failed.json()).error, /表示名/);
  assert.equal(random.mock.callCount(), 10);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 1);
  random.mock.mockImplementation(bytes => { bytes.set([0, 0, 1]); return bytes; });
  const second = await register(call, other);
  assert.notEqual(second.name, first.name);
  assert.deepEqual(await register(call), first);
});

test('migration resolves legacy duplicates while preserving identities and scores', () => {
  const { sqlite } = environment({ legacy: true });
  const insert = sqlite.prepare('INSERT INTO players(id,token_hash,name,created_at) VALUES(?,?,?,?)');
  insert.run('b', 'token-b', '金色のきつね0001', 2);
  insert.run('a', 'token-a', '金色のきつね0001', 1);
  insert.run('c', 'token-c', '金色のきつね0001', 2);
  insert.run('d', 'token-d', '星空のねこ1234', 1);
  sqlite.prepare('INSERT INTO rounds(id,player_id,rules,week,started_at,expires_at) VALUES(?,?,?,?,?,?)')
    .run('round-b', 'b', RULES, '2026-10-12', 1, 600001);
  sqlite.prepare('UPDATE rounds SET score = 500, elapsed_ms = 10000, hits = 10 WHERE id = ?').run('round-b');
  const rounds = sqlite.prepare('SELECT * FROM rounds').all();
  const bests = sqlite.prepare('SELECT * FROM weekly_bests').all();
  migrate(sqlite, '0002_unique_player_names.sql');
  assert.deepEqual(sqlite.prepare('SELECT id,token_hash,name FROM players ORDER BY id').all().map(row => ({ ...row })), [
    { id: 'a', token_hash: 'token-a', name: '金色のきつね0001' },
    { id: 'b', token_hash: 'token-b', name: '金色のきつね0001-2' },
    { id: 'c', token_hash: 'token-c', name: '金色のきつね0001-3' },
    { id: 'd', token_hash: 'token-d', name: '星空のねこ1234' }
  ]);
  assert.deepEqual(sqlite.prepare('SELECT * FROM rounds').all(), rounds);
  assert.deepEqual(sqlite.prepare('SELECT * FROM weekly_bests').all(), bests);
  assert.deepEqual(sqlite.prepare('PRAGMA foreign_key_check').all(), []);
  assert.throws(() => insert.run('e', 'token-e', '金色のきつね0001', 3), /UNIQUE/);
  assert.throws(() => sqlite.prepare('UPDATE players SET name = ? WHERE id = ?').run('金色のきつね0001', 'd'), /UNIQUE/);
});

test('migration rolls back if a manually edited name occupies a legacy suffix', () => {
  const { sqlite } = environment({ legacy: true });
  const insert = sqlite.prepare('INSERT INTO players(id,token_hash,name,created_at) VALUES(?,?,?,?)');
  insert.run('a', 'token-a', '金色のきつね0001', 1);
  insert.run('b', 'token-b', '金色のきつね0001', 2);
  insert.run('c', 'token-c', '金色のきつね0001-2', 3);
  const before = sqlite.prepare('SELECT * FROM players ORDER BY id').all();
  assert.throws(() => migrate(sqlite, '0002_unique_player_names.sql'), /UNIQUE/);
  assert.deepEqual(sqlite.prepare('SELECT * FROM players ORDER BY id').all(), before);
  assert.equal(sqlite.prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE name = 'players_name_unique'").get().n, 0);
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
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM all_time_bests').get().n, 1);
  for (const path of ['/v1/leaderboard', allTimePath]) {
    const ranking = await (await call(path, 'GET', token)).json();
    assert.equal(ranking.me.rank, 1); assert.equal(ranking.me.score, 500);
    assert.equal(ranking.entries[0].isMe, true);
    assert.equal('id' in ranking.entries[0], false);
  }
});

test('weekly and all-time bests never regress and faster equal scores win; exact ties share rank', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call } = environment();
  await register(call); await register(call, other);
  for (const [key, points, duration] of [[token, 100, 10000], [token, 50, 10000], [token, 100, 9000], [other, 100, 9000]]) {
    const r = await start(call, key); t.mock.timers.tick(10000);
    const body = valid(points); body.elapsedMs = duration;
    body.shots = body.shots.map((s, i) => ({ ...s, offsetMs: (i + 1) * duration / 10 }));
    assert.equal((await call(`/v1/rounds/${r.id}/score`, 'POST', key, body)).status, 200);
  }
  for (const path of ['/v1/leaderboard', allTimePath]) {
    const board = await (await call(path, 'GET', token)).json();
    assert.equal(board.me.score, 1000); assert.equal(board.me.elapsedMs, 9000);
    assert.deepEqual(board.entries.map(e => e.rank), [1, 1]);
  }
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
  assert.equal((await (await call(allTimePath)).json()).entries[0].score, 500);
});

test('own rank is available below the top 100 and guest views omit ownership', async () => {
  const { call, sqlite } = environment(); const me = await register(call);
  const insertPlayer = sqlite.prepare('INSERT INTO players(id,token_hash,name,created_at) VALUES(?,?,?,?)');
  const insertBest = sqlite.prepare('INSERT INTO weekly_bests VALUES(?,?,?,?,?,?,?)');
  const insertAllTimeBest = sqlite.prepare('INSERT INTO all_time_bests VALUES(?,?,?,?,?,?)');
  for (let i = 0; i < 105; i++) {
    insertPlayer.run(String(i), String(i), 'player' + i, Date.now());
    insertBest.run(String(i), weekFor(Date.now()), RULES, 1000 + i, 10000, 10, Date.now());
    insertAllTimeBest.run(String(i), RULES, 1000 + i, 10000, 10, Date.now());
  }
  insertBest.run(me.id, weekFor(Date.now()), RULES, 500, 10000, 10, Date.now());
  insertAllTimeBest.run(me.id, RULES, 500, 10000, 10, Date.now());
  for (const path of ['/v1/leaderboard', allTimePath]) {
    const board = await (await call(path, 'GET', token)).json();
    assert.equal(board.entries.length, 100); assert.equal(board.me.rank, 106);
    const guest = await (await call(path)).json();
    assert.equal(guest.me, null); assert.ok(guest.entries.every(e => !e.isMe));
  }
});

test('deletion removes player, sessions and best scores, but not another player', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, sqlite } = environment(); await register(call); await register(call, other);
  const r = await start(call); t.mock.timers.tick(10000);
  await call(`/v1/rounds/${r.id}/score`, 'POST', token, valid());
  assert.equal((await call('/v1/player', 'DELETE', token)).status, 204);
  for (const table of ['rounds', 'weekly_bests', 'all_time_bests']) assert.equal(sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
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
  assert.equal((await call(allTimePath)).status, 429);
});

test('registration throttling preserves retries for an existing identity', async () => {
  const { call, env } = environment();
  const profile = await register(call);
  env.REGISTER_LIMIT.limit = async () => ({ success: false });
  assert.deepEqual(await (await call('/v1/players', 'POST', token)).json(), profile);
  assert.equal((await call('/v1/players', 'POST', other)).status, 429);
});

test('IP quota stops rotating unknown tokens before any database route', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  t.after(() => sqlite.close());
  env.REQUEST_LIMIT = countingRequestLimit();
  const prepare = t.mock.method(env.DB, 'prepare');
  const headers = { 'cf-connecting-ip': '192.0.2.1' };
  for (let i = 0; i < 120; i++) {
    const unknown = i.toString(16).padStart(64, '0');
    assert.equal((await call('/v1/rounds', 'POST', unknown, { rules: RULES }, headers)).status, 401);
  }
  const queries = prepare.mock.callCount();
  assert.equal(queries, 120);
  const routes = [
    ['/v1/players', 'POST'], ['/v1/rounds', 'POST'],
    ['/v1/rounds/00000000-0000-0000-0000-000000000000/score', 'POST'],
    ['/v1/player', 'DELETE'], ['/v1/leaderboard', 'GET'], [allTimePath, 'GET'], ['/unknown', 'GET']
  ];
  for (const [path, method] of routes) {
    for (const key of [other, 'malformed', null]) {
      const response = await call(path, method, key, undefined, headers);
      assert.equal(response.status, 429, `${method} ${path}`);
    }
  }
  assert.equal(prepare.mock.callCount(), queries, 'blocked requests must not query D1');
  assert.equal((await call('/health', 'GET', null, undefined, headers)).status, 200);
  assert.equal(prepare.mock.callCount(), queries);
  assert.equal((await call('/v1/rounds', 'POST', other, undefined,
    { 'cf-connecting-ip': '192.0.2.2' })).status, 401, 'another source IP has its own quota');
  t.mock.timers.tick(60000);
  assert.equal((await call('/v1/leaderboard', 'GET', null, undefined, headers)).status, 200);
});

test('missing source IP uses one fallback quota despite spoofed forwarding headers', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  t.after(() => sqlite.close());
  env.REQUEST_LIMIT = countingRequestLimit();
  for (let i = 0; i < 120; i++) {
    assert.equal((await call('/v1/rounds', 'POST', i.toString(16).padStart(64, '0'), undefined,
      { 'x-forwarded-for': `192.0.2.${i}`, 'x-real-ip': `192.0.2.${i}` })).status, 401);
  }
  const prepare = t.mock.method(env.DB, 'prepare');
  for (const headers of [{}, { 'cf-connecting-ip': '' },
    { 'x-forwarded-for': '198.51.100.1', 'x-real-ip': '198.51.100.1', authorization: 'Basic anything' }]) {
    assert.equal((await call(allTimePath, 'GET', other, undefined, headers)).status, 429);
  }
  assert.equal(prepare.mock.callCount(), 0);
});

test('token quota still applies when a registered player changes source IP', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  t.after(() => sqlite.close());
  await register(call);
  env.REQUEST_LIMIT = countingRequestLimit();
  for (let i = 0; i < 120; i++) {
    assert.equal((await call(allTimePath, 'GET', token, undefined,
      { 'cf-connecting-ip': `192.0.2.${i}` })).status, 200);
  }
  const prepare = t.mock.method(env.DB, 'prepare');
  assert.equal((await call(allTimePath, 'GET', token, undefined,
    { 'cf-connecting-ip': '198.51.100.1' })).status, 429);
  assert.equal(prepare.mock.callCount(), 0);
});

test('IP and token quotas preserve shared-IP registration, score retries and deletion', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  t.after(() => sqlite.close());
  env.REQUEST_LIMIT = countingRequestLimit();
  const shared = (path, method, key, body) => call(path, method, key, body, { 'cf-connecting-ip': '192.0.2.1' });
  const profile = await register(shared);
  await register(shared, other);
  env.REGISTER_LIMIT.limit = async () => ({ success: false });
  assert.deepEqual(await register(shared), profile, 'existing registration is still idempotent');
  const round = await start(shared);
  t.mock.timers.tick(10000);
  const path = `/v1/rounds/${round.id}/score`;
  assert.equal((await shared(path, 'POST', token, valid())).status, 200);
  assert.equal((await shared(path, 'POST', token, valid())).status, 200);
  assert.equal((await shared(allTimePath, 'GET', null)).status, 200);
  assert.equal((await shared('/v1/player', 'DELETE', token)).status, 204);
  assert.equal((await shared(allTimePath, 'GET', other)).status, 200);
});

test('scheduled cleanup expires rounds, weekly bests and scoreless players but retains all-time records', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-07T00:00:00Z') });
  const { call, env, sqlite } = environment();
  const profile = await register(call);
  await register(call, other);
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
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM all_time_bests').get().n, 1);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 2);
  t.mock.timers.tick(365 * 86400000);
  await worker.scheduled({}, env);
  assert.deepEqual(sqlite.prepare('SELECT id FROM players').all().map(row => row.id), [profile.id]);
  const board = await (await call(allTimePath, 'GET', token)).json();
  assert.equal(board.me.score, 500);
  assert.equal(board.entries.length, 1);
});

test('all-time migration selects one complete best record per player and rules and preserves pending rounds', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-13T00:00:00Z') });
  const { call, sqlite } = environment({ legacy: true });
  migrate(sqlite, '0002_unique_player_names.sql');
  const player = await register(call);
  const second = await register(call, other);
  const insert = sqlite.prepare('INSERT INTO weekly_bests VALUES(?,?,?,?,?,?,?)');
  insert.run(player.id, '2026-08-31', RULES, 1000, 10000, 8, 1);
  insert.run(player.id, '2026-09-07', RULES, 1000, 9000, 9, 2);
  insert.run(player.id, '2026-09-14', RULES, 1000, 9000, 10, 3);
  insert.run(player.id, '2026-09-21', RULES, 500, 5000, 5, 4);
  insert.run(player.id, '2026-09-28', 'another-rules-version', 5000, 6000, 10, 5);
  insert.run(second.id, '2026-09-28', RULES, 0, 60000, 0, 5);
  const pending = await start(call);
  const before = sqlite.prepare('SELECT * FROM weekly_bests ORDER BY player_id, week').all();
  const roundsBefore = sqlite.prepare('SELECT * FROM rounds').all();
  migrate(sqlite, '0003_all_time_ranking.sql');
  assert.deepEqual(sqlite.prepare('SELECT * FROM weekly_bests ORDER BY player_id, week').all(), before);
  assert.deepEqual(sqlite.prepare('SELECT * FROM rounds').all(), roundsBefore);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM all_time_bests').get().n, 3);
  assert.deepEqual({ ...sqlite.prepare('SELECT * FROM all_time_bests WHERE player_id = ? AND rules = ?').get(player.id, RULES) },
    { player_id: player.id, rules: RULES, score: 1000, elapsed_ms: 9000, hits: 9, achieved_at: 2 });
  const migrated = await (await call(allTimePath, 'GET', token)).json();
  assert.equal(migrated.me.score, 1000);
  assert.equal(migrated.entries.length, 2);
  assert.deepEqual(migrated.entries.map(row => row.rank), [1, 2]);
  t.mock.timers.tick(10000);
  assert.equal((await call(`/v1/rounds/${pending.id}/score`, 'POST', token, valid(200))).status, 200);
  assert.equal((await (await call(allTimePath, 'GET', token)).json()).me.score, 2000);
  assert.deepEqual(sqlite.prepare('PRAGMA foreign_key_check').all(), []);
});

test('all-time best survives new weeks, months and years and only a better result replaces it', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-04T14:59:50Z') });
  const { call, sqlite } = environment();
  await register(call);
  const first = await start(call);
  t.mock.timers.tick(10000);
  await call(`/v1/rounds/${first.id}/score`, 'POST', token, valid(100));
  for (const date of ['2026-10-12T00:00:00Z', '2026-11-01T00:00:00Z', '2027-01-01T00:00:00Z']) {
    t.mock.timers.setTime(Date.parse(date));
    const round = await start(call);
    t.mock.timers.tick(10000);
    await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid(50));
    const board = await (await call(allTimePath, 'GET', token)).json();
    assert.equal(board.me.score, 1000);
    assert.equal(board.entries.length, 1);
    assert.equal('week' in board, false);
  }
  const improved = await start(call);
  t.mock.timers.tick(10000);
  await call(`/v1/rounds/${improved.id}/score`, 'POST', token, valid(200));
  assert.equal((await (await call(allTimePath, 'GET', token)).json()).me.score, 2000);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM all_time_bests').get().n, 1);
});

test('all-time ranking handles empty boards, invalid identities, rule isolation and tied ranks', async () => {
  const { call, sqlite } = environment();
  assert.deepEqual(await (await call(allTimePath)).json(), { rules: RULES, entries: [], me: null });
  assert.equal((await call(allTimePath, 'GET', token)).status, 401);
  const player = await register(call);
  assert.equal((await (await call(allTimePath, 'GET', token)).json()).me, null);
  const second = await register(call, other);
  const third = await register(call, 'c'.repeat(64));
  const insert = sqlite.prepare('INSERT INTO all_time_bests VALUES(?,?,?,?,?,?)');
  insert.run(player.id, 'another-rules-version', 5000, 5000, 10, 1);
  assert.deepEqual(await (await call(allTimePath, 'GET', token)).json(), { rules: RULES, entries: [], me: null });
  insert.run(player.id, RULES, 500, 10000, 10, 2);
  insert.run(second.id, RULES, 1000, 10000, 10, 3);
  insert.run(third.id, RULES, 1000, 10000, 10, 4);
  const board = await (await call(allTimePath, 'GET', token)).json();
  assert.deepEqual(board.entries.map(row => row.rank), [1, 1, 3]);
  assert.equal(board.me.rank, 3);
  assert.equal(board.entries.filter(row => row.isMe).length, 1);
  assert.equal(board.entries[0].name, second.name);
});

test('zero-point all-time records survive inactivity until the player explicitly deletes them', async t => {
  t.mock.timers.enable({ apis: ['Date'], now: Date.parse('2026-10-13T00:00:00Z') });
  const { call, sqlite, env } = environment();
  await register(call);
  const round = await start(call);
  t.mock.timers.tick(10000);
  await call(`/v1/rounds/${round.id}/score`, 'POST', token, valid(0));
  t.mock.timers.tick(400 * 86400000);
  await worker.scheduled({}, env);
  assert.equal((await (await call(allTimePath, 'GET', token)).json()).me.score, 0);
  assert.equal((await call('/v1/player', 'DELETE', token)).status, 204);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM all_time_bests').get().n, 0);
  assert.equal(sqlite.prepare('SELECT COUNT(*) AS n FROM players').get().n, 0);
  assert.equal((await call(allTimePath, 'GET', token)).status, 401);
});
