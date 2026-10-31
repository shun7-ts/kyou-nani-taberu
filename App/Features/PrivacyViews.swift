import SwiftUI

/// This version describes the actual local-only development build.
enum PrivacyPolicy {
    static let version = 2
    static let revision = "2026年10月2日"
}

struct PrivacyPolicyView: View {
    @AppStorage("privacyPolicyConsentVersion") private var version = 0
    @AppStorage("privacyPolicyConsentDate") private var acceptedAt = 0.0
    var body: some View {
        Form {
            Section {
                Text("今日何食べる？ プライバシーポリシー").font(AppFont.headline)
                Text("説明 v\(PrivacyPolicy.version) · \(PrivacyPolicy.revision)").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                Text("現在の端末内保存版について、利用するデータと選択できる操作を説明します。")
            }
            Section("保存するデータと目的") {
                Text("在庫、購入日、期限、保存方法、カスタム食材、在庫の変更履歴、今日の献立、買い物リストを保存します。在庫に合う料理の表示、不足分の買い物、購入・使用後の在庫更新に使います。")
                Text("同意した説明の版と日時、初期登録の完了状態、期限通知の設定も保存します。これらはこの端末のアプリ内で管理します。アカウント登録は不要です。")
            }
            Section("音声・写真は選択制です") {
                Text("手入力だけでも使えます。音声とレシートは、それぞれの説明に同意した後に利用できます。同意は設定で取り消せます。")
                Text("音声は日本語の端末内認識だけを使います。端末内認識が使えない場合や権限がない場合は、文章の手入力で続けられます。")
                Text("レシートはユーザーが選んだ写真またはアプリ内で撮影した静止画だけを受け取り、端末内で文字を読み取ります。撮影画像は写真ライブラリに追加せず、動画は撮影しません。読み取り用の音声・画像はメモリで扱い、録音・画像ファイルを作りません。処理終了時に解放し、未保存の文章・候補は画面を閉じると破棄します。")
                Text("保存するのは確認した食材・量・日付などの在庫情報と変更履歴だけです。発話全文、レシート全文、金額、元の音声・画像は保存しません。写真ライブラリの元の写真は削除しません。")
            }
            Section("通信と権限") {
                Text("このアプリから外部の認識サービスへ音声・写真を送信しません。現在の版にはアプリによるクラウド同期、広告、外部解析サービスはありません。")
                Text("iCloudにしかない写真を写真ライブラリから取得する場合など、OSの機能には通信が必要になることがあります。在庫管理と手入力はオフラインで使えます。")
                Text("カメラの許可はレシート撮影の開始時、マイク・音声認識の許可は録音開始時、通知の許可は期限付きの在庫を登録した後などに求めます。拒否しても手入力は使えます。OSの許可はiPhoneの設定から変更できます。")
            }
            Section("期限通知") {
                Text("許可した場合は、食材名と期限をこの端末の通知に表示します。ロック画面などで見える内容はiPhoneの通知設定に従います。アプリの設定から通知をオフにできます。")
            }
            Section("データの削除") {
                Text("設定の「端末内データを全削除」で、在庫、カスタム食材、変更履歴、献立、買い物、同意状態、アプリ内の通知設定を削除し、初回案内へ戻れます。取り除いた在庫や購入・調理済みの記録も対象です。")
                Text("このアプリの通知予約と通知センターにある通知も消します。同梱の食材・レシピは残ります。写真ライブラリ、OSの権限、iCloudなどのバックアップ、他の端末のデータは操作しません。削除は取り消せません。")
            }
            Section("同意の状況") {
                if version == PrivacyPolicy.version {
                    Text("プライバシーポリシーに同意済み（説明 v\(version)）").accessibilityIdentifier("privacy-policy-accepted")
                    if acceptedAt > 0 { Text(Date(timeIntervalSince1970: acceptedAt), style: .date) }
                } else { Text("この説明への同意はまだ記録されていません。") }
                Text("音声・レシートの利用同意は、この同意とは別に管理します。内容が変更された場合は新しい説明を案内します。")
            }
        }.navigationTitle("プライバシーポリシー")
            .scrollContentBackground(.hidden).background(AppTheme.background)
    }
}

struct PrivacyIntroductionView: View {
    @AppStorage("privacyPolicyConsentVersion") private var version = 0
    @AppStorage("privacyPolicyConsentDate") private var acceptedAt = 0.0
    @State private var reviewed = false
    var onComplete: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("今日何食べる？", systemImage: "fork.knife").font(AppFont.title2.bold())
                    Text("冷蔵庫にあるものから今日の献立を選び、不足分だけを買い物へ。購入・調理後の在庫更新までつなげます。")
                }
                Section("アカウントなしで、手入力から") {
                    Text("在庫・献立・買い物・変更履歴はこの端末に保存します。まずは手入力で始められます。")
                    Text("音声・レシートは後から選べます。機能ごとの利用同意と必要なOSの許可は、その機能を使う前に確認します。")
                }
                Section("保存するもの・消せるもの") {
                    Text("読み取り用の元の音声・画像や全文は保存せず、確認した在庫情報だけを反映します。")
                    Text("設定から説明と同意を確認し、端末内データを全削除できます。")
                    NavigationLink("プライバシーポリシー全文を読む") { PrivacyPolicyView() }
                        .accessibilityIdentifier("privacy-policy-link")
                }
                Section {
                    Toggle("プライバシーポリシーを確認しました", isOn: $reviewed)
                        .accessibilityIdentifier("privacy-policy-reviewed")
                    Text("この操作では音声・写真の利用には同意しません。カメラ・マイク・写真・通知のOS許可も求めません。")
                        .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                }
            }.navigationTitle("はじめに")
                .scrollContentBackground(.hidden).background(AppTheme.background)
                .safeAreaInset(edge: .bottom) {
                    Button("同意して手入力から始める") {
                        guard reviewed else { return }
                        acceptedAt = Date.now.timeIntervalSince1970; version = PrivacyPolicy.version; onComplete()
                    }.buttonStyle(CoralPrimaryButtonStyle()).frame(maxWidth: .infinity).padding().background(AppTheme.background)
                        .disabled(!reviewed).accessibilityIdentifier("privacy-start")
                }
        }.interactiveDismissDisabled()
    }
}
