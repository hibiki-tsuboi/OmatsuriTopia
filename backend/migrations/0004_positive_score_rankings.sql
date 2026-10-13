-- Accept completed zero-point rounds for old clients and idempotent retries,
-- but only positive scores can create or update a leaderboard record.
-- Existing records are preserved; leaderboard queries hide legacy zero scores.
DROP TRIGGER record_weekly_best;
CREATE TRIGGER record_weekly_best AFTER UPDATE OF score ON rounds
WHEN OLD.score IS NULL AND NEW.score > 0
BEGIN
  INSERT INTO weekly_bests(player_id, week, rules, score, elapsed_ms, hits, achieved_at)
  VALUES(NEW.player_id, NEW.week, NEW.rules, NEW.score, NEW.elapsed_ms, NEW.hits, NEW.started_at)
  ON CONFLICT(player_id, week, rules) DO UPDATE SET
    score = excluded.score, elapsed_ms = excluded.elapsed_ms,
    hits = excluded.hits, achieved_at = excluded.achieved_at
  WHERE excluded.score > weekly_bests.score
     OR (excluded.score = weekly_bests.score AND excluded.elapsed_ms < weekly_bests.elapsed_ms);
END;

DROP TRIGGER record_all_time_best;
CREATE TRIGGER record_all_time_best AFTER UPDATE OF score ON rounds
WHEN OLD.score IS NULL AND NEW.score > 0
BEGIN
  INSERT INTO all_time_bests(player_id, rules, score, elapsed_ms, hits, achieved_at)
  VALUES(NEW.player_id, NEW.rules, NEW.score, NEW.elapsed_ms, NEW.hits, NEW.started_at)
  ON CONFLICT(player_id, rules) DO UPDATE SET
    score = excluded.score, elapsed_ms = excluded.elapsed_ms,
    hits = excluded.hits, achieved_at = excluded.achieved_at
  WHERE excluded.score > all_time_bests.score
     OR (excluded.score = all_time_bests.score AND excluded.elapsed_ms < all_time_bests.elapsed_ms);
END;
