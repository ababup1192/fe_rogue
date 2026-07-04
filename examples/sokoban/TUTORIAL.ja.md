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
    def crateBoxes(): List[(Vec2.Vec2, Render.RenderItem)] =
        plank() :: List.flatten(seams() :: rails() :: frameJoints() :: outline() :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(): (Vec2.Vec2, Render.RenderItem) =
        boxAt(crateLeft(), crateTop(), crateSize(), crateSize(), Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = t * 0.04;
        List.map(i ->
            let x = crateLeft() + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, crateTop(), w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(): List[(Vec2.Vec2, Render.RenderItem)] =
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
    def frameJoints(): List[(Vec2.Vec2, Render.RenderItem)] =
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
    def outline(): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = 1.0;
        let x0 = crateLeft();
        let y0 = crateTop();
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        ({x = x, y = y}, Render.solidBox({x = w, y = h}, c, z))

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
    def titlePlacement(atlas: FontAtlas): (Vec2.Vec2, Render.RenderItem) =
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
    def crateBoxes(center: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let tl = topLeftOf(center);
        plank(tl) :: List.flatten(seams(tl) :: rails(tl) :: frameJoints(tl) :: outline(tl) :: Nil)

    /// Base plank: fill the whole tile with plank brown.
    def plank(tl: Vec2.Vec2): (Vec2.Vec2, Render.RenderItem) =
        boxAt(tl#x, tl#y, crateSize(), crateSize(), Palette.cratePlank(), zPlank())

    /// Vertical seams: 5 evenly spaced thin lines that make the interior read as 6 boards.
    def seams(tl: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = t * 0.04;
        List.map(i ->
            let x = tl#x + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, tl#y, w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// Outer frame: 2 full-width horizontal boards (top, bottom) and 2 vertical boards
    /// sandwiched between them (left, right).
    def rails(tl: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
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
    def frameJoints(tl: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
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
    def outline(tl: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let t = crateSize();
        let w = 1.0;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        ({x = x, y = y}, Render.solidBox({x = w, y = h}, c, z))

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
    def titlePlacement(atlas: FontAtlas): (Vec2.Vec2, Render.RenderItem) =
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
- `step` は毎フレーム定数（`crateSpeed` = 設計 1px）だけ木箱を動かします。経過時間（dt）ベースでなく毎フレーム定数を選んだのは意図的です: `step` のシグネチャを `World -> World` ちょうどに保てる — それがこの章の教材の芯です — し、倉庫番はグリッドのゲームなので、このチュートリアルの道筋では連続的な時間ベースの移動は通過点であって目的地ではありません。（正直なコスト: 120Hz のディスプレイでは 60Hz の倍速で滑ります。それが困るゲームはフレームの経過秒を `step` に通します。エンジンは経過時間を提供しています。）
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
                     facing = Robot.Direction, walkPhase = Float64 })
    }

    pub def initialWorld(): World =
        World.World({ robotX = centerX(), robotY = centerY(),
                      facing = Robot.Direction.Down, walkPhase = 0.0 })

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
    def facingOf(dx: Float64, dy: Float64, current: Robot.Direction): Robot.Direction =
        if (dx > 0.0)      Robot.Direction.Right
        else if (dx < 0.0) Robot.Direction.Left
        else if (dy > 0.0) Robot.Direction.Down
        else if (dy < 0.0) Robot.Direction.Up
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
    def titlePlacement(atlas: FontAtlas): (Vec2.Vec2, Render.RenderItem) =
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
- `readInput` のシグネチャを見てください: `Input \ GameEngine.Game`。Flix では、**その関数が何に触るかは型に書いてあります**。`\ GameEngine.Game` 自体は第0章から `start` と `loop` に付いていました — ループはウィンドウに絵を描くのだから、外に触るのは当然です。新しいのは境界線です: キーボードを読む場所はちょうど1箇所で、そこを過ぎればキーはただの Bool 4個のレコード。`step` の中で `isKeyPressed` を呼ぼうとすればコンパイラが止めます — ここでの純粋さは紳士協定ではなく、検査される性質です。
- *ルール*は全部いまも `step` の中にあり、どれも普通の世界のルールです: 逆向きのキーは打ち消し合う（`axis`）、斜めは横が勝つ（`facingOf`）、画面端で止まる（clamp）、全キーを離すと `walkPhase` が `0.0` に戻る — そして Robot の設計上、それが*そのまま*直立ポーズです。キーハンドラもコールバックも「入力システム」もなし: データが入り、World が出るだけ。
- `frame` は `Robot.parts` でプレイヤーを描きます — ギャラリーのファイルを焼いたのと*同じ関数*です。「ゲーム用の絵」は別に存在しません: 目で承認したギャラリーと画面の中のキャラクターは、ひとつの関数です。
- そして新しい語彙はゼロ: 画面のすべてはいまも **World**・**Step**・**Projection** で説明できます。`Input` は4語目ではなく、ループが `step` に手渡すただの値です。

### 試すこと

`robotSpeed` を `4.0` に — ロボットは急ぎ足になり、歩行サイクルがスケートに見えてきます。`walkRate` も合わせて上げてみてください。次はルールを変えます: 今のロボットは斜めに歩けます（両軸が同時に動く）。`step` でそれを禁止してみてください — たとえば横のキーペアが生きている間は縦のペアを無視する、など。純関数ひとつの `if` ひとつでゲームの手触りが変わります。`test/TestSokoban.flix` のテストを走らせて、どのピン留めされたルールを壊したか確かめてください。

---

## ここまでのまとめ

- ゲームは3拍子のループ: **`world |> step |> frame`** — 進めて、映して、描く。
- **World** は全状態が住む1個の値。**Step** はそれを進める純関数。**Projection**（`frame` など）は変えずに読むだけ。
- 世界の外にあるもの — キーボードなど — はループが読み、ただのデータとして `step` に入る。関数が何に触るかは effect 型に書いてあり、コンパイラがその線を守る。
- あなたが編集するのは、ほとんどいつも `step` か `frame`。
- 色は DB32 の**役割名**から、形は**比率と重ね順**で。

ロボットはもう、どこへでもなめらかに歩けます — でも倉庫番は「どこへでも」のゲームではありません。タイルのゲームです: 止める壁、1マスずつ動く木箱。木箱を*押す物*として連れ戻すには、みんなの足元に盤面が要ります。それが次章の問題です。
