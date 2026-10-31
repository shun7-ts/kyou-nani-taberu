# 公開サイトと掲載素材の更新（2026-10-24）

本人が次の作業の5・6（公開窓口・サイト、掲載画像・説明文）を指定。ローカル開発先 `${HOME}/Developer/IOSアプリ制作` の現行作業ツリーを使用。アプリ本体の実装は変更していない。

## 成果物

- `release/site-source/` と生成済み `release/site/`：紹介・サポート・プライバシーの3ページ。ホーム／お盆／冷蔵庫の実画面3枚を使い、スマートフォンでも読める紹介ページへ更新。自動合算のFAQ、端末内に保存する設定を追記。未確定の公開情報は空欄・確認版表示とnoindexのまま。
- `release/app-store/ja-JP/description.txt`：182レシピ、自動合算、現在の不足分追加の操作と3状態の表現を反映。説明文990文字。名前7文字・副題12文字・プロモーション69文字・検索語72 UTF-8バイトを確認。各制限内。値とハッシュは `release/app-store/metadata-validation-20261024.json`。
- `release/app-store/review-notes.txt`：244食材・182料理、自動合算の条件・設定・既存重複を一括整理しないことを追記。
- `release/screenshots/`：1206×2622・1320×2868のiPhone、2064×2752のiPad、各7枚・計21枚を最新UIで撮影。PNGの寸法とアルファなしを検証し、端末別一覧で全画面を目視。PNG本体は未加工。サイト掲載用の3枚だけ縮小した。
- `release/public-launch.md`：公開先3候補と、名前・連絡先確定後の公開手順。Cloudflare Pages Direct Uploadを提案。採用は未確定。
- `scripts/prepare-release-site.py`：サイト用画像の配置と未完成版のnoindexを追加。未設定の `--ready` 拒否を確認。

## 検証

- 撮影UIケース1件を3端末で実施し、3実行すべて成功。結果は `/tmp/meal-release-refresh-20261024/{iphone,iphone-large,ipad}.xcresult`。これは全UI・全単体テストの再実行ではない。撮影でSimulator向けビルドも成功した。今回の署名付きArchiveや実機インストールは未実施。
- iPadだけ既存の実行時警告 `Update the Info.plist: Support for all orientations will soon be required.` が1件。撮影フローは成功。今回の公開素材更新ではXcode設定を変更していない。
- Apple公式の2026-10-24時点の仕様を参照。必須はiPhone Dynamic Island中型とiPad 13インチ。大きいiPhone用も追加で用意。現在の21枚は指定解像度・不透明PNGを満たす。登録時の審査や将来要件への適合を保証するものではない。
- ブラウザで紹介ページを目視し、375px幅の横はみ出しなし・実画像3枚の読込・FAQ開閉・サポート／プライバシー遷移を確認。3ページの相対リンクと画像の実ファイルを照合し、未置換テンプレートなし。
- アプリ本体・同梱素材・data/・design/・AppTests/・Xcode設定の開始時278ファイルをハッシュ照合し変更なし。244食材・182料理をカタログと照合。既存の未コミット変更は保持。旧iCloud制作フォルダ未変更、Node.js不要。
- `git diff --check` 成功。変更は今回も未コミット。

画像の寸法・SHA256・撮影結果は `release/screenshots/verification-20261024.json`、サイト・保護確認はGit管理外 `tmp/previews/release-refresh-20261024/verification.json`。同フォルダに端末別一覧、ブラウザの確認画像、公開素材の確認用ZIPを保存。以前のrelease/は `/tmp/meal-release-refresh-20261024/release-before/` に退避した。

ステータスバー時刻を固定した大きいiPhoneは撮影後に解除。3端末ともテスト用引数なしの通常起動へ戻した。ローカル確認サーバーは127.0.0.1:8766、紹介タブを成果物として保持した。

## 残る確定事項

本人はサイト名を決めてから専用Gmailを新規に用意する方針。公開用の名前・メール・権利者・URLは未確定のため、サイトは確認版まで。実アカウント作成、外部へのアップロード・公開、App Store Connectへの登録・審査提出は行っていない。確認用ZIP内のサイトも公開用完成版ではない。

公式参照：

- [Appleスクリーンショット仕様](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Cloudflare Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)
- [Netlifyの手動デプロイ](https://docs.netlify.com/deploy/create-deploys/)
- [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)
