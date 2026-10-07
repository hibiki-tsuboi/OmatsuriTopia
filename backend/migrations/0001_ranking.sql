PRAGMA foreign_keys = ON;
CREATE TABLE players (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_started_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE rounds (
  id TEXT PRIMARY KEY,
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  rules TEXT NOT NULL,
  week TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  score INTEGER CHECK(score BETWEEN 0 AND 5000),
  elapsed_ms INTEGER,
  hits INTEGER,
  submission_hash TEXT
);
CREATE INDEX rounds_expiry ON rounds(expires_at);
CREATE INDEX rounds_player ON rounds(player_id);
CREATE TABLE weekly_bests (
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  week TEXT NOT NULL,
  rules TEXT NOT NULL,
  score INTEGER NOT NULL,
  elapsed_ms INTEGER NOT NULL,
  hits INTEGER NOT NULL,
  achieved_at INTEGER NOT NULL,
  PRIMARY KEY(player_id, week, rules)
);
CREATE INDEX weekly_ranking ON weekly_bests(week, rules, score DESC, elapsed_ms ASC);
-- Completing a round and improving its weekly record happen in one atomic write.
CREATE TRIGGER record_weekly_best AFTER UPDATE OF score ON rounds
WHEN OLD.score IS NULL AND NEW.score IS NOT NULL
BEGIN
  INSERT INTO weekly_bests(player_id, week, rules, score, elapsed_ms, hits, achieved_at)
  VALUES(NEW.player_id, NEW.week, NEW.rules, NEW.score, NEW.elapsed_ms, NEW.hits, NEW.started_at)
  ON CONFLICT(player_id, week, rules) DO UPDATE SET
    score = excluded.score, elapsed_ms = excluded.elapsed_ms,
    hits = excluded.hits, achieved_at = excluded.achieved_at
  WHERE excluded.score > weekly_bests.score
     OR (excluded.score = weekly_bests.score AND excluded.elapsed_ms < weekly_bests.elapsed_ms);
END;
