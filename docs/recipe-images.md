# 料理別アイキャッチ画像

2026-10-30：洋風10品の画像を内蔵image_genで生成して同梱。全192品に固有画像があり、既存182枚を保持。追加10枚は長辺1280px・JPEG品質84、合計約2.87MiB。[追加料理・検証](western-recipes-20261030.md)、[圧縮条件・対応](western-recipes-20261030-image-delivery.json)。

2026-10-21：豚もも料理8品の画像を内蔵image_genで生成して同梱し、全182料理に固有画像を設定。元の174画像は保持。追加8枚も長辺1280px・JPEG品質84にし、合計約2.32MiB。保存先・プロンプト・検証は [pork-thigh-recipes.md](pork-thigh-recipes.md)、圧縮対応は [pork-thigh-image-delivery.json](pork-thigh-image-delivery.json)。以下は過去の軽量化・生成記録。

## 配布用画像の軽量化（2026-10-15）

全174料理の対応を維持し、生成写真142枚を長辺1280px・JPEG品質84へ変換。公開写真31枚とご飯の透過イラスト1枚はバイト単位で変更していない。旧写真3枚は現在のcatalogが参照しないため配布フォルダから除外。約321.68MiB → 49.26MiB（84.7%削減）。料理の構図は保持し、切り抜きは追加していない。

現在のファイル名は `App/Resources/meal-images/catalog.json`、原本とのハッシュ・寸法・変換対応は [recipe-image-optimization.json](recipe-image-optimization.json)、作者・出典は [recipe-image-sources.json](recipe-image-sources.json)。出典の `file` は現在の配布ファイル、`originalAssetFile` は変換前。生成プロンプトのファイル名と下記の過去記録は生成時の履歴として保持している。

原本はGit `ac292e2` とローカルバックアップに保存。再変換は原本から `scripts/prepare-meal-images.py` を新しい出力先で実行し、配布JPEGを再圧縮しない。全件読込・代表画面・Release同梱の確認は [release-preparation.md](release-preparation.md) を参照。

最新（2026-10-14）：鶏そぼろ丼・卵チャーハン・トマトと卵の炒め物を内蔵image_genで再生成し、白菜6品の新画像を追加。全174料理・公開写真31枚・生成画像143枚、未対応0品。詳細と保存先・プロンプトは [voice-napa-and-category-icons.md](voice-napa-and-category-icons.md)。

前回（2026-10-13）：定番サラダ8品の画像を内蔵image_genで生成し、全168料理に固有画像を設定。公開写真34枚・生成画像134枚（ご飯イラストを含む）、未対応0品。既存160枚は保持。今回の料理・機能・検証は [salads-and-recipe-fridge.md](salads-and-recipe-fridge.md)。

直前（2026-10-13）：フランス・イタリアの新規料理12品を内蔵image_genで生成し、全160料理に固有画像を設定。公開写真34枚・生成画像126枚（ご飯イラストを含む）、未対応0品。既存148枚は保持。今回の料理・調査・検証は [french-italian-recipes.md](french-italian-recipes.md)。

2026-10-11：全148料理に固有画像を設定。未対応だった44品を内蔵image_genで新規生成し、既存104枚を保持した。合計は公開写真34枚と生成画像114枚（ご飯の専用イラストを含む）。未対応料理は0品。対応表は `App/Resources/meal-images/catalog.json`、出典は [recipe-image-sources.json](recipe-image-sources.json)、全生成条件は [recipe-image-prompts.json](recipe-image-prompts.json) に保存。

ホーム・候補・一覧・詳細は同じ料理キーで同梱画像を表示する。オフラインで利用でき、ご飯のお盆用イラストも保持。「イメージ」「AIイメージ」のキャプションは現在のUIでは表示しない。出典情報はマイページで確認できる。

## 2026-10-11 未対応44品の生成完了

生成方法は内蔵 `image_gen`。外部CLI・APIは使用せず、料理ごとに1枚を生成した。材料と最終工程を参照し、横長3:2、明るい自然光、淡い器・背景、文字やロゴなしで統一。生成結果を個別に目視確認し、さんまは細長い形を指定して再生成した2枚目を採用。最終44枚はすべて1536×1024。元の生成ファイルはCodexの生成画像フォルダに残し、採用画像を `App/Resources/meal-images/` にコピーした。

料理データ・手順・既存画像・アプリのSwift実装・data/・design/・scripts/・Xcode設定は開始時ハッシュと一致。テストだけを更新し、全有効レシピの画像対応と今回の代表3料理を検証対象にした。同梱画像全体は270,440,742 bytes、今回追加分は102,833,406 bytes。画像のピクセル編集・圧縮は行っていない。

### 検証結果

