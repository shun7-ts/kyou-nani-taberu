# App Store Connect 入力控え

作成日：2026-10-15。入力用の原稿・設定案。App Store Connectへの登録・アップロード・審査提出はまだ行っていない。

| 項目 | 現在の値／入力案 |
|---|---|
| アプリ名 | 今日何食べる？ |
| Bundle ID | com.kyounanitaberu.app |
| 主言語 | 日本語（ja-JP） |
| 最低OS | iOS / iPadOS 17.0 |
| 対応機種 | 現在のXcode設定はiPhone・iPad |
| 現在のバージョン／ビルド | 0.1.0 / 1（公開時の番号は提出前に確定） |
| 第一カテゴリ案 | フード／ドリンク |
| 第二カテゴリ案 | ライフスタイル（任意） |
| ログインが必要 | いいえ。デモアカウント不要 |
| アプリ内課金・サブスクリプション | 現在なし |
| 広告・トラッキング | なし |
| 価格・公開地域 | 未確定。現在のアプリに課金処理はないが、ストアの販売価格は別途設定する |
| 公開方式案 | 手動公開（審査承認後に公開日を決められる） |
| 著作権表記 | `2026 運営者の権利者名`。site-config.jsonのcopyrightHolderを確定後に転記 |
| サポート・プライバシーURL | urls.json。現在未確定。HTTPSでページを公開してから入力 |

## プライバシー回答案

現行のソースは、ユーザーデータをアプリ外へ収集する仕組み、外部解析SDK、広告SDK、独自サーバーを持たない。音声とレシートは端末内処理、保存は端末内のみ。

App Store Connectでは「このアプリからデータを収集しない」が現行実装に対応する回答案。Appleの「収集」は、端末外へ送信して開発者や第三者がアクセス可能になることを基準にする。端末内に在庫や同意情報を保存することとは区別される。メールで利用者が任意に送るお問い合わせは公開ポリシーに別記した。公開する最終バイナリで新しいSDKや送信処理が加わった場合は、この回答を再確認する。

同梱の `App/Resources/PrivacyInfo.xcprivacy` は、トラッキングなし・収集データなしを記載。理由が必要なAPIは次の実使用を申告している。

- UserDefaults：CA92.1。アプリ自身の人数・通知・同意・既読などの設定。
- SystemBootTime：35F9.1。音声の途中結果の更新間隔を測り、発話を保持する判断に使用。端末外へ送信しない。

## 年齢制限の回答に使う実装情報

- ユーザー間の投稿・チャット・共有、広告、課金、賭博、暴力表現、成人向け内容、年齢確認、保護者管理、医療・健康上の助言はない。
- 栄養・筋トレ目的のタグは現在導入していない。
- 外部リンクは画像・フォント・アイコンの出典確認用。アプリ内に自由閲覧のWebブラウザはない。
- 料理には調理用の酒・ワインを材料に使うものがある。酒類の購入・飲酒を促す機能はない。質問票の文言に合わせて内容を申告し、年齢区分はAppleの算定結果を採用する。原稿だけで特定の年齢区分を保証しない。

## 輸出・暗号化

現行コードに独自の暗号化実装はなく、外部認識サービスやアプリ独自のネットワーク通信もない。現在の版では非免除暗号化を使用しない扱いを想定し、`ITSAppUsesNonExemptEncryption = NO` を設定した。提出時にAppleの質問へ、提出対象の実装に基づいて回答する。

## 審査連絡先（非公開）

App Store Connectの審査連絡先には本人の氏名・メール・電話番号の入力が必要。公開サポートメールと同一である必要はない。ここには実際の非公開連絡先を保存していない。審査メモは `review-notes.txt` を使用できる。

## 公式参照先（2026-10-15確認）

- [メタデータ・連絡先・文字数](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [スクリーンショット仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Privacy](https://developer.apple.com/app-store/app-privacy-details/)
- [Required Reason APIの理由コード](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)
- [暗号化の申告](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
- [年齢制限](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
