// TilesetGreenGallery — v8 生成器（TilesetGreen・立体面シェーディング＋モチーフテーマ）をヘッドレスに焼き、
// 全 108 セルの形・材質・色数を検証する。
//
//   gallery/tileset_green_regen.png   … 全 108 セルの再現アトラス（green・312×234・座標互換の完成資産）
//   gallery/tileset_green_compare.png … 原本シート vs 再現シート（green）を各2倍・上下ラベルで比較
//   gallery/tileset_compare.png       … [原本 | green | fire | forest | ruins | flower | future | desert] の縦積み比較
//   gallery/tileset_cell_diff.png     … 全 108 セルを [原本 | 再現 | シルエットXOR | 材質XOR] の 4 列で並べる
//   gallery/rooms_original.png        … 代表 5 マップ（凹形/水プール/障害物/大部屋/Z通路）を原本テクスチャで合成
//   gallery/rooms_green.png ほか      … 同じ 5 マップをテーマ別アトラスで合成（fire/forest/ruins も）
//   gallery/tileset_layers.png        … 代表セルを [原本 | 再現 | 材質 | 虚空 | 線画 | 地 | 建築 | 風化 | 光] に分解
//
// 指標は三重: ①シルエット XOR ②材質 XOR（全 108 セルのワーストで assert・二つとも classify 共通経路）
// ③総色数（ドット絵の少色数規律。原本 31 色に対し再現も固定ランプ量子化で 50 色以下を assert —
// 中間色の氾濫 = 淡さ・ぼやけの機械検出）。部屋の合成は本物の autoRules/wallMap 適用で行い、
// 「タイルセットの最終品質は部屋で判定する」を成果物にする。
mod TilesetGreenGallery {
    import java.io.File
    import java.awt.image.BufferedImage
    import java.awt.Graphics2D
    import java.awt.{Color => AwtColor}
    import java.awt.Font
    import javax.imageio.ImageIO

    def outDir(): String = "gallery"
    def originalPath(): String = "assets/sprites/tileset_dungeon_green.png"

    // ── 全 108 セル（12×9）を検証対象にする ──
    def allCells(): List[(Int32, Int32)] =
        List.flatMap(row ->
            List.map(col -> (col, row), List.range(0, TilesetGreen.cols())),
            List.range(0, TilesetGreen.rows()))

    // ── 部屋ギャラリーの代表マップ（形の多様性: 凹形床/3×3水プール/障害物最多/大部屋+水盤/Z字通路）──
    def roomMaps(): List[(String, String)] =
        ("base_room", "assets/maps/base_room.map.json") ::
        ("room_5 (water pool)", "assets/maps/room_5.map.json") ::
        ("room_11 (obstacles)", "assets/maps/room_11.map.json") ::
        ("room_large_obstacles", "assets/maps/room_large_obstacles.map.json") ::
        ("pathway_z", "assets/maps/pathway_horizontal_z2w.map.json") :: Nil

    // ════════════════════════════════════════════════════════
    // 材質分類（原本・再現で共通。classify が透明 alpha=0 も虚空へ）
    // ════════════════════════════════════════════════════════
    def matName(argb: Int32): String = TilesetGreen.materialName(TilesetGreen.classify(argb))
    def isVoidArgb(argb: Int32): Bool = matName(argb) == "void"

    // ════════════════════════════════════════════════════════
    // 再現アトラスのレンダリング（テーマ指定・全 108 セル）
    // ════════════════════════════════════════════════════════
    def renderAtlas(theme: TilesetGreen.Theme): BufferedImage \ IO =
        let w = TilesetGreen.atlasW();
        let h = TilesetGreen.atlasH();
        let c = TilesetGreen.cell();
        let img = new BufferedImage(w, h, 2i32);  // TYPE_INT_ARGB
        List.forEach(y ->
            List.forEach(x -> {
                let argb = TilesetGreen.pixelArgbWith(theme, x / c, y / c, Int32.modulo(x, c), Int32.modulo(y, c));
                img.setRGB(x, y, argb)
            }, List.range(0, w)),
            List.range(0, h));
        img

    /// アトラスの総色数（下位 24bit の異なり数）。少色数規律 = パキッと感の機械指標。
    def countColors(img: BufferedImage): Int32 \ IO =
        region rc {
            let seen = MutSet.empty(rc);
            List.forEach(y ->
                List.forEach(x ->
                    MutSet.add(Int32.bitwiseAnd(img.getRGB(x, y), 16777215), seen),
                    List.range(0, img.getWidth())),
                List.range(0, img.getHeight()));
            MutSet.size(seen)
        }

