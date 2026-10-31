# 今日何食べる？

冷蔵庫にある食材から献立を選び、不足分だけを買い物リストに追加するiOSアプリです。

iOS 17以上 / SwiftUI / SwiftData。アカウント登録なしで端末内に保存します。

## 主な機能

- 244食材・192レシピ。食材検索、料理画像、工程ごとの作り方と目安時間
- 冷蔵庫の在庫管理、期限通知、同じ条件の在庫の自動合算
- 献立のお盆表示、日付ごとの使用材料と不足分の確認
- 買い物リスト、購入品の一括在庫登録、調理後の残量更新
- レシート読み取りと日本語音声による食材登録

## 実行方法

1. Xcodeで `KyouNaniTaberu.xcodeproj` を開きます。
2. `KyouNaniTaberu` スキームとインストール済みのiPhoneシミュレータを選び、実行します。
3. 実機で実行する場合は Signing & Capabilities で自分の開発チームと一意なBundle Identifierを設定します。

```sh
xcodebuild -project KyouNaniTaberu.xcodeproj -scheme KyouNaniTaberu \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

テストは同じスキームで実行できます。コマンドでは利用できるシミュレータを指定してください。

```sh
xcodebuild -project KyouNaniTaberu.xcodeproj -scheme KyouNaniTaberu \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
```

Swiftの実行にはNode.jsは不要です。`data/` のJSON検証を行う場合のみNode.js 18以上で `npm test` を実行します。

## 構成

| 場所 | 内容 |
| --- | --- |
| `App/` | SwiftUI画面・SwiftDataモデル・在庫計算・認識処理 |
| `App/Resources/` | 同梱JSON、画像、フォント |
| `AppTests/` / `AppUITests/` | 単体テスト・画面テスト |
| `data/` / `design/` / `scripts/` | 基礎データ・設計・検証スクリプト |
| `docs/` | 仕様・変更と検証の記録 |
| `release/` | ストア掲載と紹介サイトの準備資料 |

## 公開内容・権利表示

2026-10-31時点の開発版を初回スナップショットとして公開しています。開発中のため変更されることがあります。App Storeへの配信や紹介サイトのデプロイは別途です。`release/` には運営者・連絡先・URLなどが未設定の原稿も含まれます。

画像・フォント・アイコンにはそれぞれの利用条件があります。[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)を参照してください。ソースコード全体へのオープンソースライセンスは現時点では設定していません。

詳しい機能と過去の検証記録は[開発履歴](docs/development-history.md)、今回の公開内容は[公開準備記録](docs/github-publication.md)にまとめています。
