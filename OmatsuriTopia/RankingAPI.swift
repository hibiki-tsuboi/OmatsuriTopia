import Foundation
import Security

struct RankingIdentity: Codable {
    let token: String
    var id: String?
    var name: String?
}

struct RankingProfile: Decodable {
    let id: String
    let name: String
}

struct RankingEntry: Decodable {
    let name: String
    let score: Int
    let elapsedMs: Int
    let rank: Int
    let isMe: Bool?
}

struct WeeklyRanking: Decodable {
    let week: String
    let rules: String
    let entries: [RankingEntry]
    let me: RankingEntry?
}

struct RankingError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

enum RankingKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "jp.hibiki.omatsuritopia.ranking",
         kSecAttrAccount as String: "anonymous-player"]
    }

    static func read() throws -> RankingIdentity? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw keychainError }
        return try JSONDecoder().decode(RankingIdentity.self, from: data)
    }

    static func save(_ identity: RankingIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw keychainError }
        } else if status != errSecSuccess { throw keychainError }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError }
    }

    static func create() throws -> RankingIdentity {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw keychainError }
        return RankingIdentity(token: bytes.map { String(format: "%02x", $0) }.joined())
    }

    private static var keychainError: RankingError {
        RankingError(status: 0, message: "参加情報を安全に保存できませんでした。端末のロックを解除して再度お試しください。")
    }
}

final class RankingAPI {
    private let session: URLSession
    private var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RankingAPIURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func register(token: String) async throws -> RankingProfile {
        try await request("v1/players", method: "POST", token: token)
    }

    func start(token: String) async throws -> RankedRound {
        struct Body: Encodable { let rules = GameRules.version }
        return try await request("v1/rounds", method: "POST", token: token, body: JSONEncoder().encode(Body()))
    }

    func submit(_ pending: PendingScore, token: String) async throws {
        struct Body: Encodable { let rules: String; let elapsedMs: Int; let shots: [ShotRecord] }
        struct Reply: Decodable { let accepted: Bool }
        let body = Body(rules: pending.round.rules, elapsedMs: pending.result.elapsedMs, shots: pending.result.shots)
        let _: Reply = try await request("v1/rounds/\(pending.round.id)/score", method: "POST", token: token,
                                        body: JSONEncoder().encode(body))
    }

    func leaderboard(token: String?) async throws -> WeeklyRanking {
        try await request("v1/leaderboard", token: token)
    }

    func delete(token: String) async throws {
        _ = try await data("v1/player", method: "DELETE", token: token)
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", token: String?, body: Data? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path, method: method, token: token, body: body))
    }

    private func data(_ path: String, method: String, token: String?, body: Data? = nil) async throws -> Data {
        guard let baseURL else { throw RankingError(status: 0, message: "全国ランキングは準備中です。ひとりで遊ぶことはできます。") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "ランキングに接続できませんでした。"
            throw RankingError(status: response.statusCode, message: message)
        }
        return data
    }
}
