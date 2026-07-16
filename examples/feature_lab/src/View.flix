// View — World から絵を作る。背景に薄い格子（覆いが乗ったか一目で分かる目印）を敷き、
// その上にラベル UI（ui.json）と Transition.itemsAt が返す覆いを重ねる。
// 格子と覆いは UI ではない純粋な絵なので Render 直書き、ラベルの見た目は ui.json が持つ。

mod View {

    def bgColor(): Color = { r = 0.15f32, g = 0.16f32, b = 0.20f32 }
    def gridColor(): Color = { r = 0.30f32, g = 0.32f32, b = 0.38f32 }
    def coverColor(): Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }

    /// design 解像度（project.json の designWidth/Height と合わせる）。
    pub def design(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// 縦横 40px 格子の線（背景だけでは覆いの有無が分かりづらいための目印）。
    def gridItems(): List[Render.PlacedItem] =
        let cell = 40.0;
        let cols = List.range(0, 8);
        let rows = List.range(0, 6);
        let verticals = cols |> List.map(i -> {
            let x = Int32.toFloat64(i) * cell;
            { at = { x = x, y = 0.0 }, item = Render.box({ x = 1.0, y = design()#y }, gridColor(), 1) }
        });
        let horizontals = rows |> List.map(i -> {
            let y = Int32.toFloat64(i) * cell;
            { at = { x = 0.0, y = y }, item = Render.box({ x = design()#x, y = 1.0 }, gridColor(), 1) }
        });
        List.append(verticals, horizontals)

    /// 背景の格子 → ラベル UI（ui.json）→ 覆い（Transition）の順に重ねる。
    pub def frame(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let bg = { at = Vec2.zero(), item = Render.box(design(), bgColor(), 0) };
        let ui = UiRender.itemsWith(_ -> ctx#atlas, _ -> None, world#ui, design());
        let cover = Transition.itemsAt({ kind = world#kind, t = Transition.tOf(world#progress),
                                         viewport = design(), color = coverColor(), z = Transition.defaultZ() });
        bg :: List.flatten(gridItems() :: ui :: cover :: Nil)
}
