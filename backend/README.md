# OmatsuriTopia ranking API

Cloudflare Workers + D1. The iOS app uses the HTTPS endpoint in `OmatsuriTopia/App-Info.plist` (`RankingAPIURL`). No Cloudflare credentials belong in the app.

## Development

Requires Node.js 24+ (tests use `node:sqlite`). From `backend/`:

```sh
npm ci
npm test
npm run db:local
npm run dev
# In a second terminal; creates and deletes temporary players:
node test/smoke.mjs http://localhost:8787
```

The tests exercise real SQLite constraints/triggers through a small D1 adapter. The HTTP smoke test additionally exercises the actual Workers/D1 runtime. `wrangler dev` uses a local database; cloud data is untouched.

## Deployment

The dedicated Worker is `omatsuritopia-ranking`; the dedicated D1 database is configured in `wrangler.jsonc`. Authenticate using `npx wrangler login`, then:

```sh
npm run db:remote
npm run deploy
node test/smoke.mjs https://omatsuritopia-ranking.hibiki-apps.workers.dev
```

Apply migrations through `0003_all_time_ranking.sql`, then deploy the Worker before releasing the updated iOS app. The migration copies each player's best surviving weekly record per rules version into `all_time_bests`, preferring a shorter elapsed time on tied scores and the earliest achievement on exact ties. Records already removed by past cleanup cannot be recovered. Existing weekly records and pending rounds remain intact; the new trigger captures scores from both old and new apps. Deploy the new cleanup handler promptly after migration so inactive players with all-time records are retained.

The smoke test creates two temporary anonymous players, checks distinct names and idempotent registration, posts a zero-point result, verifies its rank, and deletes both players in `finally`. Run it only against an endpoint you operate. D1 IDs are configuration, not credentials. For another account, create a separate D1 database and replace `database_id`; ensure both rate-limit namespace IDs are unused there. Never point development migrations at an unrelated database.

## API and rules

- `POST /v1/players`: register an anonymous player using a client-generated 256-bit hexadecimal bearer token. Idempotent for that token, including concurrent retries. Returns an automatically generated, unique public name and private player ID.
- `POST /v1/rounds`: authenticated; body `{ "rules": "festival-60-v1" }`. Returns a one-use round ID, start week (for legacy clients), and upload deadline.
- `POST /v1/rounds/:id/score`: authenticated; `{ rules, elapsedMs, shots: [{ offsetMs, points }] }`. The API derives score/hits, validates timings, and atomically updates the all-time and legacy weekly bests through triggers. Repeating the same result succeeds; modifying it fails.
- `GET /v1/leaderboard/all-time`: the current app's all-time top 100 plus the caller's rank if authenticated. Returns `{ rules, entries, me }`. Each player appears once with their best score for the current rules version. Exact score/time ties share rank. Private IDs/tokens are excluded.
- `GET /v1/leaderboard`: legacy weekly ranking, including the original `week` field, for older app versions. Its semantics are unchanged so old apps never label all-time scores as weekly scores.
- `DELETE /v1/player`: authenticated; deletes the player and cascades to rounds, all-time records, and weekly records.
- `GET /health`: service/rules identifier.

Rules: 60 seconds, 10 shots, at least 400 ms between shots. A game ends on the tenth shot or at the time limit. Scores are ranked descending, elapsed milliseconds ascending. All-time rankings have no periodic reset; lower scores never replace a player's best. Legacy week boundaries remain Monday 00:00 Asia/Tokyo, based on server-issued round start time, including games finished across the boundary. A new round invalidates unfinished older rounds. Uploads expire 10 minutes after starting.

Both client and server use `festival-60-v1`; change the rules version when scoring or timing rules change. Local personal bests and server rankings are separated by version.

## Identity, failure handling, and limits

The iOS app stores the bearer token in a device-only Keychain item and the participation choice separately. D1 stores only its SHA-256 hash. Registration retries reuse the same token. There is no email/password login or cross-device account recovery.

Player names use six adjectives, six animals and four digits (360,000 combinations). The `players_name_unique` index prevents duplicate names across currently registered players, including concurrent registrations. A name collision triggers a fresh random candidate, up to 10 attempts; exhaustion returns a retryable 503 without creating or overwriting a player. Deleted names can be reused.

Apply `0002_unique_player_names.sql` before deploying this Worker version. It preserves the oldest occurrence of each legacy name and adds `-2`, `-3`, etc. to duplicates, keeping IDs and scores intact. Legacy generated names contain no hyphens. If manually edited names cause a suffix collision, the migration fails and rolls back for inspection instead of deleting data. Existing iOS installations may retain an old name in their local profile cache if a duplicate is renamed; the ranking always uses the server name.

Solo play needs no network. Ranked play must obtain a round before starting. Completed ranked results are persisted before upload and retried on network recovery, foregrounding, or an explicit retry. Expired results are dropped from the upload queue while the personal best remains. A ranked start waits for prior pending results; solo play remains immediately available.

Before any database access, every request except the database-free `/health` route consumes a source-IP request quota (120/minute). Requests with an Authorization header also consume the existing token quota (120/minute). Both use `REQUEST_LIMIT` with separate keys, so changing or omitting credentials cannot bypass the IP gate. The source is Cloudflare's `CF-Connecting-IP`; missing values share a local fallback, and client-supplied forwarding headers are ignored. Users sharing an IP share its quota. Existing registration retries remain idempotent within these request quotas; new registrations also retain their separate 10/minute IP limit. No new binding or database migration is needed for this request-limit change.

Request limits, server-side start cooldowns, body-size limits, ownership checks, legal-score validation, and idempotent writes deter simple abuse. **These checks do not prove a genuine gameplay result:** a modified client can fabricate plausible shots. App Attest and server-verifiable game events would be the next steps before prizes or high-stakes competition. [Cloudflare rate-limit bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) are per-location and eventually consistent, not a strict global quota or spending cap.

Daily cleanup removes expired rounds after a day and legacy weekly bests after roughly 90–97 days. All-time bests and their player identities remain until the player requests deletion, even after a year without play. Only players with no all-time record in any rules version are removed after a year of inactivity. Worker invocation logging is disabled; never add logging of authorization headers or shot payloads. Keep `privacy-policy.md` and the bundled `PrivacyPolicy.txt` synchronized when behavior changes.

## iOS verification

Open `OmatsuriTopia.xcodeproj`, select the shared `OmatsuriTopia` scheme, and run tests on a landscape iPhone/iPad simulator. The default UI test checks a ten-shot solo game and personal-best persistence across relaunch.

The online UI test is opt-in because it creates and deletes real records. Keep simulator ad-hoc signing enabled for Keychain access; `CODE_SIGNING_ALLOWED=NO` builds cannot register a player. Use a disposable simulator without an existing ranking player:

```sh
xcodebuild -project ../OmatsuriTopia.xcodeproj -scheme OmatsuriTopiaOnlineQA \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:OmatsuriTopiaUITests/ScoreFlowTests/testOnlineRoundRankingAndDeletion \
  CODE_SIGN_IDENTITY=- test
```

Before an App Store release, update the hosted privacy-policy page and App Store privacy disclosures to reflect the optional online identifiers and gameplay records. The repository includes the updated policy; this task does not submit an App Store release.
