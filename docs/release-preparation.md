# Git保存・画像軽量化・公開素材（2026-10-15）

開発先：`${HOME}/Developer/IOSアプリ制作`、`feature/data-foundation`。正式アイコン以外の公開素材を準備。旧iCloud制作フォルダと不完全な.gitには変更していない。

## 保存

画像変換前の全実装・設計・原本を `ac292e2` に保存。GitがこのMacから検出した既定の作者情報でコミットし、グローバルの作者設定は変更していない。

ローカルバックアップ：`${HOME}/Developer/Backups/IOSアプリ制作-20261015-094320-before-release/`。

- `working-copy/`：作業開始時の制作フォルダのコピー。
- `preparation-hashes.json`：data・design・同梱リソースの開始時ハッシュ。
- `before-release.bundle`：初期コミットからac292e2までの履歴を含む復元用bundle。`git bundle verify` 成功。
- 最終保存のbundle・コミットは、同バックアップ内の `release-prepared.bundle` と `release-prepared-commit.txt` を参照。

Gitのoriginは初回移行用の古いローカルbundle。現在の履歴はローカルGitと新しいbundleに保存し、originへのpushは行っていない。

## 画像

| 項目 | 変換前 | 変換後 |
|---|---:|---:|
| meal-images配下（catalog含む） | 337,306,013 bytes / 321.68MiB | 51,657,840 bytes / 49.26MiB |
| 画像対応 | 174料理 | 174料理 |
| 署名なしarm64 Release.appのファイル合計 | 365,978,185 bytes / 349.02MiB | 80,347,772 bytes / 76.63MiB |

画像は84.7%削減。Release.appの数値は同じMacでの未署名ビルドのファイル合計で、App Storeのダウンロード・インストール容量を示すものではない。

生成写真142枚をsipsでJPEG品質84、長辺1280pxへ。縦横比と構図を維持。公開素材31枚とご飯の透過イラストは変更なし。現在のcatalogから外れていた旧写真3枚を配布フォルダから除外した。原本は上記コミットとバックアップから復元できる。

現在の配布名・原本名・SHA256・寸法・変換条件は `recipe-image-optimization.json`、作者・ライセンス・変更内容は `recipe-image-sources.json`。プロンプトの原本パスは生成時の記録として保持。再生成ツールは `scripts/prepare-meal-images.py`。配布JPEGへの繰り返し圧縮を避け、必ず原本から新しい出力先に作る。

## 公開素材とアプリの申告

公開素材の正本は [../release/README.md](../release/README.md)。日本語の掲載文5項目、審査メモ、入力設定控え、iPhone・iPad各7画面、紹介・問い合わせ・プライバシーの静的HTMLを用意。未実装機能を掲載文に含めていない。運営者名・サポートメール・公開URL・著作権者が未確定のため、サイトは確認用原稿の表示を付けている。

`PrivacyInfo.xcprivacy` を同梱し、UserDefaultsのアプリ設定（CA92.1）と音声の更新間隔に使うSystemBootTime（35F9.1）を実使用に合わせて申告。非免除暗号化を使用しない設定を生成Info.plistへ追加。署名・対応OS・保存スキーマは変更していない。App Store Connectの回答案は `release/app-store/submission-settings.md`。

## 検証

- 全174画像の同梱・一意性・料理対応・デコード・出典を既存の画像テストで成功確認。`/tmp/meal-release-20261015/iphone.xcresult` の単体テスト1件。
- iPhoneの7画面撮影フロー成功：`iphone-final.xcresult`。初回は「作り方」をStaticTextとして探して失敗したため、表示切り替えを押して工程を開く撮影操作へ修正。
- iPadの7画面撮影フロー成功：`ipad-delivery.xcresult`。初回はiPadの浮動タブがTabBarではなくCellとして公開されていたため、撮影側のタブ選択を修正。製品のタブ構成は変更していない。修正後の初回 `ipad-final.xcresult` はケース成功後の結果保存で停止したため、そのXcode処理のみ終了。診断収集なし・並列テストなしの最終再実行は正常終了し、7画像を書き出した。
- 最終署名なしarm64 Releaseビルド成功：`/tmp/meal-release-20261015/release-final.log`。同梱175ファイル（画像174＋catalog）をソースと全件ハッシュ照合。MinimumOSVersion 17.0とPrivacyInfo、暗号化フラグを確認。
- 公開文の長さ：名前7/30文字、サブタイトル12/30文字、プロモーション69/170文字、説明834/4000文字、キーワード72/100 UTF-8 bytes。審査メモ2025/4000 bytes。
- 紹介ページのブラウザ表示、サポートとプライバシーの375px幅での表示・リンクを確認。横方向のはみ出しなし。未設定のまま`--ready`を実行すると生成を止める。
- 既存のdata・design・scripts計25ファイルのハッシュを保持。新しい補助スクリプトだけ追加した。

今回の検証は画像・公開素材の変更に対応する範囲。全単体テスト・全UIテスト・iOS17ランタイムの再実行、実機へのインストール、公開前の外部ユーザー試験、配布署名付きArchiveとAppleへの提出は実施していない。Node.jsの導入は不要。
