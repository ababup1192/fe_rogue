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
make run
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
    App.make(())
        |> App.withView(Sokoban.frame)
        |> App.launch
```

Three lines, and each one is a sentence:

- `App.make(())` — declare a game. The argument is the game's **entire state**,
  and we have none yet, so we pass the empty value `()`.
- `App.withView(Sokoban.frame)` — plug in the function that says what to draw.
- `App.launch` — read `project.json`, open the window, load the font, and keep
  the game running until it should stop. Pressing `Esc` quits, by default.

`App` is the engine's *runner* (it lives in `engine_world/`, about 150 readable
lines). Everything that touches the outside world — the window, the clock, the
keyboard, the actual drawing — is its job, not ours. Our job is the next file.

### `src/Sokoban.flix` (what to draw)

```flix
mod Sokoban {

    /// The function that returns "what to draw this frame".
    pub def frame(atlas: FontAtlas, _world: Unit): List[Render.PlacedItem] =
        let size = 28.0;
        let box = Label2D.measure(Label2D.make("Hello, Sokoban", atlas, size));
        let pos = {x = 160.0 - box#x / 2.0, y = 120.0 - box#y / 2.0};
        (pos, Render.text("Hello, Sokoban", atlas, size, 100)) :: Nil
}
```

### What just happened

- `frame` is a function that **only returns a list of pictures**. It changes
  nothing and remembers nothing. It returns one piece of text, `"Hello, Sokoban"`,
  paired with the position (`pos`) where it should go. That pair — *(where, what)*
  — is called a `Render.PlacedItem`, and a frame is just a list of them.
- The position math `160.0 - box#x / 2.0` means "step back from the center by half
  the text's width" — that's **centering**. `Label2D.measure` reports the actual
  width and height of the rendered text, so you can center precisely instead of
  guessing.
- Somewhere inside `App.launch` there is a loop that calls `frame` every frame and
  draws whatever it returns, until the window closes or `Esc` is pressed. You will
  never write that loop — and `frame` has no idea it is inside one. **Everything
  drawable lives in `frame`**; everything repetitive lives in `App`.
- The second parameter `_world` is the game state that `App.make` was given. Ours
  is `()` for now, so we ignore it — but its seat at the table is already reserved,
  and most of this tutorial is about what will come to sit in it.

In other words: the function you will edit, almost always, is `frame`.

### Try it

Change `"Hello, Sokoban"` in `frame` (both occurrences) to some other text and
`make run` again. The text in the window changes — and note that there is no loop
anywhere in your project to touch.

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
    pub def frame(atlas: FontAtlas, _world: Unit): List[Render.PlacedItem] =
        List.flatten(
            crateBoxes() ::
            cratePolys() ::
            (titlePlacement(atlas) :: Nil) :: Nil)

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
        ({x = x, y = y}, RawDraw.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    def cratePolys(): List[Render.PlacedItem] =
        let half = crateSize() * 0.09;    // half-width of the central band (0.18T thick)
        let edge = crateSize() * 0.03;    // thickness of one edge line
        braceStrip(-half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(-half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping. The vertices are absolute screen
    /// coordinates, so the placement is the origin.
    def braceStrip(o1: Float64, o2: Float64, c: Color, z: Int32): Render.PlacedItem =
        let t = crateSize();
        let f = railW();
        let ext = t * 0.04;
        let bl = {x = crateLeft() + f, y = crateTop() + t - f};
        let tr = {x = crateLeft() + t - f, y = crateTop() + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        (Vec2.zero(),
         RawDraw.polygon(
             Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
             Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
             c, z))

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))
}
```

(`Main.flix` has not changed since Chapter 0 — it still just plugs `Sokoban.frame`
into the App.)

### What just happened

- `frame` still **only returns one list of things to draw** — but the list now
  mixes three kinds of item: solid boxes, text, and a polygon. Boxes can only be
  axis-aligned rectangles, so **the diagonal band is the one shape where we
  specify 4 vertices ourselves**, via `RawDraw.polygon`. It rides in the same list
  as everything else; the App sorts out what goes where.
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
    pub def frame(atlas: FontAtlas, w: World): List[Render.PlacedItem] =
        let World.World(r) = w;
        let center = {x = r#crateX, y = centerY()};
        List.flatten(
            crateBoxes(center) ::
            cratePolys(center) ::
            (titlePlacement(atlas) :: Nil) :: Nil)

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
        ({x = x, y = y}, RawDraw.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    def cratePolys(center: Vec2.Vec2): List[Render.PlacedItem] =
        let tl = topLeftOf(center);
        let half = crateSize() * 0.09;    // half-width of the central band (0.18T thick)
        let edge = crateSize() * 0.03;    // thickness of one edge line
        braceStrip(tl, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping. The vertices are absolute screen
    /// coordinates, so the placement is the origin.
    def braceStrip(tl: Vec2.Vec2, o1: Float64, o2: Float64,
                   c: Color, z: Int32): Render.PlacedItem =
        let t = crateSize();
        let f = railW();
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        (Vec2.zero(),
         RawDraw.polygon(
             Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
             Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
             c, z))

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))
}
```

And `Main.flix` grows by exactly one line:

```flix
def main(): Unit \ IO =
    App.make(Sokoban.initialWorld())
        |> App.addSystem((_frame, w) -> Sokoban.step(w))
        |> App.withView(Sokoban.frame)
        |> App.launch
```

`App.make` now receives a real World instead of `()`, and `addSystem` plugs in
the function that advances it. A **System** is anything of shape
`(Frame, w) -> w` — the App calls every system once per frame, feeding the result
of one into the next, and hands each one a `Frame` (this frame's inputs and
clock). We have no use for it yet, so we ignore it with `_frame` — Chapter 3 is
where it earns its seat.

### Three words

This chapter introduces the first three words of this project's vocabulary. Each
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

(App, Frame and System are vocabulary too, but they come *with* the engine rather
than being built in this tutorial — think of them as the stage our words perform
on.)

### What just happened

- Every frame now beats three times: **advance the world (your systems), project
  it (your view), draw the result** — then repeat with the new world. The App
  carries the World from one frame to the next; nothing else in the program
  remembers anything. Every later chapter — input, a board, boxes to push,
  undo — just adds parts to this beat; the beat itself never changes.
- `step` moves the crate a constant amount per frame (`crateSpeed` = 1 design px).
  We chose per-frame constants over elapsed-time (`dt`) movement deliberately: it
  keeps `step`'s signature at exactly `World -> World`, which is this chapter's
  whole lesson — and Sokoban is a grid game, so on this tutorial's path,
  continuous time-based motion is a stepping stone, not a destination. (The
  honest cost: on a 120 Hz display the crate slides twice as fast as on 60 Hz.
  Games that care read the frame's elapsed seconds — it is already there, in the
  `Frame` every system receives. Keep this paragraph in mind: in Chapter 4 this
  exact bill arrives — on a real 120 Hz screen — and we pay it.)
- The wrap rule also lives in `step` — "once fully past the right edge, jump to
  just outside the left edge." Rules about how the world changes belong in
  `step`, and nowhere else.
- The crate-drawing functions now take the crate's **center as an argument**
  instead of assuming the screen center. Drawing one crate anywhere is the
  groundwork for drawing many tiles on a board — which is where this game is
  headed.
- Notice what did *not* change: `frame` still just returns the list of things to
  draw, and `Main` is still four lines that know nothing about crates. New
  capability arrived as *new parts*, not as rewrites.

### Try it

Change `crateSpeed` to `3.0` — it slides faster. Then try `-1.0`: the crate
slides left and... disappears forever, because the wrap rule only watches the
right edge. Can you add the mirror rule to `step` so it re-enters from the right?
(Everything you need is already on screen.)

---

## Chapter 3 — Keys Live Outside the World

**Goal:** retire the self-sliding crate and put a robot on screen that *you*
steer with the arrow keys — without giving up the purity of `step`.

Chapter 2 ended on a problem: the keyboard. Movement should now depend on which
arrow keys are held *right now*, and that fact is stored nowhere in our World.
It lives in the keyboard hardware — outside the program entirely.

The tempting move is to let `step` peek: call `isKeyPressed` from inside it.
Flix simply won't compile that. Reading a key is an effect — its signature says
`\ GameEngine.Game` — and an unannotated `def` like `step` is *verified pure*,
so the call is rejected. The type system is asking us to make a design decision,
and the decision this codebase makes is:

**The App reads the keyboard, once per frame, and hands the result to every
system as a plain value — the `Frame`.** The keyboard lives outside the world;
it enters as data. Remember the `_frame` parameter we ignored in Chapter 2? This
is the chapter where it earns its seat. A `Frame` carries the set of keys that
are down, the set that were just pressed, and the clock — and our job is one
pure mapping from it into the game's own words:

```flix
pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

pub def inputOf(frame: App.Frame): Input = ...

pub def step(input: Input, w: World): World = ...
```

`step` grew an argument and lost nothing: same `Input` and same `World` in,
same next `World` out, compiler-checked as before. `Input` is not a new piece
of vocabulary — it is just a record of four booleans.

### A robot with no image file

The player character deserves a face, and this project drew one the same way it
drew the crate: **out of boxes, with no image file anywhere**. `src/Robot.flix`
composes a one-eyed robot from rounded rectangles on a 16-unit grid — body slab,
lens eye, L-bent arms, feet — and exposes one pure function:
`Robot.parts(center, size, dir, phase)` returns the draw list for any facing
direction at any walk phase.

The design was chosen by eye, from galleries that `make bake` bakes as PNG and
GIF files (look in `gallery/`: six candidate robots, the four facings of the
winner, and a marching walk cycle). The walk is not an animation clip: pose is a pure
function of `(dir, phase)`, so a standing robot and a walking robot are the same
function at different phases — `walkPhase = 0.0` *is* the rest pose. The crate
steps aside this chapter to give the robot room; it returns as something to
*push* once there is a board.

### `src/Sokoban.flix` (full code as of this chapter)

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
    // The keyboard lives outside the World. The App reads it once per frame and
    // hands every system a Frame; inputOf maps that Frame into the game's own
    // words. Note that inputOf is pure — the reading already happened.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    pub def inputOf(frame: App.Frame): Input =
        { up    = App.isDown(GameEngine.Key.Up, frame),
          down  = App.isDown(GameEngine.Key.Down, frame),
          left  = App.isDown(GameEngine.Key.Left, frame),
          right = App.isDown(GameEngine.Key.Right, frame) }

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
    pub def frame(atlas: FontAtlas, w: World): List[Render.PlacedItem] =
        let World.World(r) = w;
        let center = {x = r#robotX, y = r#robotY};
        List.append(
            Robot.parts(center, robotSize(), r#facing, r#walkPhase),
            titlePlacement(atlas) :: Nil)

    /// Title text horizontally centered near the top of the screen.
    def titlePlacement(atlas: FontAtlas): Render.PlacedItem =
        let size = 28.0;
        let width = Label2D.measure(Label2D.make("Sokoban", atlas, size))#x;
        let pos = {x = centerX() - width / 2.0, y = 24.0};
        (pos, Render.textTinted("Sokoban", atlas, size, Palette.titleText(), zTitle()))
}
```

And `Main.flix` wires the keys into the system:

```flix
def main(): Unit \ IO =
    App.make(Sokoban.initialWorld())
        |> App.addSystem((frame, w) -> Sokoban.step(Sokoban.inputOf(frame), w))
        |> App.withView(Sokoban.frame)
        |> App.launch
```

### What just happened

- The beat did not change. It is still *advance, project, draw*, once per frame;
  the system now *prepares* one extra value before calling `step` —
  `step(inputOf(frame), w)` — and everything downstream is as pure as it was.
- Stop and look for an effect annotation anywhere in our project. There is
  none. **The whole game is now pure functions** — the one place the keyboard
  hardware is actually read lives inside the engine's App, which snapshots it
  into the `Frame` before any of our code runs. `App.isDown` is just a set
  lookup on that snapshot. If you try to call `isKeyPressed` inside `step`, the
  compiler stops you — purity here is a checked property, not a house rule.
  (A heads-up for readers following along in the shipped repo: this row of
  direct `App.isDown` reads is how `inputOf` *starts out*. The finished game
  replaces it with a key table — chapter 6 shows it — which is also where
  WASD joins the arrows.)
- All the *rules* still live in `step`, and they are ordinary world rules:
  opposing keys cancel (`axis`), the horizontal wins a diagonal (`facingOf`),
  the screen edge clamps, and releasing every key snaps `walkPhase` to `0.0` —
  which by Robot's design *is* the standing pose. No key handling, no callbacks,
  no "input system": just data in, World out.
- `frame` draws the player with `Robot.parts` — the exact function the gallery
  files were baked from. There is no separate "game art": the gallery you
  approve by eye and the character on screen are one function.
- And no new vocabulary: **World**, **Step**, **Projection** still cover
  everything on screen. `Input` is not a fourth word — it is just the Frame
  translated into the game's own words.

### Try it

Raise `robotSpeed` to `4.0` — the robot hurries, and the walk cycle starts to
look like skating; raise `walkRate` to match. Then try changing a rule: the
robot currently walks diagonals (both axes move at once). Make `step` forbid
it — for example, ignore the vertical pair whenever the horizontal pair is
active. One `if` in one pure function, and the game's feel changes; run the
tests in `test/TestSokoban.flix` and see which pinned rule you just broke.

---

## Chapter 4 — A World of Many Things

**Goal:** put a board under everyone's feet — walls that stop the robot, goals
that want crates, crates that move one square at a time — and meet the word for
state that comes in bulk: the **Store**.

Until now the World has carried its state one piece at a time: one `crateX` in
Chapter 2, one robot position in Chapter 3. A sokoban board is a different kind
of cargo. The first level below has 24 wall tiles, 2 crates and 2 goals — and
nobody wants a World with twenty-four wall fields.

The World stays exactly what it was: one value. What grows up is the *field*: a
field can hold a whole collection.

```flix
pub type alias Board = {
    walls = Set[(Int32, Int32)],
    goals = Set[(Int32, Int32)],
    crates = Set[(Int32, Int32)],
    ...
}
```

### The fourth word: Store

A **Store** is a World field that holds many states of one kind — a `Set` here,
a `Map` some day — instead of a single number. `walls` is a Store of wall
positions; `crates` is a Store of crate positions; `goals` is a Store of goal
positions. One kind of thing, one field, however many of them there are.

That is the fourth word of this engine's vocabulary — **World**, **Step**,
**Projection**, **Store** — and notice what it buys the moment it exists.
"Is there a wall at `target`?" is `Set.memberOf(target, walls)`: a question,
not a search. Pushing a crate is `Set.remove` plus `Set.insert`: a crate has no
object, no id, no little class of its own — it *is* a position in a Store.

### A level is text

Where do 24 walls come from? Not from 24 lines of code. A level is a string, in
the classic sokoban notation puzzle authors have used for decades:

```
#  wall       .  goal            @  robot
$  crate      *  crate on goal   +  robot on goal
```

These are the two boards that ship with this chapter — designed for this
tutorial and checked solvable by hand. The first is two clean pushes once you
see them; the second makes you walk the long way around before each push:

```
#######      ########
#     #      #      #
# .$  #      # ## $.#
#     #      # #    #
#  $. #      # $ ## #
#  @  #      #. @   #
#######      ########
```

The pleasant part: designing a level never touches the rules. The string goes
through a parser — a pure function `String -> Result[String, Parsed]` — and
comes out as Stores. A typo does not crash anything; it comes back as an `Err`
value that says what is wrong and where (`unknown tile 'X' at column 1, row 0`).
It is the same discipline the keyboard got in Chapter 3: something from outside
the rules — this time a hand-typed string — is turned into checked data at the
boundary.

### The space between two squares is state too

The robot now moves by whole squares, because the rules demand it: sokoban is
a game of exact cells, where "almost on the goal" means nothing. But a robot
that *teleports* one tile per keypress feels like editing a spreadsheet. We
want both — rules on the grid, motion on the screen — so the two are
separated.

When a hop starts, the robot's cell (the thing every rule reads) changes at
once. What takes time is the *picture*: for the next eighth of a second the robot
is drawn partway between its old cell and its new one. And "how far along is the
picture?" — the interpolation's `t` — must survive from one frame to the next.
That makes it state, and by now you know where state lives:

```flix
slide = Option[Slide]    // Some while a hop's picture is still travelling
```

While a slide is travelling, the keyboard is ignored. The moment it lands, a
key still held starts the next square. This one gate does a lot of quiet work:
a tap moves exactly one square, holding a key glides square by square in the
slide's own rhythm, and the robot can never be caught between cells — the
rules never even hear about the in-between frames.

### Playtest interlude: the 120 Hz bill arrives

The first cut of this chapter advanced the slide by a constant amount *per
frame* — Chapter 2's comfortable shortcut. Then the game was played on a
machine whose display runs at 120 Hz, and the robot moved at exactly double
speed: twitchy, hard to stop on the right square. The bill Chapter 2 predicted
had arrived, and this is what playtesting is for.

The fix uses the grammar the keyboard already taught us: **the clock lives
outside the world too.** And it is already waiting in the same place the keys
were — the `Frame` the App hands every system carries `frame#dt`, this frame's
elapsed seconds. We pass it on to `step` as a value:

```flix
pub def step(input: Input, dt: Float64, w: World): World = ...
```

The slide now advances by `dt / slideDuration()` — one display draws 60
pictures of a second, another 120, but the second itself is the same length
everywhere. The tests got *more* deterministic, not less: each one passes an
explicit `dt` and pins exact values. And since the robot now owns a clock, it
stopped standing at attention: with no key down it marches slowly in place —
the same walk cycle at a third of the tempo. Alive, not busy.

### `src/Level.flix` (new)

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

### `src/Crate.flix` (the crate returns)

Chapter 1's crate comes back as its own module, with one change: every ratio
now hangs off a tile-size argument instead of the fixed 96px, so the same
functions draw the showcase crate and a 24px board tile. This is what placing
every part relative to the crate's center was for.

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
        ({x = x, y = y}, RawDraw.box({x = w, y = h}, c, z))

    /// Diagonal brace: one thick band from the inner bottom-left to the inner top-right,
    /// plus 2 dark edge lines. All 3 strips share the same centerline and direction vector;
    /// only their normal-offset ranges differ (building the edges along the normal keeps
    /// their thickness constant everywhere).
    pub def polys(center: Vec2.Vec2, t: Float64): List[Render.PlacedItem] =
        let tl = topLeftOf(center, t);
        let half = t * 0.09;    // half-width of the central band (0.18T thick)
        let edge = t * 0.03;    // thickness of one edge line
        braceStrip(tl, t, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// A parallelogram (convex quad) covering normal offsets o1..o2 from the band's
    /// centerline. The centerline runs inner bottom-left corner -> inner top-right corner,
    /// extended by ext at both ends. The extended ends tuck under the frame rails drawn
    /// later, so the strip ends need no shaping. The vertices are absolute screen
    /// coordinates, so the placement is the origin.
    def braceStrip(tl: Vec2.Vec2, t: Float64, o1: Float64, o2: Float64,
                   c: Color, z: Int32): Render.PlacedItem =
        let f = railW(t);
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let n = {x = -d#y, y = d#x};
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        (Vec2.zero(),
         RawDraw.polygon(
             Vec2.add(p0, Vec2.mul(n, o1)) :: Vec2.add(p1, Vec2.mul(n, o1)) ::
             Vec2.add(p1, Vec2.mul(n, o2)) :: Vec2.add(p0, Vec2.mul(n, o2)) :: Nil,
             c, z))
}
```

### New Palette roles

Six new role names, from DB32 as always: stone grays for the walls — an
unpushable material, so nothing on the board can be mistaken for wood — a dim
green-gray floor, and a fresh green for goals. (`clearText`, the "CLEAR!"
yellow, joins `titleText` in the text section.)

```flix
    // ── Board tiles ──
    pub def wallFace(): Color  = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a
    pub def wallTop(): Color   = {r = 0.517647f32, g = 0.494118f32, b = 0.529412f32}  // #847e87
    pub def wallShade(): Color = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    pub def floorTile(): Color = {r = 0.196078f32, g = 0.235294f32, b = 0.223529f32}  // #323c39
    pub def goalMark(): Color  = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}  // #99e550
```

### `src/Sokoban.flix` (full code as of this chapter)

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
    // The keyboard lives outside the World. The App snapshots it into the Frame,
    // and inputOf (unchanged since Chapter 3) maps that into these four booleans.
    pub type alias Input = { up = Bool, down = Bool, left = Bool, right = Bool }

    pub def inputOf(frame: App.Frame): Input =
        { up    = App.isDown(GameEngine.Key.Up, frame),
          down  = App.isDown(GameEngine.Key.Down, frame),
          left  = App.isDown(GameEngine.Key.Left, frame),
          right = App.isDown(GameEngine.Key.Right, frame) }

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
    // this frame's elapsed seconds, taken from the Frame and handed in as a value.
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
    pub def frame(atlas: FontAtlas, w: World): List[Render.PlacedItem] =
        let World.World(b) = w;
        List.flatten(
            boardTiles(b) ::
            goalMarks(b) ::
            crateBoxes(b) ::
            Robot.parts(robotCenter(b), tile(), b#facing, b#walkPhase) ::
            onGoalBadges(b) ::
            texts(atlas, w) ::
            cratePolys(b) :: Nil)

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

    def cratePolys(b: Board): List[Render.PlacedItem] =
        List.flatMap(p -> Crate.polys(crateCenter(b, p), tile()), Set.toList(b#crates))

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.PlacedItem =
        ({x = x, y = y}, RawDraw.box({x = w, y = h}, c, z))

    /// A filled circle of diameter d centered on c.
    def circleAt(c: Vec2.Vec2, d: Float64, color: Color, z: Int32): Render.PlacedItem =
        ({x = c#x - d / 2.0, y = c#y - d / 2.0}, RawDraw.circle(d / 2.0, color, z))

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

}
```

And `Main.flix` threads the clock through — `frame#dt` was there all along
(the engine clamps the value, so a long hiccup never teleports the game forward):

```flix
def main(): Unit \ IO =
    App.make(Sokoban.initialWorld())
        |> App.addSystem((frame, w) -> Sokoban.step(Sokoban.inputOf(frame), frame#dt, w))
        |> App.withView(Sokoban.frame)
        |> App.launch
```

### What just happened

- The World grew from one position to a whole board without changing species:
  still one value, still stepped by a pure function, still projected by
  `frame`. Three of its fields are Stores. Save the World and you have saved
  the puzzle mid-solve.
- The entire rulebook of sokoban is the `move` function — a dozen lines. The
  target cell decides everything: a wall? stay. A crate with a free cell
  behind? both advance. A crate with anything else behind? stay. The game
  people have played since 1982 fits on a napkin *because* the board is
  Stores — every question is a membership test.
- **Winning is not stored.** `won` asks `Set.isSubsetOf(crates, goals)`, and
  the "CLEAR!" text is projected from the same Stores as everything else.
  There is no `isCleared` flag to set, unset, or forget to reset: state that
  can be derived is not state.
- `frame` layers the board by insertion order — floor and walls, then goal
  marks, then crates, then the robot, then badges and text. Where two parts
  share a zIndex, the one drawn later wins, so the list reads bottom-up like
  the scene itself. A crate parked on a goal keeps a small green badge on top:
  the goal answers back.
- The slide is pure projection. `robotCenter` and `crateCenter` interpolate
  between cells when a slide is travelling; `won` and every rule read only the
  Stores. When the robot pushes, the crate's picture travels in lockstep with
  the robot's — same `t`, one cell further along. And because even `t` lives
  in the World, saving the World mid-slide would resume it mid-stride.
- The walk cycle strides one beat per tile while sliding and marches slowly
  (`idleBeat`) while standing — the robot is never frozen. A starting hop
  carries the standing phase along, so the legs never snap between the two.

### Try it

Point `initialWorld` at `Level.two()` and take the long way around. Then open
`Level.flix` and edit a board — add a crate and a goal, carve a doorway in a
wall — and the parser will hold your hand through every typo. Design a level
of your own; the only code you write is a string.

Feel the constants: `slideDuration` at `0.25` makes the robot stately (four
tiles a second); `0.06` makes it scurry. `idleBeat` at `2.0` turns the standing
march into jogging on the spot. One number each, and the whole game changes
gait — the rules never notice.

Then change a *rule*: sokoban purists look away — make the robot able to
**pull**. In `move`, when the robot walks into a free cell, check whether the
cell *behind* it (opposite the walk direction) held a crate, and bring that
crate along into the robot's old cell. The tests in `test/TestSokoban.flix`
will tell you exactly which pinned rules you just rewrote.

---

## Chapter 5 — Time Travel in Two Calls

**Goal:** press Z and take a move back — any number of moves, all the way back
to the start — and meet the fifth word of vocabulary, the one this engine is
named after.

You pushed the wrong crate. Maybe not into a corner (a crate in a corner never
comes out again — sokoban's little tragedy), but one square too far is enough
to ruin a plan. Every sokoban since the original has answered this with one
key: undo. Which raises a question programs usually find painful: **what is
"the past"?**

In most codebases the past is expensive. Undo means remembering how to
*reverse* every operation — an undo stack of commands, inverse functions,
careful bookkeeping that breaks the day someone adds a feature and forgets its
inverse. But Chapter 2 quietly paid this entire bill in advance. The World is
**one value**. A past World is just a value we already had in hand. Saving it
means keeping it. Rewinding means using it again. That is the whole theory of
time travel available here.

### The fifth word: Worldline

A World is one moment. The trail a game leaves through its moments — the
current World, every World behind it, and, once you start undoing, the
abandoned Worlds ahead — is called a **worldline**, and the engine ships it as
a data structure: `Worldline[World]`, a zipper with three lanes:

```
past    — the Worlds behind you, newest first
current — where you are
future  — Worlds you undid out of (redo fuel)
```

`Worldline.record` files the present into the past and moves on (discarding
the future — a new move invalidates the timeline you abandoned).
`Worldline.undo` steps back, parking the present in the future.
`Worldline.redo` walks forward again. All pure, all total: undo at the oldest
point simply stays put.

And here the engine's name stops being a mystery. The package this game
stands on is `engine_world`; the trail of Worlds is a worldline; and this
whole way of building a game — one World value, a pure Step, Projections that
read it, Stores inside it, and a Worldline threading its moments together —
is called the **Worldline architecture**. World, Step, Projection, Store,
**Worldline**: five words, and the fifth one is the name on the box.

### Recording on the move's beat

When should history be written? A dodge-em-up records every frame — its past
is a film. Sokoban's past is not a film; it is a **move list**. The only
moments worth returning to are the ones just before each push, so we record
exactly when a move commits — and detecting that takes one comparison,
because every legal move moves the robot. Here is the entire time machine:

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

Two calls. `Worldline.record` when a hop commits (filing the *normalized*
pre-move World — the picture's slide and the rewind clock stay out of the
past), `Worldline.undo` when Z fires. `replaceCurrent` — the zipper's "adjust
in place without making history" — keeps the current point tracking the live
frame in between. There is no undo system, no command objects, no inverse of
`move` anywhere: the past is not recomputed, it is *kept*.

And notice the gate. Holding Z takes the walk keys away, and a rewind fires
only when nothing is sliding — the same rule that spaces walking hops. Undo
speaks the slide grammar the game already had: one command per landed
picture, in either direction of time.

### Rewinding is a slide played backwards

When `fireUndo` restores a snapshot, the Stores change instantly — the rules
are already back in the past — but the *picture* is not teleported. The robot
glides from the cell it occupied back to the restored one, on the same slide
mechanism walking uses, only reversed and slower: `undoDuration()` is 0.25
seconds per move against walking's 0.125 — rewinding should feel heavier, and
the clock deserves the time. While it glides, the robot wears the facing of
the move being taken back — undo a step up and it faces up while sliding
down: a little moonwalk — and the moment it lands, the snapshot's own facing
takes over, the one it wore *before* that move. It is not walking back; it is
being *taken* back, feet dragging (the walk phase still turns) the whole way.
And if the rewound move was a push, the crate rides the same reversed film
home:

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

(The `settle` around the forward branch is chapter 8's landing pop — read it
as plain `s#t` for now.)

The facing is one more such derivation. Nothing stores "the undo pose": the
reverse slide itself names the move it is unwinding — that move went from the
restored cell out to `fromCell` — and the snapshot's facing is already
sitting in the Board, waiting for the landing:

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

(`frame` now hands `Robot.parts` this `drawnFacing(b)` where it used to pass
`b#facing`; `directionTo` is the four-way inverse of `deltaOf`.)

While the reverse slide travels, walk keys are ignored and Z cannot fire
again — the shared gate — so holding Z rewinds move after move at exactly the
reverse slide's rhythm. Meanwhile a little alarm clock hangs over the robot's
head: white face, dark rim, one needle that turns **once counterclockwise per
rewound move**, in lockstep with the slide's own progress (`spin` advances by
the same fraction the picture travels). When the rewinding stops, the clock
lingers for a moment and fades. All of it is pure derivation in `frame`:
angle from `spin`, transparency from `linger`, position following the robot.
It is never recorded and never consulted by a rule — decoration with a clean
conscience.

The Worldline itself lives beside the world — not inside it. The value that
`App.make` receives, and that the systems pass along, is now the *whole line*;
the World does not know it is being remembered:

```flix
def main(): Unit \ IO =
    App.make(Worldline.make(Sokoban.initialWorld(), Sokoban.historyCap()))
        |> App.addSystem((frame, line) ->
            Sokoban.tick(Sokoban.inputOf(frame), frame#dt, line))
        |> App.withView((atlas, line) -> Sokoban.frame(atlas, Worldline.current(line)))
        |> App.launch
```

(`inputOf` now also reads Z into `undo` — still as a direct read at this
stage; `tick` wraps `step` and owns the history, and the view projects
whatever World is *current* on the line.)

### What memory costs

Isn't keeping every World expensive? Measure before worrying: the engine's
own benchmark puts a recorded sokoban-sized snapshot at roughly **172 bytes**.
Not kilobytes — the World's Sets are immutable, so a new snapshot *shares*
everything that did not change. A push creates a handful of fresh nodes in
`crates`; `walls` and `goals` are shared with every snapshot ever taken.
That is structural sharing, and it is why

```flix
pub def historyCap(): Int32 = 10000
```

— ten thousand moves of perfect memory — costs under two megabytes. Unlimited
undo is not a luxury feature. In this architecture it is loose change.

### What just happened

- **Undo is two calls.** `record` at each committed move, `undo` on Z. The
  feature that terrorizes object-oriented codebases — inverse operations,
  dirty flags, "restore points" — collapses into keeping values you already
  had. This is the dividend of Chapter 2's decision, paid five chapters
  later.
- History has a beat, and it is the *game's* beat: one snapshot per move, not
  per frame. And both directions of time speak the same slide grammar — a
  forward hop and a rewind are one mechanism with `reverse` flipped, so the
  gate ("next command only when the picture lands") needed no second
  implementation.
- The Worldline lives beside the world — it is now the value the App carries.
  The World stayed as Chapter 4 left it, save two cosmetic guests: `reverse` on
  the slide and the rewind clock's `undoFx` — both stripped by `normalize`
  before anything enters history.
- The robot breathes across time jumps: `walkPhase` rides over the rewind and
  keeps turning during it (the dragged-feet look), while the glide wears each
  undone move's own facing and hands the snapshot's back at the landing — a
  film in honest reverse, one move at a time.
- **CLEAR is still nobody's flag.** `won` stays a pure derivation from the
  Stores — nothing was set, so nothing ever needs unsetting. (In the finished
  game the CLEAR page is modal — chapter 6 — so the winning push cannot be
  rewound: once `won` turns true, only Enter and Escape are heard.)

### Try it

Wire up **redo**. The zipper's future lane is already there, so it is a
few lines: read the R key into `Input` as `redo`, and in `tick` call
`Worldline.redo(line)` when it is pressed and nothing is sliding. Then watch
the future evaporate: undo twice, make a *different* move, and try to redo —
`record` discarded the timeline you abandoned.

Shrink `historyCap` to `3` and push four times: the fourth undo has nothing
left to return to. Forgetting takes configuration; remembering was the
default.

And feel the reverse slide's weight: set `undoDuration` to `0.125` (walking
speed) and rewinding stops reading as rewinding — then flip the sign in
`clockNeedle`'s direction to feel *why* counterclockwise means "back in
time".

---

## Chapter 6 — Screens You Can Edit While It Runs

**Goal:** give the game a front door — a title page, a proper CLEAR panel
that knows your move count, a road from level to level — and meet the sixth
word of the vocabulary by editing a screen's look *while the game is
running*, without recompiling anything.

The game can take back any mistake — but when a level is solved, "CLEAR!"
just floats there, and the only way to visit the second board is to edit the
source. The game plays well and greets badly: no title to start from, no way
to move between levels. Screens raise two questions, and the two answers
live in two different places.

### Which page is showing? That is state

"Which page is the player looking at" is a fact that must survive between
frames, and chapter 2 said what that means: it lives in the World, and the
pure tick owns every change of it.

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

`Input` grows three keys — `enter`, `back` (X) and `esc` — and `enter` and
`esc` are **edges**, not levels: the Frame carries both "down now" and "went
down this frame", and the key mapping reads these two on the edge (in the
shipped `Controls.flix`, shown at the end of this chapter, they sit in a tap
table of their own, apart from the held keys). One press turns exactly one
page, no matter how long the finger rests. And
`tick` becomes a page-turner on top of the machine chapter 5 built — the
whole of that machine survives untouched underneath, renamed `playTick`:

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

(The party-clock lines in the modal branch belong to chapter 8's confetti —
read past them for now.)

Two things deserve a closer look. **CLEAR is modal.** The moment `won` turns
true the solved board becomes a finished photograph: direction keys move
nothing, and Z — for the first time — is refused, so the winning push cannot
be rewound out from under the panel. The world is not frozen, only deaf:
`step(noKeys(), ...)` keeps running, so the final slide still lands and the
rewind clock still fades. Enter turns the page (the next level, or the title
after the last one); Escape closes the panel back to the title — the only
two keys the photograph answers to.

And **every transition is `freshLine`**: a brand new Worldline around one
World. History belongs to one attempt at one board — abandon a level with X
and return, and your past is clean. The time machine never crosses a
doorway.

### The sixth word: Spec

The second question: where does a page's *look* live — the panel color, the
font size, the words on it? Not in the World: "the title is peach" is not a
fact the rules consult. And, more interesting: not in the code either. The
rule of thumb this engine keeps returning to is —

> **Whatever you want to change without recompiling, make data.** Data that
> *describes* a thing — rather than computes it — is called a **Spec**.

Here is the surprise: you have been writing Specs since chapter 4. A level
string *is* one — data that describes a board, parsed by a pure function
into Stores, designed freely without ever touching a rule. The only new step
is doing for screens what level text already did for boards. The title page,
in full, is `assets/Title.ui.json`:

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

A tree of named nodes: a `widget` says what a node is (`text`, `box`, or a
`none` container), layout keys (`dir`, `mainAlign`, `crossAlign`, `gap`) say
how children flow inside it, and colors are the same DB32 hexes the Palette
uses by role. `assets/Clear.ui.json` is its sibling: a bordered panel with
three text lines — `headline`, `moves`, `prompt`. This format belongs to
`engine_world` (the library that brought you `Worldline`): `UiSpec` parses
it, and every node lands in a **UiWorld** — a store of UI nodes, one plain
value — addressable by its name path, like `"Clear/panel/moves"`.

### Spawning pages, projecting the World onto them

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

`loadUi` runs once at startup (note its effect: `\ Fs.FileRead` — reading
files is outside the program, and the signature says so). `projectUi` runs
every frame, and it is a Projection in exactly the chapter 2 sense — it
reads the World and writes a picture — except the canvas is the UI store
instead of the screen: which pages show, what the moves line says.

And look where the move count comes from. We never added a move counter.
There is nothing to increment, nothing to reset, nothing to forget to reset.
`Worldline.pastLength` — the number of Worlds filed behind you — *is* the
move count, because chapter 5 records exactly one snapshot per move. Undo a
move and the count goes down by itself; the number you show is always the
number you could rewind. The time machine had been keeping score all along.

### The App, final form

The game now has *two* values that must survive between frames — the
Worldline and the UiWorld — and the App carries one. So we bundle them, and
the bundle gets a name:

```flix
    /// One game's worth of state: the UI pages' store, and the board with
    /// its whole past. This is the value the App carries.
    pub type alias Session = {
        ui = UiStore.UiWorld,
        line = Worldline[World]
    }

    /// While the CLEAR panel is up, Escape closes the panel (back to the
    /// title) instead of the window. The quit judge below consults this.
    pub def clearModal(w: World): Bool =
        let World.World(b) = w;
        b#screen == Screen.Playing and won(w)
```

The wiring has also grown enough to deserve files of its own. In the shipped
repo the pages live in `GameUi.flix`, the drawing in `View.flix`, the board
rules (and with them the `Input` record) in `Board.flix` — and `Controls.flix`
holds every bridge between the Frame and the game — the key mapping, the two
systems, the F1 reload and the quit judge.

And the key mapping is no longer a row of direct `App.isDown` reads. The keys
were multiplying — four directions, undo, reset, confirm, cancel — so the
shipped code names each *intent* once, in an enum, and lays the key
assignments out as a table: one row per key, mapped through **InputMap**, a
piece of the engine's vocabulary (since v0.3.2). Because several rows may
share one intent, supporting both WASD and the arrows costs exactly one extra
row per key. And the table comes in two halves that answer the edge-versus-level
question from earlier: `heldTable` for keys that keep firing while held —
movement, Z's rewind, X's reset — and `tapTable` for keys that fire once, on
the edge — Enter and Escape. `inputOf` folds whatever intents fired this
frame into the same `Input` record the rules have been reading all along; the
rules never learn a key was involved:

```flix
mod Controls {
    use GameEngine.Key

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

    def tapTable(): InputMap.Table[Intent] =
        (Key.Enter,  Intent.Confirm) ::
        (Key.Escape, Intent.Cancel)  :: Nil

    pub def inputOf(frame: App.Frame): Board.Input =
        let held = InputMap.held(heldTable(), frame) |> List.foldLeft(applyHeld, Board.noKeys());
        InputMap.taps(tapTable(), frame) |> List.foldLeft(applyTap, held)

    def applyHeld(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.MoveUp    => { up = true | acc }
        case Intent.MoveDown  => { down = true | acc }
        case Intent.MoveLeft  => { left = true | acc }
        case Intent.MoveRight => { right = true | acc }
        case Intent.Undo      => { undo = true | acc }
        case Intent.Reset     => { back = true | acc }
        case _                => acc
    }

    def applyTap(acc: Board.Input, intent: Intent): Board.Input = match intent {
        case Intent.Confirm => { enter = true | acc }
        case Intent.Cancel  => { esc = true | acc }
        case _              => acc
    }

    pub def step(frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { line = Sokoban.tick(inputOf(frame), frame#dt, s#line) | s }

    pub def projectUi(_frame: App.Frame, s: Sokoban.Session): Sokoban.Session =
        { ui = GameUi.projectUi(Worldline.pastLength(s#line), Worldline.current(s#line), s#ui) | s }

    pub def reloadUi(s: Sokoban.Session): Sokoban.Session \ {Fs.FileRead} =
        { ui = UiSpec.reloadAll(s#ui) | s }

    pub def wantsQuit(frame: App.Frame, s: Sokoban.Session): Bool =
        inputOf(frame)#esc
            and not Sokoban.clearModal(Worldline.current(s#line))
}
```

(Excerpted from `src/Controls.flix` with its doc comments elided. `step` is
system one — advance the board and its history; `projectUi` is system two —
stamp the advanced World onto the UI pages; `reloadUi` is the F1 handler; and
`wantsQuit` quits on Escape's tap — except while the CLEAR panel is up, when
that Escape belongs to `tick`, which closes the panel.)

And `Main.flix`, final form — every idea in this game is one line here:

```flix
def main(): Unit \ IO =
    let ui = run { GameUi.loadUi() } with Fs.FileRead.runWithIO;
    App.make({ ui = ui, line = Worldline.make(Board.initialWorld(), Sokoban.historyCap()) })
        |> App.addSystem(Controls.step)
        |> App.addSystem(Controls.projectUi)
        |> App.reloadOn(GameEngine.Key.F1, Controls.reloadUi)
        |> App.withView(View.compose)
        |> App.quitWhen(Controls.wantsQuit)
        |> App.launch
```

(One line is still missing — the sound. Chapter 8 adds it.)

Three things to notice. The UiWorld lives in the Session, next to the
Worldline — the same grammar the time machine used: a plain value carried
along, never a global. **Two systems** run in order every frame: advance,
then stamp — `projectUi` always sees the world `step` just produced. And the
view composes one list from two sources:

```flix
    /// The whole Session as one draw list: the board's projection plus the
    /// UI pages, laid out by the engine and returned as the same PlacedItem items.
    pub def compose(atlas: FontAtlas, s: Sokoban.Session): List[Render.PlacedItem] =
        List.append(
            Sokoban.frame(atlas, Worldline.current(s#line)),
            UiRender.itemsWith(_ -> atlas, _ -> None, s#ui, GameUi.designSize()))
```

The title page draws *nothing* from `frame` at all — on that screen,
everything you see is Spec.

Two of the plugged-in pieces are new App slots. `App.reloadOn(key, f)` runs
`f` on the key's edge — note `reloadUi`'s signature, `\ {Fs.FileRead}`: the
one file-reading footprint in the whole game, and it is written on the tin.
A Spec that fails to parse keeps its old page — reload never breaks a running
game. And `App.quitWhen` replaces the default "Escape quits": ours refuses to
quit while the CLEAR panel is up, so that Escape reaches `tick` and closes
the panel instead. The window's close button still works either way.

### What just happened

- Screens ask two questions with two different homes. *Which page* is state
  — a `Screen` value in the World, every transition owned by the pure tick.
  *What the page looks like* is a **Spec** — data on disk, spawned into a
  UiWorld, never consulted by a rule.
- **Spec is the sixth word**: whatever should change without recompiling,
  make data that describes it. Levels were Specs before we had the name;
  now pages are too. World, Step, Projection, Store, Worldline, **Spec**.
- **CLEAR is modal.** A solved board answers only Enter and Escape — walking
  and rewinding fall silent, so the finished position and its move count
  stay exactly as you earned them. The picture keeps breathing; only the
  keyboard narrows.
- **The move count was already there.** `Worldline.pastLength` is the number
  of moves because history records one snapshot per move — no counter added,
  and undo subtracts by itself.
- The UiWorld is one more field of the Session, beside the Worldline. The World
  never learns the UI exists; a projection stamps verdicts onto it once a
  frame.

### Try it

This chapter's real exercise is the reload loop. Run the game, leave it on
the title, and open `assets/Title.ui.json` in your editor. Change the
`tint` of the title, the `fontSize` of the prompt, the subtitle's words.
Save, switch to the game, press **F1**. No recompile, no restart, no lost
state — the page simply becomes what the file says. This is what Spec buys:
the look iterates at the speed of saving a file.

Now break it on purpose: delete a comma, press F1. The old page stays — a
Spec that stops parsing keeps its last good shape. Fix the comma, F1 again.

Give the clear panel a flourish: add a fourth text node under `moves`
(name it anything — it needs no code, because no code addresses it), or
restyle the panel's `borderColor`. F1.

Then add a third level. `Level.three()` with a new board string, and
`levelCount()` returns `3` — a Spec and one number. The screen flow already
knows the way: CLEAR, Enter, next board, and the title again after the last.

---

## Chapter 7 — Proof by Replay

**Goal:** run the whole game with no window at all — prove a solution, film
it, and publish a gallery — and meet the last two words of the vocabulary.
This chapter adds nothing to the game: no state, no rule, no pixel. It is
about what a game built this way hands you for free.

### The seventh word: Harness

To run a game without a screen, something must answer every question the
game would normally ask a window: which keys are down, what time it is,
where the font lives. The bundle of stand-in answers is called a
**Harness**. In a large game the harness is a serious piece of engineering —
a stack of handlers, one per effect the game leans on; this engine's big
example wires up eighteen. Here is sokoban's, in full:

```flix
// Harness — everything needed to run the whole game without a screen.
//
// It is short on purpose, and the shortness is the point: tick is a pure
// function, so the rules need no harness at all. Only the *picture* touches
// the outside world, and it wants exactly two things — a font atlas baked
// headlessly, and the Fs handlers to read the ui.json Specs. The pages hold
// only boxes and text, so `UiRender.renderUiWith` draws them from the atlas
// alone: no Game handler, no window.
mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// The font, baked without a window (AWT headless metrics only).
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.ensureHeadless();
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt")

    /// Both page Specs spawned into one UiWorld, as the launcher does.
    pub def ui(): Option[UiStore.UiWorld] \ IO =
        run {
            forM (a <- UiSpec.spawnAsset(GameUi.titleUiPath(), UiStore.empty()) |> Result.toOption;
                  b <- UiSpec.spawnAsset(GameUi.clearUiPath(), snd(a)) |> Result.toOption)
            yield snd(b)
        } with Fs.FileRead.runWithIO
}
```

Read the header comment again, because it is the paradox this whole
tutorial has been walking toward. Six chapters of insisting that `tick`
stays pure — keys as data, the clock as an argument — looked like
discipline for its own sake. Here it pays out as *absence*: the rules need
no harness at all. Not a small one. None. Every stand-in above serves the
picture, not the game — one font and two file handlers, twenty-five lines
including comments. There is not even a stub of the engine's Game effect,
because the whole projection stack is as pure as the rules: hand it an
atlas and it returns items. The thinner the boundary your pure core
touches, the thinner the harness that fakes it.

### The eighth word: Trace

A **Trace** is a list of inputs — nothing more:

```flix
    /// One beat of a Trace: hold this input for n frames.
    pub type alias Cue = { input = Sokoban.Input, frames = Int32 }

    /// The fixed clock every replay runs on: 1/64 s per frame — dyadic, so
    /// every slide t and walk phase in the pinned outcomes is exact.
    pub def dt(): Float64 = 1.0 / 64.0
```

and driving one is a fold, because `tick` is pure and the clock arrives as
a value. Same list in, same Worldline out — every run, every machine,
forever. On top of that certainty you can write a solution *as data*:

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

and then a solution *is a test* — this is the chapter's title:

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

Tests like this are called **golden**: the expected value is not derived in
the test, it is *pinned* — a concrete fact, checked once by a human and
frozen. From then on any diff means exactly one of two things: a bug, or an
intended change that must update the pin on purpose. Nothing in between,
no flakiness to argue with — determinism is what makes the contract this
blunt.

Level 2 gets the same treatment: `solveLevelTwo` — twenty-one moves through
the detours its interior walls force — has a pin of its own. With that,
both shipped levels are *provably* solvable. Chapter 4 checked this by
hand, once; now it is a machine's job, every run.

### One Trace, three artifacts

The same seven moves are also a film. `Replay.timeline` returns every frame
of a Trace, and each frame renders through the *same* projection stack the
runtime uses — `projectUi` then `View.compose` — just under the Harness
instead of a window:

```flix
    def bakeGif(atlas: FontAtlas, ui: UiStore.UiWorld, cues: List[Replay.Cue[Sokoban.Input]],
                start: Worldline[Sokoban.World], name: String): Unit \ IO =
        let path = "gallery/${name}.gif";
        let film = Replay.timeline(Sokoban.tick, Trace.dt(), cues, start);
        let frames = List.map(l -> SoftRaster.renderToImage(rasterReq(atlas, scene(atlas, ui, l), path)),
                              every(gifSampleStride(), 0, film));
        GifEncoder.encode(frames, gifFrameDelayMs(), path);
        discard Filmstrip.bakeFrames(frames, "gallery/frames/${name}")
```

Run `make bake` and the `gallery/` directory fills up: four screenshots
(the title page, level 1 at rest, a push frozen mid-slide, the CLEAR panel
counting seven moves), three films — `solve_level1.gif`, the opening act
from the title to the first CLEAR; `full_clear.gif`, one full lap of the
game, both levels, both CLEARs and back to the title; `rewind_demo.gif`,
three moves and a held Z, the alarm clock turning counterclockwise while
robot and crate glide home — and an `index.html` dashboard (engine_tools'
ReferenceSite) that lays them all out in pages. Delete the folder; one bake
rebuilds every pixel of it. (`make test` stays fast and pure: the tests verify,
the bake generates — two different verbs, two different commands.)

And the third artifact costs nothing: a failing Trace **is** a bug report.
"These inputs, this outcome" — attached to a ticket, it reproduces forever;
folded through `tick`, it is already the regression test.

### What just happened

- **Harness is the seventh word**: the stand-ins that let a game run
  without a window. Its size is a *measurement* of your architecture —
  sokoban's measures one font, two file handlers and a twelve-line stub,
  because the rules themselves are pure and need nothing.
- **Trace is the eighth**: inputs as data over a fixed clock. Determinism
  turns one Trace into three artifacts — a golden test, a film, a bug
  report — and they can never drift apart, because they are the same list.
- The gallery is disposable output, never source: `make bake` regenerates
  every PNG, every GIF and the dashboard from the code and the Specs.
- The vocabulary stops at eight. The Worldline architecture has more words
  for bigger games — a **Driver** that owns a simulation's stepping, a
  **Resource** for state shared across worlds — and this game never needed
  them. That is the honest ending: reach for the words a game needs, not
  all the words that exist.

### Try it

Take the scenic route: write a deliberately *longer* solution for level 1
as a Trace — wander a while before each push — and pin it as your own test.
Both routes end with the same crates on the same goals, but the pins
disagree on one number: `Worldline.pastLength`. The move count is your
route's fingerprint. Then tighten your route and watch the fingerprint
shrink — can you beat the shipped seven?

Retime the films: `gifSampleStride` down to 1 for a slow-motion study of
the reverse slide, or `gifFrameDelayMs` up to 80 for a flipbook feel. One
test run re-cuts all three GIFs.

Add a scene of your own to the dashboard: compose a Worldline with `Replay`
(mid-rewind makes a good picture), `shot` it to a new PNG, and give it an
`item` line in the catalog. The site generator does the rest.

---

## Chapter 8 — The Last Ten Percent

**Goal:** confetti, weight and sound — the polish pass players call
*juice* — written entirely with the vocabulary already on the table. No
new words in this chapter; that is the chapter's point. Juice has a
reputation for demanding systems: particle systems, animation systems,
event buses. Here every drop of it is a derivation, one small number in
the World, and one call at the loop's edge.

### Confetti without a particle system

A particle system keeps an array of live particles and updates each one
every frame — position += velocity, life -= dt, spawn, free. We store
none of that. The World gains exactly one number, `clearElapsed`, which
the modal CLEAR branch advances (the "party clock"), and every piece of
confetti is a *closed-form function* of that clock and its own index:

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
    def confettiQuad(t: Float64, i: Int32): Render.PlacedItem =
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
        (Vec2.zero(),
         RawDraw.polygon(
             corner(-1.0, -1.0) :: corner(1.0, -1.0) ::
             corner(1.0, 1.0) :: corner(-1.0, 1.0) :: Nil,
             Palette.confetti(i), zConfetti()))

