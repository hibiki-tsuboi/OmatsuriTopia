-- Keep the oldest player for each legacy name; retain every player's ID and scores.
-- Legacy generated names contain no hyphens, so numbered suffixes cannot clash with them.
WITH ranked AS MATERIALIZED (
  SELECT id, name, ROW_NUMBER() OVER (PARTITION BY name ORDER BY created_at, id) AS ordinal
  FROM players
)
UPDATE players
SET name = (SELECT ranked.name || '-' || ranked.ordinal FROM ranked WHERE ranked.id = players.id)
WHERE id IN (SELECT id FROM ranked WHERE ordinal > 1);

CREATE UNIQUE INDEX players_name_unique ON players(name);
