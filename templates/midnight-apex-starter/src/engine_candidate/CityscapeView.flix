// CityscapeView — JSONの夜景を循環させる薄い表示層。
mod CityscapeView {

    /// 遠景と近景で移動量を変え、円形都市を見回す感覚を作る。
    pub def draw(world: World.World, _horizon: Float64,
                 z: Int32): List[Render.PlacedItem] =
        let scenery = world#scenery;
        let panorama = panoramaOffset(world);
        drawWrapped({
            sprite = "far_city",
            top = scenery#farTop,
            offset = panorama * scenery#farParallax,
            z = z
        }, world)
        ::: drawWrapped({
            sprite = "near_city",
            top = scenery#nearTop,
            offset = panorama * scenery#nearParallax,
            z = z + 2
        }, world)

    /// 車体位置から視線の横振りだけを導き、都市の配置や速度をコードへ持ち込まない。
    def panoramaOffset(world: World.World): Float64 =
        let halfTravel = World.designWidth() / 2.0 - World.carWidth() / 2.0;
        -(world#playerX - World.designWidth() / 2.0) / halfTravel
            * world#scenery#panoramaStrength

    /// JSON側の横セル数と拡大率から一周幅を作り、前後の複製で継ぎ目を隠す。
    def drawWrapped(layer: {
                        sprite = String,
                        top = Float64,
                        offset = Float64,
                        z = Int32
                    },
                    world: World.World): List[Render.PlacedItem] =
        let scale = world#scenery#spriteScale;
        let width = Int32.toFloat64(world#scenery#spriteColumns * scale);
        let wrapped =
            if (width <= 0.0) 0.0
            else Curve.loop(1.0, width, layer#offset);
        let copyOffsets = (-width) :: 0.0 :: width :: Nil;
        copyOffsets |> List.flatMap(copyOffset ->
                PxSprite.draw(
                    world#sprites,
                    layer#sprite,
                    "idle",
                    { x = wrapped + copyOffset, y = layer#top },
                    false,
                    scale,
                    key -> colorOf(key, world#theme),
                    layer#z))

    /// 夜景の意味色キー → 実色。Studio 用の色票（Palette）も同じここを引く
    /// ので、実色を決める場所が 2 つに割れない。
    pub def colorOf(key: String, theme: ThemeDoc.Doc): Color =
        match key {
            case "star"            => ThemeDoc.darken(theme#lane, 0.34)
            case "farBuilding"     => ThemeDoc.darken(theme#roadShade, 0.18)
            case "nearBuilding"    => ThemeDoc.darken(theme#roadShade, 0.30)
            case "cyanLight"       => ThemeDoc.darken(theme#lane, 0.18)
            case "magentaLight"    => ThemeDoc.darken(theme#player, 0.18)
            case "amberLight"      => ThemeDoc.darken(theme#shoulder, 0.18)
            case _                 => theme#night
        }

}
