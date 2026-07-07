// RenderWorld — World を描画する「extract」（World → render component の draw list → 描画）
//
// 生の GameEngine.Drawable はここでは一切組まない。共有 lib の Render（RenderItem＋射影）に
// 渡すだけ＝Bevy の extract 相当（component を埋めて lib/plugin が Drawable 化）。
//   - スプライト: positions + sprites（currentTexture＋flip）→ Render.sprite
//   - テキスト  : HUD entity → Render.text（lib が Label2D.toDrawables に委譲）
//   - 矩形/背景 : Render.solidBox
// 静的型の Flix では Bevy の汎用 extract が書けないので、この関数が毎フレームの extract として残る
// （生 Drawable を触らない点が本質的改善。RenderItem を component 保存する完全形は将来拡張）。

mod RenderWorld {

    def bgColor(): Color = {r = 0.219608f32, g = 0.372549f32, b = 0.380392f32}   // project.json clearColor
    def buttonColor(): Color = {r = 0.15f32, g = 0.15f32, b = 0.18f32}

    // zIndex 帯（決定的な重なり順。render_core が stable sort する）
    def zBg(): Int32     = -100
    def zMob(): Int32    = 0
    def zPlayer(): Int32 = 10
    def zHud(): Int32    = 100

    def hudFontSize(): Float64 = 24.0

    // ── エントリ: World → draw list → Drawable（lib に委譲）──

    pub def renderWorld(world: World, atlas: FontAtlas): List[GameEngine.Drawable] =
        let World.World(w) = world;
        let bg      = ({x = 0.0, y = 0.0}, bgItem());
        let sprites = spriteItems(w#positions, w#sprites, w#player);
        let huds    = hudItems(w#huds, atlas);
        let (drawables, _) = Render.draw(bg :: List.append(sprites, huds));
        drawables

    def bgItem(): Render.RenderItem =
        Render.solidBox({x = Int32.toFloat64(World.designWi()), y = Int32.toFloat64(World.designHi())},
                        bgColor(), zBg())

    // ── スプライト（position を持つ entity）──

    def spriteItems(positions: Map[EntityId, Vec2.Vec2],
                    sprites: Map[EntityId, SpriteComp],
                    playerOpt: Option[EntityId]): List[(Vec2.Vec2, Render.RenderItem)] =
        // sprites × positions の join → (pos, RenderItem) 射影（position を持たない entity は除外）。
        Query.with2List(sprites, positions, (id, sc, pos) ->
            let z = if (playerOpt == Some(id)) zPlayer() else zMob();
            (pos, Render.sprite(World.currentTexture(sc), z, sc#flipH, sc#flipV)))

    // ── HUD（テキスト／ボタン＝Box＋Text の2アイテム）──

    def hudItems(huds: Map[EntityId, HudComp], atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        Map.foldLeftWithKey((acc, _id, h) ->
            if (not h#visible) acc
            else List.append(acc, hudOne(h, atlas)), Nil, huds)

    def hudOne(h: HudComp, atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        match h#kind {
            case HudKind.StartButton =>
                (h#pos, Render.solidBox(h#size, buttonColor(), zHud())) ::
                ({x = h#pos#x + 12.0, y = h#pos#y + 4.0}, Render.text(h#text, atlas, hudFontSize(), zHud())) :: Nil
            case _ =>
                (h#pos, Render.text(h#text, atlas, hudFontSize(), zHud())) :: Nil
        }
}
