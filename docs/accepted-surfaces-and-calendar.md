# 採用UI：カレンダー・フラットな上部アイコン・限定した影

## 2026-10-21：日付の数字を控えめに調整

本人依頼で献立の7日間カレンダーの数字を20pt・mediumから18pt・Noto Sans JP Regularへ変更。Dynamic Typeの拡大、等幅数字、曜日、選択日の背景、操作領域、日付切り替えは保持する。変更は未コミット。

Simulator向けビルドと既存の `MealPlanningUITests.testSevenDaysFutureEmptyDayAndReturnToday` が成功。7日分の順序、未来日の選択、材料の表示、献立追加、今日へ戻る操作を確認し、添付した日付列の実画面を目視した。結果 `/tmp/meal-calendar-light-20261021.xcresult`、ログ `/tmp/meal-calendar-light-20261021.log`、画像 `tmp/previews/calendar-light-20261021/calendar.png`。全テスト・最大文字の再確認・実機更新は今回未実施。Simulatorは通常起動へ戻した。iPhoneへの反映はXcodeで接続端末を選び⌘R。

以下は2026-10-15時点の実装・検証記録。

2026-10-15。開発先 `${HOME}/Developer/IOSアプリ制作`、`feature/data-foundation`、作業開始HEAD `b87aafa`。

## 反映した内容

- 献立の7日間：曜日はNoto Sans JP 12pt相当、数字は20pt相当。淡い0.5ptの区切り線、選択日だけコーラルの角丸背景と柔らかい影。通常文字では7列を画面幅に配置し、アクセシビリティ文字サイズでは横スクロールして全日付を選べる。今日が左端・未来日が右・過去は右上カレンダーという動作を保持。
- ホームのメニュー／通知、献立のカレンダー、冷蔵庫の＋／検索／並べ替えをアウトラインへ。iOS 26以降の標準ガラス背景を対象のツールバー項目だけ非表示にし、iOS 17以降の互換性を維持。各操作は44pt以上、通知件数とアクセシビリティ名を保持。冷蔵庫は最新指示の＋→検索→並べ替え。
- 今日のおすすめ：温かいグレー、opacity 0.065 / radius 12 / y 4。
- 期限カード：opacity 0.045 / radius 8 / y 2。複数の食材を1枚の白いカードに表示。
- 冷蔵庫本体：opacity 0.065 / radius 10 / y 3。白いシルエットの背後に描画し、コーラルの枠線や食材行には影を付けない。
- 食材追加の3入口：囲む白い面にopacity 0.05 / radius 8 / y 2。各アイコンや個別ボタンに影を付けない。コンパクトな高さ、検索、並べ替え、全件スクロールを保持。

共通の `AppSurfaceShadow` と `AppCardSurface` を作り、上記と選択日だけに適用。ダークモードの影は黒を使用。買い物・ほかの候補・フォーム・写真・文字には新しい影を適用していない。既存のお盆・お皿の影は変更していない。

## 描画と操作の調整

ホームの標準Listは行の背景をクリップするため、影をカードの背景として描き、描画用の外側余白を確保した。おすすめは左右10pt・上8pt・下14pt、期限は8pt。写真やボタンの高さは維持し、影が隣接する文字やカードへ重ならないようにした。画面の画素も確認し、背景の外側へ薄い影が描かれていることを確認した。

期限カードをまとめた際の個別遷移を回帰テストで確認した。複数NavigationLinkが同じList行に入ると別食材へ進む問題があり、行ごとのButtonから明示的に在庫編集へ進む方式に変更。カードの子要素を個別に公開し、各行のcontentShapeを矩形にした。最終の操作領域は44.0pt／44.3ptで、鶏もも肉と牛乳を順にタップしてそれぞれ正しい在庫画面が開くことを検証した。

## 検証

異なる関連UIケース7件の成功を分割して確認。全UIテストの一括実行ではない。

| 対象 | 成功結果（/tmp/meal-flat-cards-20261015/） |
|---|---|
| 通常の冷蔵庫：登録・全件スクロール・編集・削除と復元・フィルタ・検索 | pro-final.xcresult |
| 今日→未来日→今日、献立と材料の切り替え | pro.xcresult内のtestSevenDaysFutureEmptyDayAndReturnToday |
| 右上カレンダーから過去の献立を開く・閲覧のみ・今日へ戻る | navigation.xcresult内のtestArchiveCompletedAndActiveMealsAreReadOnlyAndReturnToday |
| ホーム・献立・冷蔵庫など7画面の撮影 | pro-delivery.xcresult |
| 期限カードの2食材の個別操作と編集画面 | expiry-hit-area.xcresult |
| 375pt・最大文字・ダークの冷蔵庫全操作 | se-final.xcresult内のtestLargestFramedRefrigerator |
| 375pt・最大文字・ダークで7日目まで移動、今日へ戻る、献立と材料・マイページ | se-calendar-final.xcresult |

最終署名なしarm64 Releaseは `release-delivery.log` で成功。最低対応17.0、署名設定・保存モデル・data/design/scripts・同梱画像とJSONはGitの開始時点と一致。

途中の失敗：冷蔵庫テストがマイページでも冷蔵庫専用のスクロールを使っていたため、該当2箇所を汎用の操作へ修正。最大文字の7日目では画面外要素のisHittable取得が例外になるため、先に可視範囲を判定して横スクロールするように変更。ホームの影のクリップと期限カードの個別操作は上記の実装修正後に成功確認した。失敗結果も同じ一時フォルダに残している。

今回の実機インストール、iOS 17ランタイム、実VoiceOver、全単体の再実行は未実施。iPhoneへの反映はローカル開発先のXcodeで接続端末を選び⌘R。

## 確認画像と変更範囲

最新の確認画像はGit管理外 `tmp/previews/accepted-surfaces-20261015/`。`home.png`・`expiry-card.png`・`meal-calendar.png`・`fridge.png` と最大文字ダークの画像を保存。カレンダー上端のプレビューは実画面の切り出し。端末内の通常保存データは使わず、専用のメモリ内在庫で確認した。

コードは `App/Features/{Theme,RecipeViews,MealPlanViews,InventoryViews}.swift`、関連UIテスト3ファイルと撮影コマンドのREADMEを更新。変更は未コミット。公開用素材はb87aafa作成時点のままなので、提出時には最新UIで再撮影する。
