# 「今日何食べる？」シードデータ

このフォルダは、SwiftData と Supabase の両方から利用するシステム標準データの原稿です。現在は、優先12レシピを成立させる `IngredientMaster v1` を収録しています。

## ファイル

- `ingredient-master-v1.json`: 食材マスター本体
- `ingredient-master.schema.json`: 食材マスターの構造定義
- `priority-recipe-coverage-v1.json`: 優先12レシピと必要食材の対応表。分量や調理手順はまだ含めない
- `../scripts/validate-ingredient-master.mjs`: ID・キー・単位・参照切れを検査するスクリプト
- `recipe-seed-v1.json`: 40レシピの1人分量、手順、時間、器具、任意材料、アレルゲン
- `recipe-seed.schema.json`: Recipe／RecipeIngredientの構造定義
- `calculation-test-cases-v1.json`: 単位換算、人数変更、在庫充足、期限切れ、先入れ、冷凍、曖昧在庫の実行例
- `calculation-test-cases.schema.json`: 計算テストデータの構造定義
- `../scripts/validate-recipe-seeds.mjs`: レシピ参照と計算テストを検査するスクリプト
- `initial-inventory-presets-v1.json`: 初回一括登録の4セクション・32項目とIngredientMasterの対応
- `initial-inventory-presets.schema.json`: 初回一括登録プリセットの構造定義
- `../scripts/validate-initial-inventory-presets.mjs`: プリセットの重複・参照・表示名を検査するスクリプト

## IDと変更ルール

- アプリ内部の正規IDは `id`（UUID）とし、一度公開したIDは変更・再利用しない。
- `key` は人が読める固定キーで、JSON作成時やマイグレーション時の参照に使う。
- 表示名、別名、カテゴリ、初期提案値は将来変更できる。食品そのものを「完全に不変」にするのではなく、IDだけを不変にする。
- 統合・廃止する食材は削除せず、`status: "deprecated"` にして移行先を別のマイグレーションで示す。
- ユーザーが追加する独自食材は `CustomIngredient` として別管理し、この予約ID帯を使わない。
- レシピ原稿は `ingredientKey` で書き、取込処理で正規UUIDへ解決する。

## 在庫と単位

- `stockMode: "exact"`: 数量を基本とする食材。
- `stockMode: "rough"`: 「十分・少ない・切れた」などの概算を基本とする調味料や薬味。
- `defaultStorage` は初期提案であり、実際の `InventoryItem` では冷蔵・冷凍・常温をユーザーが上書きできる。
- MVPで自動換算するのは `g ↔ kg` と `ml ↔ L` だけ。大さじ・小さじはレシピ表示に利用するが、mlへの自動換算は行わない。
- `trackInventory: false` の水はレシピに表示できるが、在庫差引や買い物リストの対象にしない。

## 検証

Node.js がある環境で次を実行します。

```powershell
node .\scripts\validate-ingredient-master.mjs
node .\scripts\validate-recipe-seeds.mjs
node .\scripts\validate-initial-inventory-presets.mjs
```

検証内容は、JSON構造、UUIDと固定キーの一意性、既定単位、別名衝突、優先12レシピからの参照切れ、人数変更、換算可能単位、期限切れ在庫の除外、期限順の在庫消費、曖昧在庫の要確認判定です。
