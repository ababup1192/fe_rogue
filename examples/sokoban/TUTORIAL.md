# Learn by Building: Sokoban

> 日本語版はこちら: [TUTORIAL.ja.md](TUTORIAL.ja.md)

A tutorial that builds a game in Flix, introducing one concept at a time.
It assumes you are a programmer who has never touched Flix. Any new term waits
until the moment you actually need it.

These first chapters rest on a single idea:

> **You write a function that returns "the list of things I want drawn this frame."
> The engine draws that list, every frame.**

That's all you need for the first two chapters. No state, no history — not yet.

Each chapter lists the full code as it stands at that chapter; the repository
always contains the latest chapter's version.

---

## Before you start

From the repository root, distribute the engine libraries once (this delivers them
into `examples/sokoban/lib/`):

```sh
make sync
```

Run the game (a window opens):

```sh
cd examples/sokoban
java -XstartOnFirstThread -jar bin/flix.jar run
```

Press `Esc` or close the window to quit. Reading along without running anything
is fine too.

---

## Chapter 0 — Hello, Sokoban

**Goal:** put one piece of text in the center of a window, and experience the shape
of the whole game: a function returns a list of pictures, the engine draws it every frame.

The code is three files. `project.json` decides the window and the font,
`Main.flix` boots everything, and `Sokoban.flix` returns what to draw.

### `project.json` (window and font)

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

`designWidth` / `designHeight` define the coordinate system *inside* the game.
We think in a 320×240 space, and the actual window stretches it 3× to 960×720.
So all coordinates live in 320×240, and the center of the screen is `(160, 120)`.

### `src/Main.flix` (boot)

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

No need to memorize this yet. How to read it:

- `with LwjglLayer.withProject(".")` — reads `project.json`, opens the window,
  loads the font.
- `Sokoban.start(...)` — this is where our own code begins. It receives the font
  loaded under the name `"default"` via `getFontAtlas`.

### `src/Sokoban.flix` (what to draw + the loop)

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

### What just happened

- `frame` is a function that **only returns a list of pictures**. It changes
  nothing and remembers nothing. It returns one piece of text, `"Hello, Sokoban"`,
  paired with the position (`pos`) where it should go.
- The position math `160.0 - box#x / 2.0` means "step back from the center by half
  the text's width" — that's **centering**. `Label2D.measure` reports the actual
  width and height of the rendered text, so you can center precisely instead of
  guessing.
- `start` repeats one thing until the window closes or `Esc` is pressed: call
  `frame`, draw the result, call itself again. That is what "every frame" means in
  a game. **Everything drawable lives in `frame`** — the loop itself has no idea
  what is being drawn.

In other words: the function you will edit, almost always, is `frame`.

### Try it

Change `"Hello, Sokoban"` in `frame` (both occurrences) to some other text and
`... flix.jar run` again. The text in the window changes — and note that you never
touched the loop.

---

## Chapter 1 — Drawing a Crate (composing parts into a symbol)

**Goal:** stack simple parts — rectangles and polygons — into something that reads
as "a wooden crate," with no image files.

Sokoban means crates. We won't use an image. Instead, think about what makes a
crate look like a crate: a face of parallel boards, a frame around the edge, a
diagonal brace. **Turn each feature into a simple shape, decide the stacking
order, and place them** — from a distance, it becomes a perfectly respectable
crate. Instead of pixeling a sprite, we assemble a *symbol* in code.

### Colors come from the DB32 palette, by role name

Choosing colors is genuinely one of the most paralyzing parts of making a game.
This project adopts **DB32 (DawnBringer 32)** — a well-regarded, complete 32-color
palette — as its standard. "You may only use these 32 colors" erases the infinite
choice problem. **Constraints make decisions easy.**

But writing raw codes like `#8f563b` in drawing code hides what the color is
*for*. So `src/Palette.flix` defines DB32 colors under **role names** (named for
purpose, not hue):

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

One rule: **drawing code never hardcodes a color literal; it only refers to
`Palette` role names.** When you later want a different plank color, there is
exactly one place to change (`cratePlank`).

### The crate blueprint

With `T` as the tile size (96px here), the crate has 5 kinds of parts, all sized
as ratios of `T`:

| Part | Shape | Color | Size |
|---|---|---|---|
| Base plank | 1 full-tile box | cratePlank | T × T |
| Board seams | 5 evenly spaced thin vertical boxes | crateSeam | width ≈ T×0.04 (interior reads as 6 boards) |
| Diagonal brace | bottom-left → top-right band (3 convex quads) | crateBrace | thickness ≈ T×0.18 (edges T×0.03 in crateFrame) |
| Outer frame | 2 horizontal boards + 2 vertical boards between them | crateFrame | thickness ≈ T×0.12 |
| Frame joints & outline | 8 thin line boxes | crateSeam | joints ≈ T×0.02, outline 1px |

The frame is not a single picture-frame shape but **four boards butted together**:
two horizontal boards run the full width, and two vertical boards sit between
them — with thin joint lines where board meets board. The two full-width
horizontal joint lines double, at their ends, as the four corner butt joints.
A final 1px dark outline around the whole box keeps it from floating over the
background.

**Stacking order matters**: base → seams → brace → frame → joints and outline.
Because the frame draws after the brace, the ends of the brace tuck underneath it
(so the ends never need shaping). Stacking order is set per part with `zIndex`
(larger = closer to the viewer).

### `src/Sokoban.flix` (assembling the crate)

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

### What just happened

- `frame` still **only returns the list of things to draw** — but now there are
  two kinds: the rectangles-and-text list (`Drawable`) plus a polygon list
  (`PolygonRenderCmd`). Boxes can only be axis-aligned rectangles, so **the
  diagonal band is the one shape where we specify 4 vertices ourselves** as a
  convex polygon. `start` hands both lists to the engine together.
