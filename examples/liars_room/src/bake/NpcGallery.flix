// NpcGallery — 目視承認用のシルエットギャラリーをヘッドレスに焼き込む
// （engine_tools の SoftRaster + GifEncoder、GL なし）。make bake が生成する。
//
//   gallery/people.png      — NPC 7 色 + プレイヤー × 4 方向（静止ポーズ）
//   gallery/people_walk.gif — 同じ並びがその場で行進する（歩行サイクルの確認）
//
// 描画は src/Human.flix の同じ関数を 8 倍で呼ぶだけ。デザインはここに住まない。
mod NpcGallery {
    import java.io.File

    def u(): Float64 = 8.0                       // 1 ユニット = 8 design px（8 倍表示）
    def cellW(): Float64 = 18.0 * u()
    def rowH(): Float64 = 18.0 * u()
    def colCount(): Int32 = 8                    // NPC 7 色 + プレイヤー
    def labelBand(): Float64 = 40.0
    def design(): Vec2.Vec2 =
        { x = Int32.toFloat64(colCount()) * cellW(),
          y = 4.0 * rowH() + labelBand() }

    def ttfPath(): String = "assets/PixelMplus10-Regular.ttf"
    def backdrop(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    def labelTint(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32} // #cbdbfc

    /// 列 i の塗り分け（0..6 = NPC、7 = プレイヤー）。
    def skinAt(i: Int32): Human.Skin =
        if (i < 7) Palette.npcSkin(i) else Palette.playerSkin()

    def nameAt(i: Int32): String =
        if (i < 7) Palette.nameOf(i) else "プレイヤー"

    def center(col: Int32, row: Int32): Vec2.Vec2 =
        { x = Int32.toFloat64(col) * cellW() + cellW() / 2.0,
          y = Int32.toFloat64(row) * rowH() + 9.0 * u() }

    def dirs(): List[Dir4.Dir4] =
        Dir4.Down :: Dir4.Left :: Dir4.Right :: Dir4.Up :: Nil

    /// 歩行位相 `phase`（0.0 = 静止ポーズ）における全員 × 4 方向の 1 フレーム。
    pub def frameItems(atlas: FontAtlas, phase: Float64): List[Render.PlacedItem] =
        let people = List.range(0, colCount()) |> List.flatMap(col ->
            dirs() |> List.zipWithIndex |> List.flatMap(rowDir -> {
                let (row, dir) = rowDir;
                Human.walking(center(col, row), 16.0 * u(), skinAt(col), dir, phase)
            }));
        let labels = List.range(0, colCount()) |> List.map(col -> label(atlas, col));
        List.append(people, labels)

    def label(atlas: FontAtlas, col: Int32): Render.PlacedItem =
        let text = nameAt(col);
        let size = 20.0;
        let w = Text.measure(Text.make(text, atlas, size))#x;
        let cx = Int32.toFloat64(col) * cellW() + cellW() / 2.0;
        { at = {x = cx - w / 2.0, y = 4.0 * rowH() + 8.0}, item = Render.textTinted(text, atlas, size, labelTint(), 10) }

    def req(atlas: FontAtlas, phase: Float64, path: String): SoftRaster.RasterReq =
        let (drawables, polygons) = Render.draw(frameItems(atlas, phase));
        { drawables = drawables, polygons = polygons,
          design = design(), scale = 1, background = backdrop(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    /// 静止ポーズの一覧 PNG と歩行サイクル GIF を焼く（Bake.all から呼ぶ）。
    pub def bakeAll(): Unit \ IO =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "");
        discard (new File("gallery")).mkdirs();
        SoftRaster.render(req(atlas, 0.0, "gallery/people.png"));
        let frames = List.map(p -> SoftRaster.renderToImage(req(atlas, p, "gallery/people_walk.gif")),
                              0.0 :: 0.25 :: 0.5 :: 0.75 :: Nil);
        GifEncoder.encode(frames, 150, "gallery/people_walk.gif")

    /// TestViewGuards 用の読み口: 1 フレームぶんのパーツ数。
    pub def partCount(): Int32 \ IO =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "");
        List.length(frameItems(atlas, 0.0))
}