    def structAtG(gx: Int32, gy: Int32): Bool =
        let c = TilesetGreen.cell();
        TilesetGreen.structureAt(gx / c, gy / c, Int32.modulo(gx, c), Int32.modulo(gy, c))

    /// (gx,gy) の Chebyshev 2px 近傍に構造画素があるか（許容帯検査の dilate 側）。
    def structNear(gx: Int32, gy: Int32, w: Int32, h: Int32): Bool =
        List.exists(dy ->
            List.exists(dx -> {
                let x = gx + dx; let y = gy + dy;
                x >= 0 and y >= 0 and x < w and y < h and structAtG(x, y)
            }, -2 :: -1 :: 0 :: 1 :: 2 :: Nil),
            -2 :: -1 :: 0 :: 1 :: 2 :: Nil)

    /// (gx,gy) の Chebyshev 2px 近傍に非虚空の塗り画素があるか（許容帯検査の erode 側）。
    def paintNear(atlas: BufferedImage, gx: Int32, gy: Int32, w: Int32, h: Int32): Bool \ IO =
        List.exists(dy ->
            List.exists(dx -> {
                let x = gx + dx; let y = gy + dy;
                x >= 0 and y >= 0 and x < w and y < h and not isVoidArgb(atlas.getRGB(x, y))
            }, -2 :: -1 :: 0 :: 1 :: 2 :: Nil),
            -2 :: -1 :: 0 :: 1 :: 2 :: Nil)

    /// モチーフのシルエット許容帯検査（±2px）。モチーフは内部を描き替えつつ輪郭を花の円などに沿って
    /// うねらせるので、原本と完全一致(XOR 0)ではなく「原本の dilate/erode 2px の帯」に収まることを測る。
    /// 返り値 = (原本の外へ 2px 超はみ出した画素数 over, 原本の内へ 2px 超えぐり込んだ画素数 under)。
    def silhouetteTolerance(atlas: BufferedImage): (Int32, Int32) \ IO =
        let w = TilesetGreen.atlasW();
        let h = TilesetGreen.atlasH();
        region rc {
            let over = Ref.fresh(rc, 0);
            let under = Ref.fresh(rc, 0);
            List.forEach(gy ->
                List.forEach(gx -> {
                    let isStruct = structAtG(gx, gy);
                    let nonVoid = not isVoidArgb(atlas.getRGB(gx, gy));
                    if (nonVoid and not isStruct and not structNear(gx, gy, w, h)) Ref.put(Ref.get(over) + 1, over) else ();
                    if (isStruct and not nonVoid and not paintNear(atlas, gx, gy, w, h)) Ref.put(Ref.get(under) + 1, under) else ()
                }, List.range(0, w)),
                List.range(0, h));
            (Ref.get(over), Ref.get(under))
        }

    /// 壁塗りの対象画素か（構造かつ 壁石 or 装飾金属。床/水/木などモチーフ別テクスチャは対象外）。
    def isWallLikeG(gx: Int32, gy: Int32): Bool =
        let c = TilesetGreen.cell();
        let col = gx / c; let row = gy / c;
        let lx = Int32.modulo(gx, c); let ly = Int32.modulo(gy, c);
        if (not TilesetGreen.structureAt(col, row, lx, ly)) false
        else {
            let mn = TilesetGreen.materialName(TilesetGreen.materialAt(col, row, lx, ly));
            if (mn == "metal") true
            else if (mn == "stone") row != 5 and not (row == 6 and col >= 3 and col <= 8)
            else false
        }

    /// 境界互換検査（同種セルを並べても割れない）。モチーフの壁塗りはグローバル格子で描き、周期がセル 26px を
    /// 割り切る（花/砂岩=縦横 26px・パネル=13px）。同じ壁タイルを並べたとき右端列と左端列が連続することを、
    /// 壁塗り画素が 26px（セル 1 個分）隔てても同色（= セル周期 ⟹ 継ぎ目で連続）かで測る。内部画素のみ。
    def tileSeamBreaks(atlas: BufferedImage): Int32 \ IO =
        let c = TilesetGreen.cell();
        let w = TilesetGreen.atlasW();
        let h = TilesetGreen.atlasH();
        let interior = (gx, gy) ->
            isWallLikeG(gx, gy)
                and gx > 0 and gy > 0 and gx < w - 1 and gy < h - 1
                and not isVoidArgb(atlas.getRGB(gx - 1, gy)) and not isVoidArgb(atlas.getRGB(gx + 1, gy))
                and not isVoidArgb(atlas.getRGB(gx, gy - 1)) and not isVoidArgb(atlas.getRGB(gx, gy + 1));
        region rc {
            let bad = Ref.fresh(rc, 0);
            List.forEach(gy ->
                List.forEach(gx -> {
                    if (gx + c < w and interior(gx, gy) and interior(gx + c, gy)
                        and atlas.getRGB(gx, gy) != atlas.getRGB(gx + c, gy)) Ref.put(Ref.get(bad) + 1, bad) else ();
                    if (gy + c < h and interior(gx, gy) and interior(gx, gy + c)
                        and atlas.getRGB(gx, gy) != atlas.getRGB(gx, gy + c)) Ref.put(Ref.get(bad) + 1, bad) else ()
                }, List.range(0, w)),
                List.range(0, h));
            Ref.get(bad)
        }

