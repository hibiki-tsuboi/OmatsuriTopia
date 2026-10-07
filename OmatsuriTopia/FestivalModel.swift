import Foundation
import Combine
import Network

final class FestivalModel: ObservableObject {
    enum Screen { case home, playing, result, ranking }
    @Published var screen: Screen = .home
    @Published var best: GameResult?
    @Published var result: GameResult?
    @Published var isNewBest = false
    @Published var profileName: String?
    @Published var participates = false
    @Published var busy = false
    @Published var ranking: WeeklyRanking?
    @Published var message: String?
    @Published var submissionMessage: String?
    @Published var showConsent = false
    @Published var showPrivacy = false
    @Published var showDeleteConfirmation = false
    @Published var pendingCount = 0

    var play: (() -> Void)?
    private let store = ScoreStore()
    private let api = RankingAPI()
    private let networkMonitor = NWPathMonitor()
    private var identity: RankingIdentity?
    private var round: RankedRound?
    @Published private(set) var sending = false

    init() {
        best = store.best
        participates = store.participates
        identity = try? RankingKeychain.read()
        profileName = identity?.name
        pendingCount = store.pending.count
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in await self?.retryPending() }
        }
        networkMonitor.start(queue: DispatchQueue(label: "ranking.connectivity"))
    }

    func start(ranked: Bool) {
        guard !busy else { return }
        if ranked && !participates { showConsent = true; return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                // Send outstanding results before issuing a new round that invalidates old sessions.
                if ranked {
                    await retryPending()
                    let identity = try currentIdentity()
                    guard store.pending.isEmpty else {
                        throw RankingError(status: 0, message: "前の記録をまだ送信できません。再送するか、ひとりで遊んでお待ちください。")
                    }
                    let newRound = try await api.start(token: identity.token)
                    guard newRound.rules == GameRules.version else {
                        throw RankingError(status: 400, message: "アプリを最新版に更新してください。")
                    }
                    round = newRound
                } else { round = nil }
                result = nil
                submissionMessage = nil
                screen = .playing
                play?()
            } catch { handle(error) }
        }
    }

    func finished(_ result: GameResult) {
        isNewBest = store.save(result)
        best = store.best
        self.result = result
        if let round {
            store.enqueue(result, round: round)
            submissionMessage = "ランキングに送信しています…"
        } else { submissionMessage = "自己ベストをこの端末に保存しました" }
        self.round = nil
        pendingCount = store.pending.count
        screen = .result
        Task { await retryPending() }
    }

    func join() {
        guard !busy else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                var value = try RankingKeychain.read() ?? RankingKeychain.create()
                // Persist before registering so a lost response can safely be retried.
                try RankingKeychain.save(value)
                let profile = try await api.register(token: value.token)
                value.id = profile.id
                value.name = profile.name
                try RankingKeychain.save(value)
                identity = value
                profileName = profile.name
                store.participates = true
                participates = true
                showConsent = false
                message = "参加しました。「全国に挑戦」から記録を競えます。"
            } catch { handle(error) }
        }
    }

    func loadRanking() {
        guard !busy else { return }
        screen = .ranking
        message = nil
        ranking = nil
        busy = true
        Task {
            defer { busy = false }
            await retryPending()
            do { ranking = try await api.leaderboard(token: participates ? currentIdentity().token : nil) }
            catch { handle(error) }
        }
    }

    func retryPending() async {
        guard !sending, participates, !store.pending.isEmpty else { return }
        sending = true
        defer { sending = false; pendingCount = store.pending.count }
        do {
            let identity = try currentIdentity()
            for item in store.pending {
                if item.round.expiresAt <= Date().timeIntervalSince1970 * 1000 {
                    store.removePending(item.round.id)
                    if result?.id == item.result.id { submissionMessage = "送信期限が過ぎました。自己ベストはこの端末に残っています。" }
                    continue
                }
                do {
                    try await api.submit(item, token: identity.token)
                    store.removePending(item.round.id)
                    if result?.id == item.result.id { submissionMessage = "週間ランキングに登録しました" }
                } catch let error as RankingError where [400, 404, 409, 410].contains(error.status) {
                    store.removePending(item.round.id)
                    if result?.id == item.result.id { submissionMessage = error.message }
                } catch {
                    if result?.id == item.result.id { submissionMessage = "未送信の記録があります。通信回復後、開始から10分以内なら再送できます。" }
                    throw error
                }
            }
        } catch {
            if let error = error as? RankingError, error.status == 401 { handle(error) }
        }
    }

    func deleteOnlineRecords() {
        guard !busy, !sending else { return }
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                let token = try currentIdentity().token
                do { try await api.delete(token: token) }
                catch let error as RankingError where error.status == 401 { /* Already removed. */ }
                try RankingKeychain.clear()
                store.clearPending()
                store.participates = false
                participates = false
                identity = nil
                profileName = nil
                ranking = nil
                pendingCount = 0
                screen = .home
                message = "オンライン記録を削除しました。端末の自己ベストは残っています。"
            } catch { handle(error) }
        }
    }

    private func currentIdentity() throws -> RankingIdentity {
        if let value = try RankingKeychain.read() { identity = value; return value }
        throw RankingError(status: 401, message: "参加情報が見つかりません。もう一度参加してください。")
    }

    private func handle(_ error: Error) {
        if let error = error as? RankingError {
            message = error.message
            if error.status == 401 { participates = false; store.participates = false }
        } else {
            message = "通信できませんでした。接続を確認して再度お試しください。ひとりでも遊べます。"
        }
    }
}
