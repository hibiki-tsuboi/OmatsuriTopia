export const RULES = 'festival-60-v1';
const DURATION = 60_000;
const VALID_POINTS = new Set([0, 20, 50, 100, 200, 300, 350, 400, 500]);
const DAY = 86_400_000;

class APIError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function requireValue(value, message = '記録の内容を確認できませんでした。') {
  if (!value) throw new APIError(400, message);
}
const json = (value, status = 200) => Response.json(value, {
  status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }
});
export async function hash(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
}
export function weekFor(now) {
  const jst = new Date(now + 9 * 3_600_000);
  jst.setUTCDate(jst.getUTCDate() - (jst.getUTCDay() + 6) % 7);
  return jst.toISOString().slice(0, 10);
}
async function readJSON(request) {
  requireValue(request.headers.get('content-type')?.split(';')[0] === 'application/json');
  const reader = request.body?.getReader();
  requireValue(reader);
  let length = 0;
  const chunks = [];
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > 16_384) { await reader.cancel(); throw new APIError(413, '送信データが大きすぎます。'); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const body = JSON.parse(new TextDecoder().decode(bytes));
    requireValue(body && typeof body === 'object' && !Array.isArray(body));
    return body;
  } catch { throw new APIError(400, '送信データの形式が正しくありません。'); }
}
function tokenFor(request) {
  const token = request.headers.get('authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
  if (!token) throw new APIError(401, 'ランキングへの参加登録が必要です。');
  return token;
}
async function playerFor(request, env) {
  const tokenHash = await hash(tokenFor(request));
  const player = await env.DB.prepare('SELECT id, name FROM players WHERE token_hash = ?').bind(tokenHash).first();
  if (!player) throw new APIError(401, '参加情報が見つかりません。もう一度参加してください。');
  return player;
}
export function validateRound(body) {
  requireValue(body.rules === RULES, 'アプリを最新版に更新してください。');
  requireValue(Number.isInteger(body.elapsedMs) && body.elapsedMs >= 0 && body.elapsedMs <= DURATION);
  requireValue(Array.isArray(body.shots) && body.shots.length <= 10);
  requireValue(body.shots.length === 10 || body.elapsedMs === DURATION);
  let previous = -400;
  let score = 0;
  let hits = 0;
  for (const shot of body.shots) {
    requireValue(shot && Number.isInteger(shot.offsetMs) && shot.offsetMs >= 0 &&
      shot.offsetMs < DURATION && shot.offsetMs <= body.elapsedMs && shot.offsetMs - previous >= 400);
    requireValue(VALID_POINTS.has(shot.points));
    score += shot.points;
    hits += shot.points > 0 ? 1 : 0;
    previous = shot.offsetMs;
  }
  if (body.shots.length === 10) requireValue(body.elapsedMs - previous <= 1000);
  return { score, hits };
}
async function register(request, env, now) {
  const tokenHash = await hash(tokenFor(request));
  const existing = await env.DB.prepare('SELECT id, name FROM players WHERE token_hash = ?').bind(tokenHash).first();
  if (existing) return json(existing);
  const { success } = await env.REGISTER_LIMIT.limit({ key: request.headers.get('cf-connecting-ip') || 'local' });
  if (!success) throw new APIError(429, '少し時間をおいてから参加してください。');
  const id = crypto.randomUUID();
  const adjectives = ['金色の', '星空の', 'お祭りの', '元気な', '夕焼けの', '虹色の'];
  const animals = ['きつね', 'たぬき', 'うさぎ', 'ねこ', 'パンダ', 'ペンギン'];
  const bytes = crypto.getRandomValues(new Uint32Array(3));
  const name = adjectives[bytes[0] % adjectives.length] + animals[bytes[1] % animals.length] + (bytes[2] % 10000).toString().padStart(4, '0');
  await env.DB.prepare('INSERT INTO players(id, token_hash, name, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(token_hash) DO NOTHING')
    .bind(id, tokenHash, name, now).run();
  return json(await env.DB.prepare('SELECT id, name FROM players WHERE token_hash = ?').bind(tokenHash).first(), 201);
}
async function startRound(request, env, player, now) {
  const body = await readJSON(request);
  requireValue(body.rules === RULES, 'アプリを最新版に更新してください。');
  const result = await env.DB.prepare('UPDATE players SET last_started_at = ? WHERE id = ? AND last_started_at <= ? RETURNING id')
    .bind(now, player.id, now - 5000).first();
  if (!result) throw new APIError(429, '次の挑戦まで少しお待ちください。');
  const id = crypto.randomUUID();
  const expiresAt = now + 10 * 60_000;
  const week = weekFor(now);
  await env.DB.batch([
    env.DB.prepare('UPDATE rounds SET expires_at = ? WHERE player_id = ? AND score IS NULL AND expires_at > ?').bind(now, player.id, now),
    env.DB.prepare('INSERT INTO rounds(id, player_id, rules, week, started_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)')
      .bind(id, player.id, RULES, week, now, expiresAt)
  ]);
  return json({ id, week, rules: RULES, expiresAt }, 201);
}
async function submit(request, env, player, id, now) {
  const body = await readJSON(request);
  const { score, hits } = validateRound(body);
  const submissionHash = await hash(JSON.stringify({ rules: body.rules, elapsedMs: body.elapsedMs,
    shots: body.shots.map(s => ({ offsetMs: s.offsetMs, points: s.points })) }));
  const round = await env.DB.prepare('SELECT * FROM rounds WHERE id = ? AND player_id = ?').bind(id, player.id).first();
  if (!round) throw new APIError(404, 'この挑戦は見つかりません。');
  if (round.submission_hash) {
    if (round.submission_hash !== submissionHash) throw new APIError(409, 'この挑戦は登録済みです。');
    return json({ accepted: true, week: round.week, score: round.score });
  }
  if (round.expires_at <= now) throw new APIError(410, '記録の送信期限が過ぎました。自己ベストは端末に残ります。');
  requireValue(now - round.started_at + 1000 >= body.elapsedMs);
  await env.DB.prepare('UPDATE rounds SET score = ?, elapsed_ms = ?, hits = ?, submission_hash = ? WHERE id = ? AND player_id = ? AND score IS NULL AND expires_at > ?')
    .bind(score, body.elapsedMs, hits, submissionHash, id, player.id, now).run();
  const saved = await env.DB.prepare('SELECT submission_hash FROM rounds WHERE id = ? AND player_id = ?').bind(id, player.id).first();
  if (saved?.submission_hash !== submissionHash) throw new APIError(409, 'この挑戦は登録済みか、終了しています。');
  return json({ accepted: true, week: round.week, score });
}
async function leaderboard(request, env, now) {
  const week = weekFor(now);
  const player = request.headers.has('authorization') ? await playerFor(request, env) : null;
  const rows = await env.DB.prepare(`SELECT p.id, p.name, b.score, b.elapsed_ms AS elapsedMs,
    RANK() OVER (ORDER BY b.score DESC, b.elapsed_ms ASC) AS rank
    FROM weekly_bests b JOIN players p ON p.id = b.player_id
    WHERE b.week = ? AND b.rules = ? ORDER BY b.score DESC, b.elapsed_ms ASC, b.achieved_at ASC, p.id ASC LIMIT 100`)
    .bind(week, RULES).all();
  let me = null;
  if (player) {
    me = await env.DB.prepare(`SELECT p.name, b.score, b.elapsed_ms AS elapsedMs,
      1 + (SELECT COUNT(*) FROM weekly_bests other WHERE other.week = b.week AND other.rules = b.rules
        AND (other.score > b.score OR (other.score = b.score AND other.elapsed_ms < b.elapsed_ms))) AS rank
      FROM weekly_bests b JOIN players p ON p.id = b.player_id
      WHERE b.player_id = ? AND b.week = ? AND b.rules = ?`).bind(player.id, week, RULES).first();
  }
  return json({ week, rules: RULES, entries: rows.results.map(({ id, ...row }) => ({ ...row, isMe: id === player?.id })), me });
}
export default {
  async fetch(request, env) {
    try {
      const now = Date.now();
      const path = new URL(request.url).pathname;
      if (request.method === 'GET' && path === '/health') return json({ status: 'ok', rules: RULES });
      // Token counters are stable for players; guests share a generous IP-based read limit.
      const rateKey = await hash(request.headers.get('authorization') || request.headers.get('cf-connecting-ip') || 'local');
      if (!(await env.REQUEST_LIMIT.limit({ key: rateKey })).success) throw new APIError(429, 'しばらく待ってから再度お試しください。');
      if (request.method === 'POST' && path === '/v1/players') return await register(request, env, now);
      if (request.method === 'GET' && path === '/v1/leaderboard') return await leaderboard(request, env, now);
      const player = await playerFor(request, env);
      if (request.method === 'DELETE' && path === '/v1/player') {
        await env.DB.prepare('DELETE FROM players WHERE id = ?').bind(player.id).run();
        return new Response(null, { status: 204 });
      }
      if (request.method === 'POST' && path === '/v1/rounds') return await startRound(request, env, player, now);
      const match = path.match(/^\/v1\/rounds\/([a-f0-9-]{36})\/score$/);
      if (request.method === 'POST' && match) return await submit(request, env, player, match[1], now);
      throw new APIError(404, '見つかりません。');
    } catch (error) {
      if (error instanceof APIError) return json({ error: error.message }, error.status);
      return json({ error: 'ランキングに接続できません。時間をおいてお試しください。' }, 503);
    }
  },
  async scheduled(_event, env) {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare('DELETE FROM rounds WHERE expires_at < ?').bind(now - DAY),
      env.DB.prepare('DELETE FROM weekly_bests WHERE week < ?').bind(weekFor(now - 90 * DAY)),
      env.DB.prepare('DELETE FROM players WHERE MAX(created_at, last_started_at) < ?').bind(now - 365 * DAY)
    ]);
  }
};
