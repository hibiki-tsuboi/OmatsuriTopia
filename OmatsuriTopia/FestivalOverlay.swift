import SwiftUI

struct FestivalOverlay: View {
    @ObservedObject var model: FestivalModel
    @State private var showSettings = false
    @State private var showDeleteConfirmation = false
    private let gold = Color(red: 1, green: 0.79, blue: 0.34)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16).opacity(0.9), .black.opacity(0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            Group {
                switch model.screen {
                case .home: home
                case .result: result
                case .ranking: ranking
                case .playing: Color.clear
                }
            }
            .frame(maxWidth: 1040)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
        .background {
            Image("Background").resizable().scaledToFill().ignoresSafeArea().accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .tint(gold)
        .sheet(isPresented: $model.showConsent) { consent }
        .sheet(isPresented: $model.showPrivacy) { privacy }
        .sheet(isPresented: $showSettings) { settings }
    }

    private var home: some View {
        HStack(spacing: 32) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("WEEKLY CHALLENGE", systemImage: "sparkles")
                        .font(.caption.weight(.bold)).tracking(3).foregroundStyle(gold)
                    Text("おまつり\nトピア").font(.system(size: 42, weight: .black, design: .rounded)).lineSpacing(-2)
                    Text("一発に、願いをこめて。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 12) {
                        Label("60秒", systemImage: "timer")
                        Label("10発", systemImage: "scope")
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(gold)
                    bestCard
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView {
                VStack(spacing: 10) {
                    Text("今週の射的じまん、集まれ。")
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    action("全国に挑戦", icon: "trophy.fill", prominent: true) { model.start(ranked: true) }
                    action("ひとりで遊ぶ", icon: "scope") { model.start(ranked: false) }
                    action("週間ランキング", icon: "list.number") { model.loadRanking() }
                    if model.busy { ProgressView().tint(gold).accessibilityLabel("通信中") }
                    if let message = model.message { note(message) }
                    if model.participates, let name = model.profileName {
                        Text(name).font(.caption).foregroundStyle(gold)
                            .accessibilityIdentifier("rankingPlayerName")
                    } else {
                        Text("全国への挑戦は任意参加・本名入力なし")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                    HStack(spacing: 18) {
                        Button {
                            model.message = nil
                            showSettings = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }.disabled(model.busy)
                        Button("プライバシー") { model.showPrivacy = true }
                        if model.pendingCount > 0 {
                            Button("未送信 \(model.pendingCount)件を再送") { Task { await model.retryPending() } }
                        }
                    }.font(.caption)
                }
            }
            .frame(maxWidth: 390)
        }.frame(maxHeight: 330)
    }

    private var bestCard: some View {
        HStack {
            Image(systemName: "crown.fill").foregroundStyle(gold)
            VStack(alignment: .leading, spacing: 3) {
                Text("この端末の自己ベスト").font(.caption).foregroundStyle(.white.opacity(0.65))
                Text(model.best.map { "\($0.score) 点" } ?? "まだ記録がありません")
                    .font(.title3.bold()).monospacedDigit()
                    .accessibilityIdentifier("personalBest")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private var result: some View {
        HStack(spacing: 32) {
            ScrollView {
                if let result = model.result {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.isNewBest ? "自己ベスト更新！" : "今回の記録", systemImage: "star.fill")
                            .foregroundStyle(gold).font(.headline)
                        Text("\(result.score)")
                            .font(.system(size: 66, weight: .black, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("resultScore")
                        Text("POINTS").font(.caption.bold()).tracking(4).foregroundStyle(gold)
                        HStack(spacing: 16) {
                            Text("命中 \(result.hits)/\(result.shots.count)")
                            Text("命中率 \(result.accuracy)%")
                            Text(result.timeText)
                        }.font(.subheadline).monospacedDigit()
                        bestCard
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    if let text = model.submissionMessage { note(text) }
                    action("全国に挑戦", icon: "trophy.fill", prominent: true) { model.start(ranked: true) }
                    action("ひとりでもう一度", icon: "arrow.clockwise") { model.start(ranked: false) }
                    action("週間ランキング", icon: "list.number") { model.loadRanking() }
                    Button("おまつりに戻る") { model.message = nil; model.screen = .home }
                        .padding(.top, 4).disabled(model.busy)
                    if model.busy { ProgressView().tint(gold) }
                    if let message = model.message { note(message) }
                    if model.pendingCount > 0 {
                        Button("記録を再送") { Task { await model.retryPending() } }.font(.caption)
                    }
                }
            }.frame(maxWidth: 390)
        }.frame(maxHeight: 330)
    }

    private var ranking: some View {
        VStack(spacing: 12) {
            HStack {
                Button { model.message = nil; model.screen = .home } label: {
                    Label("戻る", systemImage: "chevron.left")
                }.disabled(model.busy)
                Spacer()
                Text("週間ランキング").font(.title2.bold())
                Spacer()
                Button { model.loadRanking() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("ランキングを更新").disabled(model.busy)
            }
            HStack {
                Text(model.ranking.map { "\($0.week.replacingOccurrences(of: "-", with: "/")) からの一週間" } ?? "全国の記録")
                Spacer()
                Text("月曜 0:00 更新・日本時間")
            }.font(.caption).foregroundStyle(.white.opacity(0.65))
            if model.busy {
                Spacer()
                ProgressView("全国の記録を読み込み中…").tint(gold)
                Spacer()
            } else if let ranking = model.ranking {
                if let me = ranking.me {
                    HStack {
                        Label("あなたの順位", systemImage: "person.fill")
                        Text("\(me.rank)位").bold()
                        Spacer()
                        Text("\(me.score) 点").bold().monospacedDigit()
                    }.padding(12).background(gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                if ranking.entries.isEmpty {
                    Spacer()
                    Image(systemName: "trophy").font(.largeTitle).foregroundStyle(gold)
                    Text("今週の最初の挑戦者になろう").font(.headline)
                    Text("「全国に挑戦」で遊ぶと、ここに記録が並びます。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(ranking.entries.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: 12) {
                                    Text("\(row.rank)").font(.title3.bold()).foregroundStyle(row.rank <= 3 ? gold : .white)
                                        .frame(width: 40)
                                    Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if row.isMe == true { Text("あなた").font(.caption2).foregroundStyle(gold) }
                                    Spacer(minLength: 0)
                                    Text("\(row.score) 点").font(.headline).monospacedDigit()
                                    Text(String(format: "%.2f秒", Double(row.elapsedMs) / 1000))
                                        .font(.caption).foregroundStyle(.white.opacity(0.6)).frame(width: 65)
                                }.padding(12)
                                .background(.white.opacity(row.isMe == true ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                Text("各プレイヤーの最高記録・上位100人。得点が同じならタイム順、同タイムは同順位。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            } else {
                Spacer()
                Text(model.message ?? "記録を読み込めませんでした。")
                    .multilineTextAlignment(.center).font(.subheadline)
                Button("もう一度読み込む") { model.loadRanking() }
                Spacer()
            }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("ランキング参加情報") {
                    if model.participates {
                        if let name = model.profileName {
                            LabeledContent("表示名", value: name)
                        }
                        Button("参加をやめて記録を削除", role: .destructive) {
                            showDeleteConfirmation = true
                        }.disabled(model.busy || model.sending)
                        Text("表示名・参加情報・全国ランキングの記録を削除します。端末の自己ベストは残ります。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("全国ランキングには参加していません。")
                        Text("タイトル画面の「全国に挑戦」から参加できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.busy { ProgressView("処理中…") }
                    if model.sending {
                        Text("スコアを送信中です。送信が終わると削除できます。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let message = model.message { Text(message).font(.footnote) }
                }
                Section {
                    NavigationLink("プライバシーポリシー") { privacyContent }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("閉じる") { showSettings = false }.disabled(model.busy)
            } }
            .alert("ランキング参加をやめて、オンライン記録を削除しますか？",
                   isPresented: $showDeleteConfirmation) {
                Button("オンライン記録を削除", role: .destructive) { model.deleteOnlineRecords() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("表示名・参加情報・全国ランキングの記録を削除します。端末の自己ベストは残ります。")
            }
        }.preferredColorScheme(.dark).tint(gold).interactiveDismissDisabled(model.busy)
    }

    private var consent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("全国の射的じまんと競おう", systemImage: "trophy.fill").font(.title2.bold())
                    Text("表示名は自動で作られます。本名やメールアドレスの入力はありません。")
                    Text("参加すると匿名の参加IDを作成し、全国に挑戦したときの得点・命中数・プレイ時間・発射記録をCloudflareへ送信します。表示名・得点・タイム・順位は他のプレイヤーにも公開されます。")
                    Text("ランキングは日本時間の月曜0時に更新。60秒・10発で競います。アプリを閉じている間も制限時間は進みます。")
                    Text("参加はいつでもやめられ、タイトル画面の「設定」からオンライン記録を削除できます。端末を替えた際の記録の引き継ぎには対応していません。")
                    if let message = model.message { Text(message).foregroundStyle(.orange) }
                    Button { model.join() } label: {
                        HStack { if model.busy { ProgressView() }; Text("内容を確認して参加する").bold() }
                            .frame(maxWidth: .infinity).padding()
                    }.buttonStyle(.borderedProminent).disabled(model.busy)
                    NavigationLink("プライバシーポリシーを読む") {
                        privacyContent
                    }
                }.padding(24)
            }
            .navigationTitle("ランキングへの参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { model.showConsent = false }.disabled(model.busy)
            } }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(model.busy)
    }

    private var privacy: some View {
        NavigationStack {
            privacyContent
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { model.showPrivacy = false } } }
        }.preferredColorScheme(.dark)
    }

    private var privacyContent: some View {
        ScrollView {
            Text(privacyText).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyText: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "お問い合わせ: hibiki.tsuboi@icloud.com" }
        return text
    }

    private func action(_ title: String, icon: String, prominent: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack {
                Image(systemName: icon).frame(width: 24)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold())
            }.padding(.horizontal, 18).padding(.vertical, 14)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(prominent ? gold : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(model.busy).opacity(model.busy ? 0.6 : 1)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
