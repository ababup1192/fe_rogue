# つくって学ぶ Sokoban（倉庫番）

> English version: [TUTORIAL.md](TUTORIAL.md)

Flix でゲームを作りながら、少しずつ概念を増やしていくチュートリアルです。
読者は Flix を初めて触るプログラマを想定しています。難しい用語は、それが**必要になった瞬間**にだけ導入します。

この章で扱うのは、たったひとつの考え方です:

> **あなたは「今このフレームに描きたい物のリスト」を返す関数を書く。エンジンがそれを毎フレーム画面に描く。**

これだけで最初の2章は進みます。状態も、履歴も、まだ出てきません。

各章にはその章時点の全コードを載せます。リポジトリには常に最新章のコードが入っています。

---

## はじめる前に

リポジトリのルートで一度だけライブラリを配布します（エンジン本体を `examples/sokoban/lib/` に届けます）:

```sh
make sync
```

ゲームを起動する（ウィンドウが開きます）:

```sh
cd examples/sokoban
java -XstartOnFirstThread -jar bin/flix.jar run
```

`Esc` またはウィンドウを閉じると終了します。まだ動かさず読むだけでも大丈夫です。

---

## 第0章 — Hello, Sokoban

**ねらい:** ウィンドウの中央に文字を1つ出し、「関数が絵のリストを返し、エンジンが毎フレーム描く」形を体験する。

コードは3ファイルです。`project.json` がウィンドウとフォントを決め、`Main.flix` が起動し、`Sokoban.flix` が「描きたい物」を返します。

### `project.json`（ウィンドウとフォント）

```json
{
  "title": "Sokoban",
  "designWidth": 320,
  "designHeight": 240,
  "windowWidth": 960,
  "windowHeight": 720,
  "windowScale": 3,
  "clearColor": {"r": 0.133333, "g": 0.125490, "b": 0.203922},
  "maxDeltaTime": 0.05,
  "textures": [],
  "fonts": [
    {"name": "default", "path": "assets/Xolonium-Regular.ttf", "fontSize": 60.0}
  ],
  "sounds": []
}
```

`designWidth` / `designHeight` は「ゲームの中の座標系」です。ここでは 320×240 の広さで考え、実際のウィンドウはそれを 3 倍に引き伸ばした 960×720 で開きます。だから座標は常に 320×240 の中で考えればよく、画面中央は `(160, 120)` です。

### `src/Main.flix`（起動）

```flix
def main(): Unit \ IO =
    if (GameEngine.ensureMainThread()) ()
    else {
        run {
            Sokoban.start(GameEngine.Game.getFontAtlas("default"))
        } with LwjglLayer.withProject(".")
          with Fs.FileRead.runWithIO
          with Fs.FileWrite.runWithIO
          with Fs.Glob.runWithIO
          with Fs.ModificationTime.runWithFileTime
          with Fs.FileTime.runWithIO
    }
```

いまは中身を丸暗記しなくて構いません。読み方だけ:

- `with LwjglLayer.withProject(".")` … `project.json` を読み、ウィンドウを開き、フォントを読み込む。
- `Sokoban.start(...)` … ここから自分たちのコードが始まる。`getFontAtlas("default")` で読み込んだフォントを渡している。

### `src/Sokoban.flix`（描きたい物 + 起動ループ）

```flix
mod Sokoban {

    // The function that returns "what to draw this frame".
    pub def frame(atlas: FontAtlas): List[GameEngine.Drawable] =
        let size = 28.0;
        let box = Label2D.measure(Label2D.make("Hello, Sokoban", atlas, size));
        let pos = {x = 160.0 - box#x / 2.0, y = 120.0 - box#y / 2.0};
        Render.draw((pos, Render.text("Hello, Sokoban", atlas, size, 100)) :: Nil)

    // Keep drawing the result of frame every frame until the window closes.
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            GameEngine.Game.renderCommands(frame(atlas), Nil, Nil);
            start(atlas)
        }
}
```

### 何が起きたか

- `frame` は**絵のリストを返すだけ**の関数です。何も変えず、何も覚えていません。`"Hello, Sokoban"` という文字を1つ、置きたい場所（`pos`）とともにリストにして返しているだけです。
- 場所の計算 `160.0 - box#x / 2.0` は「文字の幅の半分だけ中央から左に戻す」＝**中央そろえ**です。`Label2D.measure` が文字の実際の幅・高さを教えてくれるので、当てずっぽうでなく正確に真ん中へ置けます。
- `start` は「ウィンドウが閉じるか `Esc` が押されるまで、`frame` を呼んで結果を描き、また自分を呼ぶ」をくり返します。これがゲームの「毎フレーム」の正体です。**描く中身は `frame` にしかありません** — ループ自身は何を描くか知りません。

つまり、あなたが書き換えるのはほとんどいつも `frame` だけです。

### 試すこと

`frame` の `"Hello, Sokoban"`（2か所）を別の文字に変えて、もう一度 `... flix.jar run` してみましょう。ウィンドウの文字が変わります。ループには一切触れていないことに注目してください。

---

## 第1章 — 木箱を描く（部品を重ねて記号を作る）

**ねらい:** 単純な部品（四角形と多角形）を重ねるだけで、「木箱」と読める記号を画像なしで作る。

倉庫番といえば木箱（クレート）です。画像は使いません。木箱を木箱たらしめている特徴を思い浮かべてください — 板が並んだ面、まわりの枠、斜めの補強材。**その特徴を1つずつ単純な図形にして、重ね順を決めて置く**と、遠目には立派なクレートになります。ドット絵を打つ代わりに、コードで「記号」を組み立てるわけです。

### 色は DB32 パレットの役割名から選ぶ

色を決めるのは、実はゲーム作りで一番迷うところです。そこでこのプロジェクトでは **DB32（DawnBringer 32）** という 32 色で完成されたパレットを標準に採用します。「使える色は 32 色だけ」という制約が、配色の無限の選択肢を消してくれます — **制約が選択を楽にする**、という発想です。

ただしコードに `#8f563b` のような色コードを直接書くと、それが何のための色か分からなくなります。そこで `src/Palette.flix` に、DB32 の色を**役割名**（色名でなく用途名）で定義しておきます:

```flix
mod Palette {
    pub def cratePlank(): Color = {r = 0.560784f32, g = 0.337255f32, b = 0.231373f32}  // #8f563b
    pub def crateFrame(): Color = {r = 0.400000f32, g = 0.223529f32, b = 0.192157f32}  // #663931
    pub def crateSeam(): Color  = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c
    pub def crateBrace(): Color = {r = 0.850980f32, g = 0.627451f32, b = 0.400000f32}  // #d9a066
    pub def titleText(): Color  = {r = 0.933333f32, g = 0.764706f32, b = 0.603922f32}  // #eec39a
    // ... backgrounds, floors, the player: future roles are added the same way.
}
```

規約はひとつ:「描画コードは色リテラルを直書きせず、`Palette` の役割名だけを参照する」。こうすると、木箱の板の色を変えたくなったとき直す場所は 1 か所（`cratePlank`）だけです。

### 木箱の設計図

タイル 1 辺を `T`（ここでは 96px）として、部品は 5 種類。すべて `T` に対する比率で決めます:

| 部品 | 図形 | 色 | 寸法 |
|---|---|---|---|
| ベース板 | box 1 枚（全面） | cratePlank | T × T |
| 縦板の目地 | 等間隔の細い縦線 box 5 本 | crateSeam | 幅 ≈ T×0.04（内部が 6 枚の板に見える） |
| 斜め補強材 | 左下→右上の帯（凸4角形 3 枚） | crateBrace | 太さ ≈ T×0.18（両縁 T×0.03 は crateFrame） |
| 外枠 | 横板 2 枚 + 間に挟まる縦板 2 枚 | crateFrame | 太さ ≈ T×0.12 |
| 枠の目地・外周輪郭 | 細線 box 8 本 | crateSeam | 目地 ≈ T×0.02、輪郭 1px |

外枠は「一体の額縁」ではなく**板 4 枚が突き合わさった構造**に見せます。横板 2 枚を全幅で通し、縦板 2 枚をその間に挟む — そして板と板の境界に細い目地線を入れます。全幅の横目地 2 本の両端が、そのまま四隅の突き合わせ目地になります。最後に箱全体を 1px の暗い線で縁取ると、背景から浮かずに締まります。

**重ね順**も大事です: ベース → 縦目地 → 斜め帯 → 外枠 → 枠の目地・輪郭。外枠を斜め帯より後に描くから、帯の端が枠の下に潜って隠れます（端の形を整える必要がなくなる）。重ね順は各部品の `zIndex`（大きいほど手前）で指定します。

### `src/Sokoban.flix`（木箱を組み立てる）

```flix
mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Center of the 320x240 design resolution.
    def centerX(): Float64 = 160.0
    def centerY(): Float64 = 120.0

    // The crate is one 16px grid tile shown at 6x magnification: 96px square.
    def crateSize(): Float64 = 96.0
    def crateLeft(): Float64 = centerX() - crateSize() / 2.0
    def crateTop(): Float64 = centerY() - crateSize() / 2.0

    // Thickness of the outer frame rails.
    def railW(): Float64 = crateSize() * 0.12

    // Drawing order (zIndex): base plank -> vertical seams -> diagonal brace -> frame rails
    // -> frame joints and outer outline. The rails draw after the brace, so the brace's
    // extended ends tuck underneath them.
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5
    def zTitle(): Int32 = 100

    // ── The function that returns the list of things to draw ──
    pub def frame(atlas: FontAtlas): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let boxes = List.append(crateBoxes(), titlePlacement(atlas) :: Nil);
        (Render.draw(boxes), cratePolys())

    // ── The crate: a composition of boxes plus convex polygon strips ──

    /// Box parts: 1 base plank + 5 vertical seams + 4 frame rails + 4 frame joints + 4 outline edges.
    def crateBoxes(): List[Render.PlacedItem] =
        plank() :: List.flatten(seams() :: rails() :: frameJoints() :: outline() :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(): Render.PlacedItem =
        boxAt(crateLeft(), crateTop(), crateSize(), crateSize(), Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(): List[Render.PlacedItem] =
        let t = crateSize();
        let w = t * 0.04;
        List.map(i ->
            let x = crateLeft() + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, crateTop(), w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(): List[Render.PlacedItem] =
        let t = crateSize();
        let f = railW();
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// Frame joints: the border lines between the frame and the interior. The 2 full-width
    /// horizontal lines double as the butt joints at the four corners at their ends;
    /// the 2 vertical lines run only between them.
    def frameJoints(): List[Render.PlacedItem] =
        let t = crateSize();
        let f = railW();
        let w = t * 0.02;
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// Outer outline: a dark 1px (design resolution) line around the whole crate.
    def outline(): List[Render.PlacedItem] =
        let t = crateSize();
        let w = 1.0;
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.PlacedItem =
        ({x = x, y = y}, Render.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    def cratePolys(): List[GameEngine.PolygonRenderCmd] =
        let half = crateSize() * 0.09;    // half-width of the central band (0.18T thick)
        let edge = crateSize() * 0.03;    // thickness of one edge line
        braceStrip(-half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(-half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping.
    def braceStrip(o1: Float64, o2: Float64, c: Color, z: Int32): GameEngine.PolygonRenderCmd =
        let t = crateSize();
        let f = railW();
        let ext = t * 0.04;
        let bl = {x = crateLeft() + f, y = crateTop() + t - f};
        let tr = {x = crateLeft() + t - f, y = crateTop() + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { vertices = Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
                     Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
          color = c, alpha = 1.0f32, zIndex = z }

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))

    // ── Launcher: keep drawing frame until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let (drawables, polys) = frame(atlas);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            start(atlas)
        }
}
```

### 何が起きたか

- `frame` はやはり**描きたい物のリストを返すだけ**です。今回は種類が 2 つになりました — 四角形と文字のリスト（`Drawable`）に加えて、多角形のリスト（`PolygonRenderCmd`）。四角形は軸に平行な矩形しか描けないので、**斜めの帯だけは 4 つの頂点を自分で指定する凸多角形**で描きます。`start` は両方をまとめてエンジンに渡します。
- 木箱は部品 21 個（box 18 枚 + 多角形 3 枚）の重ね合わせです。1 つ 1 つは「色付きの四角」「色付きの平行四辺形」にすぎませんが、**比率と重ね順**が「木箱」という記号を作ります。
- `zIndex` が重ね順です。数字が大きいほど手前に描かれます。試しに `zRail` を `0` にすると、枠が帯の下に潜って、帯の延ばした端がむき出しになります — 「外枠を斜め帯より後に描く」のが効いていたことが分かります。
- 斜め帯は 3 枚の平行四辺形（中央の明るい帯 + 両縁の暗い線）です。3 枚とも**同じ中心線と方向ベクトル `d` を共有**し、法線 `n` 方向のオフセット範囲（中央は `-half..half`、縁はその外側 `edge` 幅）だけが違います。縁を「少し大きい帯を下に敷く」方式や上下ずらしで作らないのは、斜めの図形を垂直にずらすと**見かけの太さが場所によって揺れる**からです。法線方向に測れば太さはどこでも一定になります。
- 帯の中心線は内側の隅から `ext` だけ**外へ延長**してあります。延ばした端は後から描かれる外枠の下に潜るので、端の形を整える処理がそもそも要りません — 「上に描かれる物に隠してもらう」のも重ね順の応用です。
- 外枠の「板 4 枚」感は、レール本体でなく**目地線**が作っています。全幅の横目地 2 本の両端が四隅の突き合わせに見え、内側の縦目地 2 本が枠と内部を区切ります。仕上げの外周輪郭 1px が箱を背景から切り離します。
- サイズは倉庫番の 1 マス（16px）を 6 倍にした 96px 角。中央 `(160, 120)` に置くため、左上を「中央からサイズの半分だけ戻した点」にしています（文字の中央そろえと同じ考え方）。すべての寸法が `crateSize()` に対する比率なので、この 1 か所を変えれば木箱全体が正しく拡大縮小します。
- 色はすべて `Palette` 経由で、コードの中に生の色コードはありません。

第0章から増えた新しい考え方は「重ね順（zIndex）」ひとつだけです。「`frame` が描きたい物のリストを返し、エンジンが毎フレーム描く」という形は何も変わっていません。

