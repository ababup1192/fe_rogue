# engine_world モジュール索引

「やりたいこと」からモジュールを引くための逆引きと、全モジュールの 1 行紹介。
各モジュールの詳しい説明は `engine_world/src/<名前>.flix` 冒頭の doc コメントにある。
これは `engine_world`（ゲームが直接触る土台）の索引。エンジンの奥（`engine/src`）の索引は
[engine-module-index.md](engine-module-index.md) を参照。

**初学者向け概念ノート**（黒箱に見えがちな再利用パーツを1画面で解説）:
- `docs/dual-grid.md` — チップ絵なしでマップ地形を描く仕組み（DualGrid / Material / Terrain の分業と「角の4セル→16ケース」）。
- App のゲームループ（更新系システムで進める → view で描く の2役割と1周の順）は `engine_world/src/App.flix` 冒頭の doc を参照。
- 座標→[0,1) の決定的なばらつき（乱数を使わない理由 = golden 決定性）は `engine_world/src/Hash01.flix` を参照。

## 矩形だけの画面から脱する（絵の下限）

`Render.box` を並べただけの画面は未完成。求めるのは次の 4 つの**性質**で、**どの画風で
満たすかは自由**（画風はゲームごとに決める。詳しくは `.claude/skills/visual-dict`、
シェーダーの語彙は [shader-doc.md](shader-doc.md)）。下は手の一例。

| 満たす性質 | 手の例 |
|---|---|
| 面に階調か質感がある | ShaderDoc + Render.shaderFill / Render.vgrad・gradPolygon / Material（粒・きらめき・染み）/ Render.striped・checker / PxShade のディザ |
| 主役が背景から分離して読める | PxShade（ふち光・接地影）/ Render.glowAt / Render.outline / 明度差・色相差 |
| 層が分かれている（奥・主役・手前） | Render.zShifted・zShiftedAll / Depth / Transition の覆い |
| 時間が流れている | Fx・FxDoc（粒）/ Sway（揺れ）/ Anim（コマ替え）/ Scatter / Daylight |