    /// The whole rain: one quad per index while the party clock runs.
    pub def confettiQuads(b: Board): List[Render.PlacedItem] =
        if (b#clearElapsed <= 0.0) Nil
        else List.map(confettiQuad(b#clearElapsed), List.range(0, confettiCount()))
```

`chip` deals each piece its personal constants — fall speed, sway, spin,
starting column — the same ones every frame, forever. The fall wraps
(`fract`) so the rain never runs out, and the spin is a rotated quad in
the polygon channel the crates and the clock needle already use. Nothing
spawns, nothing updates, nothing frees: press Escape and the rain is
simply never asked for again. And because the rain at time t is a pure
value, the *party is unit-testable* — a pin asserts that asking twice
gives the identical picture.

Closed-form particles carry further than they look: fireworks, smoke
puffs, sparkles — anything whose pieces do not interact can be a function
of `(index, t)`. The trick's ceiling is interaction (colliding debris
needs real state), but a celebration rarely needs physics.

### Weight

The push should *feel* heavier than the walk. Two touches, deliberately
no more:

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

Both are derivations off the `pushing` flag the Slide has carried since
chapter 4 — no new state at all. And both are tiny on purpose: one pixel
of sink, a pixel and a half of overshoot. Juice fails by excess more
often than by absence; the moment you notice the trick, it stops
working. (Note what `settle` refuses to do: a standard ease-out-back
curve would send the crate racing ahead of the robot mid-slide — but a
pushed thing cannot outrun its pusher, so the pop waits for the last
stretch.)

### Sound at the boundary

The four sound effects are **generated assets**, like the gallery:
`src/bake/SfxBake.flix` writes them as 16-bit PCM WAV files — a 44-byte
header and a list of samples, each sample a pure function of its index.
A square wave, a noise burst and a linear fade turn out to be a whole
sound vocabulary: a blip for walking, a low thud for pushing, a high
tick for each rewound move, four rising notes for CLEAR. No sample
packs, no microphone — `make bake` bakes them and `project.json` loads
them.

*Which* sound this frame deserves is a pure question, and it reads off
the two Worldlines like every other derivation in the game:

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

Note where the facts come from: a move committed exactly when the past
grew by one, a rewind when it shrank by one — the Worldline was already
the event log. The playing itself is an effect, and the App owns it: one
last line completes `Main.flix` —

```flix
        |> App.withAudio(Sfx.events)
```

— where `Sfx.events` adapts `sfxEvent` to the App's shape (the App hands it
this frame's `{before, after}` Sessions and plays whatever names come back).
That closes the frame the tutorial opened in chapter 3: keys and the clock
come *in* as values, pixels and now sound go *out* as commands, and
everything between is pure.

(One honest caveat: generated assets must be generated. Run `make bake`
once before the first `make run`, or the sound manifest will point at
files that do not exist yet.)

### What just happened

- **Juice needed no new machinery.** Confetti is a derivation from one
  number; weight is two one-pixel derivations off a flag that already
  existed; sound is a pure event read off the Worldline plus one
  `withAudio` line in Main. No particle system, no animation system, no
  event bus.
- **Closed-form particles are a real technique**, not a toy: anything
  whose pieces do not interact can be `(index, t) -> piece`, testable
  and free of lifecycle bugs by construction.
- **The sounds are generated assets** — the same grammar as the gallery:
  `make bake` writes them, the code that writes them is the source of
  truth, and no binary blob needs a provenance story.
- **The vocabulary did not grow.** Eight words were enough for the
  polish pass too.

### Try it

Make it snow on the title page: `confettiQuads` only needs a clock, so
give the title its own — or simply pass the title's idle time in — and
recolor the pieces white with `Palette.confetti`. The same closed form
is a blizzard.

Add a fifth sound: the *refused* push (crate against a wall). The facts
are already in the Worldlines — the robot's cell did not change but its
facing did — so it is one more branch in `sfxEvent` and one more `square`
call in the bake. A dull "bonk" at 80 Hz reads nicely.

Retune the thud: more noise and less square reads as sliding cardboard;
more square and less noise reads as stone. The whole sound is eleven
lines — tuning it is faster than downloading one.

---

## Recap

- A game is one value and a three-part beat — advance (your systems), project
  (your view), draw — and the **App** runs the beat: it snapshots the keys and
  the clock into a **Frame**, folds your **Systems** over the World, and draws
  whatever the view returns. You write the parts; the engine owns the loop.
- **World** is the one value where all state lives. **Step** is the pure
  function that advances it. A **Projection** (like `frame`) reads it without
  changing it. A **Store** is a World field that holds many states of one kind.
  A **Worldline** is the trail of Worlds — past, current, future — that
  `record` and `undo` walk along; it lives beside the World, not inside it.
  A **Spec** is data that describes a thing — a level string, a page's
  `ui.json` — for everything that should change without recompiling.
  A **Harness** is the bundle of stand-ins that runs the game without a
  window; a **Trace** is a list of inputs whose outcome is always the same —
  one solution that is a test, a film and a bug report at once.
- Things outside the world — the keyboard, a hand-typed level, the clock —
  are read at the boundary and enter the rules as plain data.
- State that can be derived (like "is the puzzle solved?") is not stored; it
  is projected. And state that is one value can be *kept*, which makes time
  travel two calls.
- The function you edit is almost always `step` or `frame`.
- Colors are picked from the DB32 palette **by role name**; shapes are
  composed with **ratios and stacking order**.

The game is whole now: a title that waits, boards that slide and remember,
mistakes that rewind, a clear panel that knows the score, pages you can
restyle while it runs — and a gallery that proves all of it on every test
run. Eight words carried the entire trip, and the next game you build can
start from all eight on day one.

---

## Epilogue

The trip is over; count what is on the table. One complete game — title,
two levels, undo with a spinning clock, pages you can restyle while it
runs, confetti and a fanfare. Fifty-eight tests that replay whole
solutions and pin their outcomes as plain values — including a breadth-first
solver that machine-proves every shipped level. A gallery that bakes its
own screenshots, films and dashboard on every `make bake`. A tutorial in
two languages whose code listings are checked against the source. And
carrying all of it, eight words: **World, Step, Projection, Store,
Worldline, Spec, Harness, Trace** — performing on a stage the engine
provides: the **App**, its **Frame**, your **Systems**.

None of the eight is exotic. Their whole content is one discipline —
state is one value, change is a pure function, everything else is a
derivation or a boundary — applied without exception until it stopped
feeling like discipline. The payoffs kept arriving on their own: undo
fell out of a zipper, the move counter fell out of the history, replays
fell out of purity, the test harness all but vanished.

Now make it yours. A new level is one string in `Level.flix` — write it,
pin its solution, watch it join the films. A new game is the same eight
words on an empty file, and this repository's `WORLDLINE_GUIDELINE.md`
(at the root) writes the architecture up in full, beyond what one small
sokoban needed.

Push crates. Rewind time. Ship something.
