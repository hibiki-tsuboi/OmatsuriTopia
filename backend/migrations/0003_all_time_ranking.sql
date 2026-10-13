CREATE TABLE all_time_bests (
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  rules TEXT NOT NULL,
  score INTEGER NOT NULL,
  elapsed_ms INTEGER NOT NULL,
  hits INTEGER NOT NULL,
  achieved_at INTEGER NOT NULL,
  PRIMARY KEY(player_id, rules)
);
CREATE INDEX all_time_ranking ON all_time_bests(rules, score DESC, elapsed_ms ASC);

-- Preserve the best surviving weekly record for each player and rules version.
-- On exact ties, keep the earliest achievement and its associated hit count.
INSERT INTO all_time_bests(player_id, rules, score, elapsed_ms, hits, achieved_at)
SELECT player_id, rules, score, elapsed_ms, hits, achieved_at
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY player_id, rules ORDER BY score DESC, elapsed_ms ASC, achieved_at ASC, week ASC
  ) AS ordinal
  FROM weekly_bests
)
WHERE ordinal = 1;

-- Keep the weekly trigger for older apps; both records update atomically.
CREATE TRIGGER record_all_time_best AFTER UPDATE OF score ON rounds
WHEN OLD.score IS NULL AND NEW.score IS NOT NULL
BEGIN
  INSERT INTO all_time_bests(player_id, rules, score, elapsed_ms, hits, achieved_at)
  VALUES(NEW.player_id, NEW.rules, NEW.score, NEW.elapsed_ms, NEW.hits, NEW.started_at)
  ON CONFLICT(player_id, rules) DO UPDATE SET
    score = excluded.score, elapsed_ms = excluded.elapsed_ms,
    hits = excluded.hits, achieved_at = excluded.achieved_at
  WHERE excluded.score > all_time_bests.score
     OR (excluded.score = all_time_bests.score AND excluded.elapsed_ms < all_time_bests.elapsed_ms);
END;