### 試すこと

`cratePolys()` の `half`（帯の半幅）や `edge`（縁の太さ）を変えて `run` してみましょう。縁がどこでも均一な太さのまま、帯だけが太くなります。あるいは `crateSize` を `96.0` から `128.0` にすると、比率指定のおかげで箱全体が崩れずに大きくなります。

---

## 第2章 — 動かす: 状態はどこに住む？

**ねらい:** 木箱を画面の上で滑らせる — そして「変わり続ける値はどこに置くのか」を発見する。

木箱を動かしたい。毎フレーム x 座標を少しずつ増やし、右端から完全に出たら左端に戻ってくるようにしたい。

ここで、この章の存在理由である問いが生まれます。`frame` はリストを返すだけの関数で、呼び出しの間に何も覚えていません。**木箱の位置は、どこに覚えておくのでしょう？**

このコードベースの答え: 1 個の値に入れて、ループの中で持ち回る。その値を **World** と呼びます。

### `src/Sokoban.flix`（この章時点の全コード）

```flix
mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Design resolution 320x240 and its center.
    def designW(): Float64 = 320.0
    def centerX(): Float64 = 160.0
    def centerY(): Float64 = 120.0

    // The crate is one 16px grid tile shown at 6x magnification: 96px square.
    def crateSize(): Float64 = 96.0

    // Thickness of the outer frame rails.
    def railW(): Float64 = crateSize() * 0.12

    // Drawing order (zIndex): base plank -> vertical seams -> diagonal brace -> frame rails
    // -> frame joints and outer outline. The rails draw after the brace, so the brace's
    // extended ends tuck underneath them.
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5
    def zTitle(): Int32 = 100

    // ── World: where the state lives ──
    // One value that holds everything that changes. Save this value and you can
    // reproduce this exact moment of the game.
    pub enum World {
        case World({ crateX = Float64 })
    }

    pub def initialWorld(): World = World.World({ crateX = centerX() })

    // ── step: advances the world by one frame ──
    // No effect annotation = pure, and the compiler verifies that: the same World
    // always steps to the same next World.

    // Design px per frame. The crate slides right and wraps back in from the left
    // once it has fully left the screen.
    def crateSpeed(): Float64 = 1.0

    pub def step(w: World): World =
        let World.World(r) = w;
        let x = r#crateX + crateSpeed();
        let wrapped = if (x - crateSize() / 2.0 > designW()) -(crateSize() / 2.0) else x;
        World.World({ crateX = wrapped })

    // ── frame: projects the World into the list of things to draw ──
    // It only reads the world; drawing never changes anything.
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(r) = w;
        let center = {x = r#crateX, y = centerY()};
        let boxes = List.append(crateBoxes(center), titlePlacement(atlas) :: Nil);
        (Render.draw(boxes), cratePolys(center))

    // ── The crate: a composition of boxes plus convex polygon strips ──
    // Every part is placed relative to the crate's center, so one crate can be
    // drawn anywhere (the groundwork for drawing a whole board of tiles later).

    def topLeftOf(center: Vec2.Vec2): Vec2.Vec2 =
        {x = center#x - crateSize() / 2.0, y = center#y - crateSize() / 2.0}

    /// Box parts: 1 base plank + 5 vertical seams + 4 frame rails + 4 frame joints + 4 outline edges.
    def crateBoxes(center: Vec2.Vec2): List[Render.PlacedItem] =
        let tl = topLeftOf(center);
        plank(tl) :: List.flatten(seams(tl) :: rails(tl) :: frameJoints(tl) :: outline(tl) :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(tl: Vec2.Vec2): Render.PlacedItem =
        boxAt(tl#x, tl#y, crateSize(), crateSize(), Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(tl: Vec2.Vec2): List[Render.PlacedItem] =
        let t = crateSize();
        let w = t * 0.04;
        List.map(i ->
            let x = tl#x + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, tl#y, w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(tl: Vec2.Vec2): List[Render.PlacedItem] =
        let t = crateSize();
        let f = railW();
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// Frame joints: the border lines between the frame and the interior. The 2 full-width
    /// horizontal lines double as the butt joints at the four corners at their ends;
    /// the 2 vertical lines run only between them.
    def frameJoints(tl: Vec2.Vec2): List[Render.PlacedItem] =
        let t = crateSize();
        let f = railW();
        let w = t * 0.02;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// Outer outline: a dark 1px (design resolution) line around the whole crate.
    def outline(tl: Vec2.Vec2): List[Render.PlacedItem] =
        let t = crateSize();
        let w = 1.0;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.PlacedItem =
        ({x = x, y = y}, Render.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    def cratePolys(center: Vec2.Vec2): List[GameEngine.PolygonRenderCmd] =
        let tl = topLeftOf(center);
        let half = crateSize() * 0.09;    // half-width of the central band (0.18T thick)
        let edge = crateSize() * 0.03;    // thickness of one edge line
        braceStrip(tl, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping.
    def braceStrip(tl: Vec2.Vec2, o1: Float64, o2: Float64,
                   c: Color, z: Int32): GameEngine.PolygonRenderCmd =
        let t = crateSize();
        let f = railW();
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { vertices = Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
                     Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
          color = c, alpha = 1.0f32, zIndex = z }

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))

    // ── Launcher: run world |> step |> frame, every frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        loop(atlas, initialWorld())

    def loop(atlas: FontAtlas, world: World): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let next = step(world);
            let (drawables, polys) = frame(atlas, next);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, next)
        }
}
```

### 3つの言葉

この章で、このエンジンの語彙の最初の3語を導入します。どれも、上のコードの中にすでに見えている物の名前です:

- **World** — 状態の住む場所。変わるものすべてを持つ 1 個の値（今日は `crateX` だけ）。この値を1個保存すれば、ゲームのこの瞬間を完全に再現できます。プログラムの他のどこも、何も覚えていません。
- **Step** — 世界を1フレーム進める純関数 `World -> World`。`step` のシグネチャに注目してください: effect 注釈がありません。Flix ではこれはコメントでも紳士協定でもなく、**注釈のない `def` が純粋であることをコンパイラが検証します**。同じ World を入れれば、必ず同じ次の World が出る。例外なく。
- **Projection** — `frame` は `step` の鏡像です: 世界を*読んで*絵を返すだけで、何も変えません。世界をスクリーンに映す射影です。

### 何が起きたか

- ループは毎フレーム3拍子を刻むようになりました: **`world |> step |> frame`** — 世界を進め、映し、描いて、新しい世界でくり返す。**これがこのエンジンの全てです。** 以後の章 — 入力・盤面・押す箱・undo — は全部この3拍子に部品を足すだけで、拍子そのものは変わりません。
- `step` は毎フレーム定数（`crateSpeed` = 設計 1px）だけ木箱を動かします。経過時間（dt）ベースでなく毎フレーム定数を選んだのは意図的です: `step` のシグネチャを `World -> World` ちょうどに保てる — それがこの章の教材の芯です — し、倉庫番はグリッドのゲームなので、このチュートリアルの道筋では連続的な時間ベースの移動は通過点であって目的地ではありません。（正直なコスト: 120Hz のディスプレイでは 60Hz の倍速で滑ります。それが困るゲームはフレームの経過秒を `step` に通します。エンジンは経過時間を提供しています。この段落を覚えておいてください: 第4章でまさにこの請求書が — 本物の 120Hz の画面で — 届き、私たちは支払います。）
- 折り返しのルールも `step` の中です — 「右端から完全に出たら、左端のすぐ外へ」。世界がどう変わるかのルールは `step` に置き、他の場所には置きません。
- 木箱の描画関数群は、画面中央を前提にする代わりに**中心座標を引数に取る**形になりました。1個の木箱をどこにでも描けることは、盤面にたくさんのタイルを描くことへの布石です — このゲームはそこへ向かっています。
- 変わって*いない*ものにも注目してください: `frame` は相変わらず「描きたい物のリストを返す」だけ、起動部は木箱のことを何も知らない数行のままです。新しい能力は書き換えではなく*新しい部品*として加わりました。

### 試すこと

`crateSpeed` を `3.0` に — 速く滑ります。次に `-1.0` に: 木箱は左へ滑って……そのまま永遠に消えます。折り返しルールが右端しか見ていないからです。右から再登場する鏡写しのルールを `step` に足せますか？（必要なものは全部もう画面の中にあります。）

---

## 第3章 — キーボードは世界の外に住む

**ねらい:** ひとりでに滑る木箱を退場させ、矢印キーで*あなたが*操縦するロボットを画面に立たせる — `step` の純粋さは一切手放さずに。

第2章はひとつの問題を残して終わりました: キーボードです。移動は「*いままさに*どの矢印キーが押されているか」に依存すべきですが、その事実は私たちの World のどこにも入っていません。キーボードのハードウェアの中 — プログラムの完全に外側に住んでいます。

つい試したくなるのは、`step` に覗き見させること — 中から `isKeyPressed` を呼ぶことです。Flix はそれを単純にコンパイルしません。キーを読むことは effect であり — シグネチャに `\ GameEngine.Game` と書いてあり — `step` のような注釈なしの `def` は*純粋だと検証される*ので、その呼び出しは弾かれます。型システムが設計判断を迫っているのです。このコードベースの判断はこう:

**ループが毎フレーム1回キーを読み、その結果をただの値として `step` に手渡す。** キーボードは世界の外に住む。データとなって世界に入ってくる。

```flix
pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

pub def step(input: Input, w: World): World = ...
```

`step` は引数がひとつ増えただけで、何も失っていません: 同じ `Input` と同じ `World` を入れれば、同じ次の `World` が出る。これまでどおりコンパイラが保証します。`Input` は新しい語彙ではありません — ただの Bool 4個のレコードです。

### 画像ファイルのないロボット

主役には顔が要ります。このプロジェクトは木箱と同じやり方で顔を描きました: **箱の合成だけで、画像ファイルはどこにもなし**。`src/Robot.flix` は 16 ユニットのグリッド上に丸角ボックスで単眼ロボットを組み — ボディの板・レンズの目・L字の腕・足 — 純関数をひとつ公開します: `Robot.parts(center, size, dir, phase)` が、任意の向き・任意の歩行位相の描画リストを返します。

デザインは目で選びました。テストスイートが PNG と GIF に焼き出すギャラリーからです（`gallery/` を見てください: 候補ロボ6体、当選作の4方向、行進する歩行サイクル）。歩きはアニメクリップではありません: ポーズは `(dir, phase)` の純関数なので、立っているロボットと歩いているロボットは同じ関数の別の位相です — `walkPhase = 0.0` が*そのまま*静止ポーズ。木箱はこの章ではロボットに場所を譲って退場します。盤面ができたら、*押す物*として戻ってきます。

### `src/Sokoban.flix`（この章時点の全コード）

```flix
mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Design resolution 320x240 and its center.
    def designW(): Float64 = 320.0
    def designH(): Float64 = 240.0
    def centerX(): Float64 = 160.0
    def centerY(): Float64 = 120.0

    // The robot is one 16px grid tile shown at 6x magnification: 96px square.
    def robotSize(): Float64 = 96.0

    def zTitle(): Int32 = 100

    // ── Input: this frame's keys as plain data ──
    // The keyboard lives outside the World. Every frame the loop reads it once and
    // hands step the result as a value — so step can stay pure.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    // ── World: where the state lives ──
    // One value that holds everything that changes: where the robot is, which way
    // it faces, and where it is in its walk cycle.
    pub enum World {
        case World({ robotX = Float64, robotY = Float64,
                     facing = Dir4.Dir4, walkPhase = Float64 })
    }

    pub def initialWorld(): World =
        World.World({ robotX = centerX(), robotY = centerY(),
                      facing = Dir4.Down, walkPhase = 0.0 })

    // ── step: advances the world by one frame ──
    // Still no effect annotation: the keys arrive as an argument, so the same
    // (Input, World) always steps to the same next World.

    // Design px per frame while a key is held.
    def robotSpeed(): Float64 = 1.5
    // Walk-cycle phase per moving frame: a full 4-beat cycle every 32 frames.
    def walkRate(): Float64 = 1.0 / 32.0

    pub def step(input: Input, w: World): World =
        let World.World(r) = w;
        let dx = axis(input#left, input#right);
        let dy = axis(input#up, input#down);
        if (dx == 0.0 and dy == 0.0)
            World.World({ walkPhase = 0.0 | r })    // no key: snap to the rest pose, keep the facing
        else
            World.World({
                robotX = clamp(robotSize() / 2.0, designW() - robotSize() / 2.0,
                               r#robotX + dx * robotSpeed()),
                robotY = clamp(robotSize() / 2.0, designH() - robotSize() / 2.0,
                               r#robotY + dy * robotSpeed()),
                facing = facingOf(dx, dy, r#facing),
                walkPhase = fract(r#walkPhase + walkRate())
            })

    /// -1.0, 0.0 or +1.0 from an opposing key pair (both held cancel out).
    def axis(negative: Bool, positive: Bool): Float64 =
        (if (positive) 1.0 else 0.0) - (if (negative) 1.0 else 0.0)

    /// Facing follows the movement; the horizontal wins a diagonal, and standing
    /// still keeps whatever facing the robot already had.
    def facingOf(dx: Float64, dy: Float64, current: Dir4.Dir4): Dir4.Dir4 =
        if (dx > 0.0)      Dir4.Right
        else if (dx < 0.0) Dir4.Left
        else if (dy > 0.0) Dir4.Down
        else if (dy < 0.0) Dir4.Up
        else current

    def clamp(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    /// Keep only the fractional part (the walk cycle repeats on 0..1).
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── frame: projects the World into the list of things to draw ──
    // The same Robot.parts that baked the gallery draws the player: a character
    // with no image file, composed box by box at whatever size we ask for.
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(r) = w;
        let center = {x = r#robotX, y = r#robotY};
        let boxes = List.append(
            Robot.parts(center, robotSize(), r#facing, r#walkPhase),
            titlePlacement(atlas) :: Nil);
        (Render.draw(boxes), Nil)

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))

    // ── Launcher: read input |> step |> frame, every frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        loop(atlas, initialWorld())

    /// Reading the keyboard touches something outside the program, and the
    /// signature says so: `\ GameEngine.Game`. This is the only place the keys
    /// are read; past this point they are just a value.
    def readInput(): Input \ GameEngine.Game =
        { up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
          down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
          left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
          right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right) }

    def loop(atlas: FontAtlas, world: World): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let next = step(readInput(), world);
            let (drawables, polys) = frame(atlas, next);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, next)
        }
}
```

