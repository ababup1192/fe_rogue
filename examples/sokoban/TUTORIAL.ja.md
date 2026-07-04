# つくって学ぶ Sokoban（倉庫番）

> English version: [TUTORIAL.md](TUTORIAL.md)

Flix でゲームを作りながら、少しずつ概念を増やしていくチュートリアルです。
読者は Flix を初めて触るプログラマを想定しています。難しい用語は、それが**必要になった瞬間**にだけ導入します。

この章で扱うのは、たったひとつの考え方です:

> **あなたは「今このフレームに描きたい物のリスト」を返す関数を書く。エンジンがそれを毎フレーム画面に描く。**

これだけで最初の2章は進みます。状態も、履歴も、まだ出てきません。

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

## ここまでのまとめ

- ゲームの「毎フレーム」は、**描きたい物のリストを返す関数を呼び続けているだけ**。
- あなたが書き換えるのは、ほとんどいつもその関数（`frame`）。
- 色は DB32 パレットの**役割名**から選ぶ。制約が選択を楽にする。
- 画像がなくても、単純な図形を**比率と重ね順**で組むと「木箱」と読める記号が作れる。

まだ「状態」も「動き」も出てきていません。次章から、箱を**動かしたく**なります。そのとき初めて「位置をどこに覚えておくのか？」という問いが生まれ、新しい言葉が必要になります。