- 画像同梱テスト1件成功：全148有効レシピとの完全一致、料理キー・ファイル名の一意性、出典、UIImageの読み込み・寸法を確認。
- UIテスト1件成功：油淋鶏、鶏だんごとせりのスープ、鶏南蛮そばを検索し、一覧と詳細を開く。保存した計6画面を目視し、料理ごとの画像・切り取り・タグが表示されることを確認。
- 最終Debug／署名なしarm64 Releaseビルド成功。SimulatorはiPhone 18 Pro・iOS 27.0、deployment targetはiOS 17。実機の表示は今回未検証。
- 既存104画像と191保護対象ファイルは開始時ハッシュ一致。意図した既存ファイル変更は画像catalogとテスト2ファイルのみ（ほかに画像44枚と文書更新）。
- Pro／SEの通常保存5表は全列・全値ハッシュが開始時と一致。両Simulatorへ最新アプリを配置し、テスト引数なしの通常起動に戻した。

テスト結果・6画面・生成元／ハッシュ・保護確認は `tmp/previews/complete-recipe-images/`。新画像44枚の生成自体に失敗なし。今回の2テスト成功を以前の全243単体テスト再実行とは扱わない。iPhoneへの反映はローカル開発先のXcodeプロジェクトから⌘R。旧iCloud制作フォルダは変更していない。Node.jsは不要。

### 今回追加した画像

| 料理 | 保存ファイル |
| --- | --- |
| さんまの塩焼き | `saury_salt_grill.png` |
| いかとセロリの塩炒め | `squid_celery_stir.png` |
| たこときゅうりの酢の物 | `octopus_cucumber_sunomono.png` |
| 手羽先の七味しょうゆ焼き | `wings_shichimi_grill.png` |
| 豚肩ロースの粒マスタードソテー | `pork_shoulder_mustard.png` |
| 牛ひき肉のキーマカレー | `beef_keema.png` |
| 牛ステーキのバルサミコソース | `steak_balsamic_mushroom.png` |
| 鶏南蛮そば | `chicken_soba.png` |
| ナンプラーのベトナム風そうめん | `vietnamese_somen.png` |
| 高野豆腐と干ししいたけの含め煮 | `koya_shiitake_simmer.png` |
| おからの炒り煮 | `okara_simmer.png` |
| こんにゃくとさつま揚げの煮物 | `konjac_satsuma_simmer.png` |
| 牛バラ肉としらたきのすき煮 | `beef_shirataki_sukiyaki.png` |
| 豆乳ときのこのクリームペンネ | `soy_milk_penne.png` |
| アボカドとツナのチーズサンド | `avocado_tuna_sandwich.png` |
| バナナヨーグルトのオートミール | `banana_yogurt_oatmeal.png` |
| さけ缶とコーンの簡単ドリア | `salmon_can_doria.png` |
| いわし缶のトマトチーズ煮 | `canned_sardine_tomato.png` |
| ちくわときゅうりのかにかまサラダ | `chikuwa_cucumber_salad.png` |
| ほたてとほうれん草のクリーム煮 | `scallop_spinach_cream.png` |
| まぐろとアボカドの海苔丼 | `tuna_avocado_rice.png` |
| かれいの煮付け | `flounder_simmer.png` |
| しらすと大葉の混ぜご飯 | `shirasu_shiso_rice.png` |
| 明太もちチーズ焼き | `mentaiko_mochi_pizza.png` |
| かぶと油揚げの白だしスープ | `turnip_white_dashi_soup.png` |
| 鶏だんごとせりのスープ | `chicken_seri_soup.png` |
| モロヘイヤと卵のスープ | `molokheiya_egg_soup.png` |
| 牛もも肉とピーマンのにんにく炒め | `beef_round_garlic.png` |
| 豚ヒレ肉のピカタ | `pork_tenderloin_piccata.png` |
| えびと春雨のナンプラーサラダ | `shrimp_glass_noodle_salad.png` |
| 豚肉と野菜の焼きビーフン | `rice_vermicelli_stir.png` |
| レンズ豆のトマトスープ | `lentil_tomato_soup.png` |
| 大豆とコーンのカレーサラダ | `soybean_curry_salad.png` |
| カリフラワーと芽キャベツのチーズ焼き | `cauliflower_sprout_cheese.png` |
| 豚バラ大根 | `pork_daikon_simmer.png` |
| チキン南蛮 | `chicken_nanban.png` |
| 鮭のちゃんちゃん焼き | `salmon_chanchan.png` |
| 厚揚げと小松菜の煮浸し | `atsuage_komatsuna_simmer.png` |
| 油淋鶏 | `chicken_yurinchi.png` |
| 鶏大根 | `chicken_daikon.png` |
| 筑前煮 | `chikuzenni.png` |
| 鶏もも肉と白菜のクリーム煮 | `chicken_napa_cream.png` |
| 鶏もも肉のガーリックソテー | `garlic_chicken_saute.png` |
| 鶏もも肉とキャベツのみそ炒め | `chicken_cabbage_miso.png` |