### 何が起きたか

- 拍子は変わっていません。今も毎フレーム `world |> step |> frame` です。ループは拍の始まる前に値をひとつ*用意*するようになっただけ — `step(readInput(), world)` — で、その先は今までどおり純粋です。
- `readInput` のシグネチャを見てください: `Input \ GameEngine.Game`。Flix では、**その関数が何に触るかは型に書いてあります**。`\ GameEngine.Game` 自体は第0章から `start` と `loop` に付いていました — ループはウィンドウに絵を描くのだから、外に触るのは当然です。新しいのは境界線です: キーボードを読む場所はちょうど1箇所で、そこを過ぎればキーはただの Bool 4個のレコード。`step` の中で `isKeyPressed` を呼ぼうとすればコンパイラが止めます — ここでの純粋さは紳士協定ではなく、検査される性質です。（リポジトリのコードを並べて読んでいる人へ: キーを1本ずつ直接読むこの書き方は `readInput` の*最初の姿*です。完成形ではキー割り当てを表に移します — 第6章の最後で紹介します。WASD で動けるようになるのもそこです。）
- *ルール*は全部いまも `step` の中にあり、どれも普通の世界のルールです: 逆向きのキーは打ち消し合う（`axis`）、斜めは横が勝つ（`facingOf`）、画面端で止まる（clamp）、全キーを離すと `walkPhase` が `0.0` に戻る — そして Robot の設計上、それが*そのまま*直立ポーズです。キーハンドラもコールバックも「入力システム」もなし: データが入り、World が出るだけ。
- `frame` は `Robot.parts` でプレイヤーを描きます — ギャラリーのファイルを焼いたのと*同じ関数*です。「ゲーム用の絵」は別に存在しません: 目で承認したギャラリーと画面の中のキャラクターは、ひとつの関数です。
- そして新しい語彙はゼロ: 画面のすべてはいまも **World**・**Step**・**Projection** で説明できます。`Input` は4語目ではなく、ループが `step` に手渡すただの値です。

### 試すこと

`robotSpeed` を `4.0` に — ロボットは急ぎ足になり、歩行サイクルがスケートに見えてきます。`walkRate` も合わせて上げてみてください。次はルールを変えます: 今のロボットは斜めに歩けます（両軸が同時に動く）。`step` でそれを禁止してみてください — たとえば横のキーペアが生きている間は縦のペアを無視する、など。純関数ひとつの `if` ひとつでゲームの手触りが変わります。`test/TestSokoban.flix` のテストを走らせて、どのピン留めされたルールを壊したか確かめてください。

---

## 第4章 — たくさんの物が住む世界

**ねらい:** みんなの足元に盤面を敷く — ロボットを止める壁、木箱を待つゴール、1マスずつ動く木箱 — そして「まとまって届く状態」のための言葉、**Store** に出会う。

ここまでの World は状態を1個ずつ運んできました: 第2章は `crateX` が1個、第3章はロボットの位置が1個。倉庫番の盤面は積み荷の種類が違います。下の最初のレベルには壁タイルが24枚、木箱が2個、ゴールが2個 — そして壁のフィールドを24本持つ World なんて誰も見たくありません。

World は前とまったく同じもののまま: 1個の値です。育つのは*フィールド*のほう — フィールドはコレクションをまるごと持てます。

```flix
pub type alias Board = {
    walls = Set[(Int32, Int32)],
    goals = Set[(Int32, Int32)],
    crates = Set[(Int32, Int32)],
    ...
}
```

### 4語目: Store

**Store** とは、同じ種類の状態をたくさん持つ World のフィールドです — 単一の数値の代わりに、ここでは `Set`、いつかは `Map`。`walls` は壁位置の Store、`crates` は木箱位置の Store、`goals` はゴール位置の Store。物の種類ごとにフィールド1本、個数は何個でも。

これがこのエンジンの語彙の4語目です — **World**・**Step**・**Projection**・**Store** — そして、この言葉が生まれた瞬間に何が買えるかに注目してください。「`target` に壁はあるか？」は `Set.memberOf(target, walls)`: 探索ではなく質問です。木箱を押すことは `Set.remove` と `Set.insert`: 木箱にはオブジェクトも id も専用の小さなクラスもありません — 木箱とは Store の中の位置*そのもの*です。

### レベルはテキスト

24枚の壁はどこから来るのでしょう？ 24行のコードからではありません。レベルは文字列です。パズル作家が何十年も使ってきた、倉庫番の古典記法で書きます:

```
#  壁         .  ゴール          @  ロボット
$  木箱       *  ゴール上の木箱   +  ゴール上のロボット
```

この章に同梱する2つの盤面です — このチュートリアルのために設計し、解けることを手で確認してあります。1つ目は見えてしまえば2回のまっすぐな押し、2つ目は押すたびに遠回りの歩きを要求します:

```
#######      ########
#     #      #      #
# .$  #      # ## $.#
#     #      # #    #
#  $. #      # $ ## #
#  @  #      #. @   #
#######      ########
```

気持ちのいいところ: レベルの設計はルールに一切触れません。文字列はパーサ — 純関数 `String -> Result[String, Parsed]` — を通って Store になって出てきます。タイプミスは何も壊しません。どこで何が悪いかを言う `Err` の値になって返ってくるだけです（`unknown tile 'X' at column 1, row 0`）。第3章でキーボードが受けたのと同じ規律です: ルールの外から来るもの — 今回は手打ちの文字列 — は、境界で検査済みのデータに変換されます。

### 2マスの間も状態

ロボットはマス単位で動くようになりました。ルールがそれを要求します: 倉庫番は正確なマスのゲームで、「だいたいゴールの上」に意味はありません。でもキー1回でタイル1枚を*瞬間移動*するロボットはスプレッドシートの編集みたいな手触りです。両方欲しい — ルールはグリッドの上に、動きは画面の上に — ので、この2つを分離します。

ホップが始まると、ロボットのマス（すべてのルールが読むもの）は即座に変わります。時間がかかるのは*絵*のほうです: 続く8分の1秒のあいだ、ロボットは古いマスと新しいマスの中間に描かれます。そして「絵はどこまで進んだか？」 — 補間の `t` — はフレームからフレームへ生き残らなければなりません。つまりそれは状態で、状態の住む場所はもう知っていますね:

```flix
slide = Option[Slide]    // ホップの絵がまだ移動中なら Some
```

スライドの移動中、キーボードは無視されます。着地した瞬間、キーがまだ押されていれば次の1マスが始まります。この1つの関門が静かに大仕事をします: タップはちょうど1マス、押しっぱなしはスライドのリズムで1マスずつ滑り、そしてロボットが2マスの間で捕まることは絶対にありません — ルールは中間フレームの存在を聞かされることすらないのです。

### プレイテスト interlude: 120Hz の請求書が届く

この章の最初の版は、スライドを*フレームごとに*一定量ずつ進めていました — 第2章の心地よい近道です。そしてこのゲームが 120Hz のディスプレイで回る機械でプレイされたとき、ロボットはきっかり倍速で動きました: ピーキーで、狙ったマスに止めにくい。第2章が予言した請求書が届いたのです。プレイテストとはこのためにあります。

直し方は、キーボードがもう教えてくれた文法です: **時計も世界の外に住んでいます。** ループがフレームの経過秒を読み、値として `step` に手渡します:

```flix
pub def step(input: Input, dt: Float64, w: World): World = ...
```

スライドは `dt / slideDuration()` ずつ進むようになりました — 1秒を60枚の絵に描くディスプレイもあれば120枚のものもありますが、1秒の長さ自体はどこでも同じです。テストは決定論を失うどころか*強く*なりました: 各テストが明示的な `dt` を渡し、正確な値をピン留めします。そして時計を手に入れたロボットは、直立不動をやめました: キーが押されていないあいだ、ゆっくりその場で足踏みをします — 同じ歩行サイクルを3分の1のテンポで。せわしなくなく、生きている。

### `src/Level.flix`（新規）

```flix
mod Level {

    /// The first board: two crates, two goals, no interior walls.
    pub def one(): String =
        String.unlines(
            "#######" ::
            "#     #" ::
            "# .$  #" ::
            "#     #" ::
            "#  $. #" ::
            "#  @  #" ::
            "#######" :: Nil)

    /// The second board: interior walls force a detour before each push.
    pub def two(): String =
        String.unlines(
            "########" ::
            "#      #" ::
            "# ## $.#" ::
            "# #    #" ::
            "# $ ## #" ::
            "#. @   #" ::
            "########" :: Nil)

    /// Everything a board says, as plain data. Grid positions are (column, row),
    /// counted from the top-left of the text.
    pub type alias Parsed = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32
    }

    /// A board still being read: the robot may not have appeared yet.
    type alias Draft = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = Option[(Int32, Int32)],
        cols = Int32
    }

    pub def parse(text: String): Result[String, Parsed] =
        let lines = String.lines(text);
        forM (d <- parseRows(0, lines, emptyDraft());
              robot <- requireRobot(d#robot))
        yield { walls = d#walls, goals = d#goals, crates = d#crates,
                robot = robot, cols = d#cols, rows = List.length(lines) }

    def emptyDraft(): Draft =
        { walls = Set.empty(), goals = Set.empty(), crates = Set.empty(),
          robot = None, cols = 0 }

    def requireRobot(o: Option[(Int32, Int32)]): Result[String, (Int32, Int32)] =
        match o {
            case Some(p) => Result.Ok(p)
            case None    => Result.Err("the level has no robot '@'")
        }

    def parseRows(y: Int32, lines: List[String], d: Draft): Result[String, Draft] =
        match lines {
            case Nil => Result.Ok(d)
            case line :: rest =>
                forM (d1 <- parseCells(0, y, String.toList(line), d);
                      d2 <- parseRows(y + 1, rest, d1))
                yield d2
        }

    def parseCells(x: Int32, y: Int32, cells: List[Char], d: Draft): Result[String, Draft] =
        match cells {
            case Nil => Result.Ok({ cols = Int32.max(x, d#cols) | d })
            case c :: rest =>
                forM (d1 <- cell(x, y, c, d);
                      d2 <- parseCells(x + 1, y, rest, d1))
                yield d2
        }

    def cell(x: Int32, y: Int32, c: Char, d: Draft): Result[String, Draft] =
        let p = (x, y);
        match c {
            case '#' => Result.Ok({ walls = Set.insert(p, d#walls) | d })
            case ' ' => Result.Ok(d)
            case '.' => Result.Ok({ goals = Set.insert(p, d#goals) | d })
            case '$' => Result.Ok({ crates = Set.insert(p, d#crates) | d })
            case '*' => Result.Ok({ crates = Set.insert(p, d#crates),
                                    goals = Set.insert(p, d#goals) | d })
            case '@' => placeRobot(p, d)
            case '+' => forM (d1 <- placeRobot(p, d))
                        yield { goals = Set.insert(p, d1#goals) | d1 }
            case _   => Result.Err("unknown tile '${c}' at column ${x}, row ${y}")
        }

    def placeRobot(p: (Int32, Int32), d: Draft): Result[String, Draft] =
        if (Option.isEmpty(d#robot)) Result.Ok({ robot = Some(p) | d })
        else Result.Err("more than one robot in the level")
}
```

### `src/Crate.flix`（木箱の帰還）

第1章の木箱が独立モジュールとして帰ってきます。変更は1つだけ: すべての比率が固定の96pxではなくタイルサイズ引数からぶら下がるようになり、同じ関数がショーケースの木箱も24pxの盤面タイルも描きます。すべての部品を木箱の中心からの相対位置で置いたのは、このためだったのです。

```flix
mod Crate {

    // Thickness of the outer frame rails, relative to the tile.
    def railW(t: Float64): Float64 = t * 0.12

    // Drawing order (zIndex): base plank -> vertical seams -> diagonal brace ->
    // frame rails -> frame joints and outer outline. The rails draw after the
    // brace, so the brace's extended ends tuck underneath them.
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5

    def topLeftOf(center: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        {x = center#x - t / 2.0, y = center#y - t / 2.0}

    /// Box parts: 1 base plank + 5 vertical seams + 4 frame rails + 4 frame joints + 4 outline edges.
    pub def boxes(center: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let tl = topLeftOf(center, t);
        plank(tl, t) :: List.flatten(seams(tl, t) :: rails(tl, t) :: frameJoints(tl, t) :: outline(tl, t) :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(tl: Vec2.Vec2, t: Float64): Render.PlacedItem =
        boxAt(tl#x, tl#y, t, t, Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(tl: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let w = t * 0.04;
        List.map(i ->
            let x = tl#x + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, tl#y, w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(tl: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let f = railW(t);
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// Frame joints: the border lines between the frame and the interior. The 2 full-width
    /// horizontal lines double as the butt joints at the four corners at their ends;
    /// the 2 vertical lines run only between them.
    def frameJoints(tl: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let f = railW(t);
        let w = t * 0.02;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// Outer outline: a dark 1px (design resolution) line around the whole crate.
    def outline(tl: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let w = 1.0;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.PlacedItem =
        ({x = x, y = y}, Render.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    pub def polys(center: Vec2.Vec2, t: Float64): List[GameEngine.PolygonRenderCmd] =
        let tl = topLeftOf(center, t);
        let half = t * 0.09;    // half-width of the central band (0.18T thick)
        let edge = t * 0.03;    // thickness of one edge line
        braceStrip(tl, t, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping.
    def braceStrip(tl: Vec2.Vec2, t: Float64, o1: Float64, o2: Float64,
                   c: Color, z: Int32): GameEngine.PolygonRenderCmd =
        let f = railW(t);
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { vertices = Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
                     Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
          color = c, alpha = 1.0f32, zIndex = z }
}
```

### Palette の新しい役割名

新しい役割名は6つ、いつもどおり DB32 から: 壁には石のグレー — 押せない材質なので、盤上の何かと木を見間違えることがありません — 床には沈んだ緑がかったグレー、ゴールには鮮やかな緑。（"CLEAR!" の黄色 `clearText` はテキストの節で `titleText` の隣に加わります。）

