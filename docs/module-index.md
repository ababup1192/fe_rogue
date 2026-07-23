# engine_world モジュール索引

「やりたいこと」からモジュールを引くための逆引きと、全モジュールの 1 行紹介。
各モジュールの詳しい説明は `engine_world/src/<名前>.flix` 冒頭の doc コメントにある。

## やりたいこと → モジュール

| やりたいこと | モジュール |
|---|---|
| メニューを作る（項目列・カーソル・ハイライト） | UiMenu |
| 窓より長い内容をスクロールで覗く（ログ・履歴・一覧） | UiScroll |
| 描画物を矩形で切り抜く（スクロール窓・PiP。スクリーン空間） | Render（clipped / clippedAll） |
| 文章を幅で行に折る・描く前に行数を数える | RichText（wrapLinesBy） |
| ホイールの生 delta を目盛りに畳む | InputMap（wheelSteps） |
| 固定スロットに可変個の項目を流し込む | UiSlots |
| UI を JSON（ui.json）で宣言する | UiDoc / UiSpec |
| UI の箱にドット絵の皮を着せる（九分割スキン。box の skin） | UiExtract（boxPlacedItems）/ UiDoc |
| UI 要素を並べる・整列する | UiLayout / Flex |
| UI の文字欄に実行時の値を差し込む | UiBinding |
| 会話窓・文字送りを出す | UiDialog / UiTypewriter |
| マウスの下の UI 要素を知る | UiFocus |
| meta "prefix/N" から番号を読む | UiMeta |
| 粒を舞わせる | Fx / Scatter |
| 爆発・火花を fx.json で宣言して時刻から描く | FxDoc / Fx（sample / sampleAt） |
| 撃つたびに出る効果を発生・寿命回収・描画で回す | Fx（burst / expire / drawAll） |
| 値を滑らかに動かす | EcsTween / Curve |
| スプライトをコマ送りする | Anim |
| ドット絵を文字格子(*.sprite.json)で宣言して描く | PxSpriteDoc / PxSprite |
| 一続きの振り付け(歩く→拾う→戻る)の現在区間を時刻から引く | Timeline |
| 経路(脚の列)の現在地・歩き量・到着を時刻から引く | Journey |
| 一定間隔で合図を出す・残り時間を数える | Clock |
| 巻き戻し・リプレイ・履歴 | Worldline |
| セーブ・ロード | SaveManager / Persistence |
| タイルのマス目と移動範囲 | Grid / GridSearch |
| タイルセット PNG(LDtk 互換)でマップを貼る | MapResource |
| チップ絵なしでマップ地形(壁・水)を多角形で描く | DualGrid / Material |
| rows の文字格子から地形の見た目を作る(*.terrain.json) | Terrain / TerrainDoc |
| 重なり判定・物理 | Collision / Physics2D |
| 当たり判定を JSON で宣言する | HitDoc + Hit |
| キーが押された瞬間を取る | InputEdge |
| 複数キーを 1 つの操作にまとめる（WASD と矢印の両対応） | InputMap |
| カメラで寄せる・追いかける | CameraRig |
| 起動中のゲームを外から操作・観測する | RemoteDebug |
| Studio に「いま表示中の Doc」を名乗る（表示中バッジ） | ActiveDocs |
| 画面を覆う・晴らす切り替え演出（フェード・ワイプ） | Transition |
| 光らせる・暗く沈める（加算・乗算の重ね方） | Render（blended） |
| 縁がふわっと消える光球・煙玉を置く | Render（glowAt）/ fx.json の shape "glow" |
| 暗い部屋に光源を置く（穴あき暗幕+ハロ） | Light |
| 壁に影を落とす（単一光源のハードシャドウ） | Shadow |
| BGM をだんだん出す・消す・入れ替える（音量カーブ） | AudioFade |

## 土台（App・ECS）

- **App** — ゲームを「宣言」で組み立てて走らせるランナー。
- **EntityId** — entity を識別する番号（共有 ECS lib のトップレベル型）。
- **Query** — 部品ごとに分かれた表から「同じ物が持つ複数の部品」を突き合わせて取り出す。
- **Hash01** — 2 つの整数から 0 以上 1 未満のばらついた数を 1 つ決める（決定論の乱れ）。
- **RandomUtil** — 乱数の小さな操作。リストから 1 つ選ぶ・範囲内の実数を引く。

## 描画