    // ════════════════════════════════════════════════════════
    // セル単位の二重不一致（シルエット XOR / 材質 XOR）
    // ════════════════════════════════════════════════════════
    def cellMismatch(orig: BufferedImage, regen: BufferedImage, col: Int32, row: Int32): (Int32, Int32) \ IO =
        let c = TilesetGreen.cell();
        region rc {
            let sil = Ref.fresh(rc, 0);
            let mat = Ref.fresh(rc, 0);
            List.forEach(y ->
                List.forEach(x -> {
                    let oa = orig.getRGB(col * c + x, row * c + y);
                    let ra = regen.getRGB(col * c + x, row * c + y);
                    let ov = isVoidArgb(oa);
                    let rv = isVoidArgb(ra);
                    if (ov != rv) Ref.put(Ref.get(sil) + 1, sil) else ();
                    if (matName(oa) != matName(ra)) Ref.put(Ref.get(mat) + 1, mat) else ()
                }, List.range(0, c)),
                List.range(0, c));
            (Ref.get(sil), Ref.get(mat))
        }

    // ════════════════════════════════════════════════════════
    // cell_diff: [原本 | 再現 | シルエットXOR | 材質XOR] の 4 列グリッド（全 108 セル）
    // ════════════════════════════════════════════════════════
    def dScale(): Int32 = 3
    def triGap(): Int32 = 4
    def blockGap(): Int32 = 16
    def perRow(): Int32 = 4
    def labelH(): Int32 = 20

    def bg(): AwtColor \ IO = new AwtColor(20i32, 22i32, 20i32, 255i32)
    def fg(): AwtColor \ IO = new AwtColor(228i32, 232i32, 228i32, 255i32)

    /// 1 セルを指定モードで拡大描画。mode: 0=orig, 1=regen, 2=silhouetteXor, 3=materialXor。
    def drawCell(g: Graphics2D, orig: BufferedImage, regen: BufferedImage,
                 col: Int32, row: Int32, dx: Int32, dy: Int32, mode: Int32): Unit \ IO =
        let c = TilesetGreen.cell();
        let s = dScale();
        List.forEach(y ->
            List.forEach(x -> {
                let oa = orig.getRGB(col * c + x, row * c + y);
                let ra = regen.getRGB(col * c + x, row * c + y);
                let color =
                    if (mode == 0) new AwtColor(oa, true)
                    else if (mode == 1) new AwtColor(ra, true)
                    else if (mode == 2) {
                        if (isVoidArgb(oa) != isVoidArgb(ra)) new AwtColor(255i32, 0i32, 255i32, 255i32)
                        else if (isVoidArgb(oa)) new AwtColor(32i32, 40i32, 36i32, 255i32)
                        else new AwtColor(92i32, 100i32, 92i32, 255i32)
                    }
                    else {
                        if (matName(oa) != matName(ra)) new AwtColor(255i32, 0i32, 255i32, 255i32)
                        else {
                            let (mr, mg, mb) = TilesetGreen.materialSwatch(TilesetGreen.classify(oa));
                            new AwtColor(mr, mg, mb)
                        }
                    };
                g.setColor(color);
                g.fillRect(dx + x * s, dy + y * s, s, s)
            }, List.range(0, c)),
            List.range(0, c))