```flix
    // ── Board tiles ──
    pub def wallFace(): Color  = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a
    pub def wallTop(): Color   = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}  // #847e87
    pub def wallShade(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def floorTile(): Color = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32}  // #323c39
    pub def goalMark(): Color  = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550
```

### `src/Sokoban.flix`（この章時点の全コード）

```flix
mod Sokoban {

    // Colors come only from Palette (DB32) role names. No color literals in drawing code.

    // Design resolution 320x240; the board is centered slightly below the middle
    // to clear the title line.
    def centerX(): Float64 = 160.0
    def boardCenterY(): Float64 = 132.0

    // One board cell on screen, in design px.
    def tile(): Float64 = 24.0

    def zBadge(): Int32 = 10
    def zTitle(): Int32 = 100

    // ── Input: this frame's keys as plain data ──
    // The keyboard lives outside the World. Every frame the loop reads it once and
    // hands step the result as a value — so step can stay pure.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    // ── World: where the state lives ──
    // walls / goals / crates are Stores: many things of one kind, one Set each.
    // slide is the picture's state: when a hop starts, the robot's cell changes
    // at once — the drawn position then travels from the old cell for a fraction
    // of a second, and how far it has come (t) must survive between frames, so
    // it lives in the World like everything else.
    pub type alias Slide = { fromCell = (Int32, Int32), pushing = Bool, t = Float64 }

    pub type alias Board = {
        walls = Set[(Int32, Int32)],
        goals = Set[(Int32, Int32)],
        crates = Set[(Int32, Int32)],
        robot = (Int32, Int32),
        cols = Int32,
        rows = Int32,
        facing = Dir4.Dir4,
        walkPhase = Float64,
        slide = Option[Slide]
    }

    pub enum World {
        case World(Board)
    }

    pub def initialWorld(): World = fromLevel(Level.one())

    /// The shipped level strings are pinned parseable by the tests; a broken
    /// string degrades to a bare floor instead of crashing the launcher.
    pub def fromLevel(text: String): World =
        match Level.parse(text) {
            case Result.Ok(p)  => toWorld(p)
            case Result.Err(_) => toWorld({ walls = Set.empty(), goals = Set.empty(),
                                            crates = Set.empty(), robot = (0, 0),
                                            cols = 1, rows = 1 })
        }

    def toWorld(p: Level.Parsed): World =
        World.World({ walls = p#walls, goals = p#goals, crates = p#crates,
                      robot = p#robot, cols = p#cols, rows = p#rows,
                      facing = Dir4.Down, walkPhase = 0.0,
                      slide = None })

    /// The win condition is not stored anywhere: it is derived from the Stores.
    pub def won(w: World): Bool =
        let World.World(b) = w;
        Set.isSubsetOf(b#crates, b#goals)

    // ── step: advances the world by dt seconds ──
    // Still pure: the keys arrive as an argument, and so does the clock — dt is
    // this frame's elapsed seconds, read by the loop and handed in as a value.
    // While a slide is travelling the keys are ignored; the moment it lands, a
    // key still held starts the next square — taps move exactly one cell, holds
    // glide cell by cell in rhythm, at the same speed on any display.

    /// Seconds one tile's slide takes: the single knob for movement speed.
    def slideDuration(): Float64 = 0.125

    /// The walk cycle advances one beat (0.25 of the cycle) per tile slid.
    def strideBeat(): Float64 = 0.25

    /// Walk cycles per second while standing: a slow march in place — about a
    /// third of the walking rate, alive rather than busy.
    def idleBeat(): Float64 = 0.75

    pub def step(input: Input, dt: Float64, w: World): World =
        let World.World(b) = w;
        match b#slide {
            case Some(s) =>
                let t = s#t + dt / slideDuration();
                let walked = { walkPhase = fract(b#walkPhase + strideBeat() * (dt / slideDuration())) | b };
                if (t < 1.0)
                    World.World({ slide = Some({ t = t | s }) | walked })
                else
                    // The slide has landed: only now does the keyboard get a say.
                    World.World(beginHop(input, { slide = None | walked }))
            case None =>
                // A standing robot marches slowly in place; a starting hop
                // carries the phase along, so the legs never snap.
                let marched = { walkPhase = fract(b#walkPhase + idleBeat() * dt) | b };
                World.World(beginHop(input, marched))
        }

    /// Start a hop if a direction key is down, else keep standing.
    def beginHop(input: Input, b: Board): Board =
        match pick(input#up, input#down, input#left, input#right) {
            case None    => b
            case Some(d) => move(d, b)
        }

    /// The whole rulebook of sokoban. The target cell decides: a wall stops the
    /// robot; a crate moves along only if the cell behind it is free; otherwise
    /// nothing moves and the robot just turns. A legal hop changes the cells at
    /// once and starts the slide that lets the picture catch up.
    def move(d: Dir4.Dir4, b: Board): Board =
        let (dx, dy) = deltaOf(d);
        let (rx, ry) = b#robot;
        let target = (rx + dx, ry + dy);
        let (tx, ty) = target;
        let beyond = (tx + dx, ty + dy);
        let pushing = Set.memberOf(target, b#crates);
        let blocked = Set.memberOf(target, b#walls)
            or (pushing and (Set.memberOf(beyond, b#walls) or Set.memberOf(beyond, b#crates)));
        if (blocked)
            { facing = d | b }
        else
            { robot = target,
              crates = if (pushing) Set.insert(beyond, Set.remove(target, b#crates)) else b#crates,
              facing = d,
              slide = Some({ fromCell = b#robot, pushing = pushing, t = 0.0 })
              | b }

    /// Among several held keys: up, then down, then left, then right.
    def pick(u: Bool, d: Bool, l: Bool, r: Bool): Option[Dir4.Dir4] =
        if (u) Some(Dir4.Up)
        else if (d) Some(Dir4.Down)
        else if (l) Some(Dir4.Left)
        else if (r) Some(Dir4.Right)
        else None

    def deltaOf(d: Dir4.Dir4): (Int32, Int32) = match d {
        case Dir4.Up    => (0, -1)
        case Dir4.Down  => (0, 1)
        case Dir4.Left  => (-1, 0)
        case Dir4.Right => (1, 0)
    }

    /// Keep only the fractional part (the walk cycle repeats on 0..1).
    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── frame: projects the World into the list of things to draw ──
    // Insertion order layers the board: floor and walls, then goal marks, then
    // crates, then the robot, then the on-goal badges and text on top.
    pub def frame(atlas: FontAtlas, w: World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let World.World(b) = w;
        let boxes = List.flatten(
            boardTiles(b) ::
            goalMarks(b) ::
            crateBoxes(b) ::
            Robot.parts(robotCenter(b), tile(), b#facing, b#walkPhase) ::
            onGoalBadges(b) ::
            texts(atlas, w) :: Nil);
        (Render.draw(boxes), cratePolys(b))

    /// Top-left corner of the board, chosen so the whole grid sits centered.
    def origin(b: Board): Vec2.Vec2 =
        { x = centerX() - Int32.toFloat64(b#cols) * tile() / 2.0,
          y = boardCenterY() - Int32.toFloat64(b#rows) * tile() / 2.0 }

    def cellCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        let o = origin(b);
        let (x, y) = p;
        { x = o#x + (Int32.toFloat64(x) + 0.5) * tile(),
          y = o#y + (Int32.toFloat64(y) + 0.5) * tile() }

    /// Where the robot is drawn: its cell — or partway out of the previous one.
    def robotCenter(b: Board): Vec2.Vec2 =
        match b#slide {
            case None    => cellCenter(b, b#robot)
            case Some(s) => lerp(cellCenter(b, s#fromCell), cellCenter(b, b#robot), s#t)
        }

    /// While a push is sliding, the pushed crate sits one cell past the robot's
    /// destination, along the same direction the robot came from.
    def slidingCrate(b: Board, s: Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * rx - fx, 2 * ry - fy)

    /// Where a crate is drawn: its cell — unless it is the one being pushed,
    /// which travels in lockstep with the robot.
    def crateCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        match b#slide {
            case Some(s) =>
                if (s#pushing and p == slidingCrate(b, s))
                    lerp(cellCenter(b, b#robot), cellCenter(b, p), s#t)
                else cellCenter(b, p)
            case None => cellCenter(b, p)
        }

    def lerp(a: Vec2.Vec2, z: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        { x = a#x + (z#x - a#x) * t, y = a#y + (z#y - a#y) * t }

    def cells(b: Board): List[(Int32, Int32)] =
        List.flatMap(y -> List.map(x -> (x, y), List.range(0, b#cols)), List.range(0, b#rows))

    def boardTiles(b: Board): List[Render.PlacedItem] =
        List.flatMap(p ->
            if (Set.memberOf(p, b#walls)) wallTile(cellCenter(b, p))
            else floorTile(cellCenter(b, p)),
            cells(b))

    /// Floor: one flat box per cell; the board reads as a lit area on the dark
    /// clear color around it.
    def floorTile(c: Vec2.Vec2): List[Render.PlacedItem] =
        boxAt(c#x - tile() / 2.0, c#y - tile() / 2.0, tile(), tile(), Palette.floorTile(), 0) :: Nil

    /// Wall: a stone block — flat face with a lit top edge and a shaded foot.
    def wallTile(c: Vec2.Vec2): List[Render.PlacedItem] =
        let t = tile();
        let x0 = c#x - t / 2.0;
        let y0 = c#y - t / 2.0;
        let bevel = t * 0.16;
        boxAt(x0, y0, t, t, Palette.wallFace(), 0) ::
        boxAt(x0, y0, t, bevel, Palette.wallTop(), 1) ::
        boxAt(x0, y0 + t - bevel, t, bevel, Palette.wallShade(), 1) :: Nil

    /// Goal: a small round marker on the floor (crates and the robot draw over it).
    def goalMarks(b: Board): List[Render.PlacedItem] =
        List.map(p -> circleAt(cellCenter(b, p), tile() * 0.34, Palette.goalMark(), 0),
                 Set.toList(b#goals))

    /// A crate parked on (or sliding onto) a goal gets a small badge on top:
    /// the goal answers back.
    def onGoalBadges(b: Board): List[Render.PlacedItem] =
        List.map(p -> circleAt(crateCenter(b, p), tile() * 0.25, Palette.goalMark(), zBadge()),
                 Set.toList(Set.intersection(b#crates, b#goals)))

    def crateBoxes(b: Board): List[Render.PlacedItem] =
        List.flatMap(p -> Crate.boxes(crateCenter(b, p), tile()), Set.toList(b#crates))

    def cratePolys(b: Board): List[GameEngine.PolygonRenderCmd] =
        List.flatMap(p -> Crate.polys(crateCenter(b, p), tile()), Set.toList(b#crates))

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.PlacedItem =
        ({x = x, y = y}, Render.box({x = w, y = h}, c, z))

    def circleAt(c: Vec2.Vec2, d: Float64, color: Color, z: Int32): Render.PlacedItem =
        let style = { cornerRadius = d / 2.0, borderWidth = 0.0, borderColor = color,
                      borderAlpha = 0.0f32, stripeColor = color, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({x = c#x - d / 2.0, y = c#y - d / 2.0},
         Render.Item.Box({ size = {x = d, y = d}, color = color, alpha = 1.0f32,
                                 style = Some(style), zIndex = z }))

    /// Title always; "CLEAR!" appears the moment every crate sits on a goal —
    /// not stored anywhere, just projected from the Stores.
    def texts(atlas: FontAtlas, w: World): List[Render.PlacedItem] =
        let title = centeredText("Sokoban", atlas, 28.0, Palette.titleText(), 10.0);
        if (won(w)) title :: centeredText("CLEAR!", atlas, 36.0, Palette.clearText(), 104.0) :: Nil
        else title :: Nil

    def centeredText(text: String, atlas: FontAtlas, size: Float64,
                     color: Color, y: Float64): Render.PlacedItem =
        let width = Label2D.measure(Label2D.make(text, atlas, size))#x;
        ({x = centerX() - width / 2.0, y = y}, Render.textTinted(text, atlas, size, color, zTitle()))

    // ── Launcher: read input and the clock |> step |> frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        loop(atlas, initialWorld())

    /// Reading the keyboard touches something outside the program, and the
    /// signature says so: `\ GameEngine.Game`. This is the only place the keys
    /// are read; past this point they are just a value.
    def readInput(): Input \ GameEngine.Game =
        { up    = GameEngine.Game.isKeyPressed(GameEngine.Key.Up),
          down  = GameEngine.Game.isKeyPressed(GameEngine.Key.Down),
          left  = GameEngine.Game.isKeyPressed(GameEngine.Key.Left),
          right = GameEngine.Game.isKeyPressed(GameEngine.Key.Right) }

    /// The clock lives outside the World too. The engine clamps the value, so a
    /// long hiccup (or the first frame) never teleports the game forward.
    def readDt(): Float64 \ GameEngine.Game =
        Duration.toSeconds(GameEngine.Game.getDeltaTime())

    def loop(atlas: FontAtlas, world: World): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let next = step(readInput(), readDt(), world);
            let (drawables, polys) = frame(atlas, next);
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, next)
        }
}
```

### 何が起きたか