光と影で色そのものを分けたいときは **Color.warm / Color.cool**。

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
| 宣言した UI の「名前 → 画面上の矩形」を引く（当たり判定を宣言と共有） | UiDoc（rectsOf / renderWithRects）/ Flex（keyed） |
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
| イベントシーン(カット列)を世界の状態を見ながら順に演じる | SceneSeq |
| 一定間隔で合図を出す・残り時間を数える | Clock |
| 一過性演出（発火→寿命）の経過・進行・生存を時刻から引く | Lifetime |
| 巻き戻し・リプレイ・履歴 | Worldline |
| セーブ・ロード | SaveManager / Persistence |
| タイルのマス目と移動範囲 | Grid / GridSearch |
| 敵を追わせる・逃がす・ふらつかせる(距離場の 1 歩) | Steering |
| タイルセット PNG + 自前の map.json でマップを貼る | MapResource |
| チップ絵タイルを 1 draw call で敷く(焼き置き・マスごとの照明色 tint・屋根や庇は zIndex で手前にも) | App.withTileLayers / TileScene |
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
| 面を画素ごとの計算で塗る（動く霧・水面・溶岩・vignette。単色 box の置き換え） | ShaderDoc + Render（shaderFill / shaderFillMasked）→ [書き方](shader-doc.md) |
| シェーダー面を多角形の形に抜く（池・水たまり） | Render（shaderFillMasked） |
| 光らせる・暗く沈める（加算・乗算の重ね方） | Render（blended） |
| 絵を傾ける・集まりを丸ごと傾ける（カードの傾き・振り子） | Render（turned / turnedAll）/ ui.json の rotation |
| ドット絵のコマの大きさを知る（当たり・置き場所を絵に追随させる） | PxSprite.sizeOf / PxSpriteDoc.gridSizeOf |
| 文字の並び（rows）の大きさを測る・1 マスずつほどく | Grid.dimsOfRows / Grid.cellsOfRows |
| 0〜1 に収める・小数部だけ残す・周期で折り返す（負の値も安全） | Num.clamp01 / clamp / fract / wrapTo / lerp |
| 床丸め・最近整数（0.5 は上へ）で Int32 に落とす（負の座標もマスが揃う） | Num.floorInt / roundInt |
| 素の中心＋幅高の箱どうし・点×箱の重なりを聞く（接するのは外） | Hit.boxBox / pointBox |
| スプライトが無い・読めないとき仮色の板に倒す（穴を開けない） | Render.orBoxAt |
| Doc の一覧を台帳 1 枚にし watchFile・一括リロード・表示中バッジを導出 | DocTable |
| 色を作る（0〜1・0〜255・#rrggbb）・2 色を混ぜる・比べる | Color.rgb / rgb8 / hex / mix / channels |
| 置き場所つきの絵に修飾を掛ける・列を丸ごと薄くする | Render.overItem / Render.fadeAll |
| Doc を fail-open で読む（読めない・壊れは既定値へ） | DocJson.loadOr / decodeObject |
| 太さのある線・棒を引く（法線を手計算しない） | Render.lineSeg / Quad.strip |
| 値を範囲に収める（1 軸） | Num.clamp（カメラの寄せ幅は CameraRig.clampAxis） |
| 色を明るく・暗くする | Color.lighten / Color.darken |
| 文字を中央に置く・幅を測る | TextDraw.centered / TextDraw.width |
| 文字格子から 1 種類の文字のマスを集める | Terrain.cellsOf |
| テスト用の入力フレームを組む | App.frameOf |
| 焼いた絵に出ない指定を知る（実機との食い違い防止） | SoftRaster（dropped）/ [対応表](backend-parity.md) |
| 縁がふわっと消える光球・煙玉を置く | Render（glowAt）/ fx.json の shape "glow" |
| 空・水面・光の帯のグラデを 1 部品で塗る（頂点色つき凸ポリゴン。1px の色帯を積まない） | Render（gradPolygon / vgrad） |
| 箱に枠線を付ける（半透明の枠も） | Render（outline / outlineA） |
| 暗い部屋に光源を置く（穴あき暗幕+ハロ） | Light |
| 光源を JSON で宣言する（light.json） | LightDoc + Light |
| 壁に影を落とす（単一光源のハードシャドウ） | Shadow |
| 夜のガラス・鏡・磨いた床に姿を映す（明るいところは光として返し、暗いところは影として重ねる） | Mirror |
| 効果音を鳴らしたい | App.withAudio（前後 World の差分から鳴らす名前の List を返す。詳しくは [audio.md](audio.md)） |
| BGM を流す・止める・音量やループを変える | AudioStreamPlayer（play / stop / setVolume / setLooping。詳しくは [audio.md](audio.md)） |
| BGM をだんだん出す・消す・入れ替える（音量カーブ） | AudioFade |
| 効果音の素材を録音なしで作りたい（波形合成） | SfxSynth（engine_tools。詳しくは [audio.md](audio.md)） |
| 揺れる演出を作る（浮遊・風のなびき） | Sway |
| リソース JSON の形（型・必須・既定値）を公式スキーマ方言で宣言する | Schema |
| 見下ろしで「足元が下にある物ほど手前」に並べる（人が木の裏に回る） | Depth |
| ゲームの中の時計と暦を回す（分・時・日・季節・年） | Calendar |
| 時刻で世界の色を変える（朝の青・夕の橙・夜の紺）・影の向きと長さを回す | Daylight |
| ドット絵の塗りに光を当てる（ふち光・接地影・ディザ・地肌の粒） | PxShade |
| 見下ろしの落ち影を置く（接地の暗がり + 時刻で回る日影） | Daylight.groundShadow |
| 見えている範囲に重なるマスだけ並べる（盤が広くても仕事は画面ぶん） | Grid.cellsIn |
| ドット絵を握るところで回す・左上でそろえて並べる | PxSprite.drawQuadTurned / drawQuadTopLeft |
| 走行中に焼いた絵を bake でも同じ絵にする | Bakery.imagePngs / imageTextureInfo |
| 光側は暖色・影側は寒色へ寄せて階調を増やす | Color.warm / Color.cool |
| 焼いたドット絵アトラスを名前付きテクスチャとして使う（1 体 = 1 クアッド） | App.withSpriteAtlases |
| ドット絵の輪郭をにじませない（カメラと頂点を画素の升目に載せる） | App.withPixelSnap / Render.snapped |
| 同じ絵を色だけ変えて使い回す・重なり順をまとめてずらす | Render.tinted / Render.zShifted |
| マスごとの「いま」を持つ（耕した・濡れた・置いた。セーブに乗る側） | TileState |

