// Gallery — キャラの動きを目視確認する成果物を焼く:
//   - knight_a.gif        … 単独リール（全クリップ一巡の振り付け・scale 4 = 本体 128px）
//   - parade_knight.gif   … 同職 3 案の横並び同期リール（Phase 0 は 1 体 + 空レーン 2 本）
//   - lineup.png          … 全キャラ IdleDown frame0 の 8 職 × 3 案一覧（Phase 0 は 1 体）
//   - contrast_check.png  … fe_rogue の床っぽい緑系スウォッチの上に置いた視認性チェック
//   - index.html          … SnapshotSite のカタログページ
//
// 全成果物は決定的に生成される（時刻・乱数を焼き込まない）ので、挙動を変えない
// リファクタは shasum のバイト一致で機械的に証明できる。

mod Gallery {
    import java.io.File

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outDir(): String = "gallery"
    /// ドット絵の拡大率。32px のキャラが 128px で見える。
    def scale(): Int32 = 4
    /// リールは 24 ticks/s → 1 tick ≈ 42ms。
    def gifDelayMs(): Int32 = 42

    def bgColor(): Color = RoguePalette.night()
    def labelColor(): Color = RoguePalette.white()
    def frameColor(): Color = RoguePalette.darkSlate()

    // ── レイアウト ──

    /// 単独リールの舞台（design px）。キャラ原点 (16,16)・上部にラベル。
    def soloW(): Int32 = 64
    def soloH(): Int32 = 52

    /// パレードのレーン幅と本数（1 職 = 3 案）。
    def laneW(): Int32 = 48
    def laneCount(): Int32 = 3

    // ── RasterReq 組み立て ──

    def reqOf(atlas: FontAtlas, items: List[Render.PlacedItem], w: Int32, h: Int32,
              path: String): SoftRaster.RasterReq =
        let (drawables, polygons) = Render.draw(items);
        { drawables = drawables, polygons = polygons,
          design = { x = Int32.toFloat64(w), y = Int32.toFloat64(h) }, scale = scale(),
          background = bgColor(), texturePath = Map.empty(),
          fontTtf = ttfPath(), fontAtlas = atlas, outPath = path }

    def label(atlas: FontAtlas, text: String, x: Int32, y: Int32): Render.PlacedItem =
        { at = { x = Int32.toFloat64(x), y = Int32.toFloat64(y) },
          item = Render.textTinted(text, atlas, 7.0, labelColor(), 50) }

    // ── 全部を焼く（Bake.all から呼ぶ）──

    pub def bakeAll(): Unit \ IO + Fs.FileWrite =
        discard (new File(outDir())).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/none.txt");
        let films = Roster.entries() |> List.map(entry -> bakeChar(atlas, entry));
        registeredClassIds() |> List.forEach(cid -> bakeParade(atlas, cid, String.toUpperCase(cid)));
        bakeLineup(atlas);
        bakeContrast(atlas);
        SnapshotSite.generate(
            { outDir = outDir(), title = "Rogue Chars Gallery", cssScale = 1 },
            catalog(films))

    // ── 単独リール GIF ──

    /// 1 キャラのリール GIF を焼き、カタログ用の (Entry, 表示名ラベル) を返す。
    def bakeChar(atlas: FontAtlas,
                 entry: (Roster.Entry, (RogueStage.Clip, Int32) -> PixelCanvas.Canvas)): Roster.Entry \ IO =
        let (info, drawFn) = entry;
        let name = "${info#classId}_${info#variant}";
        let path = "${outDir()}/${name}.gif";
        let caption = String.toUpperCase("${info#classId} ${info#variant}");
        let images = Reel.frames(drawFn) |> List.map(tick -> {
            let items = label(atlas, caption, 4, 3) :: tickPlaced(16, 16, tick);
            SoftRaster.renderToImage(reqOf(atlas, items, soloW(), soloH(), path))
        });
        GifEncoder.encode(images, gifDelayMs(), path);
        info

