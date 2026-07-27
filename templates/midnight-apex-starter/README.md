# MIDNIGHT APEX

夜の未来都市を2周する、4:3画面・後方視点の短編ホバーレースゲームです。
地平線へ収束する発光コースを読み、大きなS字とヘアピンでブレーキとブーストを使い分けます。
道を少し外れると最高速とハンドルの効きが落ち、壁のない路端から大きく外れると転落します。
ライバルへ触れると速度とエネルギーを失います。
ブレーキ中は曲がりやすくなるため、減速そのものがコース攻略になります。無料の加速帯、
ジャンプ台、形の異なる2台のライバル、独自合成したサイバーパンクBGMと連続駆動音も備えています。
エネルギーはブースト資源と機体の耐久を兼ね、壁やライバルとの接触、使い切るブーストで
0になると爆発してゲームオーバーになります。

操作:

- ↑ / W: アクセル
- ↓ / S: ブレーキ
- ←→ / A D: ハンドル
- Space: 走行中のブースト
- Space / Enter: 表紙から開始・結果から再挑戦

## 始め方

| コマンド | 何をするか |
|---|---|
| `make run` | ゲームを起動する |
| `make debug` | Doc の保存即反映と F8 注釈を有効にして起動する |
| `make check` | 型検査だけを行う |
| `make test` | ルールと JSON の橋渡しをテストする |
| `make palette` | Studio 用の色の写し(`assets/apex.palette.json`)を作り直す |
| `make bake` | 主要13場面と11の音を `gallery/` / `assets/sfx/` に焼く |
| `make bench` | `gallery/` と `golden/` をバイト比較する |
| `make golden` | 現在の `gallery/` を基準画像として祝福する |

## コースの6区間

1. 発進キャニオン — 幅広い道と無料の加速帯で速度を作る。
2. ネオンシケイン — 細い連続S字で細かなハンドルを要求する。
3. 長い高速旋回 — 道幅は広いが、片側へ大きく振られる。
4. トンネルヘアピン — ネオン骨格と電磁壁の中で、ブレーキ旋回を要求する。
5. 夜空の細橋 — 都市影が消え、反発壁と路肩ビーコンを頼りに大きくジャンプする。
6. 最終加速区間 — 広がるS字、ジャンプ台、加速帯から次周またはゴールへ戻る。

`assets/apex.course.json` の `rows` では `#` が通常路面、`=` がエネルギーを
使わない加速帯、`^` がジャンプ台、`[ ]` がエネルギーを失って弾かれる壁、
`.` が開いた路外です。路面の帯を左右へ動かすとカーブ、幅を変えると
走り方が変わります。一周の長さは
rows の数から自動で決まるため、コースを増減しても周回判定と表示がずれません。

## コードを読む順

このテンプレートは、遊べるゲームであると同時に教育用の土台です。
次の順で読むと、外部との接続から純粋なルールへ一段ずつ降りられます。

1. `src/Main.flix`
   - Doc、毎フレーム更新、描画、保存即反映を `App.game` へ接続する目次。
2. `src/World.flix`
   - `Title → Countdown → Racing → Finish / Crashed → GameOver` の進行と、加減速・順位・周回・損傷。
   - `tickRacing` のパイプが1フレームの処理順になっています。
3. `src/Course.flix`
   - 累積距離を道路の中心と幅へ変え、加速帯・ジャンプ台・壁の通過を読む唯一の座標変換。
   - World の路面判定と View の道路描画が同じ `Course.sample` を使います。
4. `src/Jump.flix`
   - 地上と空中の時間進行、高さの放物線だけを扱う純粋な小モジュール。
5. `src/Perspective.flix`
   - Course の断面を、地平線から手前までの疑似3D座標へ変換。
   - 道、ゲート、ライバルが同じ射影を共有します。
6. `src/View.flix` / `src/CityscapeView.flix` / `src/CarView.flix` / `src/SceneryView.flix` / `src/FxView.flix`
   - View は未来都市と空中コース、CarView は浮遊マシン、UiView は HUD と幕を担当。
   - CityscapeView は `apex.sprite.json` の遠景・近景を循環させ、層ごとの視差だけを担当。
   - SceneryView は `apex.scenery.json` の値を道路断面へ投影し、平らな回路平原を作ります。
   - FxView は爆発だけを担当し、演出をWorldへ漏らしません。