- The crate is 21 parts (18 boxes + 3 polygons) stacked. Each one is just "a
  colored rectangle" or "a colored parallelogram" — it is the **ratios and the
  stacking order** that produce the symbol "crate."
- `zIndex` is the stacking order; bigger draws on top. Try setting `zRail` to `0`:
  the frame sinks under the band and the band's extended ends stick out exposed —
  proof that "frame draws after brace" was doing real work.
- The diagonal brace is 3 parallelograms (a bright central band + 2 dark edge
  lines). All three **share the same centerline and direction vector `d`**; only
  their offset ranges along the normal `n` differ (the band covers `-half..half`,
  the edges sit just outside it with width `edge`). Why not build the edges by
  laying a slightly bigger band underneath, or by shifting vertically? Because
  shifting a diagonal shape vertically makes its **apparent thickness wobble from
  place to place**. Measured along the normal, thickness is constant everywhere.
- The band's centerline is **extended past the inner corners** by `ext`. The
  extended ends tuck under the frame rails drawn later, so no end-shaping code is
  needed at all — "let something drawn on top hide it" is another use of stacking
  order.
- The "four boards" look of the frame comes from the **joint lines**, not the
  rails themselves: the two full-width horizontal joints read as corner butts at
  their ends, and the two inner vertical joints separate frame from interior. The
  finishing 1px outline cuts the crate out of the background.
- The crate is one 16px Sokoban tile at 6× magnification: 96px square. To center
  it at `(160, 120)` we put the top-left corner at "center minus half the size" —
  the same idea as centering text. Every dimension is a ratio of `crateSize()`, so
  changing that one number scales the whole crate correctly.
- Every color goes through `Palette`; there is not a single raw color code in the
  drawing code.

The only new idea since Chapter 0 is **stacking order (`zIndex`)**. The overall
shape — `frame` returns the list, the engine draws it every frame — has not
changed at all.

### Try it

Tweak `half` (the band's half-width) or `edge` (edge thickness) in `cratePolys()`
and `run`: the band grows while its edges stay perfectly uniform. Or bump
`crateSize` from `96.0` to `128.0` — thanks to ratio-based sizing, the whole crate
scales up without falling apart.

---

## Chapter 2 — Making it Move: where does state live?

**Goal:** make the crate slide across the screen — and discover where a changing
value has to live.

We want the crate to move: its x position should grow a little every frame, and
wrap back to the left edge after it slides off the right.

And here is the question this chapter exists for. `frame` is a function that
returns a list — it remembers nothing between calls. **Where do we keep the
crate's position?**

This codebase's answer: in one value, carried around the loop. We call that value
the **World**.

### `src/Sokoban.flix` (full code as of this chapter)

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

### Three words

This chapter introduces the first three words of this engine's vocabulary. Each
one names something you can already see in the code above:

- **World** — the place where state lives. One value that holds everything that
  changes (today: just `crateX`). Save this one value and you can reproduce this
  exact moment of the game. Nothing else in the program remembers anything.
- **Step** — a pure function `World -> World` that advances the world by one
  frame. Look at `step`'s signature: no effect annotation. In Flix that is not a
  comment or a convention — **the compiler verifies that an unannotated `def` is
  pure**. Same World in, same next World out. Always.
- **Projection** — `frame` is the mirror image of `step`: it *reads* the world
  and returns pictures, changing nothing. A projection of the world onto the
  screen.

### What just happened

- The loop now beats three times a frame: **`world |> step |> frame`** — advance
  the world, project it, draw the result, repeat with the new world. **This is
  the whole engine.** Every later chapter — input, a board, boxes to push, undo —
  just adds parts to this beat; the beat itself never changes.
- `step` moves the crate a constant amount per frame (`crateSpeed` = 1 design px).
  We chose per-frame constants over elapsed-time (`dt`) movement deliberately: it
  keeps `step`'s signature at exactly `World -> World`, which is this chapter's
  whole lesson — and Sokoban is a grid game, so on this tutorial's path,
  continuous time-based motion is a stepping stone, not a destination. (The
  honest cost: on a 120 Hz display the crate slides twice as fast as on 60 Hz.
  Games that care thread the frame's elapsed seconds through `step`; the engine
  provides it.)
- The wrap rule also lives in `step` — "once fully past the right edge, jump to
  just outside the left edge." Rules about how the world changes belong in
  `step`, and nowhere else.
- The crate-drawing functions now take the crate's **center as an argument**
  instead of assuming the screen center. Drawing one crate anywhere is the
  groundwork for drawing many tiles on a board — which is where this game is
  headed.
- Notice what did *not* change: `frame` still just returns the list of things to
  draw, and the launcher is still a few lines that know nothing about crates. New
  capability arrived as *new parts*, not as rewrites.

### Try it

Change `crateSpeed` to `3.0` — it slides faster. Then try `-1.0`: the crate
slides left and... disappears forever, because the wrap rule only watches the
right edge. Can you add the mirror rule to `step` so it re-enters from the right?
(Everything you need is already on screen.)

---

## Recap

- A game is a loop with a three-part beat: **`world |> step |> frame`** —
  advance, project, draw.
- **World** is the one value where all state lives. **Step** is the pure function
  that advances it. A **Projection** (like `frame`) reads it without changing it.
- The function you edit is almost always `step` or `frame`.
- Colors are picked from the DB32 palette **by role name**; shapes are composed
  with **ratios and stacking order**.

Next you will want to *control* the crate instead of watching it drift — which
means the keyboard: something that lives outside the world. That is the next
chapter's problem.
