// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 盤・固定セル・落下中ミノ・着地予測（ゴースト）・NEXT・スコア・ライン消しの閃光・
// GAME OVER の幕を、World を読むだけで（変えずに）絵にする。幾何はここに閉じる。
//
// ── z 層（重なり順。大きいほど手前）──
//   bg=0 / 盤背景=1 / grid 線=2 / ghost=8 / 固定セル=10 / current=11 / 演出=20 / HUD=30 / overlay=40
//
// View は fail-open: 盤が空でも Doc が既定でも必ず何かを描く（プレイヤーの前で白画面にしない）。
mod View {

    use World.Cell

    // ── z 層 ──
    def zBg(): Int32 = 0
    def zBoard(): Int32 = 1
    def zGrid(): Int32 = 2
    def zGhost(): Int32 = 8
    def zLocked(): Int32 = 10
    def zCurrent(): Int32 = 11
    def zClear(): Int32 = 20
    def zHud(): Int32 = 30
    def zOverlay(): Int32 = 40

    // ── レイアウトの定数（project.json の design 256×352 と対）──
    def cell(): Float64 = 16.0                     // 1 マスの 1 辺（px）
    def originX(): Float64 = 16.0                   // 盤の左上 x（盤は x[16..176]）
    def originY(): Float64 = 16.0                   // 盤の左上 y（盤は y[16..336]）
    def panelX(): Float64 = 184.0                   // 右パネルの左端（NEXT・スコア）

