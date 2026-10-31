# UIデザイン基盤

「今日何食べる？」は、食欲を強く刺激する派手なデザインより、毎日開いても疲れず、すぐ献立を決められる温かい道具感を優先します。基調はオフホワイトとコーラルです。

## 現在の完成度

- 情報設計・画面遷移：14画面の低忠実度ワイヤーフレームまで完成
- 操作できる画面案：[meal-app-wireframes.html](meal-app-wireframes.html)。ブラウザで開いて確認できる
- コンポーネント構成：ホーム、冷蔵庫、レシピ、買い物、認識確認、一括登録の主要構成を確定
- ビジュアル：ライト／ダークの基礎色は定義済み。高忠実度化と実機調整は未完了
- 実装：共通SwiftUIテーマ、枠と接続した食材線画ボタン、冷蔵庫の固定枠を実装済み。[最新仕様・検証](../docs/coral-ui-refinement.md)

## 表現方針

- 温かいオフホワイトを背景にし、温かい赤寄りのコーラルを主要ボタンと線画へ、濃いコーラルを文字・操作アイコンへ使う。主要塗りボタンの文字は白。白文字が読める濃さのコーラルを塗りに使う。通常は44ptで、拡大文字では必要に応じて伸ばす。
- 食材写真はホームの第一候補とレシピ詳細で大きく使い、在庫一覧では情報密度を優先する。
- 第一操作だけを塗りボタンにし、補助操作は枠線またはテキストにする。
- 期限間近は黄、入力エラーや期限切れは赤を使うが、色だけで状態を伝えない。
- カードを重ねすぎず、一覧では区切り線と余白を中心に整理する。

## 優先コンポーネント

1. HomeRecipeHero
2. SecondaryRecipeRow／RecipeCarouselCard
3. ExpiryIngredientStrip
4. InventoryCompactRow
5. IngredientTag／FilterChip
6. RecipeIngredientRow
7. ShoppingCheckRow
8. RecognitionEditableRow
9. BulkSelectionTile
10. StickyPrimaryAction

## 実装時のルール

- Dynamic Typeを使い、固定フォントサイズだけに依存しない。
- タップ領域は44pt以上にする。
- 本文と背景、主要ボタン文字のコントラストを実機で確認する。
- VoiceOverでは食材名、数量、期限、状態を一続きで読めるようにする。
- iPhone SE相当の幅でも主要操作が横にはみ出さないことを確認する。
- ダークモード、空状態、読み込み、要確認、通信不能、権限拒否を同じコンポーネント体系で表現する。

数値の正本は[design-tokens-v1.json](design-tokens-v1.json)です。SwiftUI実装時はColor、Font、Spacing、Radiusへ移植します。


2026-10-07の追加調整：献立追加は白文字＋#E65445、下タブの選択は#F23829。4タブは選択時もアウトラインを保持。検索と並び替えを同じ行へ、登録欄の縦余白を抑え一覧を広げた。食材ボタンは野菜を曲線中心に簡略化し、尾ひれのPathを保持。


最新UI：検索欄は普段隠し、右上に＋／並び替え／検索を配置。食材の線画はOpenMoji 15.1.0のApple／Tomatoを使用（原典・CC BY-SA 4.0はicons/openmoji/）、尾ひれは保持。在庫編集の説明・履歴表示を削除。 [仕様・検証](../docs/compact-search-and-food-icons.md)。


最新の食材ボタンは元の人参（左上）・トマト（右下）配置。OpenMoji Carrot／Tomatoで接続線を整え、尾ひれ保持。重複するグレーの見出しを削除、おすすめアクセントを右上へ。詳細は ../docs/compact-search-and-food-icons.md の配置修正。


最新調整：ホームの見える上部間隔を約半分へ（54→23pt、scrollContentのtop marginは4pt）。人参の葉・本体をつなぎ、背景色のクリアランスで枠と分離。トマト・尾ひれ保持。詳細は ../docs/compact-search-and-food-icons.md。


2026-10-07：ホームに「食べたい料理から選ぶ」「食材から選ぶ」の対になる入口を実装。通常幅は横並び、狭い画面・最大文字は縦並び。縦フォークと抽象形の尾を採用し、人参の葉・本体の接続と枠との隙間を保持。レシピ一覧は料理名検索と種類の絞り込みへ。関連単体2＋UI6ケースを分割で成功、最終arm64 Release成功。 [仕様・検証](../docs/paired-home-entries-and-recipe-search.md)。実機はローカルXcodeで接続iPhoneを選び⌘Rで更新。


2026-10-07：最新採用案へホーム入口を更新（透過・#E65445、内部矢印と皿を削除、枠へつながるフォーク／ナイフと食材線画）。買い物チェックは即時表示＋専用キューの対象1件保存へ。連続操作・失敗復元・購入／Undoを保持。関連単体28＋UI8ケースを分割で成功、最終arm64 Release成功。詳細は[仕様・検証](../docs/home-cutlery-and-shopping-response.md)。実機はXcode⌘Rで更新。


2026-10-07：ホームの入口を少し低く（最低86→78pt）、両方を白い背景へ。料理から選ぶへ短縮、人参とトマトを重ね、ナイフ上辺を直線に、尾びれの先端を尖らせた。関連UI2・最終arm64 Release成功。詳細は[最新調整](../docs/home-cutlery-and-shopping-response.md)。実機はXcode⌘R。
