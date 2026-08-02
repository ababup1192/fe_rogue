# engine モジュール索引

`engine/src` 側（core / render / トップレベル）の「やりたいこと」からモジュールを引くための
逆引きと、全モジュールの 1 行紹介。ゲームが日常的に触る `engine_world` 側の索引は
[module-index.md](module-index.md) を参照。ここに載っているのは主に engine_world の各モジュールが
内部で使う下請けの型・関数で、ゲーム側から直接触ることは少ない。
各モジュールの詳しい説明は `engine/src/<パス>.flix` 冒頭の doc コメントにある。

## 描画の 2 つの経路（Drawable と PlacedItem）

このエンジンには描画物を組み立てる経路が歴史的に 2 つある。

- **PlacedItem 経路**（`engine_world` の `Render.Item` + `App.withView`）。**新しく作るゲームは
  必ずこちら**を使う。位置つきの絵を値として返すだけの宣言的な組み方で、CameraRig・
  DualGrid・Fx など engine_world の道具はすべてこの経路の上に乗る。
- **Drawable 経路**（`engine/src/render/Camera.flix` と `Projection.flix`、および
  `view = None` で `GameEngine.Drawable` を自分で組むゲーム）。**examples/fe_rogue だけが
  使う古い経路**で、新規のゲームでは使わない。Sprite / Rect / Polygon / Arc / Text /
  TileLayer / Tileset / Transform / Visual といった `render/` 配下の描画物の型も、
  もともとはこの経路のノード型（Godot のノードに近い作り）で、PlacedItem 経路は
  これらを直接は使わず `core/DrawCmd` を土台に `Render.Item` を組む。
  例外は **Text** だけで、PlacedItem 経路の文字描画も内部で `Text.toDrawables` に
  委譲する共有の下請けになっている。

**BootFontData.flix は生成物**（`make boot-font` で焼き直す）。手で編集しない。

## やりたいこと → モジュール

| やりたいこと | モジュール |
|---|---|
| ゲームとエンジンの境界の共有型・効果（描画・入力・音・時間）を知りたい | GameEngine |
| 効果音・BGM の再生／停止の低レベル効果口を知りたい（`GameEngine.Audio`） | GameEngine（Audio 効果）/ AudioStreamPlayer（engine_world 側の呼び口。詳しくは [audio.md](audio.md)） |
| WAV ファイルの中身（形式・波形データの位置）を読み解きたい | AudioUtil |
| engine の fpkg 読み込みを consumer 側で trigger したい | EngineSentinel |
| project.json を読み込んでエンジン設定と scene 一覧を得たい | ProjectLoader |
| 面をシェーダーで塗る「宣言データ」の型そのものを知りたい | ShaderDoc |
| シェーダー宣言を GLSL のソースへ変換する仕組みを知りたい | ShaderGen |
| シェーダーの式を GPU なしで検証したい（テスト用） | ShaderEval |
| shader.json を読み書きしたい | ShaderJson |
| シェーダー面を描く GPU 側の効果口を知りたい | ShaderEffect |
| 位置ベクトルの足し引き・長さ・回転を計算したい | Vec2 |
| マス目やピクセルなど整数の (x, y) を計算したい | Vec2i |
| 矩形の当たり・包含・膨張を計算したい | Rect2 |
| 色（sRGB-linear）を作る・GL の uniform に渡したい | Color（core 側の基礎型。ゲーム側の色操作は engine_world の Color を参照） |
| 時間の長さ（継続・経過・残り）を型で扱いたい | Duration |
| 1 フレームぶんの描画命令の共通の型を知りたい | DrawCmd |
| GPU が割り当てるリソース（VAO・テクスチャ id）を型で包みたい | GpuHandle |
| フォントアトラスのメタデータの型を知りたい | FontAtlas |
| フォントに焼き込む常用漢字・UI 記号の一覧が欲しい | JoyoKanji |
| 親の枠の中で子をどこに置くか名前で選びたい（中央・右下など） | Anchor |
| 文字列の改行・折り返し・中央寄せの座標計算をしたい | TextLayout |
| 凹みのある多角形を三角形に分割したい | Triangulate |
| GL の uniform に渡す前の数値変換・丸めをしたい | RenderUtil |
| 0〜1 に収める・小数部だけ残す（core 側の基礎計算） | Num |
| 起動画面（ロゴ+ゲージ）を組み立てたい | Splash |
| 起動画面の組み込みフォント・ロゴを使いたい | BootFont（素データは BootFontData。生成物なので手で触らない） |
| 円弧・リングを描きたい（Drawable 経路） | Arc |
| 単色の多角形を塗りたい（Drawable 経路） | Polygon |
| 単色矩形・枠線・角丸を描きたい（Drawable 経路） | Rect |
| スプライト 1 枚を表示したい（Drawable 経路） | Sprite |
| 名前つきのコマ送り素材集を持ちたい（Drawable 経路） | SpriteFrames |
| 文字を 1 文字ずつグリフに分けて描きたい（両経路が使う共有の下請け） | Text |
| タイルの格子を 1 層まとめて描きたい（Drawable 経路） | TileLayer |
| タイルセット画像からマスを切り出す設定を持ちたい（Drawable 経路） | Tileset |
| 位置・回転・スケール・せん断をまとめて持ちたい（Drawable 経路の値部品） | Transform |
| 色変調・可視性・重なり順をまとめて持ちたい（Drawable 経路の値部品） | Visual |
| 当たり判定の幾何形状（矩形・円・カプセル・坂）を計算したい | CollisionShape2D |
| 今フレーム押されているキー・マウスボタンの集合を取りたい | InputEvent |
| HUD を本体より確実に手前に出す zIndex の基準が欲しい | CanvasLayer |
| Drawable 経路のカメラ・投影を知りたい（fe_rogue 以外では使わない） | Camera / Projection |

