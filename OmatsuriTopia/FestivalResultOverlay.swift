import SwiftUI

struct FestivalResultOverlay: View {
    @ObservedObject var model: FestivalModel
    let onConfirm: () -> Void
    private let gold = Color(red: 1, green: 0.79, blue: 0.34)

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            result
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .tint(gold)
    }

    private var result: some View {
        VStack(spacing: 14) {
            ScrollView {
                if let result = model.result {
                    VStack(spacing: 18) {
                        HStack(alignment: .center) {
                            Label("結果発表", systemImage: "flag.checkered")
                                .font(.title2.bold()).foregroundStyle(gold)
                                .accessibilityAddTraits(.isHeader)
                            Spacer(minLength: 12)
                            Text(result.shots.count >= GameRules.ammunition ? "10発すべて撃ち終えました" : "時間切れ")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.white.opacity(0.08), in: Capsule())
                                .accessibilityIdentifier("resultEndReason")
                        }
                        HStack(spacing: 24) {
                            VStack(spacing: 3) {
                                Text("今回のスコア").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(result.score)")
                                        .font(.system(size: 64, weight: .black, design: .rounded)).monospacedDigit()
                                        .minimumScaleFactor(0.6).lineLimit(1)
                                        .accessibilityIdentifier("resultScore")
                                    Text("点").font(.headline).foregroundStyle(gold)
                                }
                                if model.isNewBest {
                                    Label("自己ベスト更新！", systemImage: "crown.fill")
                                        .font(.subheadline.bold()).foregroundStyle(gold)
                                }
                                HStack(spacing: 4) {
                                    Text("自己ベスト")
                                    Text("\(model.best?.score ?? result.score) 点")
                                        .accessibilityIdentifier("personalBest")
                                }.font(.caption).foregroundStyle(.white.opacity(0.7))
                            }.frame(maxWidth: .infinity)
                            VStack(spacing: 14) {
                                resultDetail("命中", value: "\(result.hits)/\(result.shots.count)", icon: "scope")
                                resultDetail("命中率", value: "\(result.accuracy)%", icon: "percent")
                                resultDetail("プレイ時間", value: result.timeText, icon: "timer")
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                        }
                        if let message = model.message { note(message) }
                    }
                }
            }
            Divider().overlay(.white.opacity(0.15))
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    if let text = model.submissionMessage { note(text) }
                    if model.pendingCount > 0 {
                        Button("記録を再送") { Task { await model.retryPending() } }
                            .font(.caption).disabled(model.sending)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onConfirm) {
                    Label("タイトルへ戻る", systemImage: "checkmark")
                        .font(.headline)
                        .padding(.horizontal, 24).padding(.vertical, 15)
                        .foregroundStyle(.black)
                        .background(gold, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("resultConfirm")
            }
        }
        .padding(22)
        .frame(maxWidth: 820, maxHeight: 370)
        .background(Color(red: 0.07, green: 0.08, blue: 0.16), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(gold.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
    }

    private func resultDetail(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 8)
            Text(value).bold().monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
