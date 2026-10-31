# App Store用スクリーンショット

2026-10-24に最新のアプリから再撮影。画像の差し替え・画面の合成・機能の描き足しは行っていない。架空の在庫18件と、画面から選んだご飯・鶏の照り焼き・冷ややっこ・豆腐とわかめのみそ汁を使用。通常のユーザーデータは読み書きしない専用のメモリ内ストアで撮影した。

| 保存先 | 寸法 | 端末／OS | 枚数 |
|---|---|---|---|
| `iphone-1206x2622/` | 1206 × 2622 | iPhone 18 Pro / iOS 27.0 | 7 |
| `iphone-1320x2868/` | 1320 × 2868 | iPhone 18 Pro Max / iOS 27.0 | 7 |
| `ipad-2064x2752/` | 2064 × 2752 | iPad Pro 13-inch (M5) / iPadOS 27.0 | 7 |

全21枚が縦長PNG・アルファチャンネルなし。Apple公式の必須画面はiPhoneのDynamic Island中型画面と、iPad対応アプリの13インチ画面。加えて大きいiPhone用も用意した。3端末とも撮影フローが成功。画像を引き伸ばしたり別端末用に加工せず、それぞれのSimulatorから撮影している。登録時の表示枠と要件は [Apple公式の仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) を確認する。

## 掲載順と見出し案

見出しは画像に焼き込んでいない。画像はそのまま登録でき、後でグラフィックを作る場合には以下の短い文を使える。

| ファイル | 内容 | 見出し案 |
|---|---|---|
| 01-home.png | 冷蔵庫からのおすすめ、作れるタグ | 冷蔵庫から、今日のごはん。 |
| 02-meal-tray.png | 4品を並べた今日の献立 | お盆に並べて、献立を決める。 |
| 03-materials.png | 使用材料と不足分 | 足りない材料が、ひと目で。 |
| 04-shopping.png | 献立からの買い物リスト | 献立の不足分を、買い物へ。 |
| 05-fridge.png | 食材の在庫と期限、登録方法 | あるものを、気軽に管理。 |
| 06-recipe.png | 料理画像とレシピ詳細 | 料理を選んで、詳しく見る。 |
| 07-steps.png | 工程・材料・工程ごとの時間 | 作り方と時間を、一緒に。 |

## 再撮影

`StoreScreenshotCapture.testCaptureJapaneseStoreScreenshots` は通常のUIテストではスキップする。明示的に以下のように実行する。Node.jsは不要。

```sh
TEST_RUNNER_CAPTURE_STORE_SCREENSHOTS=1 xcodebuild \
  -project KyouNaniTaberu.xcodeproj -scheme KyouNaniTaberu \
  -destination 'platform=iOS Simulator,id=対象のSimulatorのUUID' \
  -derivedDataPath /tmp/meal-store-capture/Derived \
  -resultBundlePath /tmp/meal-store-capture/screens.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:KyouNaniTaberuUITests/StoreScreenshotCapture/testCaptureJapaneseStoreScreenshots \
  test CODE_SIGNING_ALLOWED=NO
```

結果から `xcrun xcresulttool export attachments --path 結果.xcresult --output-path 新しい出力先 --filter '*.png'` で書き出し、manifest.jsonに記録された名前で7枚を整理する。status_barの時刻変更を行った場合は撮影後にclearする。再撮影後は各画面を目視し、寸法とアルファを確認する。

## 2026-10-24の確認記録

撮影結果は `/tmp/meal-release-refresh-20261024/{iphone,iphone-large,ipad}.xcresult`。各1件の撮影UIケースが成功。全UIテストの実行ではない。最新カレンダー18pt Regular・上部の平坦なアイコン・最新182品のカタログを含む現行コードから撮影した。自動合算の設定は初期オン。通常ユーザーの保存情報は使わない。

ファイル寸法・アルファ・ハッシュは `verification-20261024.json`、端末別の目視一覧はGit管理外の `tmp/previews/release-refresh-20261024/`。日付・時刻は撮影時の表示。追加の大きいiPhoneだけステータスバーを9:41に固定し、撮影後に解除。旧画像は `/tmp/meal-release-refresh-20261024/release-before/` に退避した。
