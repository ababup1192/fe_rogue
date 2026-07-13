// ArtGallery — 絵作り候補のシートをヘッドレスに焼き、承認用ダッシュボードを組む。
// make bake が再生成する。ゲーム本体はまだ無い — 絵の承認が全部済んでから組む。
mod ArtGallery {
    import java.io.File

    def ttfPath(): String = "assets/fonts/MPLUSU-Medium.ttf"

    def labelTint(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32} // #cbdbfc

    // ── のび候補シート: 4 案 × （横向き / 横+帽子 / こっち見+帽子 / 濃い緑） ──

    /// 1 セルの一辺（のびは 32 グリッドなので 6 倍で 192px）。
    def cellPx(): Float64 = 192.0
    def cellPad(): Float64 = 10.0
    def labelBand(): Float64 = 26.0

    /// 統合案 1 本（V09 白 + 斑細く後ろ寄り + 傾き強め + はみ出し封止）。
    def designs(): List[(String, Nobi.Detail)] =
        ("V16 統合案", Nobi.baseDetail()) :: Nil

    /// 列 = 見せ方のバリエーション。
    def columns(): List[(String, Nobi.Style -> Nobi.Style)] =
        ("よこ向き", st -> st) ::
        ("帽子つき", st -> { hat = true | st }) ::
        ("こっち見+帽子", st -> { hat = true, look = Nobi.Look.Front | st }) ::
        ("濃い緑", st -> { skin = Palette.nobiDeep() | st }) :: Nil

    def baseStyle(detail: Nobi.Detail): Nobi.Style =
        { design = Nobi.Design.P1, skin = Palette.nobiBright(), look = Nobi.Look.Side,
          hat = false, detail = detail }

    def nobiSheetSize(): Vec2.Vec2 =
        let rows = Int32.toFloat64(List.length(designs()));
        { x = 4.0 * (cellPx() + cellPad()) + cellPad(),
          y = rows * (cellPx() + labelBand()) + cellPad() + labelBand() }

    def nobiSheetItems(atlas: FontAtlas): List[Render.Placed] =
        let rows = designs() |> List.zipWithIndex |> List.flatMap(rowEntry -> {
            let (row, designPair) = rowEntry;
            let (designName, design) = designPair;
            let cy = cellPad() + labelBand()
                + Int32.toFloat64(row) * (cellPx() + labelBand()) + cellPx() / 2.0;
            let cells = columns() |> List.zipWithIndex |> List.flatMap(colEntry -> {
                let (col, colPair) = colEntry;
                let (_, tweak) = colPair;
                let cx = cellPad() + Int32.toFloat64(col) * (cellPx() + cellPad()) + cellPx() / 2.0;
                Nobi.parts({x = cx, y = cy}, cellPx(), tweak(baseStyle(design)))
            });
            let label = { at = {x = cellPad(), y = cy + cellPx() / 2.0 + 4.0},
                item = Render.textTinted(designName, atlas, 16.0, labelTint(), 50) };
            label :: cells
        });
        let headers = columns() |> List.zipWithIndex |> List.map(colEntry -> {
            let (col, colPair) = colEntry;
            let (colName, _) = colPair;
            let cx = cellPad() + Int32.toFloat64(col) * (cellPx() + cellPad());
            { at = {x = cx + 8.0, y = 6.0}, item = Render.textTinted(colName, atlas, 14.0, labelTint(), 50) }
        });
        List.append(headers, rows)

