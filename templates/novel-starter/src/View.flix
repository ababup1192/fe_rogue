// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 場面は雨の夜の書斎: 壁・雨の窓・絵が消えた額縁（ドット絵）・館の灯り。
// 疑うたびに灯りが消え、部屋には暗幕が重なる（濃さは novel.kind.json の dim）。
// 会話窓と選択肢の枠は ui.json（UiRender）、本文の文字送りは NovelKit.body が描く。
mod View {

    // ── z 層（部屋 0..9 / 額縁 10 / 灯り 20 / 暗幕 50 / 表紙 60。UI は ui.json 側で 100+） ──

    def zRoom(): Int32 = 0
    def zWall(): Int32 = 1
    def zWindow(): Int32 = 2
    def zTrace(): Int32 = 9
    def zFrame(): Int32 = 10
    def zLamp(): Int32 = 20
    def zVeil(): Int32 = 50
    def zTitle(): Int32 = 60

    /// スプライトの格子は 1 セル = 4px で描く（16×12 の額縁 = 64×48px）。
    def px(): Int32 = 4

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               room(w#theme)
            :: emptyFrame(w)
            :: lamps(w)
            :: veil(w)
            :: title(ctx#atlas, w)
            :: UiRender.itemsWith(_ -> ctx#atlas, _ -> None, w#ui, ctx#visible#size)
            :: NovelKit.body(ctx#atlas, w#theme#ink,
                   { size = w#kind#bodySize, lineGap = w#kind#bodyGap }, w#ui, w#kit)
            :: TextDraw.errorBanner(ctx#atlas, w#docError)
            :: Nil)

    // ── 部屋（壁・床・雨の窓） ──

    def room(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
           { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = World.width(), y = World.height() }, theme#bg, zRoom()) }
        :: { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = World.width(), y = 190.0 }, theme#wall, zWall()) }
        :: window(theme)

    /// 雨の窓。枠は壁の派生色、雨すじは Hash01 で決定的に散らす（保存も乱数の種も持たない）。
    def window(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let frameColor = ThemeDoc.lighten(theme#wall, 0.18);
        let paneAt = { x = 336.0, y = 38.0 };
        let paneSize = { x = 88.0, y = 104.0 };
        List.flatten(
               border(paneAt, paneSize, 4.0, frameColor, zWindow())
            :: ({ at = paneAt, item = Render.box(paneSize, theme#window, zWindow()) } :: Nil)
            :: ({ at = { x = paneAt#x + paneSize#x / 2.0 - 2.0, y = paneAt#y },
                  item = Render.box({ x = 4.0, y = paneSize#y }, frameColor, zWindow() + 1) } :: Nil)
            :: rain(paneAt, paneSize, theme)
            :: Nil)

    /// 矩形のまわりの枠線 4 本。
    def border(at: Vec2.Vec2, size: Vec2.Vec2, thickness: Float64,
               color: Color, z: Int32): List[Render.PlacedItem] =
           { at = { x = at#x - thickness, y = at#y - thickness },
             item = Render.box({ x = size#x + thickness * 2.0, y = thickness }, color, z) }
        :: { at = { x = at#x - thickness, y = at#y + size#y },
             item = Render.box({ x = size#x + thickness * 2.0, y = thickness }, color, z) }
        :: { at = { x = at#x - thickness, y = at#y },
             item = Render.box({ x = thickness, y = size#y }, color, z) }
        :: { at = { x = at#x + size#x, y = at#y },
             item = Render.box({ x = thickness, y = size#y }, color, z) }
        :: Nil

    /// 雨すじ。本数と明るさは色票（novel.theme.json）から、
    /// i 番目の位置と長さは Hash01 が決める（毎回同じ = bake が決定的）。
    def rain(paneAt: Vec2.Vec2, paneSize: Vec2.Vec2, theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let streakColor = ThemeDoc.lighten(theme#window, theme#rainGlow);
        List.range(0, theme#rainCount) |> List.map(i ->
            { at = { x = paneAt#x + 4.0 + Hash01.at(i, 0) * (paneSize#x - 8.0),
                     y = paneAt#y + Hash01.at(i, 1) * (paneSize#y - 34.0) },
              item = Render.box({ x = 1.0, y = 12.0 + Hash01.at(i, 2) * 20.0 },
                                streakColor, zWindow() + 1) })

    // ── 絵が消えた額縁（ドット絵。内側に「絵があった跡」が透ける） ──

    def frameTopLeft(): Vec2.Vec2 = { x = 118.0, y = 64.0 }

    def emptyFrame(w: World.World): List[Render.PlacedItem] =
        let topLeft = frameTopLeft();
        let cell = Int32.toFloat64(px());
        // 絵があった跡: 長く飾られて壁が焼けなかった、ひとまわり明るい矩形。
        let trace = { at = { x = topLeft#x + cell * 2.0, y = topLeft#y + cell * 2.0 },
                      item = Render.box({ x = cell * 12.0, y = cell * 8.0 },
                                        ThemeDoc.lighten(w#theme#wall, 0.08), zTrace()) };
        let items = PxSprite.draw(w#sprites, "frame", "idle", topLeft,
            false, px(), key -> ThemeDoc.resolver(w#theme, key), zFrame());
        if (List.isEmpty(items))
            // fail-open: スプライトが無い・読めないときは差し色の枠線だけ。
            trace :: border(topLeft, { x = cell * 16.0, y = cell * 12.0 }, cell,
                            w#theme#accent, zFrame())
        else
            trace :: items

    // ── 館の灯り（疑うたびに右からひとつ消える） ──

    def lamps(w: World.World): List[Render.PlacedItem] =
        let count = w#story#lamps;
        let lit = World.lampsLit(w);
        List.range(0, count) |> List.flatMap(i -> lamp(lampX(count, i), i < lit, w#theme))

    /// i 番目の灯りの x（壁の上に等間隔。1 つなら真ん中）。
    def lampX(count: Int32, i: Int32): Float64 =
        if (count <= 1) World.width() / 2.0
        else 80.0 + Int32.toFloat64(i) * (World.width() - 160.0) / Int32.toFloat64(count - 1)

    /// 灯りひとつ: 腕木 + 火屋。ついていれば glow（加算の光球）をまとう。
    def lamp(x: Float64, litNow: Bool, theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let head = { x = x - 4.0, y = 28.0 };
        let arm = { at = { x = x - 2.0, y = 36.0 },
                    item = Render.box({ x = 4.0, y = 10.0 },
                                      ThemeDoc.lighten(theme#wall, 0.1), zLamp()) };
        let headColor = if (litNow) ThemeDoc.lighten(theme#accent, 0.3)
                        else ThemeDoc.lighten(theme#bg, 0.08);
        let headBox = { at = head, item = Render.box({ x = 8.0, y = 8.0 }, headColor, zLamp() + 1) };
        let glow = if (litNow)
            Render.glowAt({ x = x, y = 32.0 }, 36.0, theme#accent,
                          { alpha = 0.32, blend = DrawCmd.BlendMode.Add }, zLamp() + 2)
        else Nil;
        arm :: headBox :: glow

    // ── 暗幕（消えた灯りの数 × dim の濃さで部屋が沈む） ──

    def veil(w: World.World): List[Render.PlacedItem] =
        let alpha = Float64.min(1.0, Int32.toFloat64(w#lightsOut) * w#kind#dim);
        if (alpha <= 0.0) Nil
        else { at = { x = 0.0, y = 0.0 },
               item = Render.box({ x = World.width(), y = World.height() },
                                 { r = 0.02f32, g = 0.02f32, b = 0.05f32 }, zVeil())
                   |> Render.fade(Float64.truncateToFloat32(alpha)) } :: Nil

    // ── 表紙（文言はすべて台本 Doc から: 事件の名前・一行・はじめ方のヒント） ──

    def title(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Story => Nil
            case World.Phase.Title =>
                   TextDraw.centered({ text = w#story#title, atlas = atlas, size = 30.0,
                                       color = ThemeDoc.lighten(w#theme#accent, 0.2),
                                       z = zTitle(), centerX = World.width() / 2.0, y = 118.0 })
                :: TextDraw.centered({ text = w#story#subtitle,
                                       atlas = atlas, size = 10.0, color = w#theme#ink,
                                       z = zTitle(), centerX = World.width() / 2.0, y = 160.0 })
                :: TextDraw.centered({ text = w#story#hint, atlas = atlas, size = 9.0,
                                       color = ThemeDoc.lighten(w#theme#bg, 0.35),
                                       z = zTitle(), centerX = World.width() / 2.0, y = 196.0 })
                :: Nil
        }
}