- World は1個の位置から盤面まるごとへ育ちましたが、種は変わっていません: いまも1個の値、いまも純関数で進み、いまも `frame` で映されます。フィールドのうち3本が Store です。World を保存すれば、解きかけのパズルが保存されます。
- 倉庫番のルールブック全体が `move` 関数 — 十数行です。行き先のマスがすべてを決めます: 壁？ 動かない。裏が空いている木箱？ 両方進む。裏に何かある木箱？ 動かない。1982年から遊ばれてきたゲームがナプキン1枚に収まるのは、盤面が Store *だから*です — すべての質問が所属テストになります。
- **勝利は保存されません。** `won` は `Set.isSubsetOf(crates, goals)` と尋ねるだけで、"CLEAR!" の文字は他のすべてと同じ Store から映し出されます。立てて、下ろして、戻し忘れる `isCleared` フラグは存在しません: 導出できる状態は状態ではないのです。
- `frame` は挿入順で盤面を積み重ねます — 床と壁、ゴールマーク、木箱、ロボット、バッジとテキスト。zIndex が同じ部品同士は後から描いたほうが勝つので、リストは場面そのものと同じように下から上へ読めます。ゴールに収まった木箱には小さな緑のバッジが上に乗ります: ゴールが返事をするのです。
- スライドは純粋に射影です。`robotCenter` と `crateCenter` はスライド移動中だけマスの間を補間し、`won` もすべてのルールも Store しか読みません。ロボットが押すとき、木箱の絵はロボットの絵と足並みを揃えて移動します — 同じ `t` で、1マスだけ先を。そして `t` さえ World に住んでいるので、スライドの途中で World を保存すれば、歩幅の途中から再開されます。
- 歩行サイクルは、スライド中はタイル1枚につき1拍で闊歩し、静止中は（`idleBeat` で）ゆっくり足踏みします — ロボットが凍りつく瞬間はありません。ホップの開始は静止中の位相をそのまま引き継ぐので、脚が飛びつなぎになることもありません。

### 試すこと

`initialWorld` を `Level.two()` に向けて、遠回りを歩いてください。次に `Level.flix` を開いて盤面を編集します — 木箱とゴールを1組足す、壁に出入り口を彫る — タイプミスのたびにパーサが手を引いてくれます。自分のレベルを設計してみてください。書くコードは文字列だけです。

定数の手触りも: `slideDuration` を `0.25` にするとロボットは悠然と歩き（秒4マス）、`0.06` なら小走りになります。`idleBeat` を `2.0` にすると足踏みがその場ジョギングに変わります。それぞれ数字1個でゲーム全体の歩き方が変わります — ルールは何も気づきません。

そして*ルール*を変えます: 倉庫番の純粋主義者は目をつぶってください — ロボットが**引ける**ようにするのです。`move` で、ロボットが空きマスへ歩くとき、*背後*のマス（歩く向きの反対側）に木箱があったかを調べ、あればその木箱をロボットの元いたマスへ連れてきます。`test/TestSokoban.flix` のテストが、どのピン留めされたルールを書き換えたのかを正確に教えてくれます。

---

## 第5章 — 2つの呼び出しで時間旅行

**ねらい:** Z を押して1手戻す — 何手でも、最初の盤面まででも — そして語彙の5語目、このエンジンの名前になっている言葉に出会う。

押す木箱を間違えました。隅にでなければ幸いですが（隅に入った木箱は二度と出てきません — 倉庫番の小さな悲劇です）、1マス押しすぎただけでも計画は台無しです。元祖以来すべての倉庫番がこれに同じキーで答えてきました: undo。ここで、プログラムが普通は痛がる問いが立ちます: **「過去」とは何でしょう？**

たいていのコードベースで、過去は高くつきます。undo とは全操作の*逆再生*を覚えておくこと — コマンドの undo スタック、逆関数、誰かが機能を足して逆操作を書き忘れた日に壊れる几帳面な帳簿。でも第2章が、この請求書を丸ごと前払いしてありました。World は**1個の値**です。過去の World とは、単にかつて手に持っていた値のこと。保存する = 値を取っておく。巻き戻す = 取っておいた値をまた使う。ここで使える時間旅行の理論は、これで全部です。

### 5語目: Worldline

World は1つの瞬間です。ゲームが瞬間たちの中に残す軌跡 — いまの World、その後ろに連なるすべての World、そして undo を始めれば、乗り捨てた先の World たち — を **worldline（世界線）** と呼びます。エンジンはこれをデータ構造として同梱しています: `Worldline[World]`、3本のレーンを持つ zipper です:

```
past    — 背後の World たち（新しい順）
current — いまいる場所
future  — undo で抜け出してきた World たち（redo の燃料）
```

`Worldline.record` は現在を past に綴じて先へ進みます（future は捨てます — 新しい一手を指せば、乗り捨てた時間線は無効になるからです）。`Worldline.undo` は1段戻り、手放した現在を future に停めます。`Worldline.redo` はまた前へ歩きます。すべて純粋で、すべて全域: 最古の点で undo しても、そこに留まるだけです。

そしてここで、エンジンの名前が謎でなくなります。このゲームが載っているパッケージは `engine_world`。World の軌跡は worldline。そしてこのゲームの作り方全体 — 1個の World 値、純粋な Step、それを読む Projection、中に住む Store、瞬間たちを綴じる Worldline — が **Worldline アーキテクチャ**と呼ばれるものです。World・Step・Projection・Store・**Worldline**: 5つの言葉、その5番目が箱に書いてある名前でした。

### 手の拍で記録する

歴史はいつ書くべきでしょう？ 避けゲーは毎フレーム記録します — その過去はフィルムです。倉庫番の過去はフィルムではなく**棋譜**です。戻る価値のある瞬間は各押しの直前だけ。だから記録は手が確定した瞬間ちょうどに行います — そしてその検出は比較1回です。合法手は必ずロボットを動かすからです。これが時間機械の全体です:

```flix
    // ── tick: one frame of the whole session, time machine included ──
    // The Worldline records one snapshot per committed move — the game's natural
    // beat — never per frame. Z rewinds move by move; each rewind plays the
    // move's slide backwards, and the next command (walk or rewind alike) is
    // accepted only when the picture lands: one gate for both directions of time.

    /// Snapshots to keep. At the engine benchmark's ~172 bytes per record this
    /// is under 2 MB: unlimited undo is, in effect, free.
    pub def historyCap(): Int32 = 10000

    pub def tick(input: Input, dt: Float64, line: Worldline[World]): Worldline[World] =
        let world = Worldline.current(line);
        // Holding Z takes the walk keys away; rewinding has right of way.
        let moveInput = if (input#undo) noKeys() else input;
        let next = step(moveInput, dt, world);
        if (hopStarted(world, next))
            // A move committed: file the pre-move World in the past.
            Worldline.record(next, Worldline.replaceCurrent(normalize(world), line))
        else if (input#undo and not inFlight(next))
            // The gate is open (nothing sliding) and Z is down: rewind one move.
            fireUndo(Worldline.replaceCurrent(next, line))
        else
            // Just motion; adjust the current point in place, no history made.
            Worldline.replaceCurrent(next, line)

    /// Rewind one move: the Stores return to the snapshot at once, and a
    /// reverse slide carries the picture back — the robot glides backwards
    /// wearing the undone move's facing, feet dragging, while the clock
    /// turns; the snapshot's own facing waits at the landing.
    def fireUndo(line: Worldline[World]): Worldline[World] =
        if (not Worldline.canUndo(line)) line
        else {
            let World.World(l) = Worldline.current(line);
            let line1 = Worldline.undo(line);
            let World.World(r) = Worldline.current(line1);
            let back = World.World({
                slide = Some({ fromCell = l#robot, pushing = l#crates != r#crates,
                               reverse = true, t = 0.0 }),
                walkPhase = l#walkPhase,
                undoFx = Some({ spin = spinOf(l#undoFx), linger = 0.0 })
                | r });
            Worldline.replaceCurrent(back, line1)
        }

    /// A hop committed exactly when the robot's cell changed (every legal move
    /// moves the robot; a blocked one moves nothing).
    def hopStarted(before: World, after: World): Bool =
        let World.World(a) = before;
        let World.World(z) = after;
        a#robot != z#robot

    def inFlight(w: World): Bool =
        let World.World(b) = w;
        not Option.isEmpty(b#slide)

    def noKeys(): Input =
        { up = false, down = false, left = false, right = false, undo = false }

    /// What goes into history: the logical state. The picture's travel and the
    /// rewind clock stay out of the past.
    def normalize(w: World): World =
        let World.World(b) = w;
        World.World({ slide = None, undoFx = None | b })
```

呼び出しは2つ。ホップが確定したら `Worldline.record`（*正規化した*直前の World を綴じます — 絵のスライドと巻き戻し時計は過去に入れません）、Z が発火したら `Worldline.undo`。あいだのフレームは `replaceCurrent` — zipper の「歴史を刻まずその場を直す」 — が current を生きたフレームに追従させます。undo システムも、コマンドオブジェクトも、`move` の逆関数も、どこにもありません: 過去は再計算されるのではなく、*取ってある*のです。

そして関門に注目してください。Z を押している間は歩行キーが取り上げられ、巻き戻しは「何も滑っていないとき」にだけ発火します — 歩行のホップに間隔を与えているのと同じ規則です。undo はゲームが最初から持っていたスライドの文法を話します: 絵が着地するごとに1コマンド、時間のどちら向きでも。

### 巻き戻しは逆再生のスライド

`fireUndo` がスナップショットを復元する瞬間、Store は即座に変わります — ルールはもう過去に戻っています — が、*絵*はテレポートしません。ロボットはいたセルから復元先のセルへ、歩行と同じスライド機構で滑って戻ります。ただし逆向きに、そしてゆっくりと: `undoDuration()` は1手 0.25 秒、歩行の 0.125 の2倍です — 巻き戻しには重さがあるべきで、時計にも見せ場が要ります。滑って戻るあいだ、ロボットは**戻している手の向き**を着ています — 上への一歩を undo すると、上を向いたまま下へ滑る: 小さなムーンウォークです — そして着地した瞬間、スナップショット自身の向き、つまり*その手を打つ前*の向きに引き継がれます。歩いて帰るのではなく、時間に*連れ戻されて*いる — 足は最後まで引きずられ続けます（walkPhase は回り続けます）。そして巻き戻した手が押し手だったなら、木箱も同じ逆再生のフィルムに乗って家に帰ります:

```flix
    /// While a push is rewinding, the returning crate now rests where the
    /// robot stood after the push (s#fromCell) — and its picture travels home
    /// from one cell further out.
    def crateReturnStart(b: Board, s: Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * fx - rx, 2 * fy - ry)

    /// Where a crate is drawn: its cell — unless it is the one being pushed
    /// (or un-pushed), which travels in lockstep with the robot, forward or
    /// backward: the same slide, film reversed.
    def crateCenter(b: Board, p: (Int32, Int32)): Vec2.Vec2 =
        match b#slide {
            case Some(s) =>
                if (s#pushing and not s#reverse and p == slidingCrate(b, s))
                    lerp(cellCenter(b, b#robot), cellCenter(b, p), settle(s#t))
                else if (s#pushing and s#reverse and p == s#fromCell)
                    lerp(cellCenter(b, crateReturnStart(b, s)), cellCenter(b, p), s#t)
                else cellCenter(b, p)
            case None => cellCenter(b, p)
        }
```

（forward 側を包む `settle` は第8章の着地ポップです — いまはただの `s#t` として読んでください。）

向きもまた、同じ種類の導出です。「undo 中のポーズ」を保存する場所はどこにもありません: 逆スライド自身が、いま巻き戻している手を名指ししています — その手は復元先のセルから `fromCell` へ進んだのですから — そしてスナップショットの向きはもう Board の中に座って、着地を待っています:

```flix
    /// The facing the picture wears. A rewind slide shows the direction of
    /// the undone move — that move went from the restored cell out to
    /// fromCell, so that line names it — and only when the slide lands does
    /// the snapshot's own facing (already in the Board) take over.
    pub def drawnFacing(b: Board): Dir4.Dir4 =
        match b#slide {
            case Some(s) => if (s#reverse) directionTo(b#robot, s#fromCell) else b#facing
            case None    => b#facing
        }
```

（`frame` は `Robot.parts` に `b#facing` の代わりにこの `drawnFacing(b)` を渡すようになりました。`directionTo` は `deltaOf` の4方向の逆写像です。）

逆スライドの移動中は歩行キーが無視され、Z も再発火できません — 共有の関門です — ので、Z の長押しはちょうど逆スライドのリズムで1手ずつ巻き戻します。そのあいだ、ロボットの頭上に小さな目覚まし時計が浮かびます: 白い文字盤、暗い縁、**巻き戻し1手につき反時計回りに1回転**する針 — スライド自身の進みと足並みを揃えて（`spin` は絵が進んだのと同じ割合だけ進みます）。巻き戻しが止まると、時計はひと呼吸残ってから消えていきます。すべて `frame` の中の純粋な導出です: 角度は `spin` から、透明度は `linger` から、位置はロボットに追従。記録されることはなく、ルールに参照されることもない — 良心に曇りのない飾りです。

Worldline 自身はループの中、world の隣に住んでいます — 中ではなく。World は自分が記憶されていることを知りません:

```flix
    // ── Launcher: read input and the clock |> tick |> frame, until the window closes ──
    pub def start(atlas: FontAtlas): Unit \ GameEngine.Game =
        loop(atlas, Worldline.make(initialWorld(), historyCap()))

    // ... readInput (now also reading Z) and readDt as before ...

    def loop(atlas: FontAtlas, line: Worldline[World]): Unit \ GameEngine.Game =
        if (GameEngine.Game.shouldClose() or GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let line1 = tick(readInput(), readDt(), line);
            let (drawables, polys) = frame(atlas, Worldline.current(line1));
            GameEngine.Game.renderCommands(drawables, Nil, polys);
            loop(atlas, line1)
        }
```

### 記憶の値段

すべての World を取っておいたら高いのでは？ 心配の前に測りましょう: エンジン自身のベンチマークでは、倉庫番サイズのスナップショット1件はおよそ **172 バイト**です。キロバイトではありません — World の Set は不変なので、新しいスナップショットは変わらなかったものを全部*共有*します。1回の押しが作るのは `crates` の中のひと握りの新ノードだけで、`walls` と `goals` はこれまで撮ったすべてのスナップショットと共有されたままです。これが構造共有で、だから

```flix
pub def historyCap(): Int32 = 10000
```

— 1万手ぶんの完全な記憶 — が 2 メガバイト未満で済みます。無制限 undo は贅沢機能ではありません。このアーキテクチャでは小銭です。

### 何が起きたか