## 土台（App・ECS）

- **App** — ゲームを「宣言」で組み立てて走らせるランナー。
- **EntityId** — entity を識別する番号（共有 ECS lib のトップレベル型）。
- **Query** — 部品ごとに分かれた表から「同じ物が持つ複数の部品」を突き合わせて取り出す。
- **Hash01** — 2 つの整数から 0 以上 1 未満のばらついた数を 1 つ決める（決定論の乱れ）。
- **RandomUtil** — 乱数の小さな操作。リストから 1 つ選ぶ・範囲内の実数を引く。

## 描画

- **Render** — 「何をどう見せたいか」だけ書いた Item を、描画部が食べられる形に変換する。
- **CameraRig** — world のどこを・どれだけ寄せて映すかを描画物の列に掛ける道具箱。
- **Depth** — 見下ろし画面で「足元が下にある物ほど手前」を重なり順（zIndex）の数として決める。
- **Daylight** — 1 日の進み（0〜1）から「空気の色」と「太陽の位置」を決める。色は画面全体に乗算で薄く掛け、太陽からは影の向き・長さ（shadowAt）とドット絵に当てる光の向き（lightStepAt）を導く。暗さ（darkness）を読めば、明かりの点灯と空の色が食い違わない。
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
- **PxShade** — 文字格子のドット絵に「塗りの仕上げ」を 1 度だけ掛ける純粋な filter（ふち光・接地影・ディザ・地肌の粒）。絵は平らに塗り、光の当て方は後から重みで指定する。掛けるのは読み込み直後の 1 回だけなので走行中の負荷は増えない。
- **PxSpriteAtlas** — PxSpriteDoc×resolver を 1 枚のアトラス画素（ARGB+コマ→矩形の目次）に焼く純関数。GL（RenderTexture.loadTextureFromPixels）と PNG（SoftRaster.writeRadialPng）が同じ Baked を読む。
- **Viewport** — 画面の矩形の外へ出た物を見つけて返す。
- **Transition** — 進行度 t から画面を覆う/晴らす描画物を作る（フェード・ワイプ）。
- **Light** — 光源の値（位置・半径・色）から穴あき暗幕+ハロの描画物を導く。
- **Shadow** — 光と壁の頂点列から影の四角形を導く（当たり判定の形からも作れる）。
- **Mirror** — 面（夜のガラス・鏡・磨いた床）に映る姿を、ドット絵の走り（PxSprite.Run）から組む。映り込み用の絵を別に描かないので、元の絵を直せば映るほうも一緒に直る。映るかどうかと、どのコマをどこへ合わせるかは呼び側の決めごと。
- **LightDoc** — light.json（光源の質感）の宣言層。暗さ・照り返しフチ・ハロの大きさ・光源の並びを JSON に書き、Spec へ畳む。壁の遮蔽形はゲームの World が持つので含まない。

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
- **Calendar** — ゲームの中の時計と暦。実時間の秒を分・時・日・季節・年へ畳み、日またぎを合図する。
- **Clock** — 経過時間を貯めて「一定間隔で合図」「残り時間を数える」を数値だけで扱う。
- **Lifetime** — 一過性のもの（発火して時刻で進み寿命で消える）の「誕生時刻＋長さ」から経過・進行(0..1)・残り・生存を now の純関数で導く。得点ポップ等の表示期間や Fx.Burst の寿命に使う（now から導くので巻き戻しに強い）。
- **Curve** — 時間や進行度から、放物線の山・周回・揺れなどの値を計算する、状態を持たない小さな関数の詰め合わせ。
- **EcsTween** — 値をある値から別の値へ、時間をかけて滑らかに動かす（補間する）。
- **Journey** — 脚(出発点・行き先・速さ)の列を「時刻の純関数」で歩く。到着判定(done)と絵の位置(pos)を同じ戻り値で返す。
- **Motion** — 物の動かし方の小さな道具箱（等速移動と往復運動）。
- **Timeline** — 区間(名前+長さ)の列を「時刻の純関数」でサンプルする。範囲外は None = 終わり。履歴・巻き戻しは Worldline（別物）。
- **SceneSeq** — カット列の逐次シーケンサ骨格。perform（カットを 1 コマ演じる）と idle（尽きたあと時間だけ流す）を注入し、Skip・打ち切りは notes に残す（fail-open だが無音ではない）。
- **Sway** — 時刻から微小な揺れを作る純粋な道具（蓮の葉の浮遊・草や旗の風・吊るした物）。一様にずらせば浮遊（drift）、高さに比例して曲げれば根が止まって先だけしなる（wave）。掛け方は呼び側が決める。