## 土台

- **GameEngine** — ゲームとエンジンの境界に置く共有の型（描画データ・キー・色など）と、副作用の窓口（描画・入力・音・時間の取得）をまとめて定義する。各ゲームはここの型とエフェクトだけを見れば、内部実装を知らずに描画や入力を組める。
- **EngineSentinel** — engine fpkg のロードを consumer 側で trigger するためのモジュール。
- **EngineSentinel.Marker** — EngineSentinel が使う印だけの小さな型。

## シェーダー

- **ShaderDoc** — 面（矩形）を GPU シェーダーで塗るための「宣言データ」。生の GLSL を書かず、少数の部品（値の場・色・出力）を組み合わせて水面のような連続した見た目を作る。部品の型（Spec）を持つ。
- **ShaderGen** — Spec を GLSL の fragment シェーダー文字列へ変換する codegen。各部品が自分の GLSL 片（式）を返し、compile が 1 枚の main() に繋ぐ。出力は決定論なのでスナップショットで釘打ちできる。
- **ShaderEval** — Spec 木を CPU（Float64）で評価する検証用の純関数。描画経路ではなく、式の構造が GLSL 側と揃っているかをテストで確かめるために使う。
- **ShaderJson** — シェーダー面の宣言（ShaderDoc.Spec）を JSON と相互変換する codec。engine を触らず `*.shader.json` の保存だけで調整できる（App.watchFile によるホットリロードの受け皿）。
- **ShaderEffect** — 宣言シェーダー面を GPU で描くための別チャンネルの効果口（`eff Shader`）。`eff Game` に描画オペを足すとハンドラ全てが波及するため、シェーダー面だけ別効果に切り出している。

## core（基礎の値と計算）