    def buildCellDiff(orig: BufferedImage, regen: BufferedImage): BufferedImage \ IO =
        let c = TilesetGreen.cell();
        let s = dScale();
        let cellPx = c * s;                            // 78
        let blockW = cellPx * 4 + triGap() * 3;
        let blockH = cellPx + labelH();
        let cells = allCells();
        let n = List.length(cells);
        let cols = perRow();
        let rowsN = (n + cols - 1) / cols;
        let margin = 16;
        let w = margin * 2 + cols * blockW + (cols - 1) * blockGap();
        let h = margin * 2 + rowsN * (blockH + blockGap());
        let img = new BufferedImage(w, h, 1i32);       // TYPE_INT_RGB
        let g = img.createGraphics();
        g.setColor(bg());
        g.fillRect(0i32, 0i32, w, h);
        g.setFont(new Font("SansSerif", 1i32, 11i32));
        List.forEach(pair -> {
            let (i, cell) = pair;
            let (col, row) = cell;
            let gc = Int32.modulo(i, cols);
            let gr = i / cols;
            let bx = margin + gc * (blockW + blockGap());
            let by = margin + gr * (blockH + blockGap());
            g.setColor(fg());
            g.drawString("c${col}/r${row} ${TilesetGreen.cellName(col, row)}", bx, by + labelH() - 6i32);
            let cy = by + labelH();
            drawCell(g, orig, regen, col, row, bx, cy, 0i32);
            drawCell(g, orig, regen, col, row, bx + (cellPx + triGap()), cy, 1i32);
            drawCell(g, orig, regen, col, row, bx + (cellPx + triGap()) * 2, cy, 2i32);
            drawCell(g, orig, regen, col, row, bx + (cellPx + triGap()) * 3, cy, 3i32)
        }, List.zip(List.range(0, n), cells));
        g.dispose();
        img

    // ════════════════════════════════════════════════════════
    // 部屋合成: 本物のオートタイル規則（wallMap/autoRules + manual）でマップを組む
    // ════════════════════════════════════════════════════════
    def loadLevel(path: String): Option[MapResource.Level] \ IO =
        run { Persistence.load(path) } with Fs.FileRead.runWithIO

    def loadMaterial(path: String): Option[MapResource.Material] \ IO =
        run { Persistence.load(path) } with Fs.FileRead.runWithIO