## 2026-10-06時点の記録

以下の件数・表示キャプションは当時の状態。現在の対応状況は冒頭を参照。

料理別画像を100品へ設定した。初回26品、前回40品に続き、今回34品を追加（公開写真2枚・内蔵image_gen生成32枚）。累計はWikimedia Commonsの素材34枚と生成画像66枚。ホームのおすすめ、ほかの候補、レシピ一覧、詳細で同じ固定キーの画像を使う。画像はアプリに同梱してオフラインで表示する。

135品すべての固有画像を完成させたわけではない。残る35品は従来の共通生成画像 `App/Resources/shared-meal.jpg` を表示する。今後は同じcatalogへ画像と出典を追記する。元の共通画像は保持した。

## 採用と表示

Wikimedia Commons APIで135料理名を調査。121件は検索結果を取得し、14件はHTTPエラー等で取得できなかった。取得に失敗したことや候補が少ないことを「フリー素材が存在しない」証拠にはしていない。採用素材は個別の作者・ライセンス情報を確認し、画像を目視して選んだ。Pexelsの利用条件も調べたが、今回は採用していない。

麻婆豆腐の縦写真はご飯が写らず画面の切り取りにも不向き、豚キムチ丼の候補には店名表示、オムライスはクリームソース、えびとチンゲン菜は麺入り、焼きそばはあんかけだったため採用せず生成画像へ置き換えた。ツナマヨ丼の候補は生のまぐろ料理等で、材料が合わなかった。

表示は「イメージ」、生成画像は「AIイメージ」。調理した実物の証明には使わない。盛り付けや付け合わせはレシピと異なる場合がある。カレーの素材は牛肉版、アプリの材料は豚肉版。料理の見た目の参考として使用する。

画像・対応表の保存先は `App/Resources/meal-images/`（100ファイルとcatalog.json）。画像ファイルのピクセル編集は行わず、画面枠で中央を切り取って表示する。ファイル名を固定キーで対応させ、読み込み後は枚数／容量上限付きキャッシュを使う。未対応・読込失敗時は既存の共通画像へ戻る。

## 作者・利用条件

マイページ → データについて → **画像の出典** から、料理名、作者、出典、ライセンスへのリンクと表示上の切り取りを確認できる。CC0・Public domain・CC BY・CC BY-SAを採用。NC/ND等の候補は採用しない。写真のライセンスは各写真についての条件として保持し、アプリのコードのライセンスと混同しない。CC BY-SAの写真およびその画像の改変物には元の同一ライセンスを維持する。