    /// リールの 1 tick を置く。フェード段つき（白骨の消滅）はギャラリー専用の見せ方として、
    /// 各ピクセルを背景色へ段階ブレンドして描く（シートには焼かない・lint 対象外）。
    def tickPlaced(ox: Int32, oy: Int32, tick: Reel.Tick): List[Render.PlacedItem] =
        match tick#fade {
            case None        => PixelCanvas.toPlaced(ox, oy, tick#canvas)
            case Some(stage) => PixelCanvas.toPlaced(ox, oy, fadedCanvas(stage, tick#canvas))
        }

    /// フェード段 stage（0..3）: 残存率 3/4 → 2/4 → 1/4 → 0（段 3 = 背景と同化 = 完全消滅）。
    def fadedCanvas(stage: Int32, cv: PixelCanvas.Canvas): PixelCanvas.Canvas =
        let keep = Int32.toFloat32(3 - stage) / 4.0f32;
        Map.map(c -> blendToBg(keep, c), cv)

    /// 色 c を背景色 #222034 へ (1-keep) だけ寄せる。
    def blendToBg(keep: Float32, c: Color): Color =
        let bg = bgColor();
        { r = c#r * keep + bg#r * (1.0f32 - keep),
          g = c#g * keep + bg#g * (1.0f32 - keep),
          b = c#b * keep + bg#b * (1.0f32 - keep) }

    // ── パレード GIF（3 案の横並び同期。Phase 0 は a 案 + 空レーン 2 本で形だけ実証）──

    def bakeParade(atlas: FontAtlas, classId: String, caption: String): Unit \ IO =
        let path = "${outDir()}/parade_${classId}.gif";
        let variants = "a" :: "b" :: "c" :: Nil;
        let ticks = List.length(RogueStage.reel());
        let reels = variants |> List.map(v -> reelOf(classId, v));
        let images = List.range(0, ticks) |> List.map(t -> {
            let lanes = List.zipWithIndex(reels) |> List.flatMap(pair -> {
                let (i, reelOpt) = pair;
                laneItems(atlas, i, reelOpt |> Option.map(fs -> List.nth(t, fs)))
            });
            let items = label(atlas, caption, 4, 3) :: lanes;
            SoftRaster.renderToImage(reqOf(atlas, items, laneW() * laneCount(), soloH(), path))
        });
        GifEncoder.encode(images, gifDelayMs(), path)

    /// classId の variant 案のリール。未登録の案は None（空レーンとして描く）。
    def reelOf(classId: String, variant: String): Option[List[Reel.Tick]] =
        Roster.entries()
            |> List.findMap(entry -> {
                let (info, drawFn) = entry;
                if (info#classId == classId and info#variant == variant)
                    Some(Reel.frames(drawFn))
                else
                    None
            })

    /// レーン 1 本: 仕切り線 + キャラ（または空レーンの "?"）。
    def laneItems(atlas: FontAtlas, idx: Int32, tickFrame: Option[Option[Reel.Tick]]): List[Render.PlacedItem] =
        let left = idx * laneW();
        let sep = if (idx == 0) Nil else
            { at = { x = Int32.toFloat64(left), y = 0.0 },
              item = Render.box({ x = 1.0, y = Int32.toFloat64(soloH()) }, frameColor(), 1) } :: Nil;
        let body = match tickFrame {
            case Some(Some(tick)) => tickPlaced(left + 8, 16, tick)
            case _              =>
                { at = { x = Int32.toFloat64(left + 21), y = 26.0 },
                  item = Render.textTinted("?", atlas, 10.0, frameColor(), 10) } :: Nil
        };
        List.append(sep, body)

    // ── 整列写真（8 職 × 3 案の IdleDown frame0 一覧。空枠は将来のキャラが埋める）──

    // fe_rogue units.json のプレイヤー8職と同じ並び。
    def classIds(): List[String] =
        "knight" :: "fighter" :: "ranger" :: "rogue" :: "paladin" :: "barbarian" :: "cleric" :: "mage" :: Nil

    /// Roster に 1 体でも登録がある職種だけ（8 職の並び順のまま）。パレードはこれに対して焼く。
    def registeredClassIds(): List[String] =
        let present = Roster.entries() |> List.map(entry -> fst(entry)#classId);
        classIds() |> List.filter(cid -> List.memberOf(cid, present))

    // 最長の職名 BARBARIAN(9文字)のヘッダが収まる幅。
    def cellW(): Int32 = 52
    def cellH(): Int32 = 44
    def headerH(): Int32 = 12

    def bakeLineup(atlas: FontAtlas): Unit \ IO =
        let path = "${outDir()}/lineup.png";
        let variants = "a" :: "b" :: "c" :: Nil;
        let headers = List.zipWithIndex(classIds()) |> List.map(pair -> {
            let (col, cid) = pair;
            label(atlas, String.toUpperCase(cid), col * cellW() + 2, 3)
        });
        let cells = List.zipWithIndex(classIds()) |> List.flatMap(pair -> {
            let (col, cid) = pair;
            List.zipWithIndex(variants) |> List.flatMap(vp -> {
                let (rowIdx, v) = vp;
                cellItems(cid, v, col, rowIdx)
            })
        });
        let w = cellW() * List.length(classIds());
        let h = headerH() + cellH() * List.length(variants);
        SoftRaster.render(reqOf(atlas, List.append(headers, cells), w, h, path))

    /// 一覧の 1 マス: 枠 + IdleDown frame0（未登録は枠だけ）。
    def cellItems(classId: String, variant: String, col: Int32, rowIdx: Int32): List[Render.PlacedItem] =
        let x0 = col * cellW();
        let y0 = headerH() + rowIdx * cellH();
        let frame =
            { at = { x = Int32.toFloat64(x0 + 1), y = Int32.toFloat64(y0 + 1) },
              item = Render.box({ x = Int32.toFloat64(cellW() - 2), y = Int32.toFloat64(cellH() - 2) },
                        frameColor(), 0) } :: Nil;
        let body = drawOf(classId, variant)
            |> Option.map(drawFn -> PixelCanvas.toPlaced(x0 + (cellW() - PixelCanvas.size()) / 2, y0 + 8, drawFn(RogueStage.Clip.IdleDown, 0)))
            |> Option.getWithDefault(Nil);
        List.append(frame, body)

    def drawOf(classId: String, variant: String): Option[(RogueStage.Clip, Int32) -> PixelCanvas.Canvas] =
        Roster.entries()
            |> List.findMap(entry -> {
                let (info, drawFn) = entry;
                if (info#classId == classId and info#variant == variant) Some(drawFn) else None
            })

    // ── コントラスト確認（fe_rogue の床っぽい緑系スウォッチの上に置く）──

    def bakeContrast(atlas: FontAtlas): Unit \ IO =
        let path = "${outDir()}/contrast_check.png";
        // fe_rogue の床の代表色（DB32 の緑系 3 種をハードコード）。
        let floors = RoguePalette.darkGreen() :: RoguePalette.olive() :: RoguePalette.moss() :: Nil;
        let sw = 44;
        let idle0 = KnightA.draw(RogueStage.Clip.IdleDown, 0);
        let swatches = List.zipWithIndex(floors) |> List.flatMap(pair -> {
            let (i, c) = pair;
            let x0 = i * sw;
            { at = { x = Int32.toFloat64(x0), y = 12.0 },
              item = Render.box({ x = Int32.toFloat64(sw), y = 44.0 }, c, 0) } ::
            PixelCanvas.toPlaced(x0 + 6, 20, idle0)
        });
        let items = label(atlas, "FLOOR CONTRAST", 4, 3) :: swatches;
        SoftRaster.render(reqOf(atlas, items, sw * List.length(floors), 56, path))

    // ── カタログ ──

    def catalog(chars: List[Roster.Entry]): List[SnapshotSite.Item] =
        let charItems = chars |> List.flatMap(info -> {
            let name = "${info#classId}_${info#variant}";
            let scenario = String.toUpperCase(info#classId);
            gifItem(name, "${info#displayName} のリール: 主要クリップ一巡（Idle/歩き 3 方向/反転右向き/Attack/UseItem/Damage/Death→白骨→フェード消滅）", scenario, soloW() * scale()) ::
            pngItem("sheets/${name}", "スプライトシート 256×512（8 列 × 16 行 × 32px・透明背景）。同名 .json がクリップ表", scenario, 256) :: Nil
        });
        let paradeItems = registeredClassIds() |> List.map(cid ->
            gifItem("parade_${cid}", "同職 3 案の横並び同期リール（空レーンは後続が埋める）", String.toUpperCase(cid), laneW() * laneCount() * scale()));
        let rosterItems =
            pngItem("lineup", "全キャラ IdleDown frame0 の 8 職 × 3 案一覧（空枠 = 未登録）", "Roster", cellW() * 8 * scale()) ::
            pngItem("contrast_check", "fe_rogue の床っぽい緑系スウォッチ上の視認性チェック", "Roster", 44 * 3 * scale()) :: Nil;
        List.append(charItems, List.append(paradeItems, rosterItems))

    def pngItem(name: String, desc: String, scenario: String, px: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = px, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gifItem(name: String, desc: String, scenario: String, px: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = px, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }
}