    /// マップ 1 枚の (幅セル, 高さセル, 配置リスト)。配置 = (destCol,destRow,srcCol,srcRow)。
    /// 描画順: 床(decor) → 自動壁(wallMap) → manualTiles（壁の上書き・水プール等）→ autoRule 装飾。
    def roomPlacementsFor(path: String): (Int32, Int32, List[(Int32, Int32, Int32, Int32)]) \ IO =
        match loadLevel(path) {
            case None => (0, 0, Nil)
            case Some(level) =>
                let d = MapResource.levelData(level);
                let c = TilesetGreen.cell();
                let floorMask = d#decorTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
                let wallCells = MapLoader.computeWallCells(floorMask, d#width, d#height);
                let manualCoords = d#manualTiles |> List.map(t -> (t#x, t#y)) |> List.toSet;
                let matPath = MapLoader.materialPathFor(path, d#materialId);
                match loadMaterial(matPath) {
                    case None => (d#width, d#height, Nil)
                    case Some(mat) =>
                        let md = MapResource.materialData(mat);
                        let intGrid = MapLoader.buildIntGrid(floorMask, wallCells, d#width, d#height);
                        let decor = d#decorTiles
                            |> List.map(t -> (t#x, t#y, t#srcX / c, t#srcY / c));
                        let walls = wallCells
                            |> Set.toList
                            |> List.filterMap(coord -> {
                                let (col, row) = coord;
                                if (Set.memberOf(coord, manualCoords)) None
                                else match MapLoader.lookupWallTile(wallCells, floorMask, md#wallMap, col, row) {
                                    case Some((sx, sy)) => Some((col, row, sx / c, sy / c))
                                    case None           => None
                                }
                            });
                        let manual = d#manualTiles
                            |> List.map(t -> (t#x, t#y, t#srcX / c, t#srcY / c));
                        let rules = MapLoader.buildAutoRuleTiles(intGrid, d#width, d#height, md#autoRules, manualCoords, c)
                            |> List.map(t -> {
                                let dc = ftoi(t#px#x) / c;
                                let dr = ftoi(t#px#y) / c;
                                (dc, dr, ftoi(t#srcX) / c, ftoi(t#srcY) / c)
                            });
                        (d#width, d#height, List.append(decor, List.append(walls, List.append(manual, rules))))
                }
        }

    def ftoi(x: Float64): Int32 = Float64.tryToInt32(x + 0.5) |> Option.getWithDefault(0)

    def blitCell(dst: BufferedImage, src: BufferedImage, dxPx: Int32, dyPx: Int32,
                 destCol: Int32, destRow: Int32, srcCol: Int32, srcRow: Int32): Unit \ IO =
        let c = TilesetGreen.cell();
        List.forEach(y ->
            List.forEach(x ->
                dst.setRGB(dxPx + destCol * c + x, dyPx + destRow * c + y,
                           src.getRGB(srcCol * c + x, srcRow * c + y)),
                List.range(0, c)),
            List.range(0, c))

    /// 代表 5 マップを横に並べた 1 枚（ラベル付き）。src = テーマ別アトラス or 原本。
    def buildRoomsSheet(src: BufferedImage, sheetLabel: String,
                        rooms: List[(String, (Int32, Int32, List[(Int32, Int32, Int32, Int32)]))],
                        voidHex: Int32): BufferedImage \ IO =
        let c = TilesetGreen.cell();
        let margin = 16;
        let gap = 12;
        let lh = 18;
        let totalW = margin * 2
            + List.foldLeft((a, r) -> { let (_, (w, _, _)) = r; a + w * c }, 0, rooms)
            + gap * (List.length(rooms) - 1);
        let maxH = rooms |> List.map(r -> { let (_, (_, h, _)) = r; h }) |> List.maximum |> Option.getWithDefault(14);
        let totalH = margin * 2 + lh * 2 + maxH * c;
        let img = new BufferedImage(totalW, totalH, 1i32);
        let g = img.createGraphics();
        g.setColor(bg());
        g.fillRect(0i32, 0i32, totalW, totalH);
        g.setFont(new Font("SansSerif", 1i32, 14i32));
        g.setColor(fg());
        g.drawString(sheetLabel, margin, margin + 12i32);
        g.setFont(new Font("SansSerif", 0i32, 11i32));
        region rc {
            let xOff = Ref.fresh(rc, margin);
            List.forEach(r -> {
                let (nm, (w, h, placements)) = r;
                let x0 = Ref.get(xOff);
                let y0 = margin + lh * 2;
                g.setColor(new AwtColor(TilesetGreen.packArgb(255, rgbTuple(voidHex)), true));
                g.fillRect(x0, y0, w * c, h * c);
                g.setColor(fg());
                g.drawString(nm, x0, y0 - 4i32);
                List.forEach(p -> {
                    let (dc, dr, sc, sr) = p;
                    blitCell(img, src, x0, y0, dc, dr, sc, sr)
                }, placements);
                Ref.put(x0 + w * c + gap, xOff)
            }, rooms)
        };
        g.dispose();
        img

    def rgbTuple(hex: Int32): (Int32, Int32, Int32) =
        (Int32.modulo(hex / 65536, 256), Int32.modulo(hex / 256, 256), Int32.modulo(hex, 256))

    // ════════════════════════════════════════════════════════
    // シート比較（2倍・縦積み・ラベル）
    // ════════════════════════════════════════════════════════
    def blitAtlasScaled(g: Graphics2D, src: BufferedImage, dx: Int32, dy: Int32, scale: Int32): Unit \ IO =
        let w = src.getWidth();
        let h = src.getHeight();
        List.forEach(y ->
            List.forEach(x -> {
                g.setColor(new AwtColor(src.getRGB(x, y), true));
                g.fillRect(dx + x * scale, dy + y * scale, scale, scale)
            }, List.range(0, w)),
            List.range(0, h))

    /// ラベル付きアトラスを縦に積む汎用ビルダー（green_compare と theme compare が共用）。
    def buildStackCompare(entries: List[(String, BufferedImage)]): BufferedImage \ IO =
        let scale = 2;
        let aw = TilesetGreen.atlasW() * scale;
        let ah = TilesetGreen.atlasH() * scale;
        let margin = 16;
        let labelH2 = 20;
        let n = List.length(entries);
        let w = margin * 2 + aw;
        let h = margin * (n + 1) + (labelH2 + ah) * n;
        let img = new BufferedImage(w, h, 1i32);
        let g = img.createGraphics();
        g.setColor(bg());
        g.fillRect(0i32, 0i32, w, h);
        g.setFont(new Font("SansSerif", 1i32, 15i32));
        region rc {
            let yOff = Ref.fresh(rc, margin);
            List.forEach(e -> {
                let (label, atlas) = e;
                let y0 = Ref.get(yOff);
                g.setColor(fg());
                g.drawString(label, margin, y0 + labelH2 - 5i32);
                blitAtlasScaled(g, atlas, margin, y0 + labelH2, scale);
                Ref.put(y0 + labelH2 + ah + margin, yOff)
            }, entries)
        };
        g.dispose();
        img

    // ════════════════════════════════════════════════════════
    // tileset_layers: [原本 | 再現 | 材質 | 虚空 | 線画 | 地 | 建築 | 風化 | 光]
    // ════════════════════════════════════════════════════════
    def layerCols(): List[String] =
        "orig" :: "regen" :: "material" :: "void" :: "line" :: "ground" :: "arch" :: "weather" :: "light" :: Nil

    def layerForMode(mode: Int32): TilesetGreen.Layer =
        if (mode == 3)      TilesetGreen.Layer.Void
        else if (mode == 4) TilesetGreen.Layer.Line
        else if (mode == 5) TilesetGreen.Layer.Ground
        else if (mode == 6) TilesetGreen.Layer.Arch
        else if (mode == 7) TilesetGreen.Layer.Weather
        else                TilesetGreen.Layer.Light

    def drawLayerColumn(g: Graphics2D, orig: BufferedImage, regen: BufferedImage,
                        col: Int32, row: Int32, dx: Int32, dy: Int32, mode: Int32): Unit \ IO =
        let c = TilesetGreen.cell();
        let s = dScale();
        List.forEach(y ->
            List.forEach(x -> {
                let color =
                    if (mode == 0) new AwtColor(orig.getRGB(col * c + x, row * c + y), true)
                    else if (mode == 1) new AwtColor(regen.getRGB(col * c + x, row * c + y), true)
                    else if (mode == 2) {
                        let oa = orig.getRGB(col * c + x, row * c + y);
                        let ra = regen.getRGB(col * c + x, row * c + y);
                        if (matName(oa) != matName(ra)) new AwtColor(255i32, 0i32, 255i32, 255i32)
                        else {
                            let (mr, mg, mb) = TilesetGreen.materialSwatch(TilesetGreen.classify(oa));
                            new AwtColor(mr, mg, mb)
                        }
                    }
                    else new AwtColor(TilesetGreen.layerArgb(col, row, x, y, layerForMode(mode)), true);
                g.setColor(color);
                g.fillRect(dx + x * s, dy + y * s, s, s)
            }, List.range(0, c)),
            List.range(0, c))

    def layerCells(): List[(Int32, Int32)] =
        (11,0)::(11,1)::(4,4)::(5,4)::(0,5)::(5,6)::
        (0,6)::(1,7)::(2,7)::(10,7)::(0,8)::(2,8)::
        (3,8)::(5,8)::(7,7)::(8,7)::(10,3)::(11,3)::
        (7,4)::(9,4)::(7,8)::(8,8)::(9,8)::(3,7)::
        (10,6)::(11,6)::Nil

    def buildLayers(orig: BufferedImage, regen: BufferedImage): BufferedImage \ IO =
        let c = TilesetGreen.cell();
        let s = dScale();
        let cellPx = c * s;
        let ncol = 9;
        let colGap = 3;
        let blockW = cellPx * ncol + colGap * (ncol - 1);
        let blockH = cellPx + labelH();
        let cells = layerCells();
        let n = List.length(cells);
        let perR = 2;
        let rowsN = (n + perR - 1) / perR;
        let margin = 16;
        let legendH = 22;
        let w = margin * 2 + perR * blockW + (perR - 1) * blockGap();
        let h = margin * 2 + legendH + rowsN * (blockH + blockGap());
        let img = new BufferedImage(w, h, 1i32);
        let g = img.createGraphics();
        g.setColor(bg());
        g.fillRect(0i32, 0i32, w, h);
        g.setFont(new Font("SansSerif", 0i32, 11i32));
        g.setColor(fg());
        List.forEach(bi -> {
            let bx0 = margin + bi * (blockW + blockGap());
            List.forEach(miName -> {
                let (mi, nm) = miName;
                g.drawString(nm, bx0 + mi * (cellPx + colGap), margin + legendH - 8i32)
            }, List.zip(List.range(0, ncol), layerCols()))
        }, List.range(0, perR));
        g.setFont(new Font("SansSerif", 1i32, 12i32));
        List.forEach(pair -> {
            let (i, cell) = pair;
            let (col, row) = cell;
            let gc = Int32.modulo(i, perR);
            let gr = i / perR;
            let bx = margin + gc * (blockW + blockGap());
            let by = margin + legendH + gr * (blockH + blockGap());
            g.setColor(fg());
            g.drawString("c${col}/r${row} ${TilesetGreen.cellName(col, row)}", bx, by + labelH() - 6i32);
            let cy = by + labelH();
            List.forEach(mode ->
                drawLayerColumn(g, orig, regen, col, row, bx + mode * (cellPx + colGap), cy, mode),
                List.range(0, ncol))
        }, List.zip(List.range(0, n), cells));
        g.dispose();
        img

    // ════════════════════════════════════════════════════════
    // TileLint: 周回レンガ幅（壁レンガのシーム連続性）
    // ════════════════════════════════════════════════════════
    def wrapWidthsOk(cuts: List[Int32], lo: Int32, hi: Int32): Bool =
        TilesetGreen.wrapStoneWidths(cuts, 2)
            |> List.forAll(w -> w >= lo and w <= hi)

    // ════════════════════════════════════════════════════════
    // テストエントリ
    // ════════════════════════════════════════════════════════
    @Test
    def testTilesetGreenGallery(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        discard (new File(outDir())).mkdirs();
        let orig = ImageIO.read(new File(originalPath()));
        let regen = renderAtlas(TilesetGreen.themeGreen());
        let flower = renderAtlas(TilesetGreen.themeFlower());
        discard ImageIO.write(regen, "png", new File("${outDir()}/tileset_green_regen.png"));
        discard ImageIO.write(flower, "png", new File("${outDir()}/tileset_flower.png"));
        let diff = buildCellDiff(orig, regen);
        discard ImageIO.write(diff, "png", new File("${outDir()}/tileset_cell_diff.png"));
        let layers = buildLayers(orig, regen);
        discard ImageIO.write(layers, "png", new File("${outDir()}/tileset_layers.png"));
        // green の原本比較（作業A の監修対象）
        let compareGreen = buildStackCompare(
            ("original  (tileset_dungeon_green.png)", orig) ::
            ("regen v10 (green・原本実測の立体面シェーディング・固定ランプ量子化・線画・座標互換)", regen) :: Nil);
        discard ImageIO.write(compareGreen, "png", new File("${outDir()}/tileset_green_compare.png"));
        // [原本 | green 再現 | flower] の 3 段比較
        let compareThemes = buildStackCompare(
            ("original", orig) ::
            ("regen green (原本忠実再現)", regen) ::
            ("motif flower (セル別に花で装飾)", flower) :: Nil);
        discard ImageIO.write(compareThemes, "png", new File("${outDir()}/tileset_compare.png"));

        // 部屋ギャラリー: original/green は代表 5 マップ、flower は base_room + room_5 の 2 部屋。
        let rooms = roomMaps() |> List.map(m -> {
            let (nm, path) = m;
            (nm, roomPlacementsFor(path))
        });
        let flowerRooms = List.take(2, rooms);
        discard ImageIO.write(buildRoomsSheet(orig, "rooms - original", rooms, 0x19201a),
            "png", new File("${outDir()}/rooms_original.png"));
        discard ImageIO.write(buildRoomsSheet(regen, "rooms - green", rooms, TilesetGreen.themeGreen()#voidC),
            "png", new File("${outDir()}/rooms_green.png"));
        discard ImageIO.write(buildRoomsSheet(flower, "rooms - flower", flowerRooms, TilesetGreen.themeFlower()#voidC),
            "png", new File("${outDir()}/rooms_flower.png"));

        // 全 108 セルの二重成績表（シルエット/材質 XOR。ワースト降順）
        let c = TilesetGreen.cell();
        let area = Int32.toFloat64(c * c);
        let scored = allCells()
            |> List.map(cell -> {
                let (col, row) = cell;
                let (sil, mat) = cellMismatch(orig, regen, col, row);
                let silPct = Int32.toFloat64(sil) / area * 100.0;
                let matPct = Int32.toFloat64(mat) / area * 100.0;
                (cell, sil, mat, silPct, matPct)
            });
        let worstKey = t -> { let (_, sil, mat, _, _) = t; -1i32 * Int32.max(sil, mat) };
        let sorted = List.sortBy(worstKey, scored);
        println("=== tileset v7 全 108 セル成績表（ワースト降順: silhouetteXOR / materialXOR）===");
        List.forEach(t -> {
            let ((col, row), sil, mat, silPct, matPct) = t;
            println("  c${col}/r${row} ${TilesetGreen.cellName(col, row)}"
                + "  sil=${sil}px(${silPct}%)  mat=${mat}px(${matPct}%)")
        }, sorted);
        let worstSil = scored |> List.map(t -> { let (_, sil, _, _, _) = t; sil }) |> List.maximum |> Option.getWithDefault(0);
        let worstMat = scored |> List.map(t -> { let (_, _, mat, _, _) = t; mat }) |> List.maximum |> Option.getWithDefault(0);
        println("=== ワースト: silhouette=${worstSil}px / material=${worstMat}px  [閾値 各 5% = ${ftoi(area * 0.05)}px] ===");

        // 線画レイヤーの健全性: 線画は「構造内の最暗段で締める明度の話」であって材質分類には効かないこと（本丸の不変条件）。
        // 全 108 セルの線画画素を数え、各画素の再現色を classify し直しても materialAt と一致する（＝材質 XOR を汚さない）ことを assert。
        let (lineN, lineBad) = region rc {
            let ln = Ref.fresh(rc, 0);
            let bad = Ref.fresh(rc, 0);
            List.forEach(cell -> {
                let (col, row) = cell;
                List.forEach(ly ->
                    List.forEach(lx ->
                        if (TilesetGreen.isLineAt(col, row, lx, ly)) {
                            Ref.put(Ref.get(ln) + 1, ln);
                            let argb = TilesetGreen.pixelArgb(col, row, lx, ly);
                            let clsName = TilesetGreen.materialName(TilesetGreen.classify(argb));
                            let maskName = TilesetGreen.materialName(TilesetGreen.materialAt(col, row, lx, ly));
                            if (clsName != maskName) Ref.put(Ref.get(bad) + 1, bad) else ()
                        } else (),
                        List.range(0, c)),
                    List.range(0, c))
            }, allCells());
            (Ref.get(ln), Ref.get(bad))
        };
        println("=== 線画: ${lineN}px（全構造の設計線・green 最暗段で締め）/ 分類ずれ ${lineBad}px（0 = 材質 XOR を汚さない）===");

        // 少色数規律（パキッと感の機械指標）: 原本 31 色に対しどのテーマも 50 色以下。
        // 立体面シェーディングもモチーフも固定ランプの段しか使わない（中間色を作らない）ので少色数を保つ。
        let origColors = countColors(orig);
        let regenColors = countColors(regen);
        let flowerColors = countColors(flower);
        println("=== 総色数(≤50): 原本=${origColors} / green=${regenColors} / flower=${flowerColors} ===");
        let colorsOk = regenColors <= 50 and flowerColors <= 50;

        // シルエット許容帯（±2px）: flower は内部を花で描き替えつつ輪郭を花の円に沿ってうねらせるので、
        // green と完全一致(XOR 0)ではなく「原本の dilate/erode 2px の帯」に収まることを測る（over/under=帯超え画素）。
        let (flowerOver, flowerUnder) = silhouetteTolerance(flower);
        println("=== flower のシルエット許容帯(±2px・over/under=0 が理想): flower=${flowerOver}/${flowerUnder} ===");
        // 境界互換（同種セルを並べても割れない）: セル塗りは周期がセル 26px を割り切るので継ぎ目で連続。
        let flowerSeam = tileSeamBreaks(flower);
        println("=== 境界互換(割れ画素 0 が理想): flower=${flowerSeam} ===");
        let silhouetteOk =
            flowerOver == 0 and flowerUnder == 0 and flowerSeam == 0;

        // TileLint 周回レンガ: 壁レンガのシーム連続性（sliver/横長を機械検出）
        let railW = TilesetGreen.wrapStoneWidths(TilesetGreen.railCuts(), 2);
        let faceW = TilesetGreen.wrapStoneWidths(TilesetGreen.faceCuts(), 2);
        let soldierW = TilesetGreen.wrapStoneWidths(TilesetGreen.soldierCuts(), 2);
        println("=== TileLint wrapBrick: rail=${railW} face=${faceW} soldier=${soldierW} ===");
        let wrapOk = wrapWidthsOk(TilesetGreen.railCuts(), 6, 12)
            and wrapWidthsOk(TilesetGreen.faceCuts(), 6, 14)
            and wrapWidthsOk(TilesetGreen.soldierCuts(), 4, 8);

        // 合格条件: green は全 108 セルのワースト silhouette ≤5% かつ material ≤5%、
        // 全テーマ 50 色以下、モチーフのシルエット漏れ 0。
        let threshPx = ftoi(area * 0.05);
        Assert.assertEq(expected = true,
            worstSil <= threshPx
                and worstMat <= threshPx
                and colorsOk
                and silhouetteOk
                and lineN > 0
                and lineBad == 0
                and wrapOk
                and (new File("${outDir()}/tileset_green_regen.png")).exists()
                and (new File("${outDir()}/tileset_flower.png")).exists()
                and (new File("${outDir()}/tileset_cell_diff.png")).exists()
                and (new File("${outDir()}/tileset_compare.png")).exists()
                and (new File("${outDir()}/rooms_original.png")).exists()
                and (new File("${outDir()}/rooms_green.png")).exists()
                and (new File("${outDir()}/rooms_flower.png")).exists()
                and (new File("${outDir()}/tileset_layers.png")).exists()
                and (new File("${outDir()}/tileset_green_compare.png")).exists())
}