- **Render** — 「何をどう見せたいか」だけ書いた Item を、描画部が食べられる形に変換する。
- **CameraRig** — world のどこを・どれだけ寄せて映すかを描画物の列に掛ける道具箱。
- **TextDraw** — 文字列を「中心をここに置きたい」で配置する。
- **RichText** — 一部だけ色や太さの違う文章をスパンの列として持ち、描画アイテムへ組む。
- **Quad** — 回転した矩形や太さのある線の、四隅の座標を計算する。
- **Bezier** — ベジエ曲線の平坦化と、曲線から作る描画部品。
- **Fx** — たくさんの粒を、保存せず「今の時刻から計算」して並べる薄い仕組み。「撃つたびに出る」効果の器（burst / expire / drawAll）も持つ。
- **FxDoc** — fx.json（閉形式パーティクル）を Spec に読むパーサ。絵は Fx.sample が導く。R3 で mode: loop（常時系）/ spawn（発生源の広がり）/ accel（重力/風・½at²）/ seed（決定的シードの上乗せ）/ parseWith（"@名前" の色キーをパレットで解決）を追加。
- **Scatter** — どこまでスクロールしても同じ配置が再現される、無限の「物の撒き方」。
- **Anim** — スプライトシートのコマ送りを「時刻の純関数」で導く。
- **PxSpriteDoc** — *.sprite.json（文字格子+意味色キー+名前付きコマ+anchor）を読む fail-open の Doc 層。
- **PxSprite** — PxSpriteDoc のコマを box 列（横連続の同色文字は 1 矩形に結合・既定）または drawQuad（アトラス 1 クアッド・opt-in）で描く。色は resolver（キー→実色）が解決。
- **PxSpriteAtlas** — PxSpriteDoc×resolver を 1 枚のアトラス画素（ARGB+コマ→矩形の目次）に焼く純関数。GL（RenderTexture.loadTextureFromPixels）と PNG（SoftRaster.writeRadialPng）が同じ Baked を読む。
- **Viewport** — 画面の矩形の外へ出た物を見つけて返す。
- **Transition** — 進行度 t から画面を覆う/晴らす描画物を作る（フェード・ワイプ）。
- **Light** — 光源の値（位置・半径・色）から穴あき暗幕+ハロの描画物を導く。
- **Shadow** — 光と壁の頂点列から影の四角形を導く（当たり判定の形からも作れる）。

## UI

- **UiDoc** — ui.json 方言の唯一のパーサ。JSON のノード木を Spec へ畳む。
- **UiSpec** — UiDoc の Spec を UiStore 向けに射影し、spawn / リロードを担う宣言層。
- **UiStore** — UI を作る「部品ごとの表」の束と、その足し引きの基本操作。
- **UiLayout** — 縦か横に並べる指定から、各 UI 要素の画面上の矩形を自動で決める。
- **Flex** — 宣言的なノード木を UiLayout でレイアウトし、描画物の列に落とす薄い汎用層。
- **UiWidget** — UI 要素の「見た目の中身」（箱・文字・スプライト）の属性と操作。
- **UiShape** — 図形 widget の共有語彙（circle / star / line などのパラメトリック図形）。
- **UiExtract** — 配置と表示可否が決まった UI を、描画部が食べられる絵の列に変換する。
- **UiRender** — UI 全体を毎フレーム、そのまま描ける絵の列に変換する入口。
- **UiHierarchy** — UI entity の親子ツリー走査（完全純粋）。
- **UiFocus** — マウス座標の下にある一番手前の UI 要素を見つけて返す。
- **UiBinding** — UI のテキスト欄に付けた「差し込み名」を実行時の値に置き換える。
- **UiSlots** — ui.json に用意した固定数のスロットへ、可変個の項目を先頭から流し込む。
- **UiMenu** — 選択メニュー共通の「項目の並べ方」「選択中の見せ方」「カーソルの動かし方」。
- **UiScroll** — 窓より長い内容を位置ひとつで覗く共通の勘定（末尾基準 offset・両端 clamp・▲▼判定）。
- **UiMeta** — UI の目印（meta 文字列）の共通の読み方（接頭辞 + 番号）。
- **UiDialog** — 会話窓の中身（誰が・何を・どこまで見せたか）と、その進め方。
- **UiTypewriter** — 文章を 1 文字ずつ現す「文字送り」の進み具合を持つ小さな値。

## 時間と動き

