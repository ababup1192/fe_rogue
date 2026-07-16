// View — World から絵を作る。背景に薄い格子（覆いが乗ったか一目で分かる目印）を敷き、
// design 領域の縁取りと四隅マーカーで「画面の端がどこか」を目視できるようにし、
// その上にラベル UI（ui.json）と Transition.itemsAt が返す覆いを重ねる。
// 格子・縁取り・覆いは UI ではない純粋な絵なので Render 直書き、ラベルの見た目は ui.json が持つ。

mod View {

    def bgColor(): Color = { r = 0.18f32, g = 0.19f32, b = 0.24f32 }
    def gridColor(): Color = { r = 0.30f32, g = 0.32f32, b = 0.38f32 }
    def coverColor(): Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }
    /// 縁取り・十字の色（design の四辺そのものを示す線）。
    def edgeColor(): Color = { r = 0.2f32, g = 0.9f32, b = 0.95f32 }
    /// 四隅 L 字マーカーの色（縁取りと見分けるため別色）。
    def cornerColor(): Color = { r = 0.95f32, g = 0.85f32, b = 0.2f32 }

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

    /// design 領域の四辺いっぱいに引く縁取りの太さ（フルスクリーン時に外側の黒帯と見分けやすい太さ）。
    def edgeThickness(): Float64 = 4.0

    /// 四隅 L 字マーカーの一辺の長さ。
    def cornerLen(): Float64 = 20.0

    /// 十字マーカーの半径（中心からの腕の長さ）。
    def crossLen(): Float64 = 12.0

    /// design 四辺いっぱいの縁取り 4 本（上下左右）。フルスクリーン時、この外側が
    /// 黒帯（レターボックス）として見えれば viewport が design 通りに収まっている証拠になる。
    def edgeItems(): List[Render.PlacedItem] =
        let w = design()#x;
        let h = design()#y;
        let t = edgeThickness();
        { at = { x = 0.0, y = 0.0 },     item = Render.box({ x = w, y = t }, edgeColor(), 20) } ::
        { at = { x = 0.0, y = h - t },   item = Render.box({ x = w, y = t }, edgeColor(), 20) } ::
        { at = { x = 0.0, y = 0.0 },     item = Render.box({ x = t, y = h }, edgeColor(), 20) } ::
        { at = { x = w - t, y = 0.0 },   item = Render.box({ x = t, y = h }, edgeColor(), 20) } ::
        Nil

    /// 四隅 1 つぶんの L 字（横棒 + 縦棒）。sign で内向きの方向を決める
    /// （左上=(+1,+1)・右上=(-1,+1)・左下=(+1,-1)・右下=(-1,-1)）。
    def cornerMarker(corner: Vec2.Vec2, sign: Vec2.Vec2): List[Render.PlacedItem] =
        let len = cornerLen();
        let t = edgeThickness();
        let horiz = { x = if (sign#x > 0.0) corner#x else corner#x - len, y = corner#y };
        let vert  = { x = corner#x, y = if (sign#y > 0.0) corner#y else corner#y - len };
        { at = horiz, item = Render.box({ x = len, y = t }, cornerColor(), 21) } ::
        { at = vert,  item = Render.box({ x = t, y = len }, cornerColor(), 21) } ::
        Nil

    /// 四隅の L 字マーカー（スケーリングの歪み・欠けが起きると真っ先にズレて見える位置）。
    def cornerItems(): List[Render.PlacedItem] =
        let w = design()#x;
        let h = design()#y;
        let corners = ({ x = 0.0, y = 0.0 }, { x = 1.0, y = 1.0 }) ::
                      ({ x = w, y = 0.0 },   { x = -1.0, y = 1.0 }) ::
                      ({ x = 0.0, y = h },   { x = 1.0, y = -1.0 }) ::
                      ({ x = w, y = h },     { x = -1.0, y = -1.0 }) :: Nil;
        corners |> List.flatMap(pair -> { let (corner, sign) = pair; cornerMarker(corner, sign) })

    /// 画面中央の小さな十字（design の中心そのものが分かる目印）。
    def crossItems(): List[Render.PlacedItem] =
        let center = { x = design()#x / 2.0, y = design()#y / 2.0 };
        let len = crossLen();
        Render.lineSeg({ x = center#x - len, y = center#y }, { x = center#x + len, y = center#y },
                        2.0, cornerColor(), 21) ::
        Render.lineSeg({ x = center#x, y = center#y - len }, { x = center#x, y = center#y + len },
                        2.0, cornerColor(), 21) :: Nil

    /// フルスクリーン起動確認用の目印一式（縁取り + 四隅 L 字 + 中央十字）。
    /// 縁取りの外側に黒帯が見えれば viewport 正常、四隅マーカーが直角のまま欠けなければ
    /// スケーリングも歪んでいない。
    def viewportMarkerItems(): List[Render.PlacedItem] =
        List.flatten(edgeItems() :: cornerItems() :: crossItems() :: Nil)

    /// 背景の格子 → viewport 目印 → ラベル UI（ui.json）→ 覆い（Transition）の順に重ねる。
    /// 覆いは再生中だけ描く（Idle でも描き続けると FadeOut 後の黒が残り、画面が消えたように見える）。
    pub def frame(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let bg = { at = Vec2.zero(), item = Render.box(design(), bgColor(), 0) };
        let ui = UiRender.itemsWith(_ -> ctx#atlas, _ -> None, world#ui, design());
        let cover = world#playing
            |> Option.map(progress -> Transition.itemsAt({
                   kind = world#kind, t = Transition.tOf(progress),
                   viewport = design(), color = coverColor(), z = Transition.defaultZ() }))
            |> Option.getWithDefault(List.empty());
        bg :: List.flatten(gridItems() :: viewportMarkerItems() :: ui :: cover :: Nil)
}
