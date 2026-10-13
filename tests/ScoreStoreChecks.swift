import Foundation

@main
struct ScoreStoreChecks {
    static func main() throws {
        let suite = "OmatsuriTopia.ScoreStoreChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScoreStore(defaults: defaults)
        let zero = GameResult(id: UUID(), score: 0, hits: 0, elapsedMs: 60000, shots: [], playedAt: Date())
        let hit = GameResult(id: UUID(), score: 20, hits: 1, elapsedMs: 60000,
                             shots: [ShotRecord(offsetMs: 1000, points: 20)], playedAt: Date())
        let expiry = Date().timeIntervalSince1970 * 1000 + 600000
        let zeroRound = RankedRound(id: "zero", week: "2026-10-12", rules: GameRules.version, expiresAt: expiry)
        let hitRound = RankedRound(id: "hit", week: "2026-10-12", rules: GameRules.version, expiresAt: expiry)

        precondition(store.save(zero), "A zero-point result can still be saved on the device.")
        precondition(store.best?.score == 0)
        store.enqueue(zero, round: zeroRound)
        precondition(store.pending.isEmpty, "Zero-point rounds must never enter the upload queue.")
        precondition(store.save(hit))
        precondition(!store.save(zero), "A zero-point result must not replace a positive personal best.")
        precondition(ScoreStore(defaults: defaults).best?.id == hit.id)
        store.enqueue(hit, round: hitRound)
        precondition(store.pending.map(\.round.id) == [hitRound.id], "One hit must qualify for ranking.")

        // Simulate an upgrade with both zero and positive rounds left by an older app.
        let legacyQueue = [PendingScore(round: zeroRound, result: zero), PendingScore(round: hitRound, result: hit)]
        defaults.set(try JSONEncoder().encode(legacyQueue), forKey: "scores.\(GameRules.version).pending")
        let upgraded = ScoreStore(defaults: defaults)
        precondition(upgraded.pending.map(\.round.id) == [hitRound.id], "Legacy zero scores must not be retried.")
        upgraded.removePending(hitRound.id)
        precondition(ScoreStore(defaults: defaults).pending.isEmpty)
        precondition(upgraded.best?.id == hit.id)
        print("PASS: zero-score exclusion, one-hit eligibility, saved best preservation, legacy queue filtering")
    }
}