    /// design の幅・高さ（背景の全面塗りに使う）。project.json と同じ値。
    def designW(): Float64 = 256.0
    def designH(): Float64 = 352.0

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               background(w#theme)
            :: gridLines(w#theme)
            :: ghost(w)
            :: lockedCells(w)
            :: currentCells(w)
            :: clearFx(w)
            :: nextPreview(ctx#atlas, w)
            :: hud(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 盤面の座標（(col,row) → 画面座標） ──

    /// セルの中心の画面座標。
    def cellCenter(c: Int32, r: Int32): Vec2.Vec2 =
        { x = originX() + (Int32.toFloat64(c) + 0.5) * cell(),
          y = originY() + (Int32.toFloat64(r) + 0.5) * cell() }

    /// 1 マスを塗る（中心置き・0.5px の隙間でマス目感を出す）。
    def blockAt(c: Int32, r: Int32, color: Color, z: Int32): Render.PlacedItem =
        Render.boxAt(cellCenter(c, r), { x = cell() - 1.0, y = cell() - 1.0 }, color, z)

    // ── 背景・枠・grid ──

    /// 盤外の背景 → 盤の中の背景 → 枠（wall）。fail-open の土台（常に何か出る）。
    def background(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let boardW = Int32.toFloat64(World.cols()) * cell();
        let boardH = Int32.toFloat64(World.rows()) * cell();
        // 枠は盤より 2px 外に一回り大きく敷いてから、盤背景を上に重ねる（縁取りに見える）。
           { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = designW(), y = designH() }, theme#bg, zBg()) }
        :: { at = { x = originX() - 2.0, y = originY() - 2.0 },
             item = Render.box({ x = boardW + 4.0, y = boardH + 4.0 }, theme#wall, zBg()) }
        :: { at = { x = originX(), y = originY() },
             item = Render.box({ x = boardW, y = boardH }, theme#board, zBoard()) }
        :: Nil

    /// マス目の薄い線（縦・横）。盤の手触りを出すだけの飾り。
    def gridLines(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let boardW = Int32.toFloat64(World.cols()) * cell();
        let boardH = Int32.toFloat64(World.rows()) * cell();
        let verticals = List.range(1, World.cols()) |> List.map(c ->
            { at = { x = originX() + Int32.toFloat64(c) * cell(), y = originY() },
              item = Render.box({ x = 1.0, y = boardH }, theme#grid, zGrid()) });
        let horizontals = List.range(1, World.rows()) |> List.map(r ->
            { at = { x = originX(), y = originY() + Int32.toFloat64(r) * cell() },
              item = Render.box({ x = boardW, y = 1.0 }, theme#grid, zGrid()) });
        List.append(verticals, horizontals)

    // ── 固定セル・落下中ミノ・ゴースト ──

    /// 盤に固定されたセル（それぞれの Kind の色で）。
    def lockedCells(w: World.World): List[Render.PlacedItem] =
        Map.toList(w#board) |> List.map(entry -> {
            let (cellPos, kind) = entry;
            let (c, r) = cellPos;
            blockAt(c, r, ThemeDoc.colorOf(w#theme, kind), zLocked())
        })

    /// いま操作しているミノ。Clearing / GameOver 中は消える行や幕に集中させるため出さない。
    def currentCells(w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Playing =>
                pieceCells(w#current, ThemeDoc.colorOf(w#theme, w#current#kind), zCurrent())
            case _ => Nil
        }

    /// 着地予測（ゴースト）: current をこれ以上落ちない所まで落とした位置を薄い色で描く。
    /// 「Space でどこに落ちるか」が一目で分かる補助。Playing のときだけ。
    def ghost(w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Playing =>
                let landed = World.dropToBottom(w);
                pieceCells(landed#current, w#theme#ghost, zGhost())
                    |> List.map(item -> { item = Render.fade(0.35f32, item#item) | item })
            case _ => Nil
        }

    /// Piece の 4 マスを 1 色で描く（current・ghost・NEXT が共有）。
    def pieceCells(p: World.Piece, color: Color, z: Int32): List[Render.PlacedItem] =
        World.piecesCells(p) |> List.filterMap(cellPos -> {
            let (c, r) = cellPos;
            if (r < 0) None else Some(blockAt(c, r, color, z))   // 上にはみ出した分は描かない
        })

    // ── ライン消しの演出（凝りすぎない: 閃光の帯 + ソフトな光球）──
    // 進度 t（0→1）で薄れていく。t は clearTimer / clearDuration。
    def clearFx(w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Clearing =>
                let t = clampF(0.0, 1.0, w#clearTimer / Float64.max(0.0001, w#doc#clearDuration));
                let fade = Float64.truncateToFloat32(1.0 - t);          // 1→0 に減衰
                let boardW = Int32.toFloat64(World.cols()) * cell();
                w#clearRows |> List.flatMap(r -> {
                    // 行全幅に閃光の帯（白）を重ねる。
                    let band = { at = { x = originX(), y = originY() + Int32.toFloat64(r) * cell() },
                                 item = Render.box({ x = boardW, y = cell() }, w#theme#flash, zClear())
                                     |> Render.fade(fade) };
                    // さらに各セルの中心にソフトな光球（Add ブレンド。閉形式で安全な glowAt）。
                    let glows = List.range(0, World.cols()) |> List.flatMap(c ->
                        Render.glowAt(cellCenter(c, r), cell() * 0.7, w#theme#flash,
                            { alpha = 0.6 * (1.0 - t), blend = DrawCmd.BlendMode.Add }, zClear() + 1));
                    band :: glows
                })
            case _ => Nil
        }

    // ── NEXT プレビュー ──

    /// 右パネルに "NEXT" と、次のミノを rot 0 で小さく描く。
    def nextPreview(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let label = { at = { x = panelX(), y = originY() },
                      item = Render.textTinted("NEXT", atlas, 10.0, w#theme#wall, zHud()) };
        // プレビューの原点（ラベルの下）。cellsOf の相対座標をここから並べる。
        let px0 = panelX();
        let py0 = originY() + 16.0;
        let s = cell() - 3.0;                          // 少し小さめのマス
        let color = ThemeDoc.colorOf(w#theme, w#nextKind);
        let blocks = Pieces.cellsOf(w#nextKind, 0) |> List.map(cellPos -> {
            let (c, r) = cellPos;
            { at = { x = px0 + Int32.toFloat64(c) * s, y = py0 + Int32.toFloat64(r) * s },
              item = Render.box({ x = s - 1.0, y = s - 1.0 }, color, zHud()) }
        });
        label :: blocks

    // ── HUD（スコア・ライン数）──

    def hud(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let x = panelX();
        // 文言はコードに直書きせず「見出し + 数」を組む。ラベルだけは UI の見出しなので固定でよい。
        let scoreY = 120.0;
        let linesY = 160.0;
           { at = { x = x, y = scoreY },
             item = Render.textTinted("SCORE", atlas, 9.0, w#theme#wall, zHud()) }
        :: { at = { x = x, y = scoreY + 12.0 },
             item = Render.textTinted(Int32.toString(w#score), atlas, 12.0,
                 ThemeDoc.lighten(w#theme#wall, 0.6), zHud()) }
        :: { at = { x = x, y = linesY },
             item = Render.textTinted("LINES", atlas, 9.0, w#theme#wall, zHud()) }
        :: { at = { x = x, y = linesY + 12.0 },
             item = Render.textTinted(Int32.toString(w#lines), atlas, 12.0,
                 ThemeDoc.lighten(w#theme#wall, 0.6), zHud()) }
        :: Nil

    // ── GAME OVER の幕 ──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.GameOver =>
                   { at = { x = 0.0, y = 0.0 },
                     item = Render.box({ x = designW(), y = designH() }, w#theme#bg, zOverlay())
                         |> Render.fade(0.6f32) }
                :: centered(atlas, "GAME OVER", 20.0, w#theme#flash, 150.0)
                :: centered(atlas, "PRESS SPACE", 10.0, w#theme#wall, 180.0)
                :: Nil
            case _ => Nil
        }

    /// 画面中央にテキストを 1 行置く（幅はエンジンが実測して中央へ揃える）。
    def centered(atlas: FontAtlas, s: String, size: Float64, color: Color, y: Float64): Render.PlacedItem =
        TextDraw.centered({ text = s, atlas = atlas, size = size, color = color,
                            z = zOverlay() + 1, centerX = designW() / 2.0, y = y })

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
