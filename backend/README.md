# OmatsuriTopia ranking API

Cloudflare Workers + D1. The iOS app uses the HTTPS endpoint in `OmatsuriTopia/App-Info.plist` (`RankingAPIURL`). No Cloudflare credentials belong in the app.

## Development

Requires Node.js 24+ (tests use `node:sqlite`). From `backend/`:

```sh
npm ci
npm test
npm run db:local
npm run dev
# In a second terminal; creates and deletes a temporary player:
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

The smoke test creates a temporary anonymous player, posts a zero-point result, verifies its rank, and deletes it in `finally`. Run it only against an endpoint you operate. D1 IDs are configuration, not credentials. For another account, create a separate D1 database and replace `database_id`; ensure both rate-limit namespace IDs are unused there. Never point development migrations at an unrelated database.

## API and rules

- `POST /v1/players`: register an anonymous player using a client-generated 256-bit hexadecimal bearer token. Idempotent for that token. Returns an automatically generated public name and private player ID.
- `POST /v1/rounds`: authenticated; body `{ "rules": "festival-60-v1" }`. Returns a one-use round ID, start week, and upload deadline.
- `POST /v1/rounds/:id/score`: authenticated; `{ rules, elapsedMs, shots: [{ offsetMs, points }] }`. The API derives score/hits, validates timings, and atomically updates the weekly best through a trigger. Repeating the same result succeeds; modifying it fails.
- `GET /v1/leaderboard`: top 100 plus the caller's rank if authenticated. Exact score/time ties share rank. Private IDs/tokens are excluded.
- `DELETE /v1/player`: authenticated; deletes the player and cascades to rounds and weekly records.
- `GET /health`: service/rules identifier.

Rules: 60 seconds, 10 shots, at least 400 ms between shots. A game ends on the tenth shot or at the time limit. Scores are ranked descending, elapsed milliseconds ascending. Week boundaries are Monday 00:00 Asia/Tokyo, based on server-issued round start time. Finishing across the boundary records the previous week. A new round invalidates unfinished older rounds. Uploads expire 10 minutes after starting.

Both client and server use `festival-60-v1`; change the rules version when scoring or timing rules change. Local personal bests and server rankings are separated by version.

## Identity, failure handling, and limits

The iOS app stores the bearer token in a device-only Keychain item and the participation choice separately. D1 stores only its SHA-256 hash. Registration retries reuse the same token. There is no email/password login or cross-device account recovery.

Solo play needs no network. Ranked play must obtain a round before starting. Completed ranked results are persisted before upload and retried on network recovery, foregrounding, or an explicit retry. Expired results are dropped from the upload queue while the personal best remains. A ranked start waits for prior pending results; solo play remains immediately available.

Per-token request limits, registration IP limits, server-side start cooldowns, body-size limits, ownership checks, legal-score validation, and idempotent writes deter simple abuse. **These checks do not prove a genuine gameplay result:** a modified client can fabricate plausible shots. App Attest and server-verifiable game events would be the next steps before prizes or high-stakes competition. Rate-limit bindings are per Cloudflare location, not a strict global quota.

Daily cleanup removes expired rounds after a day, weekly bests after roughly 90–97 days, and inactive players after a year. Worker invocation logging is disabled; never add logging of authorization headers or shot payloads. Keep `privacy-policy.md` and the bundled `PrivacyPolicy.txt` synchronized when behavior changes.

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
