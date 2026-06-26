// RenderWorld — World を List[GameEngine.Drawable] に射影する（描画ブリッジ）
//
// scene-tree を介さず、World の component から直接 Drawable を組み立てて
// GameEngine.Game.renderCommands に渡す。これがエンジン改修ゼロで ECS を描く要。
//   - スプライト: positions + sprites（centered=true、flip は scale 符号）
//   - テキスト  : HUD entity を Label2D.toDrawables（純粋）で
//   - ボタン枠  : Drawable.style=Some(box)（texture="" の単色矩形）
// FontAtlas は Label2D.make が要求するので引数で受け取る（World には持たせない）。

mod RenderWorld {

    // ── 色 ──

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// project.json の clearColor と同じ teal（背景塗り）
    def bgColor(): Color = {r = 0.219608f32, g = 0.372549f32, b = 0.380392f32}

    // ── zIndex 帯（決定的な重なり順）──
    def zBg(): Int32     = -100
    def zMob(): Int32    = 0
    def zPlayer(): Int32 = 10
    def zHud(): Int32    = 100

    def hudFontSize(): Float64 = 24.0

    // ── エントリ ──

    pub def renderWorld(world: World, atlas: FontAtlas): List[GameEngine.Drawable] =
        let World.World(w) = world;
        let bg = bgDrawable();
        let sprites = spriteDrawables(w#positions, w#sprites, w#player);
        let huds = hudDrawables(w#huds, atlas);
        bg :: List.append(sprites, huds)

    // ── 背景 ──

    def bgDrawable(): GameEngine.Drawable =
        boxDrawable({x = 0.0, y = 0.0},
                    {x = Int32.toFloat64(World.designWi()), y = Int32.toFloat64(World.designHi())},
                    bgColor(), zBg())

    // ── スプライト ──

    def spriteDrawables(positions: Map[EntityId, Vec2.Vec2],
                        sprites: Map[EntityId, SpriteComp],
                        playerOpt: Option[EntityId]): List[GameEngine.Drawable] =
        Map.foldLeftWithKey((acc, id, sc) -> match Map.get(id, positions) {
            case None      => acc
            case Some(pos) =>
                let z = if (playerOpt == Some(id)) zPlayer() else zMob();
                spriteDrawable(World.currentTexture(sc), pos, z, sc#flipH, sc#flipV) :: acc
        }, Nil, sprites)

    def spriteDrawable(tex: String, pos: Vec2.Vec2, z: Int32,
                       flipH: Bool, flipV: Bool): GameEngine.Drawable =
        { texture  = tex,
          position = pos,
          scale    = {x = if (flipH) -1.0 else 1.0, y = if (flipV) -1.0 else 1.0},
          rotation = 0.0,
          color    = white(),
          alpha    = 1.0f32,
          centered = true,
          uvOffset = {x = 0.0, y = 0.0},
          uvScale  = {x = 1.0, y = 1.0},
          zIndex   = z,
          style    = None }

    // ── HUD ──

    def hudDrawables(huds: Map[EntityId, HudComp], atlas: FontAtlas): List[GameEngine.Drawable] =
        Map.foldLeftWithKey((acc, _id, h) ->
            if (not h#visible) acc
            else List.append(acc, hudOne(h, atlas)), Nil, huds)

    def hudOne(h: HudComp, atlas: FontAtlas): List[GameEngine.Drawable] =
        match h#kind {
            case HudKind.StartButton =>
                let box = boxDrawable(h#pos, h#size, {r = 0.15f32, g = 0.15f32, b = 0.18f32}, zHud());
                box :: textDrawables(h#text, {x = h#pos#x + 12.0, y = h#pos#y + 4.0}, atlas)
            case _ =>
                textDrawables(h#text, h#pos, atlas)
        }

    def textDrawables(text: String, pos: Vec2.Vec2, atlas: FontAtlas): List[GameEngine.Drawable] =
        // zIndex は Drawable を後処理で上書き（Label2D.setZIndex の有無に依存しない）
        Label2D.toDrawables(Label2D.make(text, atlas, hudFontSize()), pos)
            |> List.map(d -> {zIndex = zHud() | d})

    // ── 単色矩形（背景・ボタン枠）──
    // Drawable.style=Some + texture="" で単色塗り。position=左上、scale=ピクセルサイズ、centered=false。

    def boxDrawable(pos: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): GameEngine.Drawable =
        { texture  = "",
          position = pos,
          scale    = size,
          rotation = 0.0,
          color    = color,
          alpha    = 1.0f32,
          centered = false,
          uvOffset = {x = 0.0, y = 0.0},
          uvScale  = {x = 1.0, y = 1.0},
          zIndex   = z,
          style    = Some({ cornerRadius = 0.0, borderWidth = 0.0,
                            borderColor = white(), borderAlpha = 0.0f32,
                            stripeColor = white(), stripeAlpha = 0.0f32,
                            stripeWidth = 0.0, stripePeriod = 0.0 }) }
}