7. `src/AudioView.flix` / `src/AudioSystem.flix` / `src/bake/SfxBake.flix`
   - AudioView は状態の変化から単発音を選び、AudioSystem は速度で低・高駆動音を混ぜます。
   - SfxBake はBGMを含む全音源を波形から生成します。
   - 録音素材に依存せず、音の設計とゲームの規則を分離した例です。
8. `src/Controls.flix`
   - 矢印と WASD を、アクセル・ブレーキ・ハンドルという意図へ変換。
9. `src/*Doc.flix`
   - JSON を fail-open で読み、安全な既定値へ倒す境界。
10. `src/bake/Bake.flix`
   - 実機と同じ描画経路で、決定的な主要場面を PNG に焼く脚本。

## Studio から調整できるもの

- `assets/apex.tuning.json`
  - 通常・ブースト最高速、加速、エネルギー消費と回復、ブレーキ旋回、路外の手触り、
    壁反発、転落までの路端距離、ジャンプ時間と高さ、ライバル速度、周回数、得点。
- `assets/apex.scenery.json`
  - 背景の振れ幅、遠景・近景の移動倍率、回路線の密度・太さ・位置、発光板の間隔、
    通常時とブースト時の速度線。
- `assets/apex.sprite.json`
  - 夜景そのもの。文字格子で星、遠い建物、手前の塔、窓明かりを描きます。
  - `far_city` と `near_city` を直すと、Flixコードを変えずに街の形が変わります。
- `assets/apex.course.json`
  - コースの曲がり方と道幅。rows を増減できます。
- `assets/apex.theme.json`
  - 夜空、路面、路肩、自機、ライバル、警告、文字の色。
- `assets/apex.palette.json`
  - Studio のドット絵エディタに「意味色キー → 実色」を教える写し（生成物・手で直さない）。
  - 夜景と回路の色はテーマから導いていて Studio からは見えないので、`make palette` で書き出し、
    `apex.sprite.json` の `paletteFile` から指します。色を変えるのは `apex.theme.json` 側です。
  - 回路模様は実機が道の左右で色を振り分けるので、写しに載るのは左側の代表色です。
- `assets/apex.copy.json`
  - 表紙、操作案内、HUD、結果画面の文言。

すべて `version` と schema を持ち、`project.json` の `editor.resources` に登録されています。
数値、色、文言は保存すると走行中へ即反映されます。コースの構造を保存した時だけは、
古い距離を別の道へ無理に継ぎ足さないため、安全に表紙へ戻ります。F1 でも全 Doc を読み直せます。

## エンジンへ昇格できる境界

このテンプレートは、既存の `PxSpriteDoc` / `PxSprite` / `Render` をそのまま使っています。
追加で共通化する候補は次の2点です。

- `PxPanorama`
  - 複数の文字格子スプライトを横へ循環させ、視点位置と移動倍率から層ごとの位置を返す。
  - レース以外でも横スクロール、街の背景、室内の窓景色に使えます。
- `ProjectedPattern`
  - 奥・手前の断面列へ、JSONの線位置・間隔・発光板を平面投影する。
  - 現在は道路の `Perspective.Slice` に依存するため、入力型を汎用化してから昇格する候補です。

ゲーム固有のコース記号や損傷規則はテンプレートへ残し、循環・視差・平面投影だけを
エンジン候補にするのが境界です。

## テストと絵の役割

テストは次の2種類だけに絞っています。

- ゲームの規則・進行・収支
  - 加速、ブレーキ、自然減速、路外、転落、壁反発、空中、追い抜き、順位、周回、結果の固定。
- JSON とプログラムの橋渡し
  - 壊れた JSON、1項目の上書き、rows の増減、危険値の既定値化。

機体の傾き、バーナー長、道路の遠近、背景の循環、発光の大きさはテストしません。見た目は次の13枚を
`make bake` で焼き、目視と golden 比較で守ります。

- `title.png`
- `countdown.png`
- `race_boost.png`
- `panorama_left.png`
- `panorama_right.png`
- `race_offroad.png`
- `checkpoint.png`
- `sky_bridge.png`
- `race_jump.png`
- `wall_bounce.png`
- `crash.png`
- `game_over.png`
- `finish.png`

## 意図的に入れていないもの

逆走、ドリフト、車種選択、セーブ、着地損傷、複雑な上下物理は入れていません。
ゲームの核とコードの責務を読みやすく保ち、別のレースへ育てる余地を残すためです。