- **Anchor** — 親の枠の中で子をどこに置くか（左上・中央・全面など）を、決まった型で選ぶ。
- **AudioUtil** — 音声ファイル（WAV）の中身を読み解くための小さな計算。形式（モノラル/ステレオ・ビット数）の判別や波形データの在り処探しを一箇所にまとめる。実際のファイル読み込みや再生はしない。
- **Color** — 3 チャンネル sRGB-linear カラー（Float32・0.0〜1.0）。GL の uniform に直接渡せる。
- **DrawCmd** — 1 フレームぶんの描画命令の型。フロント（engine のシーングラフ）が組み立て、バックエンド（GL 描画・SoftRaster）が消費する共有の型。
- **Duration** — 時間の長さ（継続時間・経過時間・残り時間）を表す型。
- **FontAtlas** — フォントアトラス型定義。STBTruetype で焼き込んだフォントビットマップのメタデータを保持する。
- **GpuHandle** — バックエンドが割り当てる描画リソースのハンドル（タイル VBO やテクスチャの実体を 1 枚の型で包む）。
- **JoyoKanji** — フォントアトラスにベイクする常用漢字 + UI 記号のコードポイント列。
- **Num** — 数の小さな道具（0〜1 に収める・小数部だけ残す・周期で折り返す）。書き方の揺れをなくすため 1 箇所にまとめる。
- **ProjectLoader** — project.json を読み込んで engine 起動用の設定 + scene ファイル列挙を提供する。engine / examples が共通で読む唯一の真実。
- **Rect2** — 2D の矩形を「左上の座標」と「幅・高さ」で表し、当たり・包含・膨張などを計算する。
- **RenderUtil** — 描画に使う数値変換ヘルパー。GL の uniform やシェーダに渡す前の Float32 変換・丸め・三角関数をまとめる。
- **TextLayout** — 文字列の一文字ずつを、どこに置くか（改行・折り返し・中央寄せ）を計算する。
- **Triangulate** — 単純多角形（自己交差しない・凹あり可）を三角形の列に分割する耳切り法。GL の塗り（GL_TRIANGLES）と SoftRaster（スキャンライン）の絵を一致させるための芯。
- **Vec2** — 2D の位置や向きを表す (x, y) の組と、その足し引き・長さ・回転などの計算。
- **Vec2i** — 整数の (x, y) の組に対する足し引きなどの計算。マス目やピクセルの位置を丸め誤差なく扱える。

## render（描画物・Drawable 経路の部品）

- **Arc** — 円弧・リングを描く描画物。中心から半径・太さのリングを、開始角から終了角まで単色で塗る。
- **BootFont** — 起動画面が使う組み込みフォントとロゴを、埋め込みデータ（BootFontData）から組み立てる。ゲームのフォントは起動時にまだ焼けていないため、起動画面専用に持つ。
- **BootFontData** — 生成物。手で編集しない（`make boot-font` で焼き直す）。Splash が使う組み込みフォントとロゴの素データ。
- **Camera** — Drawable 経路（`view = None` で renderCommands を自前で組むゲーム。fe_rogue が実例）専用のカメラ部品。PlacedItem 経路は `App.withCamera` / `App.withZoom` + `CameraRig` を使うので、そちらでは使わない。
- **CanvasLayer** — HUD やオーバーレイを本体より手前に重ねるための描画レイヤー番号の基準。レイヤー番号 × layerStride を zIndex に加算する。
- **CollisionShape2D** — 当たり判定に使う 2D の幾何形状（矩形・円・カプセル・坂）。形状同士の重なり・点の内外・押し出しベクトルの計算をまとめて持つ。
- **InputEvent** — 現在フレームで押されているキー・マウスボタンをまとめて取得する。押下エッジは呼び側が前フレームと差分して取る。
- **Polygon** — 局所座標の単純多角形を単色（color + alpha）で塗り潰す描画物。
- **Projection** — Drawable 経路専用の投影部品（ワールド座標→画面座標）。PlacedItem 経路は CameraRig が同じ役割を担う。
- **Rect** — テクスチャなしで単色の矩形を描く描画物。枠線・角丸・45° の斜線ハッチも指定でき、枠付きパネルもこれ 1 つで描ける。
- **Splash** — 起動画面 1 枚ぶんの絵を組み立てる。読み込みの間、何も描かれない時間が「固まった」ように見えるのを防ぐ。
- **Sprite** — テクスチャを 1 枚表示するだけの軽い描画物で、見た目（visual）と座標変換（transform）を持つ。
- **SpriteFrames** — 名前つきのパラパラ漫画（アニメーション素材）をまとめて持つリソース。AnimatedSprite2D が参照する素材置き場。
- **Text** — テキストを 1 文字ずつグリフに分けて描画する描画物。Drawable 経路・PlacedItem 経路の両方が使う共有の下請け（PlacedItem 側は engine_world の Render が内部で `Text.toDrawables` を呼ぶ）。
- **TileLayer** — 格子状に並べたタイルの層を 1 枚まとめて描く。大量のタイルを 1 回の描画でまとめて出せる。
- **Tileset** — タイルセットのアトラス元。1 枚のタイル画像と、そこからマスを切り出す設定（texWidth / texHeight / tileSize）を持つ。
- **Transform** — 2D の位置・回転・スケール・せん断をまとめた値部品。描画型はこれを埋め込んで座標変換を共有する。
- **Visual** — 描画の見た目（色変調・可視性・重なり順）をまとめた値部品。