進行 4 抽象の分業（どれも「列を順に消化する」が、決め手が違う）:

| 抽象 | 決め手 | 向く場面 |
|---|---|---|
| Timeline | 尺が既知。時刻 t から現在区間を引くだけの純関数 | 振り付け（歩く→しゃがむ→戻る） |
| Journey | 脚の列（出発点・行き先・速さ）の時刻純関数 | 経路の現在地・到着判定 |
| Replay | 入力が固定。入力列を tick へ流す再生 | プレイの再現・自動操作 |
| SceneSeq | 世界を見て尺が決まる再生。終わりは世界の状態から判定 | イベントシーン（カット列） |

## 盤面

- **Grid** — 正方タイルの「何列目・何行目」と画面上のピクセル位置を相互に変換する。
- **TileState** — マス目の「いま」を持つ疎な表（耕した・濡れた・置いた）。日ごとの一斉更新とセーブの往復を持つ。地図の形（読むだけの設計図）とは置き場所を分ける。
- **GridSearch** — マス目の上で「どこまで行けるか・何歩かかるか・どこが射程か」を求める。
- **Steering** — 距離場（GridSearch）の 1 歩 chase / flee / wander。「入れるか」は canEnter で注入。敵 AI とイベントシーンが同じ 1 歩を使う。乱数を持たず同着は固定順 — 焼けば毎回同じ。
- **Dir4** — 上下左右の 4 方向を 1 つの値としてまとめて表す。
- **MapResource**（legacy/） — タイルセット PNG + 自前の map.json でマップを貼る旧世代層。新規は DualGrid / Material / TerrainDoc を使う(棲み分けは docs/dual-grid.md)。
- **TileScene** — App.withTileLayers のタイル層宣言(TileLayerSpec)を CPU 投影で普通の絵に畳む。headless bake・F8 停止画面・golden が GPU 焼き置きと同じ絵になるための橋。
- **DualGrid** — セル4角の埋まり方から 16 ケースの地形多角形(丸/四角/ひし形/揺らぎ)を作る純幾何。概念: docs/dual-grid.md。
- **Material** — DualGrid のタイルに質感(塗り・フチ帯・持ち上げ・表面の粒)を着せる。チップ絵は使わない。MapResource が「タイルセット PNG を貼る」のに対し、こちらは「色と質感パラメータで手続き生成する」並立の経路。
- **Terrain** — 「どのセル文字に、どの質感を着せるか」の表と rows アダプタ。rows の文字格子を塗るだけで DualGrid の角の変化形が自動生成される。fromRows は Doc+rows だけで完結する教科書 API(実装例: rpg-starter)。
- **TerrainDoc** — セル文字→質感の表の宣言(*.terrain.json)を読む codec。色は #rrggbb か @キー(テーマ参照)。