- **AudioFade** — 進行度 t から音量をひとつ決める（フェードイン・アウト・クロスフェード）。
- **Clock** — 経過時間を貯めて「一定間隔で合図」「残り時間を数える」を数値だけで扱う。
- **Curve** — 時間から値をひとつ計算する、状態を持たない小さな関数の詰め合わせ。
- **EcsTween** — 値をある値から別の値へ、時間をかけて滑らかに動かす（補間する）。
- **Journey** — 脚(出発点・行き先・速さ)の列を「時刻の純関数」で歩く。到着判定(done)と絵の位置(pos)を同じ戻り値で返す。
- **Motion** — 物の動かし方の小さな道具箱（等速移動と往復運動）。
- **Timeline** — 区間(名前+長さ)の列を「時刻の純関数」でサンプルする。範囲外は None = 終わり。

## 盤面

- **Grid** — 正方タイルの「何列目・何行目」と画面上のピクセル位置を相互に変換する。
- **GridSearch** — マス目の上で「どこまで行けるか・何歩かかるか・どこが射程か」を求める。
- **Dir4** — 上下左右の 4 方向を 1 つの値としてまとめて表す。
- **MapResource** — タイルセット PNG(LDtk 互換)でマップを貼る。チップ絵なしの並立経路は DualGrid / Material(§3.3 の棲み分け)。
- **DualGrid** — セル4角の埋まり方から 16 ケースの地形多角形(丸/四角/ひし形/揺らぎ)を作る純幾何。
- **Material** — DualGrid のタイルに質感(塗り・フチ帯・持ち上げ・表面の粒)を着せる。チップ絵は使わない。MapResource が「タイルセット PNG を貼る」のに対し、こちらは「色と質感パラメータで手続き生成する」並立の経路。
- **Terrain** — 「どのセル文字に、どの質感を着せるか」の表と rows アダプタ。rows の文字格子を塗るだけで DualGrid の角の変化形が自動生成される。fromRows は Doc+rows だけで完結する教科書 API(実装例: rpg-starter)。
- **TerrainDoc** — セル文字→質感の表の宣言(*.terrain.json)を読む codec。色は #rrggbb か @キー(テーマ参照)。

## 物理・衝突

- **Physics2D** — 物理を「積分・検出・反射・分離」の 4 つの純関数に切り出して合成する。
- **Collision** — たくさんの物体の中から、実際に重なっている組を見つけて返す。
- **Hit** — JSON で宣言した形（円・箱の列）で「触れているか」だけを聞く照会専用の判定。
- **HitDoc** — 当たりの形の宣言（hitbox.json）を読む codec。欠け・間違いは位置付きで断る。

## データと保存

- **Persistence** — 値をディスクに保存し、また読み戻すための汎用のしくみ。
- **SaveManager** — セーブデータをスロット番号でファイルに保存・読み出しする薄い層。
- **Worldline** — World の軌跡（履歴・巻き戻し・リプレイ・分岐の土台）。
- **JsonCodec** — JSON の読み書きでよく使う小さなヘルパを 1 箇所に集める。
- **JsonCompat** — 標準 `Util.Json` への委譲層 + 宣言ドキュメント共通の読み方（version 確認・ファイル読み）。
- **EcsCodec** — 「番号ごとの値の表」を JSON と相互変換する共通ヘルパ。
- **Resource** — ゲーム独自のデータ型に「どんなフィールドがあり、どう編集するか」を宣言する。
- **CatalogContainer** — 「1 ファイル = 1 種類の一覧」を表す汎用の入れ物。

## 入力

- **InputEdge** — キーが「今まさに押された瞬間」か「押しっぱなし」かを見分ける。
- **InputMap** — 生のキーを「操作の意図」へ写す表。同じ意図に複数キーを並べられる（WASD と矢印の両対応など）。
- **Replay** — 入力の列を順番に tick へ流し込む（再現・自動操作）。

## デバッグ・開発

- **ActiveDocs** — 「いま表示に使っている Doc(JSON)はどれか」を debug/active-docs.json に名乗る（Studio の「表示中」バッジの窓口。同じ内容なら書かない）。
- **Annotate** — 実行中のゲームを一時停止して、画面の気になる場所を矩形で囲んで記録する。
- **RemoteDebug** — 起動中のゲームを外部プロセスが HTTP で操作・観測する口。POST /bake は App.onBakeRequest で登録した「焼きの実体」を温まった JVM で実行し、焼けたパス列を返す（プレイ状態には触れない）。
- **GameLogger** — 起きたことを 1 行ずつログに積み、あとでまとめて取り出す effect。