- **undo は2つの呼び出しです。** 手の確定ごとに `record`、Z で `undo`。オブジェクト指向のコードベースを恐怖に陥れるあの機能 — 逆操作、ダーティフラグ、「復元ポイント」 — が、かつて手にしていた値を取っておくことに畳まれます。第2章の決断の配当が、5章遅れて支払われました。
- 歴史には拍があり、それは*ゲームの*拍です: 1手1スナップショット、フレームごとではなく。そして時間の両方向が同じスライド文法を話します — 前進のホップと巻き戻しは `reverse` を裏返しただけの1つの機構で、「絵が着地したときだけ次のコマンド」という関門に2つ目の実装は要りませんでした。
- Worldline はループに住み、world の隣にいます。World は第4章のまま — 化粧品のお客が2人増えただけです: スライドの `reverse` と巻き戻し時計の `undoFx`。どちらも `normalize` が歴史に入る前に剥がします。
- ロボットは時間ジャンプをまたいで呼吸します: `walkPhase` は巻き戻しの向こうへ乗り継ぎ、その最中も回り続けます（足を引きずる見た目）。滑っているあいだは戻している手それぞれの向きを着て、着地でスナップショットの向きに引き継ぐ — 1手ずつ、正直な逆再生のフィルムです。
- **CLEAR は自分で解除されます。** `won` は Store からの導出なので、勝利の一押しを巻き戻せばまた false になるだけ。フラグを立てていないから、下ろすフラグもない — テストがピン留めしています。

### 試すこと

**redo** を配線してください。zipper の future レーンはもうそこにあるので、数行です: X キーを `redo` として `Input` に読み、`tick` で「押されていて、かつ何も滑っていない」ときに `Worldline.redo(line)` を呼ぶだけ。そして future が蒸発するのを見てください: 2回 undo して、*別の*手を指してから redo してみる — `record` が、乗り捨てた時間線を捨てたはずです。

`historyCap` を `3` にして4回押してみてください: 4回目の undo には帰る場所が残っていません。忘れるには設定が要り、覚えていることがデフォルトでした。

そして逆スライドの重さを味わってください: `undoDuration` を `0.125`（歩行と同速）にすると、巻き戻しが巻き戻しに見えなくなります — 次に `clockNeedle` の向きの符号を反転して、なぜ反時計回りが「時間を戻る」の意味になるのかを体感してください。

---

## 第6章 — 動かしたまま編集できる画面

**ゴール:** ゲームに玄関を付けます — タイトルページ、手数を知っている本物の CLEAR パネル、レベルからレベルへの道 — そして語彙の6語目に出会います。画面の見た目を、*ゲームを動かしたまま*、何も再コンパイルせずに編集して。

このゲームはどんな間違いでも取り消せます — でもレベルを解いたとき、"CLEAR!" はただ浮かんでいるだけで、2つ目の盤面へ行く方法はソースを書き換えることだけです。よく遊べて、迎え方を知らないゲーム。画面というものは2つの問いを立て、その2つの答えは別々の場所に住みます。

### どのページが映っているか — それは状態

「プレイヤーがいまどのページを見ているか」はフレームをまたいで生き残るべき事実で、それが何を意味するかは第2章が言いました: World に住み、変えるのは純粋な tick だけです。

```flix
    // ── Screen: which page of the game the frame shows ──
    // The screen is state like everything else, so it lives in the World and
    // the pure tick owns every transition: Title --Enter--> level 1,
    // CLEAR --Enter--> the next level (or back to Title after the last one),
    // X abandons a level. Each transition starts a fresh Worldline — history
    // belongs to one attempt at one board.
    pub enum Screen with Eq {
        case Title
        case Playing
    }
```

`Input` にはキーが3つ増えます — `enter`・`back`（X）・`esc` — そして `enter` と `esc` は押しっぱなしの**レベルではなくエッジ**です: ループが今フレームのキーを前フレームと見比べ、キーが下りたそのフレームだけ World に `true` を手渡します。指がどれだけ長く乗っていても、1押しでめくれるページはちょうど1枚。そして `tick` は、第5章が組んだ機械の上に載るページめくり係になります — あの機械は一切無傷のまま下で生きていて、名前だけ `playTick` に変わりました:

```flix
    pub def tick(input: Input, dt: Float64, line: Worldline[World]): Worldline[World] =
        let World.World(b) = Worldline.current(line);
        match b#screen {
            case Screen.Title =>
                if (input#enter) freshLine(playingWorld(1)) else line
            case Screen.Playing =>
                let world = Worldline.current(line);
                if (won(world))
                    // CLEAR is modal: only Enter and Escape are heard. The
                    // picture still breathes — the winning slide lands, the
                    // clock fades — but walking and rewinding fall silent.
                    if (input#enter)
                        (if (b#level < levelCount()) freshLine(playingWorld(b#level + 1))
                         else freshLine(titleWorld()))
                    else if (input#esc)
                        freshLine(titleWorld())
                    else {
                        // The party clock: confetti is a pure function of
                        // how long the board has been solved.
                        let World.World(b1) = step(noKeys(), dt, world);
                        Worldline.replaceCurrent(
                            World.World({ clearElapsed = b1#clearElapsed + dt | b1 }), line)
                    }
                else if (input#back)
                    freshLine(titleWorld())
                else
                    playTick(input, dt, line)
        }

    /// A brand new Worldline around one World: how every screen transition
    /// begins. The previous history is dropped with the previous screen.
    def freshLine(w: World): Worldline[World] =
        Worldline.make(w, historyCap())
```

（モーダル分岐の party clock の行は第8章の紙吹雪のものです — いまは読み飛ばしてください。）

2つ、目を近づける価値があります。**CLEAR はモーダルです。** `won` が true になった瞬間、解けた盤面は完成した写真になります: 方向キーは何も動かさず、Z は — 初めて — 拒まれます。勝利の一押しがパネルの下から巻き戻されることはありません。世界は凍っているのではなく、耳をふさいでいるだけです: `step(noKeys(), ...)` は回り続けるので、最後のスライドはちゃんと着地し、巻き戻し時計はちゃんと消えていきます。Enter はページをめくり（次のレベル、最後のレベルの後はタイトル）、Escape はパネルを閉じてタイトルへ — 写真が返事をするのはこの2つのキーだけ。

そして**すべての遷移は `freshLine`** — 1つの World を包む真新しい Worldline です。歴史は「1つの盤面への1回の挑戦」に属します: X でレベルを離れて戻ってくれば、past は真っさら。時間機械が戸口をまたぐことはありません。

### 6語目: Spec

2つ目の問い: ページの*見た目*はどこに住むのか — パネルの色、フォントサイズ、書かれた言葉。World ではありません:「タイトルは桃色」はルールが参照する事実ではない。そして、こちらが面白いところ — コードでもありません。このエンジンが何度でも帰ってくる経験則は:

> **再コンパイルせずに変えたいものは、データにする。** ものを計算するのではなく*記述する*データを **Spec** と呼ぶ。

ここに種明かしがあります: あなたは第4章からずっと Spec を書いてきました。レベル文字列こそがそれです — 盤面を記述するデータで、純関数が Store へパースし、ルールに一切触れずに自由にデザインできた。新しいのは、レベルテキストが盤面にしてくれたことを画面にもする、その一歩だけです。タイトルページの全文が `assets/Title.ui.json`:

```json
{
  "root": {
    "name": "Title", "widget": "none", "visible": false, "layer": 1,
    "dir": "column", "mainAlign": "center", "crossAlign": "center", "gap": 8,
    "children": [
      { "name": "title", "widget": "text", "text": "SOKOBAN",
        "font": "default", "fontSize": 40, "tint": "#eec39a", "zIndex": 110 },
      { "name": "rule", "widget": "box", "color": "#d9a066",
        "width": 150, "height": 2, "zIndex": 110 },
      { "name": "subtitle", "widget": "text", "text": "push crates. rewind time.",
        "font": "default", "fontSize": 12, "tint": "#847e87", "zIndex": 110 },
      { "name": "spacer", "widget": "none", "width": 1, "height": 16 },
      { "name": "prompt", "widget": "text", "text": "Press Enter",
        "font": "default", "fontSize": 14, "tint": "#fbf236", "zIndex": 110 }
    ]
  }
}
```

名前つきノードの木です: `widget` がノードの正体を言い（`text`・`box`・入れ物の `none`）、レイアウトキー（`dir`・`mainAlign`・`crossAlign`・`gap`）が子の流れ方を言い、色は Palette が役割名で使うのと同じ DB32 の16進です。`assets/Clear.ui.json` はその兄弟: 枠線つきパネルに3行のテキスト — `headline`・`moves`・`prompt`。このフォーマットは `engine_world`（`Worldline` を連れてきたあのライブラリ）のもので、`UiSpec` がパースし、全ノードが **UiWorld** — UI ノードの Store、ただの1個の値 — に収まって、`"Clear/panel/moves"` のような名前パスで指せるようになります。

### ページを spawn し、World をページへ映す

```flix
    pub def titleUiPath(): String = "assets/Title.ui.json"
    pub def clearUiPath(): String = "assets/Clear.ui.json"

    def designSize(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// Spawn both page Specs into one UiWorld. A broken or missing file
    /// degrades to no page — the game still runs, like a broken level string.
    def loadUi(): UiStore.UiWorld \ Fs.FileRead =
        UiStore.empty() |> spawnPage(titleUiPath()) |> spawnPage(clearUiPath())

    def spawnPage(path: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match UiSpec.spawnAsset(path, ui) {
            case Result.Ok((_, ui1)) => ui1
            case Result.Err(_)       => ui
        }

    /// Stamp the World onto the UI store: page visibility and the move count.
    /// The count is nobody's counter — it is Worldline.pastLength, handed in
    /// by the loop: the history was already counting the moves.
    pub def projectUi(moves: Int32, w: World, ui: UiStore.UiWorld): UiStore.UiWorld =
        let World.World(b) = w;
        ui |> UiStore.setVisible("Title", b#screen == Screen.Title)
           |> UiStore.setVisible("Clear", b#screen == Screen.Playing and won(w))
           |> UiStore.setText("Clear/panel/moves", "Moves: ${moves}")
```

`loadUi` は起動時に1回走ります（エフェクトに注目: `\ Fs.FileRead` — ファイルを読むのはプログラムの外の話で、シグネチャがそう言っています）。`projectUi` は毎フレーム走り、これは正確に第2章の意味での Projection です — World を読んで絵を書く — ただしキャンバスが画面ではなく UI store なだけ: どのページが見えるか、moves の行が何と言うか。

そして手数がどこから来るかを見てください。手数カウンタは足していません。インクリメントするものも、リセットするものも、リセットし忘れるものもない。`Worldline.pastLength` — 背後に綴じられた World の数 — が*そのまま*手数です。第5章が1手にちょうど1スナップショットを記録するからです。undo すれば数字はひとりでに減り、表示している数はいつでも巻き戻せる数と一致する。時間機械は最初からずっとスコアも付けていました。

### ループ、最終形

```flix
    /// While the CLEAR panel is up, Escape closes the panel (back to the
    /// title) instead of the window.
    def clearModal(w: World): Bool =
        let World.World(b) = w;
        b#screen == Screen.Playing and won(w)

    /// The loop threads three values: the UI store, the Worldline, and last
    /// frame's key state (enter and esc start true so a key already held at
    /// launch says nothing until released once).
    def loop(atlas: FontAtlas, ui: UiStore.UiWorld, line: Worldline[World],
             prev: { enter = Bool, esc = Bool, f1 = Bool }): Unit \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead} =
        let escDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Escape);
        let escEdge = escDown and not prev#esc;
        if (GameEngine.Game.shouldClose()
            or (escEdge and not clearModal(Worldline.current(line)))) ()
        else {
            let enterDown = GameEngine.Game.isKeyPressed(GameEngine.Key.Enter);
            let f1Down = GameEngine.Game.isKeyPressed(GameEngine.Key.F1);
            let line1 = tick(readInput(enterDown and not prev#enter, escEdge), readDt(), line);
            match sfxEvent(line, line1) {
                case Some(name) => GameEngine.Audio.playAudio(name)
                case None       => ()
            };
            // F1 re-reads every spawned Spec from disk: edit the json while
            // the game runs, press F1, and the page changes under you.
            let ui1 = if (f1Down and not prev#f1) UiSpec.reloadAll(ui) else ui;
            let world = Worldline.current(line1);
            let ui2 = projectUi(Worldline.pastLength(line1), world, ui1);
            let (drawables, polys) = frame(atlas, world);
            let out = UiRender.renderUi(ui2, designSize());
            GameEngine.Game.renderCommands(
                List.append(drawables, out#drawables), Nil,
                List.append(polys, out#polygons));
            loop(atlas, ui2, line1, { enter = enterDown, esc = escDown, f1 = f1Down })
        }
```

（`sfxEvent` の match と `GameEngine.Audio` effect は第8章の音が先に届いたものです — 手書きのループとしては、これが最終形です。）

UiWorld はループの中、Worldline の隣に住みます — 時間機械が使ったのと同じ文法: ただの値を糸のように通す、グローバルにはしない。毎フレーム `UiRender.renderUi` が見えているページをレイアウトし、`frame` が既に作っているのと同じ2チャンネルで箱とグリフを返す; ループはそれを連結して1回の呼び出しでエンジンに渡します。タイトルページでは `frame` は*何も*描きません — あの画面に見えているものは、すべて Spec です。

そして、小さなキーに大きな帰結がひとつ: **F1** は `UiSpec.reloadAll` を呼び、spawn 済みのすべての Spec をディスクから読み直してノードをその場で組み直します。パースに失敗したファイルは古いページを保ちます — リロードが動いているゲームを壊すことはありません。

ここまでのループは、この章の時点の姿です。出荷されているリポジトリのコードはもう一歩進んでいて、手書きのループはエンジンの **App** に置き換わりました: App が毎フレーム1回キーと時計を **Frame** という値に写し取り、`App.addSystem(Controls.step)` のように差し込まれた純粋な部品へ順に手渡します（英語版チュートリアルはこの形で書かれています）。

入力まわりでは、設計がひとつ進んでいます。キーを1本ずつ直接読む代わりに、**まず「操作の意図」（Intent）の表に写してから読みます**。表を引くのは InputMap — エンジン（v0.3.2）の語彙です。同じ意図に複数キーを並べられるので、WASD と矢印の両対応が表 1 行ずつで済みます。表は2枚あって、この章で手作りした「エッジかレベルか」の区別が、どちらの表に住むかという選択になります: 押しっぱなしで効く操作（移動、Z の巻き戻し、X のリセット）は `heldTable`、押した瞬間だけ効く操作（Enter と Escape）は `tapTable`。出荷されている `src/Controls.flix` の中身がこれです:

```flix
mod Controls {
    use GameEngine.Key

    /// 操作の意図。キーとの対応は heldTable / tapTable が持ち、ルールはこの意図だけを見る。
    enum Intent with Eq {
        case MoveUp
        case MoveDown
        case MoveLeft
        case MoveRight
        case Undo
        case Reset
        case Confirm
        case Cancel
    }

    /// 押しっぱなしで効く操作の表。移動は WASD と矢印のどちらでも同じ意図になる。
    def heldTable(): InputMap.Table[Intent] =
        (Key.W,     Intent.MoveUp)    ::
        (Key.Up,    Intent.MoveUp)    ::
        (Key.S,     Intent.MoveDown)  ::
        (Key.Down,  Intent.MoveDown)  ::
        (Key.A,     Intent.MoveLeft)  ::
        (Key.Left,  Intent.MoveLeft)  ::
        (Key.D,     Intent.MoveRight) ::
        (Key.Right, Intent.MoveRight) ::
        (Key.Z,     Intent.Undo)      ::
        (Key.X,     Intent.Reset)     :: Nil

    /// 押した瞬間だけ効く操作の表（決定と、CLEAR を閉じる・終了の Escape）。
    def tapTable(): InputMap.Table[Intent] =
        (Key.Enter,  Intent.Confirm) ::
        (Key.Escape, Intent.Cancel)  :: Nil

    /// このフレームのキーを sokoban の意味（Board.Input）へ写す。押しっぱなし系と
    /// 単発系それぞれの発火した意図を、中立の入力へ旗として畳み込む。
    pub def inputOf(frame: App.Frame): Board.Input =
        let held = InputMap.held(heldTable(), frame) |> List.foldLeft(applyHeld, Board.noKeys());
        InputMap.taps(tapTable(), frame) |> List.foldLeft(applyTap, held)

    /// 押しっぱなし系の意図 1 つを Input の旗にする。
    def applyHeld(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.MoveUp    => { up = true | acc }
        case Intent.MoveDown  => { down = true | acc }
        case Intent.MoveLeft  => { left = true | acc }
        case Intent.MoveRight => { right = true | acc }
        case Intent.Undo      => { undo = true | acc }
        case Intent.Reset     => { back = true | acc }
        case _                => acc
    }

    /// 単発系の意図 1 つを Input の旗にする。
    def applyTap(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.Confirm => { enter = true | acc }
        case Intent.Cancel  => { esc = true | acc }
        case _              => acc
    }

    /// 毎フレームのシステムその一: キーを Input へ写し、tick のルールで盤面と履歴を
    /// 1 歩進める（純粋）。
    pub def step(frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { line = Sokoban.tick(inputOf(frame), frame#dt, s#line) | s }

    /// 毎フレームのシステムその二: 進んだ後の盤面から UI ページの見た目を導く
    /// （Title / Clear の表示切替と手数の文言）。UI の状態はここで毎フレーム
    /// 上書きされるので、どの画面に居るかを UI 側が別に覚える必要はない。
    pub def projectUi(_frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { ui = GameUi.projectUi(Worldline.pastLength(s#line), Worldline.current(s#line), s#ui) | s }

    /// F1 リロード: 生成済みの UI Spec を 1 つ残らずディスクから読み直す。
    /// ゲーム実行中に ui.json を編集し、F1 を押せば、その場でページが変わる。
    pub def reloadUi(s: Sokoban.Session): Sokoban.Session \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(s#ui) | s }

    /// 終了判定: Escape の押した瞬間 —— ただし CLEAR パネルが出ている間は除く
    /// （そのときの Escape はパネルを閉じる操作として tick が受け取る）。
    pub def wantsQuit(frame: App.Frame, s: Sokoban.Session): Bool =
        inputOf(frame)#esc
            and not Sokoban.clearModal(Worldline.current(s#line))
}
```

（このファイルでは盤面のルールと `Input` のレコードは `Board.flix` に住んでいます。）ルールが見るのは相変わらず `Input` のレコードだけです — どのキーがどの意図だったかを知っているのは、この表だけ。キーを1本足すのも、割り当てを変えるのも、表の1行で済みます。

### 何が起きたか

- 画面は2つの問いを立て、答えの住所は別々です。*どのページか*は状態 — World の `Screen` 値で、遷移はすべて純粋な tick が握る。*ページがどう見えるか*は **Spec** — ディスク上のデータで、UiWorld に spawn され、ルールから参照されることはない。
- **Spec が6語目です**: 再コンパイルせずに変えるべきものは、それを記述するデータにする。レベルは名前が付く前から Spec でした; いまやページもそうです。World、Step、Projection、Store、Worldline、**Spec**。
- **CLEAR はモーダルです。** 解けた盤面は Enter と Escape にしか返事をしません — 歩行も巻き戻しも沈黙し、完成した局面とその手数は稼いだままの姿で残ります。絵は呼吸を続け、狭まるのはキーボードだけ。
- **手数は最初からそこにありました。** 歴史が1手1スナップショットを記録するから、`Worldline.pastLength` がそのまま手数 — カウンタは足さず、undo はひとりでに引き算します。
- UiWorld はループのもう1つの値で、Worldline の隣にいます。World は UI の存在を知らないまま; 毎フレーム、projection が判定を押印するだけです。

### 試すこと

この章の本当の演習はリロードのループです。ゲームを走らせ、タイトルに置いたまま、エディタで `assets/Title.ui.json` を開いてください。タイトルの `tint` を、prompt の `fontSize` を、subtitle の言葉を変える。保存して、ゲームに切り替えて、**F1**。再コンパイルなし、再起動なし、状態も失われない — ページはただ、ファイルが言う姿になります。これが Spec の買ってくれるもの: 見た目の反復が、ファイル保存の速度で回ります。

今度はわざと壊してください: カンマを1個消して、F1。古いページが残ります — パースできなくなった Spec は最後の正しい形を保つ。カンマを直して、もう一度 F1。

CLEAR パネルに飾りを足してみましょう: `moves` の下に4つ目のテキストノードを足す（名前は何でも構いません — どのコードもそれを指さないので、コードは1行も要りません）、あるいはパネルの `borderColor` を変える。F1。

それから3つ目のレベルを。`Level.three()` に新しい盤面文字列、`levelCount()` が `3` を返す — Spec 1枚と数字1個。画面の流れはもう道を知っています: CLEAR、Enter、次の盤面、最後の後はまたタイトル。

---

## 第7章 — リプレイという証明

**ゴール:** ウィンドウなしでゲーム全体を走らせます — 解法を証明し、フィルムに撮り、ギャラリーを出版する — そして語彙の最後の2語に出会います。この章はゲームに何も足しません: 状態も、ルールも、ピクセルも。この作り方をしたゲームが*ただでくれるもの*の話です。

### 7語目: Harness

画面なしでゲームを走らせるには、ゲームが普段ウィンドウに尋ねるすべての問いに、何かが答えなければなりません: どのキーが下りているか、いま何時か、フォントはどこにあるか。その身代わりの答えの束を **Harness** と呼びます。大きなゲームでは Harness は本格的なエンジニアリングです — 頼っている effect 1つにつき handler が1枚積み上がる。このエンジンの大きい方の例は18枚を配線しています。sokoban のは、これで全文です:

```flix
// Harness — everything needed to run the whole game without a screen.
//
// It is short on purpose, and the shortness is the point: tick is a pure
// function, so the rules need no harness at all. Only the *picture* touches
// the outside world, and it wants exactly three things — a font atlas baked
// headlessly, the Fs handlers to read the ui.json Specs, and a stub of the
// Game effect whose only real answer is that font atlas. Every other
// operation returns a constant.
mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// The font, baked without a window (AWT headless metrics only).
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.ensureHeadless();
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt")

    /// Both page Specs spawned into one UiWorld, as the launcher does.
    pub def ui(): Option[UiStore.UiWorld] \ IO =
        run {
            forM (a <- UiSpec.spawnAsset(Sokoban.titleUiPath(), UiStore.empty()) |> Result.toOption;
                  b <- UiSpec.spawnAsset(Sokoban.clearUiPath(), snd(a)) |> Result.toOption)
            yield snd(b)
        } with Fs.FileRead.runWithIO

    /// A Game handler with no GL behind it. renderUi only ever asks for the
    /// font atlas; a handler must still name every operation, so the rest
    /// answer with constants.
    pub def withMockGame(atlas: FontAtlas, f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, k)  = k(())
            def initTileBuffer(_, k)        = k((0i32, 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.1))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(atlas)
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 320.0, y = 240.0}})
            def getTextureInfo(_, k)        = k(None)
            def setCursor(_, k)             = k(())
        }
}
```

冒頭のコメントをもう一度読んでください — このチュートリアル全体が歩いて向かってきた逆説がそこにあります。6つの章にわたって `tick` を純粋に保つと言い張ってきたこと — キーはデータで、時計は引数で — は、それ自体のための規律に見えたかもしれません。ここでその配当が*不在*として支払われます: ルールには Harness が要らない。小さいのが要る、ではなく。ゼロ。上の身代わりはすべて絵のためであって、ゲームのためではありません — フォント1つ、ファイル handler 2枚、そして12 operation のうち11個が定数で1個がアトラスの Game スタブ。純粋な芯が触る境界が薄いほど、それを偽る Harness も薄くなります。

### 8語目: Trace

**Trace** は入力のリストです — それだけ:

```flix
    /// One beat of a Trace: hold this input for n frames.
    pub type alias Cue = { input = Sokoban.Input, frames = Int32 }

    /// The fixed clock every replay runs on: 1/64 s per frame — dyadic, so
    /// every slide t and walk phase in the pinned outcomes is exact.
    pub def dt(): Float64 = 1.0 / 64.0
```

そしてそれを駆動するのは fold です — `tick` が純粋で、時計が値として届くから。同じリストを入れれば、同じ Worldline が出てくる — どの実行でも、どのマシンでも、永遠に。その確実さの上に、解法を*データとして*書けます:

```flix
    /// One walked move: tap the key for a frame, then let the slide land
    /// (a slide is 0.125 s = 8 frames at this clock).
    pub def walk(d: Dir4.Dir4): List[Cue] =
        hold(dirInput(d), 1) :: hold(idle(), 8) :: Nil

    /// Z held for n frames — each landed reverse slide chains the next
    /// rewind, so one long hold walks the history back move by move.
    pub def rewind(frames: Int32): Cue =
        hold({ undo = true | idle() }, frames)

    /// The shipped solution of level 1, as data: seven moves. The two
    /// pushes are the third move (lower crate to its goal) and the last
    /// (upper crate home — CLEAR).
    pub def solveLevelOne(): List[Cue] =
        List.flatMap(walk,
            Dir4.Left :: Dir4.Up :: Dir4.Right ::
            Dir4.Up :: Dir4.Right :: Dir4.Up ::
            Dir4.Left :: Nil)
```

すると解法は*テストになります* — それがこの章の題名です:

```flix
    @Test
    def testReplaySolvesLevelOne(): Unit \ Assert =
        // The shipped solution, driven through the pure tick at a fixed dt.
        // Same Trace, same Worldline, always: the win, the move count and
        // the final positions are pinned as plain values.
        let end = Replay.play(Replay.solveLevelOne(), fresh(Sokoban.playingWorld(1)));
        let w = Worldline.current(end);
        Assert.assertEq(expected = (true, 7, (3, 2), Set#{(2, 2), (4, 4)}),
            (Sokoban.won(w), Worldline.pastLength(end), robotOf(w), cratesOf(w)))
```

この種のテストは **golden** と呼ばれます: 期待値はテストの中で導出されるのではなく、*ピン留め*されています — 具体的な事実として、人間が一度確かめて、凍結する。それ以降、差分の意味はきっかり2つのどちらかです: バグか、意図した変更（なら pin を意図的に更新する）か。中間はなく、言い争う flakiness もない — この契約をここまで無愛想にできるのは決定論のおかげです。

レベル2も同じ扱いを受けます: `solveLevelTwo` — 内壁が強いる遠回りを縫う21手 — にも専用の pin があります。これで出荷している2つのレベルは、どちらも*解けることが証明済み*です。第4章では手で一度確かめただけでした; いまや毎回、機械の仕事です。

### 1つの Trace、3つの成果物

同じ7手は、フィルムでもあります。`Replay.timeline` は Trace の全フレームを返し、各フレームはランチャーが使うのと*同じ*射影の積み重ね — `frame`、`projectUi`、`renderUi` — を、ウィンドウの代わりに Harness の下で通ります:

```flix
    def bakeGif(atlas: FontAtlas, ui: UiStore.UiWorld, cues: List[Replay.Cue],
                start: Worldline[Sokoban.World], path: String): Unit \ IO =
        let film = Replay.timeline(cues, start);
        let frames = List.map(l -> SoftRaster.renderToImage(rasterReq(atlas, scene(atlas, ui, l), path)),
                              every(gifSampleStride(), 0, film));
        GifEncoder.encode(frames, gifFrameDelayMs(), path)
```

`flix test` を走らせると `gallery/` が満ちていきます: スクリーンショット4枚（タイトルページ、静止したレベル1、スライド中間で凍った押し、7手を数える CLEAR パネル）、フィルム3本 — `solve_level1.gif` はタイトルから最初の CLEAR までの開幕、`full_clear.gif` はゲームまるごと1周 — 両レベル、両 CLEAR、そしてタイトルへの帰還、`rewind_demo.gif` は3手進めて Z 長押し、ロボットと木箱が家へ滑って帰るあいだ目覚まし時計が反時計回りに回る — そして全部をページに並べる `index.html` ダッシュボード（engine_tools の SnapshotSite）。フォルダごと消しても、テスト1回で全ピクセルが再建されます。

そして3つ目の成果物は無料です: 失敗する Trace は**そのまま**バグ報告です。「この入力列で、この結果」 — チケットに貼れば永遠に再現し、`tick` に畳めばそのまま回帰テストです。

### 何が起きたか