    /// Bakery に渡す焼き込み設定。シートごとに解像度と拡大率が違うので design/scale は引数で渡す
    /// （静止画だけなので frame/gif 系は使わない）。
    def config(atlas: FontAtlas, design: Vec2.Vec2, scale: Int32): Bakery.BakeConfig =
        { design = design, scale = scale, background = Palette.galleryBg(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outDir = "gallery", frameW = 0, frameH = 0, gifDelayMs = 0, gifFps = 0 }

    /// 描画アイテム列を 1 枚の PNG に焼く（配管は Bakery が担う）。
    def shotScene(atlas: FontAtlas, items: List[Render.Placed], design: Vec2.Vec2,
                  scale: Int32, name: String): Unit \ IO =
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(config(atlas, design, scale), drawables, polygons, name)

    /// のび候補シートを焼く。
    def bakeNobi(atlas: FontAtlas): Unit \ IO =
        shotScene(atlas, nobiSheetItems(atlas), nobiSheetSize(), 1, "nobi_candidates")

    // ── キッチン 3 案（320×240 まるごと・2 倍で出力）──

    def kitchens(): List[(String, Palette.KitchenTone, Kitchen.Layout, Kitchen.PropSet)] =
        ("kitchen_cream", Palette.toneCream(), Kitchen.Layout.TriangleUp, Kitchen.PropSet.Classic) ::
        ("kitchen_mint", Palette.toneMint(), Kitchen.Layout.TriangleUp, Kitchen.PropSet.Cozy) ::
        ("kitchen_wood", Palette.toneWood(), Kitchen.Layout.TriangleDown, Kitchen.PropSet.Classic) :: Nil

    def bakeKitchens(atlas: FontAtlas): Unit \ IO =
        kitchens() |> List.forEach(entry -> {
            let (name, tone, layout, props) = entry;
            shotScene(atlas, Kitchen.scene(tone, layout, props, atlas),
                {x = 320.0, y = 240.0}, 2, name)
        })

    // ── 持ち場の小物 2 案の比較シート ──

    def stationsSheetItems(atlas: FontAtlas): List[Render.Placed] =
        let tone = Palette.toneCream();
        let rows =
            (30.0, "案1 クラシック", Kitchen.PropSet.Classic) ::
            (140.0, "案2 コージー", Kitchen.PropSet.Cozy) :: Nil;
        rows |> List.flatMap(row -> {
            let (y, label, props) = row;
            List.flatten(
                ({ at = {x = 10.0, y = y - 24.0}, item = Render.textTinted(label, atlas, 12.0, labelTint(), 50) } :: Nil) ::
                Kitchen.counter(tone, 14.0, y + 20.0, props, Kitchen.Station.Bowl, atlas) ::
                Kitchen.counter(tone, 120.0, y + 20.0, props, Kitchen.Station.Cutter, atlas) ::
                Kitchen.oven(240.0, y - 4.0, props, atlas) :: Nil)
        })

    def bakeStations(atlas: FontAtlas): Unit \ IO =
        shotScene(atlas, stationsSheetItems(atlas), {x = 320.0, y = 250.0}, 2, "stations")

    // ── 品物アイコン一覧 ──

    def itemsSheetItems(atlas: FontAtlas): List[Render.Placed] =
        Items.allKinds() |> List.zipWithIndex |> List.flatMap(entry -> {
            let (i, kind) = entry;
            let col = Int32.modulo(i, 6);
            let row = i / 6;
            let cx = 50.0 + Int32.toFloat64(col) * 100.0;
            let cy = 60.0 + Int32.toFloat64(row) * 120.0;
            let label = { at = {x = cx - 44.0, y = cy + 46.0},
                item = Render.textTinted(Items.nameOf(kind), atlas, 12.0, labelTint(), 50) };
            label :: Items.icon(kind, {x = cx, y = cy}, 80.0, atlas)
        })

    def bakeItems(atlas: FontAtlas): Unit \ IO =
        shotScene(atlas, itemsSheetItems(atlas), {x = 620.0, y = 250.0}, 1, "items")

    // ── UI モック 2 案（キッチン + のび + 品物 + HUD を仮合成）──

    /// のびの足元が床座標 spot に着くように中心を決める（のびの接地は 32 グリッドの y=25.5）。
    def nobiAt(spot: Vec2.Vec2, size: Float64, style: Nobi.Style): List[Render.Placed] =
        Nobi.parts({x = spot#x, y = spot#y - size * 0.297}, size, style)
            |> List.map(raise(20))

    def raise(delta: Int32, placed: Render.Placed): Render.Placed =
        { item = Render.raiseZ(delta, placed#item) | placed }

    def mockNobiStyle(): Nobi.Style =
        { design = Nobi.Design.P1, skin = Palette.nobiBright(), look = Nobi.Look.Side,
          hat = true, detail = Nobi.baseDetail() }

    /// 十字リング型: のびの周りの 4 スロットに品物 + 方向記号。
    def ringSlots(atlas: FontAtlas, spot: Vec2.Vec2): List[Render.Placed] =
        let slots =
            ({x = spot#x, y = spot#y - 96.0}, "▲", Items.Kind.Flour) ::
            ({x = spot#x, y = spot#y + 20.0}, "▼", Items.Kind.Fish) ::
            ({x = spot#x - 62.0, y = spot#y - 38.0}, "◀", Items.Kind.Egg) ::
            ({x = spot#x + 62.0, y = spot#y - 38.0}, "▶", Items.Kind.StarCutter) :: Nil;
        slots |> List.flatMap(slot -> {
            let (pos, arrow, kind) = slot;
            slotCard(atlas, pos, arrow, kind)
        })

    /// スロット 1 枚（角丸カード + 品物 + 方向記号）。明るい床でも読めるように、
    /// カードは暗色 + ふち、方向記号も小さな暗色バッジに載せる。
    def slotCard(atlas: FontAtlas, pos: Vec2.Vec2, arrow: String,
                 kind: Items.Kind): List[Render.Placed] =
        ({ at = {x = pos#x - 14.0, y = pos#y - 14.0},
            item = Render.solidBox({x = 28.0, y = 28.0}, Palette.slotBg(), 30)
                |> Render.rounded(5.0) |> Render.fade(0.92f32)
                |> Render.outline(Palette.slotEdge(), 1.5) } ::
         { at = {x = pos#x - 7.0, y = pos#y - 28.5},
            item = Render.solidBox({x = 14.0, y = 12.0}, Palette.hudBg(), 31)
                |> Render.rounded(4.0) |> Render.fade(0.92f32)
                |> Render.outline(Palette.slotEdge(), 1.0) } ::
         { at = {x = pos#x - 4.0, y = pos#y - 26.5},
            item = Render.textTinted(arrow, atlas, 9.0, Palette.uiAccent(), 32) } :: Nil)
            |> List.append(Items.icon(kind, pos, 22.0, atlas) |> List.map(raise(31)))

    /// 下カード型: 画面下に 4 枚並べる。
    def bottomCards(atlas: FontAtlas): List[Render.Placed] =
        let entries =
            ("◀", Items.Kind.Egg, 100.0) ::
            ("▲", Items.Kind.Flour, 140.0) ::
            ("▼", Items.Kind.Fish, 180.0) ::
            ("▶", Items.Kind.StarCutter, 220.0) :: Nil;
        entries |> List.flatMap(entry -> {
            let (arrow, kind, x) = entry;
            slotCard(atlas, {x = x, y = 216.0}, arrow, kind)
        })

    /// 上バー型 HUD。
    def hudBar(atlas: FontAtlas): List[Render.Placed] =
        { at = {x = 0.0, y = 0.0}, item = Render.solidBox({x = 320.0, y = 18.0}, Palette.hudBg(), 40)
            |> Render.fade(0.88f32) } ::
        { at = {x = 8.0, y = 5.0}, item = Render.textTinted("のこり", atlas, 9.0, Palette.uiText(), 42) } ::
        { at = {x = 40.0, y = 5.5}, item = Render.solidBox({x = 90.0, y = 7.0}, Palette.ovenDark(), 41)
            |> Render.rounded(3.0) } ::
        { at = {x = 41.0, y = 6.5}, item = Render.solidBox({x = 62.0, y = 5.0}, Palette.timeGauge(), 42)
            |> Render.rounded(2.5) } ::
        { at = {x = 150.0, y = 3.0}, item = Render.textTinted("クッキー ×7", atlas, 10.0, Palette.uiAccent(), 42) } ::
        { at = {x = 240.0, y = 4.0}, item = Render.textTinted("ベスト 12", atlas, 9.0, Palette.uiText(), 42) } :: Nil

    /// 四隅型 HUD。
    def hudCorners(atlas: FontAtlas): List[Render.Placed] =
        { at = {x = 6.0, y = 4.0}, item = Render.solidBox({x = 96.0, y = 16.0}, Palette.hudBg(), 40)
            |> Render.rounded(4.0) |> Render.fade(0.88f32) } ::
        { at = {x = 11.0, y = 8.5}, item = Render.solidBox({x = 86.0, y = 7.0}, Palette.ovenDark(), 41)
            |> Render.rounded(3.0) } ::
        { at = {x = 12.0, y = 9.5}, item = Render.solidBox({x = 58.0, y = 5.0}, Palette.timeLow(), 42)
            |> Render.rounded(2.5) } ::
        { at = {x = 234.0, y = 4.0}, item = Render.solidBox({x = 80.0, y = 16.0}, Palette.hudBg(), 40)
            |> Render.rounded(4.0) |> Render.fade(0.88f32) } ::
        { at = {x = 240.0, y = 6.0}, item = Render.textTinted("×7  ベスト12", atlas, 9.0, Palette.uiAccent(), 42) } :: Nil

    def mockItems(atlas: FontAtlas, ring: Bool): List[Render.Placed] =
        let spot = Kitchen.stationSpot(Kitchen.Layout.TriangleUp, Kitchen.Station.Bowl);
        List.flatten(
            Kitchen.scene(Palette.toneCream(), Kitchen.Layout.TriangleUp, Kitchen.PropSet.Classic, atlas) ::
            nobiAt(spot, 72.0, mockNobiStyle()) ::
            (if (ring) ringSlots(atlas, spot) else bottomCards(atlas)) ::
            (if (ring) hudBar(atlas) else hudCorners(atlas)) :: Nil)

    def bakeMocks(atlas: FontAtlas): Unit \ IO =
        shotScene(atlas, mockItems(atlas, true), {x = 320.0, y = 240.0}, 2, "mock_ring");
        shotScene(atlas, mockItems(atlas, false), {x = 320.0, y = 240.0}, 2, "mock_cards")

    // ── ダッシュボード ──

    def item(name: String, desc: String, scenario: String, pxWidth: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = pxWidth, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def catalog(): List[SnapshotSite.Item] =
        item("nobi_candidates", "のび 4 体型案 ×（横向き/帽子/こっち見/濃い緑）", "Nobi", 818) ::
        item("kitchen_cream", "クリーム系・正三角形（オーブン上）", "Kitchen", 640) ::
        item("kitchen_mint", "ミントタイル系・正三角形・コージー小物", "Kitchen", 640) ::
        item("kitchen_wood", "木目カントリー系・逆三角形（オーブン手前）", "Kitchen", 640) ::
        item("stations", "持ち場の小物 2 案（ボール/型抜き/オーブン）", "Stations", 640) ::
        item("items", "品物アイコン 12 種（正解系 9 + ネタ 3）", "Items", 620) ::
        item("mock_ring", "UI 案1: のびの周りに十字リング + 上バー HUD", "UI", 640) ::
        item("mock_cards", "UI 案2: 画面下カード + 四隅 HUD", "UI", 640) :: Nil

    /// すべて焼いてダッシュボードを組む。
    pub def bakeAll(): Unit \ IO =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "");
        discard (new File("gallery")).mkdirs();
        bakeNobi(atlas);
        bakeKitchens(atlas);
        bakeStations(atlas);
        bakeItems(atlas);
        bakeMocks(atlas);
        run {
            SnapshotSite.generate(
                { outDir = "gallery", title = "のびのクッキーやさん 絵作り候補", cssScale = 2 },
                catalog())
        } with Fs.FileWrite.runWithIO
}
