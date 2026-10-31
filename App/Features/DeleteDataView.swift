import SwiftUI
import SwiftData

struct DeleteDataView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var notices: ExpiryNotifications
    @State private var summary: UserDataSummary?
    @State private var reviewed = false
    @State private var confirming = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text("この端末のアプリ内データを削除します。").font(AppFont.headline)
                Text("取り除いた在庫や購入・調理済みの記録も対象です。削除後は初回案内から始め直せます。この操作は取り消せません。")
            }
            Section("削除するデータ") {
                if let summary {
                    LabeledContent("在庫（取り除いたものを含む）", value: "\(summary.inventory)件")
                    LabeledContent("カスタム食材", value: "\(summary.customs)件")
                    LabeledContent("在庫変更履歴", value: "\(summary.events)件")
                    LabeledContent("献立", value: "\(summary.meals)件")
                    LabeledContent("買い物（購入済みを含む）", value: "\(summary.shopping)件")
                } else { ProgressView("件数を確認しています…") }
                Text("初期登録の状態、プライバシー・音声・レシートの同意と日時、通知の日数・時刻・設定")
                Text("このアプリの通知予約と、通知センターに表示済みの通知")
            }
            Section("削除しないもの") {
                Text("アプリ同梱の食材とレシピ、写真ライブラリの元の写真、OSの許可設定、iCloudなどのバックアップ、他の端末のデータ")
                Text("マイク・音声認識・通知のOS許可を変更する場合は、iPhoneの設定を使ってください。")
            }
            Section {
                Toggle("削除範囲と取り消せないことを確認しました", isOn: $reviewed)
                    .accessibilityIdentifier("delete-data-reviewed")
                Button("端末内データを全削除", role: .destructive) { confirming = true }
                    .disabled(!reviewed || summary == nil || session.isResetting)
                    .accessibilityIdentifier("delete-data-request")
                if let error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("delete-data-error")
                    Button("件数を確認し直す") { load() }
                }
            }
        }.navigationTitle("端末内データを全削除")
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .task { load() }
            .alert("すべての利用データを削除しますか？", isPresented: $confirming) {
                Button("キャンセル", role: .cancel) {}
                Button("すべて削除する", role: .destructive) { Task { await delete() } }
            } message: { Text("在庫・履歴・献立・買い物・設定・同意と、このアプリの通知を削除します。取り消しはできません。") }
    }
    private func load() {
        do { summary = try UserDataService(container: context.container).summary(); error = nil }
        catch { self.error = "件数を読み込めませんでした。もう一度お試しください。" }
    }
    private func delete() async {
        do { try await session.reset(service: UserDataService(container: context.container), notices: notices) }
        catch { self.error = "データを削除できませんでした。データと設定は変更していません。もう一度お試しください。" }
    }
}