- **Harness が7語目**: ウィンドウなしでゲームを走らせる身代わりの束。その大きさはアーキテクチャの*実測値*です — sokoban の実測はフォント1つ、ファイル handler 2枚、12行のスタブ。ルール自体が純粋で、何も要らないから。
- **Trace が8語目**: 固定時計の上の、データとしての入力列。決定論が1つの Trace を3つの成果物に変えます — golden テスト、フィルム、バグ報告 — そして三者は決して食い違えない。同じリストなのだから。
- ギャラリーは使い捨ての出力であってソースではない: `flix test` が全 PNG・全 GIF・ダッシュボードをコードと Spec から再生成します。
- 語彙は8語で止まります。Worldline アーキテクチャにはもっと大きなゲームのための言葉がまだあります — シミュレーションの歩みを持つ **Driver**、world をまたいで共有される状態のための **Resource** — このゲームには要りませんでした。それが正直な結末です: あるだけの言葉ではなく、ゲームが必要とする言葉に手を伸ばす。

### 試すこと

遠回りをしてみてください: レベル1のわざと*長い*解法を Trace に書いて — 押す前にしばらくさまよって — 自分のテストとして pin する。どちらの道順も同じ箱を同じゴールに置きますが、pin は1つの数字で食い違います: `Worldline.pastLength`。手数はあなたの道順の指紋です。それから道順を切り詰めて、指紋が縮むのを見てください — 出荷版の7手は破れますか？

フィルムの速度を変えてみてください: `gifSampleStride` を 1 に下げれば逆スライドのスローモーション研究、`gifFrameDelayMs` を 80 に上げればパラパラ漫画。テスト1回で3本全部の GIF が切り直されます。

自分の場面をダッシュボードに足してみましょう: `Replay` で Worldline を組み（巻き戻しの途中はいい画になります）、新しい PNG へ `shot` して、カタログに `item` を1行。あとはサイト生成器がやってくれます。

---

## 第8章 — 最後の10%

**ゴール:** 紙吹雪、手応え、音 — プレイヤーが *juice* と呼ぶ磨きの工程です — を、もう卓上にある語彙だけで書きます。この章に新しい言葉は出てきません。それがこの章の主張です。juice はシステムを要求する評判があります: パーティクルシステム、アニメーションシステム、イベントバス。ここではその一滴一滴が、導出と、World の小さな数字1個と、ループの縁の1呼び出しです。

### パーティクルシステム無しの紙吹雪

パーティクルシステムは生きた粒の配列を持ち、毎フレーム全部を更新します — 位置 += 速度、寿命 -= dt、spawn、free。私たちはそのどれも保存しません。World に増える数字はちょうど1個、モーダルな CLEAR 分岐が進める `clearElapsed`（パーティーの時計）だけで、紙吹雪の一片一片はその時計と自分の番号の*閉形式の関数*です:

```flix
    // ── Confetti: rain without a particle system ──
    // No particle is stored anywhere. Each piece's position, spin and color
    // are a pure function of (its index, the seconds since the board was
    // solved): the whole rain is a derivation from one number in the World,
    // clearElapsed. There is nothing to spawn, update or free — leaving the
    // screen simply stops asking for the picture.

    def confettiCount(): Int32 = 48

    def zConfetti(): Int32 = 95

    /// A cheap integer hash onto [0, 1): piece i's k-th personal constant.
    /// The same piece always gets the same answers, so it always flutters
    /// the same way — determinism all the way down to the party.
    def chip(i: Int32, k: Int32): Float64 =
        let h = i * 374761393 + k * 668265263 + 1442695041;
        Int32.toFloat64(Int32.modulo(h * (h + 30011), 100003)) / 100003.0

    /// Where piece i hangs t seconds into the party: it falls at its own
    /// speed, sways on its own sine, spins at its own rate, and wraps back
    /// above the screen so the rain never runs out.
    def confettiQuad(t: Float64, i: Int32): GameEngine.PolygonRenderCmd =
        let speed = 55.0 + 50.0 * chip(i, 1);
        let sway = 6.0 + 10.0 * chip(i, 2);
        let phase = 6.283185307179586 * chip(i, 3);
        let spin = (2.0 + 4.0 * chip(i, 4)) * (if (chip(i, 5) < 0.5) -1.0 else 1.0);
        let x = 320.0 * chip(i, 6) + sway * RenderUtil.sinF(1.5 * t + phase);
        let y = fract((speed * t + 260.0 * chip(i, 7)) / 260.0) * 260.0 - 10.0;
        let a = spin * t + phase;
        let u = { x = RenderUtil.cosF(a), y = RenderUtil.sinF(a) };
        let v = { x = -u#y, y = u#x };
        let c = { x = x, y = y };
        let corner = (sx, sy) -> Vec2.add(c, Vec2.add(Vec2.mul(u, sx * 2.2), Vec2.mul(v, sy * 1.4)));
        { vertices = corner(-1.0, -1.0) :: corner(1.0, -1.0) ::
                     corner(1.0, 1.0) :: corner(-1.0, 1.0) :: Nil,
          color = Palette.confetti(i), alpha = 1.0f32, zIndex = zConfetti() }

    /// The whole rain: one quad per index while the party clock runs.
    pub def confettiQuads(b: Board): List[GameEngine.PolygonRenderCmd] =
        if (b#clearElapsed <= 0.0) Nil
        else List.map(confettiQuad(b#clearElapsed), List.range(0, confettiCount()))
```

`chip` が各片に個人的な定数 — 落下速度、揺れ、回転、初期位置 — を配ります。毎フレーム同じもの、永遠に同じもの。落下は折り返し（`fract`）て雨が尽きることはなく、回転は木箱や時計の針が既に使っているポリゴンチャンネルの回転 quad です。何も spawn せず、何も更新せず、何も free しない: Escape を押せば、雨はただ*もう尋ねられなくなる*だけです。そして時刻 t の雨が純粋な値だから、*パーティーはユニットテストできます* — 2回尋ねたら同一の絵、という pin が立っています。

閉形式の粒は見た目より遠くまで運べます: 花火、煙、きらめき — 片どうしが相互作用しないものは何でも `(番号, t)` の関数にできます。天井は相互作用（ぶつかり合う破片には本物の状態が要る）ですが、お祝いに物理はめったに要りません。

### 手応え

押しは歩きより*重く感じられる*べきです。手を入れたのは2箇所、意図してそれ以上はやりません:

```flix
    /// The robot leans into its work: while a forward push slides, the whole
    /// picture sits one pixel lower — weight on the crate, nothing more.
    def robotDrawCenter(b: Board): Vec2.Vec2 =
        let c = robotCenter(b);
        { x = c#x, y = c#y + pushSink(b) }

    def pushSink(b: Board): Float64 =
        match b#slide {
            case Some(s) => if (s#pushing and not s#reverse) 1.0 else 0.0
            case None    => 0.0
        }
```

```flix
    /// The pushed crate's travel. It rides the robot's linear slide (a
    /// pushed thing cannot outrun its pusher), then over the last stretch
    /// pops about a pixel past the target and settles exactly as it lands.
    pub def settle(t: Float64): Float64 =
        if (t < 0.8) t
        else t + 0.06 * RenderUtil.sinF(3.141592653589793 * (t - 0.8) / 0.2)
```

どちらも第4章から Slide が持っていた `pushing` フラグからの導出で、新しい状態はゼロ。そしてどちらも意図的に微小です: 沈み1ピクセル、行き過ぎ1.5ピクセル。juice は足りないより、やりすぎで壊れることの方が多い — 仕掛けに気づかれた瞬間、効かなくなります。（`settle` が*やらない*ことに注目してください: 標準の ease-out-back 曲線はスライド中盤で木箱をロボットより先へ走らせてしまう — 押される物は押す者を追い越せないので、飛び出しは最後の一伸びまで待ちます。）

### 境界の音

4つの効果音は、ギャラリーと同じ**生成する資産**です: `test/SfxBake.flix` が 16-bit PCM の WAV として書き出します — 44 バイトのヘッダとサンプルのリスト、各サンプルは自分の番号の純関数。矩形波とノイズと線形フェードだけで、まるごと1つの音の語彙になります: 歩きの blip、押しの低い thud、巻き戻し1手ごとの高い tick、CLEAR の上昇4音。サンプルパックもマイクも無し — `flix test` が焼き、`project.json` が読み込みます。

このフレームが*どの*音に値するかは純粋な問いで、ゲームの他のあらゆる導出と同じように、2つの Worldline から読み取れます:

```flix
    /// What this frame sounds like: the winning push is a fanfare, a rewind
    /// ticks, a committed move thuds if it pushed and blips if it walked.
    /// Guarded to one page of one level, so screen changes stay silent.
    pub def sfxEvent(before: Worldline[World], after: Worldline[World]): Option[String] =
        let wb = Worldline.current(before);
        let wa = Worldline.current(after);
        let World.World(b) = wb;
        let World.World(a) = wa;
        let samePage = b#screen == Screen.Playing and a#screen == Screen.Playing
            and b#level == a#level;
        if (not samePage) None
        else if (won(wa) and not won(wb)) Some("clear")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) - 1) Some("undo")
        else if (Worldline.pastLength(after) == Worldline.pastLength(before) + 1)
            (if (a#crates != b#crates) Some("push") else Some("move"))
        else None
```

事実の出どころに注目してください: 手が確定したのは past がちょうど1つ伸びたとき、巻き戻しは1つ縮んだとき — Worldline は最初からイベントログでもありました。再生そのものは effect で、他の境界越えと一緒にループに住みます。第3章で開いたフレームがここで閉じます: キーと時計は値として*入って*きて、ピクセルと — いまや音も — コマンドとして*出て*いく。そのあいだは全部、純粋です。

（正直な注意をひとつ: 生成する資産は生成されなければなりません。最初の `flix run` の前に一度 `flix test` を走らせてください。さもないとサウンドマニフェストがまだ存在しないファイルを指します。）

### 何が起きたか

- **juice に新しい機構は要りませんでした。** 紙吹雪は数字1個の上の閉形式、手応えは既存フラグからの1ピクセル導出2つ、音は Worldline から読む純粋なイベント + ループの縁の `playAudio` 1つ。パーティクルシステムも、アニメーションシステムも、イベントバスも無し。
- **閉形式の粒は本物の技法です**、おもちゃではなく: 片どうしが相互作用しないものは `(番号, t) -> 片` にでき、テスト可能で、構造的にライフサイクルバグが存在しない。
- **音は生成する資産** — ギャラリーと同じ文法: `flix test` が書き、それを書くコードが正であり、出所を説明すべきバイナリの塊がどこにもない。
- **語彙は増えませんでした。** 磨きの工程にも8語で足りました。

### 試すこと

タイトルページに雪を降らせてください: `confettiQuads` に必要なのは時計だけなので、タイトルに専用の時計を与える — あるいはタイトルの経過時間をそのまま渡す — そして `Palette.confetti` の色を白系に。同じ閉形式が吹雪になります。

5つ目の音を足してください: *拒まれた*押し（壁に当たった木箱）。事実はもう Worldline の中にあります — ロボットのセルは変わらず facing だけ変わった — ので、`sfxEvent` に分岐を1つ、焼き込みに `square` を1つ。80 Hz の鈍い「ゴッ」がよく合います。

thud を調律してください: ノイズを増やし矩形波を減らすと段ボールの滑り、逆にすると石。音の全体が11行 — ダウンロードするより調律の方が速い。

---

## ここまでのまとめ

- ゲームは3拍子のループ: **`world |> step |> frame`** — 進めて、映して、描く。
- **World** は全状態が住む1個の値。**Step** はそれを進める純関数。**Projection**（`frame` など）は変えずに読むだけ。**Store** は同じ種類の状態をたくさん持つ World のフィールド。**Worldline** は World の軌跡 — past・current・future — で、`record` と `undo` がその上を歩く。World の中ではなく、隣に住む。**Spec** はものを記述するデータ — レベル文字列、ページの `ui.json` — 再コンパイルせずに変えたいすべてのために。**Harness** はウィンドウなしでゲームを走らせる身代わりの束。**Trace** は結果が常に同じになる入力列 — 1つの解法がテストでありフィルムでありバグ報告でもある。
- 世界の外にあるもの — キーボード、手打ちのレベル、時計 — は境界で読まれ、ただのデータとしてルールに入る。
- 導出できる状態（「パズルは解けたか？」など）は保存しない。映すだけ。そして1個の値である状態は*取っておける* — だから時間旅行が2つの呼び出しになる。
- あなたが編集するのは、ほとんどいつも `step` か `frame`。
- 色は DB32 の**役割名**から、形は**比率と重ね順**で。

ゲームは完成しました: 待っていてくれるタイトル、滑って記憶する盤面、巻き戻せる間違い、スコアを知っている CLEAR パネル、動かしたまま着せ替えられるページ — そしてテストのたびにその全部を証明するギャラリー。旅の全部を8つの言葉が運びました。次に作るゲームは、初日からこの8語全部の上で始められます。
\n
---

## エピローグ

旅は終わりました。卓の上を数えましょう。完全なゲームが1本 — タイトル、2つのレベル、回る時計つきの undo、動かしたまま着せ替えられるページ、紙吹雪とファンファーレ。解法まるごとをリプレイして結果を具体値で pin する55本のテスト。テストのたびに自分のスクリーンショットとフィルムとダッシュボードを焼き直すギャラリー。コードリスティングがソースと突き合わされる2言語のチュートリアル。そしてその全部を運んだ、8つの言葉: **World、Step、Projection、Store、Worldline、Spec、Harness、Trace**。

8語のどれも突飛ではありません。その中身はたった1つの規律 — 状態は1個の値、変化は純関数、それ以外はすべて導出か境界 — を、例外なく、規律だと感じなくなるまで適用しただけです。配当は勝手に届き続けました: undo は zipper からこぼれ落ち、手数カウンタは歴史からこぼれ落ち、リプレイは純粋さからこぼれ落ち、テストの Harness はほとんど消えてなくなりました。

ここからはあなたのものです。新しいレベルは `Level.flix` の文字列1個 — 書いて、解法を pin して、フィルムに加わるのを見てください。新しいゲームは空のファイルの上の同じ8語です。そしてこのリポジトリのルートにある `WORLDLINE_GUIDELINE.md` が、小さな倉庫番1本には要らなかった先まで含めて、このアーキテクチャの全体を書き上げています。

箱を押せ。時間を巻き戻せ。何かを出荷しよう。