## 物理・衝突

- **Physics2D** — 物理を「積分・検出・反射・分離」の 4 つの純関数に切り出して合成する。
- **Collision** — たくさんの物体の中から、実際に重なっている組を見つけて返す。
- **Hit** — JSON で宣言した形（円・箱の列）で「触れているか」だけを聞く照会専用の判定。
- **HitDoc** — 当たりの形の宣言（hitbox.json）を読む codec。欠け・間違いは位置付きで断る。

## データと保存

新しい Doc（*.kind.json）を 1 つ足すときは、この順で使う:

1. **Schema** — 形を宣言する（`*.schema.json`。任意）
2. **`<X>Doc.flix`** — 型と fromJson/toJson を書く（decode は JsonCodec、エラー位置は DocJson.atNode）
3. **DocJson** — decodeObject で fromJson を 1 行に / loadOr で fail-open 読み
4. **DocTable** — 台帳に 1 行足す（watch・F1 リロード・表示中バッジが導出される）
5. **Persistence / EcsCodec** — セーブに乗る値だけ（表なら EcsCodec）

- **Persistence** — 値をディスクに保存し、また読み戻すための汎用のしくみ。
- **SaveManager** — セーブデータをスロット番号でファイルに保存・読み出しする薄い層。
- **Worldline** — World の軌跡（履歴・巻き戻し・リプレイ・分岐の土台）。時間区間の振り付けは Timeline（別物）。
- **JsonCodec** — 値 ⇄ JSON の純変換ヘルパ（expect 系 / encode・decode）。
- **DocJson** — Doc を読むときの JSON 道具箱。parse・デコード補助（atNode 等）と fail-open 読み込み（loadOr・checkVersion）。
- **EcsCodec** — 「番号ごとの値の表」を JSON と相互変換する共通ヘルパ。
- **Resource**（legacy/） — 旧世代のスキーマ方言。新規は Schema を使う（残り使用者は fe_rogue 系のみ）。
- **CatalogContainer** — 「1 ファイル = 1 種類の一覧」を表す汎用の入れ物。
- **Schema** — リソース（ゲームデータ JSON）の形を宣言する公式スキーマ方言（例: level.json の隣の level.schema.json）。データの形（type / required / default）はゲームも検証に使い、見せ方（widget）はエディタ専用でエンジンは開けない封筒として運ぶ。未知の type タグ・kind は黙って通さず Err にする。

## 入力

- **InputEdge** — キーが「今まさに押された瞬間」か「押しっぱなし」かを見分ける。
- **InputMap** — 生のキーを「操作の意図」へ写す表。同じ意図に複数キーを並べられる（WASD と矢印の両対応など）。
- **Replay** — 入力の列を順番に tick へ流し込む（再現・自動操作）。

## デバッグ・開発

- **ActiveDocs** — 「いま表示に使っている Doc(JSON)はどれか」を debug/active-docs.json に名乗る（Studio の「表示中」バッジの窓口。同じ内容なら書かない）。
- **DocTable** — Doc の台帳（id・パス・読み直し）1 枚から、watchFile の配線・一括リロード・ActiveDocs の名乗りを導出する。一覧の手写しを 1 か所に。
- **Annotate** — 実行中のゲームを一時停止して、画面の気になる場所を矩形で囲んで記録する。
- **RemoteDebug** — 起動中のゲームを外部プロセスが HTTP で操作・観測する口。POST /bake は App.onBakeRequest で登録した「焼きの実体」を温まった JVM で実行し、焼けたパス列を返す（プレイ状態には触れない）。
- **GameLogger** — 起きたことを 1 行ずつログに積み、あとでまとめて取り出す effect。
