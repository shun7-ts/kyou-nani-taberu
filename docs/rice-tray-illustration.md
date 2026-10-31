# 献立のご飯イラスト（2026-10-08）

内蔵 image_gen で新規生成。透過背景、1254×1254 PNG、約1.86MB。生成後のピクセル加工は行わず、出力をそのままアプリへ同梱する。

素材：[plain-rice-tray-illustration-v1.png](../App/Resources/meal-images/plain-rice-tray-illustration-v1.png)。アプリの出典一覧は既存catalogへAI生成として追記。献立の通常／大きな文字のトレイでplain_riceにのみ使用。候補・詳細の従来の茶碗とほかの料理写真は維持。透過の茶碗を直接置き、ご飯には追加の白い皿枠を重ねない。素材が読み込めない場合は既存Canvasへ戻る。器の位置・献立と材料の保存は変更しない。

仕様と最終検証は [today-meal-tray.md](today-meal-tray.md) 最新節を参照。

## 最終生成プロンプト

```text
Use case: stylized-concept
Asset type: final transparent PNG food illustration for the staple dish on a Japanese meal-planning app's wooden serving tray.
Primary request: one beautiful bowl filled with freshly cooked plain Japanese short-grain white rice, viewed STRICTLY FROM DIRECTLY ABOVE (90 degree overhead). Create a finished, high quality food illustration, not a schematic icon.
Subject: a single round Japanese rice bowl in warm ivory glazed ceramic with a delicate pale celadon blue rim, filled generously with a soft, naturally irregular mound of fluffy cooked white rice. Make the rice visibly appetizing: many overlapping plump short grains, subtle translucent edges and creamy shadows, tiny moist highlights, varied directions and sizes. Rice must read clearly as cooked Japanese rice, not seeds, loops, popcorn, pasta or a geometric pattern.
Style/medium: refined hand-painted digital editorial food illustration with gently realistic volume, detailed food texture and restrained brushwork; polished for a warm minimal iOS app. Soft warm daylight from the upper left. No heavy outlines or cartoon faces.
Composition: one centered complete circular bowl, no visible side wall or pedestal, no tilt or perspective ellipse. Entire bowl visible, occupying about 90 percent of a square canvas, small even transparent margin. Rice fills the bowl almost to its thin rim. Genuine transparent alpha background outside the bowl. No tabletop or tray.
Constraints: no text, labels, watermark, hands, utensils, chopsticks, garnish, other foods, collage, steam or scenery. No background color or baked checkerboard. Only the single bowl of cooked white rice.
```
