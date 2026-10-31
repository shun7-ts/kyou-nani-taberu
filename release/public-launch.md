# サイト名・窓口・公開先の準備

更新日：2026-10-24。サイトはローカルの確認版。外部公開、アカウント作成、ドメイン購入は未実施。

## 現在の状態

- 紹介・サポート・プライバシーの3ページと、最新アプリ画面を使った紹介画像を用意した。
- 本人回答：サイト名を決めた後、その名前に合わせた専用Gmailを新しく用意する。現時点では名前・メールを確定しない。
- サイトの表示名は確認用にアプリ名「今日何食べる？」を使用している。別ブランド名の採用は未確定。
- 公開用の運営者表示・著作権者・メール・URLは `site-config.json` に未設定。取得前のメールを連絡先として記載しない。
- 未設定の確認版には案内とnoindexを付けている。noindexはアクセス制限ではない。ローカルでのみ確認する。

## 公開先の候補

| 候補 | 今回の使い方 | 判断材料 |
|---|---|---|
| Cloudflare Pages（提案） | Direct Uploadで完成済みHTML・画像をアップロード。`プロジェクト名.pages.dev`のURLを使用 | Git連携・Node.jsなしで今回のファイルを配置できる。無料プランのファイル数・サイズ制限に十分収まる |
| Netlify | 手動デプロイの画面へ完成したサイトフォルダを渡す | ファイルからの公開が簡単。継続運用するアカウントと利用枠は開始時に確認 |
| GitHub Pages | サイト専用リポジトリから配信 | サイトの更新履歴をGitで運用したい場合。GitHub Freeは公開リポジトリで利用できる。アプリ本体を含めず、サイト用ファイルだけを登録する |

推奨は現状の静的HTMLを直接置けるCloudflare Pages。これは提案であり、公開先はまだ採用していない。独自ドメインは後から検討できる。

公式情報（2026-10-24確認）：

- [Cloudflare Pages Direct Upload](https://developers.cloudflare.com/pages/get-started/direct-upload/)
- [Cloudflare Pagesの制限](https://developers.cloudflare.com/pages/platform/limits/)
- [Netlifyの手動デプロイ](https://docs.netlify.com/deploy/create-deploys/)
- [GitHub Pagesの概要](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)

## 名前を決めた後の手順

1. サイト名、公開してよい運営者・著作権者の表示を確定する。
2. 専用Gmailを用意し、実際に受信できることを確認する。取得可否は未確認。パスワードや復旧コードはこのプロジェクトに保存しない。
3. 公開先のプロジェクト名・URLを確定し、`site-config.json` の4項目を入力する。表示名を変える場合は `site-source/` と生成スクリプトのタイトル・ブランド表記も合わせる。
4. リポジトリのルートで `python3 scripts/prepare-release-site.py --ready` を実行する。未設定があれば生成を止める。
5. 確認した `release/site/` の中身だけを公開する。アプリ本体・Vault・バックアップ・非公開の連絡先はアップロード対象に含めない。
6. 公開URLで3ページの表示、画像、ナビゲーション、メールリンクを確認する。`app-store/urls.json` の3つのURLをApp Store Connectへ使用する。

現時点では専用Gmail・公開URLを確定できないため、正式公開はここまでの準備を終えてから続ける。
