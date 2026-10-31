# 2026-10-07 ホーム入口と買い物チェックの反応改善

開発場所：iCloud外 `${HOME}/Developer/IOSアプリ制作`、feature/data-foundation。旧iCloudコピーは変更しない。

## ホーム

最新採用画像 `exec-f62df8b6-f9a4-43c3-891e-90bb3bfacf19.png` を目視して実装。2つの同サイズの入口、透過背景、文字・枠・線画を #E65445 へ統一。両方の内部「＞」と料理側の皿を撤去。料理側は縦フォーク・縦ナイフの端を上辺・下辺の共有点につなぐPathへ。食材側は葉本体が一続きの斜め人参、元のOpenMojiトマト、二葉と浅いVの尾。トマトの下端の水平接線を枠へつないで細い折り返しを避ける。左右の基準位置と線幅1.6ptを共通化。文字はネイティブ、通常は横並び、狭い画面と最大文字は縦並び。料理一覧・食材選択・解除・検索・献立追加の既存導線を保持。元OpenMoji素材・ライセンスを残し、画像出典には現行トマトと初期人参素材を区別して記載。

## 買い物チェック

ShoppingChecksがタップの表示を同期的に更新し、チェック・取り消し線・フィルター・購入件数で同じ状態を参照する。保存はShoppingCheckWriterの専用シリアルキュー内で新しいModelContextを作り、対象UUIDの未登録行だけをpredicate＋fetchLimit1で取得・更新・保存。UIのコンテキストやモデルを別スレッドへ渡さず、キューの同一ブロック内で全操作を完了し、UUID・Bool・測定値だけを境界へ渡す。参考：[AppleのSwiftData ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)。

同じ商品の保存中にタップした新しい状態を保持し、順番に保存する。未着手の重複操作は最後の状態へまとめる。古い成功／失敗・query更新で新しい選択を上書きしない。最新の保存失敗は直前の確定状態へ戻し、既存アラートを表示。購入確認は保存完了後の選択をスナップショットにし、保存中の編集・削除を当該行だけ無効にする。購入確認へ移る間は追加タップを止める。画面を閉じても開始済みの保存は完了させる。

買い物のチェックは在庫変更通知を発行しない。従来の同期setCheckedも同じ対象1件更新と通知抑制へ。購入確定・調理・実在庫の登録・Undoは従来どおり期限通知を更新する。成功したチェックは従来どおり直前のUndoを無効にするが、保存中にできた新しい在庫操作のUndoは消さない。保存失敗ではUndoを保持する。

## 検証

関連単体28件（ShoppingCheckTests 7、InventoryUndoTests 15、ExpiryNotificationTests 6）とUI8ケースの成功を分割確認。通常の料理入口・検索／種類・献立追加、食材選択の買い物→冷蔵庫／自由入力、保存を5秒止めた状態での即時チェック・連続タップ・最終状態から購入、失敗時の復元／件数／フィルター、購入／調理Undo、375pt最大文字のライト／ダーク両入口、人数・買い物絞り込み／購入確認を確認した。

最終ソースのRelease arm64ビルドは署名なしで成功（`/tmp/meal-touch-utensils/release-verified.log`）。ホームの通常横並び・最大文字縦並びの画像を目視確認し、最終画像を `tmp/previews/home-cutlery-and-shopping-response/` に保存。既存data/scripts/写真/アイコンなど保護119ファイルのハッシュ一致。PBXの変更は新しいShoppingChecks.swiftのソース登録4行のみ。通常保存の在庫・イベント・献立・買い物・カスタム5表は全値ハッシュ一致。両Simulatorはテスト引数なしで通常起動に戻した。旧iCloudコピー未変更、未コミット。

### 結果の所在と途中失敗

- `/tmp/meal-touch-utensils-pro.xcresult`：28単体と既存の在庫購入・Undoを含むUI4成功。新規UI1は固定フッターをスクロール本文へ移動しようとしたテストヘルパーで失敗。失敗復元UIで警告1件。
- `/tmp/meal-touch-utensils-pro-final.xcresult`：最新ホームと連続チェック→購入のUI2成功、runtimeWarnings 0。固定フッターは直接タップへ修正。
- `/tmp/meal-touch-utensils-failure-final.xcresult`：失敗復元UI1成功、runtimeWarnings 0。エラー閉じる際のObservableObject更新を次のメインアクター処理へ送り、SwiftUIの表示更新中の公開警告を解消。
- `/tmp/meal-touch-utensils-se-final.xcresult`：最新ホーム最大文字ライト／ダークUI2成功、runtimeWarnings 0。買い物UI1は献立追加後に消えるrecipe-selectを古いテストが参照して失敗。
- `/tmp/meal-touch-utensils-se-shopping.xcresult`：買い物最大文字UI1成功、runtimeWarnings 0。おすすめへスクロールし、選択後はrecipe-startを確認するよう修正。

単体の途中案は排他的アクセスのコンパイルエラーと、保存済みqueryが未通知の状態を捨てる不具合を修正。初期のModelActor案は、この環境の実測で保存がメインスレッドに残りスレッド検証が失敗した。最終の専用キュー案ではコンテキスト操作がメイン外であること、失敗rollback・登録済み／削除済み拒否・通知抑制・購入／Undoの通知維持を確認した。初期画像の簡略トマトは元のOpenMoji輪郭へ戻した。

### 測定の範囲

iOS 27 Simulatorのディスク保存、買い物100件・30回更新で、旧全件fetch＋saveの中央値1.771ms、新対象1件fetch＋saveは0.603ms（最大0.880ms）。表示状態を同期更新する処理は0.024ms。この比較は旧経路の期限通知処理を含まず、端末のタップ遅延・描画フレーム・体感速度を示すものではない。実機の遅延は未計測。実機へのインストールはXcodeで接続iPhoneを選び⌘R。最低対応17.0を保持し、今回のテストはiOS 27上、iOS 17実行は未実施。Node.jsは不要。


## 2026-10-07 追加調整：白い入口と短いラベル

ホームの2入口の通常最低高さを86→78pt、縦paddingを14→10ptへ縮めた。左は「料理から選ぶ」に短縮（ネイティブ文字・2段表示）。枠／文字の#E65445は維持し、両入口の内側はライト／ダークとも#FFFFFF。トマトを左上へ寄せ、人参の手前に白い塗りで重ね、後ろの輪郭が透けない構成。トマト下端と枠の共有点も合わせた。料理側の上辺からナイフ先端への浅い曲がりを水平線へ変更。尾びれは二葉と浅いVを維持し、外側先端を直線で尖らせた。

最初の2ケースは成功したが、最大文字ダークの画像で、開いた柄のPathを塗ると暗い三角の隙間が生じるのを確認。塗りは閉じた外周だけ、フォーク／ナイフ内側は線だけに分離して修正した。

修正後の関連UI2ケース成功、runtimeWarnings 0。通常幅ライトは料理入口→かな／複数語検索・種類の絞り込み・献立追加・買い物へ、375pt最大文字ダークは料理入口→検索／絞り込みを確認。最終両画像を目視し、塗りの隙間がなく、文字と輪郭が読めることを確認した。最終署名なしarm64 Releaseビルド成功。結果は `/tmp/meal-white-entries-pro-verified.xcresult` と `se-verified.xcresult`、ビルドログは `/tmp/meal-white-entries/release-verified.log`。確認画像は `tmp/previews/white-home-entries/`。既存食材・写真・スクリプトなど保護119ファイルと通常保存5表を保持。今回のiPhoneインストールは未実施、Xcode⌘Rで反映。
