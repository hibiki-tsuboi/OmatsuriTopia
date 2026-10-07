import Foundation

enum GameRules {
    static let version = "festival-60-v1"
    static let duration: TimeInterval = 60
    static let ammunition = 10
}

struct ShotRecord: Codable {
    let offsetMs: Int
    let points: Int
}

struct GameResult: Codable {
    let id: UUID
    let score: Int
    let hits: Int
    let elapsedMs: Int
    let shots: [ShotRecord]
    let playedAt: Date

    var accuracy: Int { shots.isEmpty ? 0 : Int(Double(hits) / Double(shots.count) * 100) }
    var timeText: String { String(format: "%.2f秒", Double(elapsedMs) / 1000) }

    func isBetter(than other: GameResult) -> Bool {
        score > other.score || (score == other.score && elapsedMs < other.elapsedMs)
    }
}

struct RankedRound: Codable {
    let id: String
    let week: String
    let rules: String
    let expiresAt: Double
}

struct PendingScore: Codable {
    let round: RankedRound
    let result: GameResult
}

final class ScoreStore {
    private let defaults: UserDefaults
    private let prefix = "scores.\(GameRules.version)."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var best: GameResult? { read(GameResult.self, key: "best") }
    var pending: [PendingScore] { read([PendingScore].self, key: "pending") ?? [] }
    var participates: Bool {
        get { defaults.bool(forKey: "ranking.participates") }
        set { defaults.set(newValue, forKey: "ranking.participates") }
    }

    @discardableResult
    func save(_ result: GameResult) -> Bool {
        let improved = best.map { result.isBetter(than: $0) } ?? true
        if improved { write(result, key: "best") }
        return improved
    }

    func enqueue(_ result: GameResult, round: RankedRound) {
        var values = pending.filter { $0.round.id != round.id && $0.round.expiresAt > Date().timeIntervalSince1970 * 1000 }
        values.append(PendingScore(round: round, result: result))
        write(Array(values.suffix(20)), key: "pending")
    }

    func removePending(_ id: String) { write(pending.filter { $0.round.id != id }, key: "pending") }
    func clearPending() { defaults.removeObject(forKey: prefix + "pending") }

    private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: prefix + key) }
    }
}