- [CC BY-SA 4.0の利用条件](https://creativecommons.org/licenses/by-sa/4.0/)
- [Public domainの確認：ほうれん草のごまあえ](https://commons.wikimedia.org/wiki/File:Hourensougomaae001.jpg)

| 料理 | 作者・種別 | 利用条件 | 出典 | ファイル |
| --- | --- | --- | --- | --- |
| 親子丼 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Oyakodon_003.jpg) | `oyakodon.jpg` |
| 豚肉と玉ねぎの生姜焼き | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Shogayaki_002.jpg) | `pork_ginger.jpg` |
| 牛丼 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Gyuu-don_001.jpg) | `gyudon.jpg` |
| カレーライス | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Beef_curry_rice_003.jpg) | `curry_rice.jpg` |
| ソース焼きそば | AI生成 | AI生成 | 内蔵image_genで生成 | `sauce_yakisoba.png` |
| ツナマヨ丼 | AI生成 | AI生成 | 内蔵image_genで生成 | `tuna_mayo_bowl.png` |
| 豆腐と卵のふわとろ丼 | AI生成 | AI生成 | 内蔵image_genで生成 | `tofu_egg_bowl.png` |
| 鶏の照り焼き | AI生成 | AI生成 | 内蔵image_genで生成 | `teriyaki_chicken.png` |
| 豚肉とキャベツのみそ炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `miso_pork_cabbage.png` |
| 麻婆豆腐丼 | AI生成 | AI生成 | 内蔵image_genで生成 | `mapo_tofu_bowl.png` |
| 卵チャーハン | AI生成 | AI生成 | 内蔵image_genで生成（2026-10-14差し替え） | `egg_fried_rice.png` |
| 豚キムチ鍋 | Daderot | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Kimchi_jjigae_-_San_Francisco,_CA.jpg) | `pork_kimchi_hotpot.jpg` |
| 鶏そぼろ丼 | AI生成 | AI生成 | 内蔵image_genで生成（2026-10-14差し替え） | `chicken_soboro_bowl.png` |
| 豚キムチ丼 | AI生成 | AI生成 | 内蔵image_genで生成 | `pork_kimchi_bowl.png` |
| オムライス | AI生成 | AI生成 | 内蔵image_genで生成 | `omurice.png` |
| ナポリタン | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Spaghetti_Naporitan_002.jpg) | `napolitan.jpg` |
| 冷ややっこ | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Hiya-yakko_003.jpg) | `chilled_tofu.jpg` |
| ほうれん草のごまあえ | Babi Hijau | Public domain | [素材ページ](https://commons.wikimedia.org/wiki/File:Hourensougomaae001.jpg) | `spinach_sesame_salad.jpg` |
| 鶏のから揚げ | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Chicken_karaage_006.jpg) | `chicken_karaage.jpg` |
| フレンチトースト | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:French_toast_001.jpg) | `french_toast.jpg` |
| ポテトサラダ | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Potato_salad_001.jpg) | `potato_salad.jpg` |
| 切り干し大根の煮物 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Kiriboshi_daikon_002.jpg) | `simmered_kiriboshi.jpg` |
| ほうれん草のおひたし | Lombroso | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Spinach_Ohitashi.jpg) | `spinach_ohitashi.jpg` |
| 野菜のラタトゥイユ | Marcus Guimarães | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Ratatouille.jpg) | `ratatouille.jpg` |
| にんじんしりしり | Nissy-KITAQ | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Ninjin_Shirishiri.JPG) | `carrot_shirishiri.jpg` |
| えびとチンゲン菜のオイスター炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `bok_choy_shrimp.png` |
| カレーうどん | Pacamah | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Curry_Udon.jpg) | `curry_udon.jpg` |
| 豚肉とキャベツの焼きうどん | Flickr.com user "Blue Lotus" | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Yaki-udon.jpg) | `pork_cabbage_yakiudon.jpg` |
| ペペロンチーノ | matsuyuki | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Spaghetti_aglio_olio_e_peperoncino_by_matsuyuki_retouched.jpg) | `peperoncino.jpg` |
| トマトと卵の炒め物 | AI生成 | AI生成 | 内蔵image_genで生成（2026-10-14差し替え） | `tomato_egg_stir_fry.png` |
| さばのみそ煮 | 권재원 | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Miso_Saba.jpg) | `mackerel_miso_simmer.jpg` |
| ゴーヤチャンプルー | Ippei Suzuki | [CC BY 2.0](https://creativecommons.org/licenses/by/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Goya_Champuru_1.jpg) | `goya_champuru.jpg` |
| たらこパスタ | Ocdp | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Tarako_spaghetti.jpg) | `tarako_pasta.jpg` |
| かぼちゃの煮物 | Kentin | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Nimono_of_japanese_pumpkin_2014.jpg) | `simmered_pumpkin.jpg` |
| マカロニサラダ | Bodhi Peace | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Macaroni_salad_in_bowl.jpg) | `macaroni_salad.jpg` |
| あさりのみそ汁 | Kentin | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Miso_soup_of_Japanese_littleneck_clam(asari)_2014.jpg) | `asari_miso_soup.jpg` |
| けんちん汁 | User:Kentin | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Kenchinjiru_soy_sauce_flavor_2009.JPG) | `kenchin_soup.jpg` |
| 冷やし中華 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Hiyashi_chuka_002.jpg) | `hiyashi_chuka.jpg` |
| 肉じゃが | Yumi Kimura from Yokohama, JAPAN | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Braised_pork_and_potatoes_(3089327692).jpg) | `nikujaga.jpg` |
| とんかつ | ayustety from Tokyo, Japan | [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Tonkatsu_by_ayustety_in_Tokyo.jpg) | `tonkatsu.jpg` |
| かつおのたたきと大葉のぽん酢サラダ | ノボホショコロトソ | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0) | [素材ページ](https://commons.wikimedia.org/wiki/File:Katsuo_no_tataki_in_Kochi_01.jpg) | `bonito_tataki_salad.jpg` |
| ツナしょうゆパスタ | AI生成 | AI生成 | 内蔵image_genで生成 | `tuna_soy_pasta.png` |
| 鮭のバターしょうゆ焼き | AI生成 | AI生成 | 内蔵image_genで生成 | `butter_soy_salmon.png` |
| 納豆卵ごはん | AI生成 | AI生成 | 内蔵image_genで生成 | `natto_egg_rice.png` |
| 豚もやしの塩炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `salt_pork_bean_sprouts.png` |
| 鶏のねぎ塩焼き | AI生成 | AI生成 | 内蔵image_genで生成 | `green_onion_salt_chicken.png` |
| 鶏肉のトマト煮 | AI生成 | AI生成 | 内蔵image_genで生成 | `tomato_stewed_chicken.png` |
| 豆腐のひき肉あんかけ | AI生成 | AI生成 | 内蔵image_genで生成 | `tofu_ground_pork_sauce.png` |
| キャベツとツナの蒸し煮 | AI生成 | AI生成 | 内蔵image_genで生成 | `steamed_cabbage_tuna.png` |
| さば缶とキャベツのみそ炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `miso_mackerel_cabbage.png` |
| 卵あんかけうどん | AI生成 | AI生成 | 内蔵image_genで生成 | `egg_ankake_udon.png` |
| きのこのバターしょうゆパスタ | AI生成 | AI生成 | 内蔵image_genで生成 | `mushroom_butter_soy_pasta.png` |
| 豚汁ごはんセット | AI生成 | AI生成 | 内蔵image_genで生成 | `tonjiru_rice_set.png` |
| ミネストローネパスタ | AI生成 | AI生成 | 内蔵image_genで生成 | `minestrone_pasta.png` |
| 豆腐とわかめのみそ汁 | AI生成 | AI生成 | 内蔵image_genで生成 | `tofu_wakame_miso_soup.png` |
| 卵と長ねぎのスープ | AI生成 | AI生成 | 内蔵image_genで生成 | `egg_green_onion_soup.png` |
| 小松菜のごまあえ | AI生成 | AI生成 | 内蔵image_genで生成 | `komatsuna_sesame_salad.png` |
| キャベツのコールスロー | AI生成 | AI生成 | 内蔵image_genで生成 | `cabbage_coleslaw.png` |
| じゃがバター | AI生成 | AI生成 | 内蔵image_genで生成 | `butter_potato.png` |
| きゅうりの酢の物 | AI生成 | AI生成 | 内蔵image_genで生成 | `cucumber_sunomono.png` |
| トマトときゅうりのさっぱりあえ | AI生成 | AI生成 | 内蔵image_genで生成 | `tomato_cucumber_salad.png` |
| 和風ハンバーグ | AI生成 | AI生成 | 内蔵image_genで生成 | `wafu_hamburger.png` |
| ぶりの照り焼き | AI生成 | AI生成 | 内蔵image_genで生成 | `yellowtail_teriyaki.png` |
| 青椒肉絲 | AI生成 | AI生成 | 内蔵image_genで生成 | `chinjaorosu.png` |
| エビチリ | AI生成 | AI生成 | 内蔵image_genで生成 | `shrimp_chili.png` |
| 揚げ出し豆腐 | AI生成 | AI生成 | 内蔵image_genで生成 | `agedashi_tofu.png` |
| ほうれん草とツナのパスタ | AI生成 | AI生成 | 内蔵image_genで生成 | `spinach_tuna_pasta.png` |
| 鶏肉とブロッコリーのオイスター炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `broccoli_chicken_oyster.png` |
| なすと豚肉のみそ炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `eggplant_pork_miso.png` |
| 豆腐とブロッコリーのあんかけ | AI生成 | AI生成 | 内蔵image_genで生成 | `tofu_broccoli_ankake.png` |
| レタスと卵のチャーハン | AI生成 | AI生成 | 内蔵image_genで生成 | `lettuce_egg_fried_rice.png` |
| なすとツナのしょうゆパスタ | AI生成 | AI生成 | 内蔵image_genで生成 | `eggplant_tuna_pasta.png` |
| 鮭とブロッコリーの蒸し焼き | AI生成 | AI生成 | 内蔵image_genで生成 | `salmon_broccoli_steam.png` |
| ブロッコリーとツナのサラダ | AI生成 | AI生成 | 内蔵image_genで生成 | `broccoli_tuna_salad.png` |
| なすのしょうがしょうゆ | AI生成 | AI生成 | 内蔵image_genで生成 | `eggplant_ginger_soy.png` |
| レタスのごまサラダ | AI生成 | AI生成 | 内蔵image_genで生成 | `lettuce_sesame_salad.png` |
| れんこんのきんぴら | AI生成 | AI生成 | 内蔵image_genで生成 | `lotus_root_kinpira.png` |
| ごぼうとにんじんのきんぴら | AI生成 | AI生成 | 内蔵image_genで生成 | `burdock_carrot_kinpira.png` |
| さつまいものレモン煮 | AI生成 | AI生成 | 内蔵image_genで生成 | `sweet_potato_lemon.png` |
| ほうれん草と豆腐のみそ汁 | AI生成 | AI生成 | 内蔵image_genで生成 | `spinach_tofu_miso_soup.png` |
| トマトと卵のスープ | AI生成 | AI生成 | 内蔵image_genで生成 | `tomato_egg_soup.png` |
| ブロッコリーのコンソメスープ | AI生成 | AI生成 | 内蔵image_genで生成 | `broccoli_consomme_soup.png` |
| ごぼうとにんじんのみそ汁 | AI生成 | AI生成 | 内蔵image_genで生成 | `burdock_carrot_miso_soup.png` |
| ピーマンの肉詰め | AI生成 | AI生成 | 内蔵image_genで生成 | `stuffed_green_peppers.png` |
| 棒々鶏 | AI生成 | AI生成 | 内蔵image_genで生成 | `chicken_banbanji.png` |
| ひじきの煮物 | AI生成 | AI生成 | 内蔵image_genで生成 | `simmered_hijiki.png` |
| えのきのなめたけ | AI生成 | AI生成 | 内蔵image_genで生成 | `enoki_nametake.png` |
| あさりの酒蒸し | AI生成 | AI生成 | 内蔵image_genで生成 | `asari_sake_steam.png` |
| なめこと豆腐のみそ汁 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Aka-Dashi_001.jpg) | `nameko_tofu_miso_soup.jpg` |
| アスパラとベーコンのマスタード炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `asparagus_bacon_mustard.png` |
| レバニラ炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `pork_liver_chives.png` |
| 豆苗と厚揚げのナムル | AI生成 | AI生成 | 内蔵image_genで生成 | `pea_shoot_atsuage_namul.png` |
| オクラと長芋のぽん酢和え | AI生成 | AI生成 | 内蔵image_genで生成 | `okra_nagaimo_ponzu.png` |
| 水菜とささみのかいわれサラダ | AI生成 | AI生成 | 内蔵image_genで生成 | `mizuna_tenderloin_salad.png` |
| いんげんとスナップえんどうのごま和え | AI生成 | AI生成 | 内蔵image_genで生成 | `green_bean_snap_pea_sesame.png` |
| しいたけ・まいたけ・エリンギのバター炒め | AI生成 | AI生成 | 内蔵image_genで生成 | `three_mushroom_butter.png` |
| とうもろこしと枝豆の炊き込みご飯 | AI生成 | AI生成 | 内蔵image_genで生成 | `corn_edamame_rice.png` |
| たらときのこのホイル蒸し | AI生成 | AI生成 | 内蔵image_genで生成 | `cod_mushroom_foil.png` |
| あじの南蛮漬け | AI生成 | AI生成 | 内蔵image_genで生成 | `aji_nanban.png` |
| いわしのしょうが煮 | Ocdp | [CC0](https://creativecommons.org/publicdomain/zero/1.0/deed.en) | [素材ページ](https://commons.wikimedia.org/wiki/File:Sardine_dishes_of_Japan_001.jpg) | `sardine_ginger_simmer.jpg` |

## 生成指示（再生成用のプロンプトセット）

内蔵image_genを使用。外部CLI/APIは使用していない。初回9枚、前回25枚、今回32枚を上記の保存先へコピーし、元の生成ファイルも保持した。前回・今回の57枚の最終プロンプト全文と保存先は [recipe-image-prompts.json](recipe-image-prompts.json) に記録。初回9枚の指示は以下。

共通指示：

> Use case: photorealistic-natural. Asset type: iOS recipe hero and thumbnail. One appetizing, realistic photograph of a home-cooked dish for one person. Warm soft natural window lighting, neutral off-white table, centered complete dish, 45-degree close view, wide 3:2 composition safe for a square center crop. Visible natural food texture. No people, text, watermark, logos, branding or unrelated side dishes. This is a recipe illustration, not a cooked test photograph.

料理別の指示：

- ツナマヨ丼：cooked canned tuna mixed with mayonnaise and soy sauce over steamed white rice in an ivory bowl; no raw tuna, avocado or fried egg.
- 豆腐と卵のふわとろ丼：Japanese soft tofu and scrambled egg over steamed white rice in an ivory bowl, pale tofu cubes gently cooked with yellow egg ribbons and translucent onion; no meat or raw egg.
- 鶏の照り焼き：pan-fried chicken thigh teriyaki on an ivory plate, sliced skin-on chicken with glossy soy-mirin glaze; no fried breading or other main dish.
- 豚肉とキャベツのみそ炒め：thin sliced cooked pork and cooked green-white cabbage with a light glossy brown miso sauce on a shallow ivory plate; no scrambled eggs.
- ソース焼きそば：Japanese sauce yakisoba, thin brown wheat noodles with pork, cabbage, carrot and bean sprouts; authentic dry stir-fried texture, no starch gravy or curry.

`mapo_tofu_bowl`：

```text
Use case: photorealistic-natural. Asset type: iOS recipe hero and thumbnail. One appetizing, realistic photograph of this home-cooked dish for one person: Japanese mapo tofu rice bowl, soft tofu cubes and cooked minced pork in reddish brown spicy sauce over steamed white rice, centered ivory bowl. No noodles. Warm soft natural window lighting, neutral off-white table, centered complete dish, 45-degree close view, wide 3:2 composition safe for a square center crop. Visible natural food texture. No people, text, watermark, logos, branding or unrelated side dishes. This is a recipe illustration, not a cooked test photograph.
```

`pork_kimchi_bowl`：

```text
Use case: photorealistic-natural. Asset type: iOS recipe hero and thumbnail. One appetizing, realistic photograph of this home-cooked dish for one person: Japanese pork kimchi rice bowl, cooked thin slices of pork and orange red napa cabbage kimchi stir-fried together over steamed white rice, centered ivory bowl. No noodles, no separate side dishes. Warm soft natural window lighting, neutral off-white table, centered complete dish, 45-degree close view, wide 3:2 composition safe for a square center crop. Visible natural food texture. No people, text, watermark, logos, branding or unrelated side dishes. This is a recipe illustration, not a cooked test photograph.
```

`omurice`：

```text
Use case: photorealistic-natural. Asset type: iOS recipe hero and thumbnail. One appetizing, realistic photograph of this home-cooked dish for one person: Japanese home-style omurice on an ivory plate, cooked chicken and onion ketchup rice wrapped in a thin fully cooked yellow omelette, simple bright red ketchup drizzle on top. No cream sauce, no gravy. Warm soft natural window lighting, neutral off-white table, centered complete dish, 45-degree close view, wide 3:2 composition safe for a square center crop. Visible natural food texture. No people, text, watermark, logos, branding or unrelated side dishes. This is a recipe illustration, not a cooked test photograph.
```

`bok_choy_shrimp`：

```text
Use case: photorealistic-natural. Asset type: iOS recipe hero and thumbnail. One appetizing, realistic photograph of this home-cooked dish for one person: Japanese peeled shrimp and bok choy oyster-sauce stir fry on a shallow ivory plate, cooked peeled orange shrimp and glossy tender green bok choy with a light brown sauce. No noodles, rice, shells or heads. Warm soft natural window lighting, neutral off-white table, centered complete dish, 45-degree close view, wide 3:2 composition safe for a square center crop. Visible natural food texture. No people, text, watermark, logos, branding or unrelated side dishes. This is a recipe illustration, not a cooked test photograph.
```

## 追加時の確認

基本の `data/recipe-seed-v1.json` の40品はすべて専用画像に対応。さらに肉じゃが、とんかつ、冷やし中華、和風ハンバーグ、エビチリ、汁物・副菜などを追加。既存26枚を上書きせず保持し、`data/`・`design/`・`scripts/`・プロジェクト設定も保持した。

納豆ごはんの生卵写真、トマトときゅうりが別々の器に入った写真、ヨーグルトのないオートミール、海鮮入りビーフン、たけのこの代わりににんじんが入った青椒肉絲、ぼやけた写真や画角が合わない写真は採用していない。じゃがバターの初回生成は丸ごとの形だったため、皮をむいた一口大の形へ再生成した。採用した公開写真には、薬味や付け合わせがレシピと異なるものがある（たらこパスタの大葉、ゴーヤチャンプルーの少量のにんじん、冷やし中華のもやし・わかめ、肉じゃがのかいわれ、とんかつのキャベツ、かつおの薬味等）。仕上がりのイメージとして表示し、材料・手順の正本はアプリのレシピとする。

100枚の対応表は `App/Resources/meal-images/catalog.json`、写真の詳細出典は [recipe-image-sources.json](recipe-image-sources.json)。残る35品の一覧は [recipe-images-remaining.json](recipe-images-remaining.json) に記録。今後も料理ごとに一致を確認して追加できる。

## 前回の検証（40品追加時・合計66品）

- 全単体142件成功。66枚の画像デコード・キーとファイル名の重複・料理との対応・作者と出典・基本40品の画像漏れ・未対応fallbackを確認。
- 関連UIの異なる2ケース成功（分割実行）。ホーム、画像出典、既存の生成・公開写真、追加した鮭・みそ汁・冷やし中華の検索結果と詳細を確認し、10枚の画面を目視確認。`/tmp/meal-photo-more-final.xcresult` は単体142＋既存画像UI1が成功、追加UI1は主菜フィルター未解除のテスト操作で失敗。操作を直した `/tmp/meal-photo-more-ui-verified.xcresult` は追加UI1成功。両結果runtimeWarnings0。アプリコードや画像の修正による失敗ではない。
- Simulator test buildと署名なしarm64 Release成功。`/tmp/meal-photo-more-release.log`。最低17.0・Teamを含むプロジェクト設定は保持。Debug／Releaseの全66画像とcatalogはソースと同一ハッシュ。
- `data/`・`design/`・`scripts/`・既存26画像・その他既存同梱リソースを保持。食材240／カスタム0／在庫19／履歴19／献立1／買い物2件と、通常保存5表の全値ハッシュが一致。Proを引数なし通常起動に戻した。
- QA画面・結果の一覧はGit管理外 `tmp/previews/recipe-photo-more-verified.json`。変更は未コミット。今回のiPhoneへのインストールとiOS17ランタイム、最大文字での再確認は未実施。Xcodeで接続iPhoneを選び⌘Rで反映する。

## 今回の34品追加（合計100品）

パスタ、ブロッコリー料理、なす料理、きんぴら、汁物、肉詰め、棒々鶏、ひじき、あさり、豆苗、長芋、きのこ、炊き込みご飯、魚料理を追加。今回のキーは `nameko_tofu_miso_soup`, `sardine_ginger_simmer`, `spinach_tuna_pasta`, `broccoli_chicken_oyster`, `eggplant_pork_miso`, `tofu_broccoli_ankake`, `lettuce_egg_fried_rice`, `eggplant_tuna_pasta`, `salmon_broccoli_steam`, `broccoli_tuna_salad`, `eggplant_ginger_soy`, `lettuce_sesame_salad`, `lotus_root_kinpira`, `burdock_carrot_kinpira`, `sweet_potato_lemon`, `spinach_tofu_miso_soup`, `tomato_egg_soup`, `broccoli_consomme_soup`, `burdock_carrot_miso_soup`, `stuffed_green_peppers`, `chicken_banbanji`, `simmered_hijiki`, `enoki_nametake`, `asari_sake_steam`, `asparagus_bacon_mustard`, `pork_liver_chives`, `pea_shoot_atsuage_namul`, `okra_nagaimo_ponzu`, `mizuna_tenderloin_salad`, `green_bean_snap_pea_sesame`, `three_mushroom_butter`, `corn_edamame_rice`, `cod_mushroom_foil`, `aji_nanban`。

日本語で公開素材を9料理追加検索し、以前の検索結果も照合。6枚の公開候補を目視し、なめこと豆腐のみそ汁といわしのしょうが煮を採用。レタスチャーハンの追加具材、肉詰めの輪切り、レバニラのにんじん、あさり写真のもやしと別の料理は今回の材料／手順や画角に合わず不採用。いわし写真には粉状の薬味が少量あり、仕上がりのイメージとして表示する。

今回の32枚は内蔵image_genで料理ごとに生成し、すべて目視した。調理手順の切り方・使用材料・完成時の状態を指定。生成元を保持してプロジェクトへコピーし、原画像のピクセル編集・既存66枚の置換はしていない。今回と前回の実際の最終プロンプト57件は [recipe-image-prompts.json](recipe-image-prompts.json)、初回9件は上の原稿を参照。保存先は `App/Resources/meal-images/`。

- 全単体142件と関連画像UI2件、計144件が同じ最終実行で成功。`/tmp/meal-photo-third-final.xcresult`、runtimeWarnings0。100枚のデコード・キー／ファイル名重複・料理との対応・出典情報・基本40品の漏れ・fallbackを確認。
- 追加UIはピーマンの肉詰め（生成）・なめこと豆腐のみそ汁（公開）・ほうれん草とツナのパスタ（生成）の検索結果と詳細を確認。ホーム、牛丼詳細、画像出典も含め10枚の画面を目視。全UI一括や最大文字での再実行ではない。
- Simulator test buildと署名なしarm64 Release成功。`/tmp/meal-photo-third-release.log`。Debug／Releaseの100画像とcatalog計101ファイルはソースと同一ハッシュ。画像データは約152.0MiBで、配布前の容量調整は別途検討する。
- 既存66画像、その他同梱リソース、元data/design/scriptsとXcode署名・最低17.0設定を保持。開始前の87ファイルをハッシュ照合し、意図的なcatalog変更だけを除外。通常保存240／0／19／19／1／2件と5表の全値ハッシュが前回の確認値と一致。Proを引数なし通常起動へ戻した。
- QAと結果はGit管理外 `tmp/previews/recipe-photo-third-verified.json`。未コミット。旧iCloudフォルダ・不完全.gitは変更なし。Node.jsは不要・未導入。今回のiPhoneインストール、iOS17ランタイム、最大文字の再確認は未実施。接続iPhoneをXcodeで選んで⌘Rで更新する。



## 2026-10-07 画像キャプションの削除

共通画像部品から「イメージ／AIイメージ」オーバーレイを削除し、ホーム・候補・一覧・詳細・献立画像へ反映。料理の状態／種類タグは保持。画像の出典・生成区分・利用条件はマイページの「画像の出典」に残す。画像ファイル・カタログは変更なし。後続のホーム整理と合わせた検証は[ホーム整理とスワイプ削除](home-and-swipe-inventory.md)。
