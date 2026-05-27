// MapGridCanvas — Maps タブ中央の JavaFX Canvas に Level の中身を描く。
//
// 描画レイヤー (下から上):
//   1. 背景 (ダークグレー)
//   2. decorTiles (Floor 層) — tilemap_floor PNG から実タイル描画
//   3. 自動壁 (Walls 層下部) — floorMask の 8 近傍判定 + Material.wallMap から自動補完
//   4. manualTiles (Walls 層上部) — 自動壁の上書きとして実タイル描画
//   5. grid 線 (薄い色)
//   6. Entities (シアン円 + identifier ラベル)
//
// 衝突判定は自動壁から生成される (Walls の manualTiles は装飾)。
// Layer モード切替時の左/右クリック挙動:
//   Floor    : decorTiles に追加 / 削除 (副作用で周囲の自動壁が変化)
//   Walls    : manualTiles に追加 / 削除 (装飾の上書きだけ、衝突は変化しない)
//   Entities : identifier テキストで Entity 追加 / 削除

mod MapGridCanvas {
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.paint.Color
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ZoomEvent
    import javafx.scene.input.KeyEvent
    import javafx.scene.Scene
    import javafx.scene.Node
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.{Object => JObject}
    import javafx.event.EventHandler

    /// 1 セルの表示ピクセル数。tileSize (=16 等) と独立に「IDE 上で見やすい大きさ」で持つ。
    pub def defaultCellPx(): Int32 = 24

    /// Level の中身を Canvas に描く。
    /// Canvas は Level サイズ × zoom にリサイズされ、gc.scale で内部 draw を拡縮する。
    /// tileset Image が無い場合は単に絵が描かれない (オレンジ overlay 等は使わない)。
    /// `vis` は目玉トグルの状態。false のレイヤーは draw をスキップする。
    /// `zoom=1.0` で等倍。`MapEditorState.mapZoomRef` がピンチで更新される。
    /// Walls visibility が ON のとき自動壁 + manualTiles 上書きを両方描画する。
    /// `material` が `None` のときは自動壁の描画スキップ (manualTiles のみ)。
    pub def drawLevel(canvas: Canvas, level: MapResource.Level, cellPx: Int32,
                       wallsImg: Option[Image], floorImg: Option[Image],
                       vis: MapEditorState.LayerVisibility, zoom: Float64,
                       material: Option[MapResource.Material],
                       selectedTrbl: Option[String],
                       selectedRange: Option[(Int32, Int32, Int32, Int32)]): Unit \ IO = {
        let d = MapResource.levelData(level);
        resizeAndFill(canvas, d#width, d#height, cellPx, zoom);
        let gc = canvas.getGraphicsContext2D();
        gc.save();
        gc.scale(zoom, zoom);
        if (vis#floor) {
            match floorImg {
                case Some(img) => drawTiles(canvas, d#decorTiles, img, d#tileSize, cellPx)
                case None      => ()
            }
        } else ();
        if (vis#walls) {
            // 自動壁を先に (下)、その上に manualTiles (上書き)
            let floorMask = floorMaskOf(d);
            let wallCells = computeWallCells(floorMask, d#width, d#height);
            match (wallsImg, material) {
                case (Some(img), Some(mat)) =>
                    drawAutoLayerWalls(canvas, wallCells, floorMask,
                                         MapResource.materialData(mat),
                                         img, d#tileSize, cellPx)
                case _ => ()
            };
            match wallsImg {
                case Some(img) => drawTiles(canvas, d#manualTiles, img, d#tileSize, cellPx)
                case None      => ()
            };
            // AutoRule (装飾) を最前面に描画
            match (wallsImg, material) {
                case (Some(img), Some(mat)) => {
                    let intGrid = buildIntGrid(floorMask, wallCells, d#width, d#height);
                    let md = MapResource.materialData(mat);
                    drawAutoRuleTiles(canvas, intGrid, d#width, d#height,
                                        md#autoRules, img, d#tileSize, cellPx)
                }
                case _ => ()
            };
            // auto-layer タブで選択中のキー (4-trit or 4-bit) に該当する壁セルを紫網掛け
            match selectedTrbl {
                case None      => ()
                case Some(key) => drawTrblPreview(canvas, wallCells, floorMask, key, cellPx)
            }
        } else ();
        drawGridLines(canvas, d#width, d#height, cellPx);
        if (vis#entities) drawEntities(canvas, d#entities, cellPx) else ();
        // 範囲選択ハイライト (最前面)
        match selectedRange {
            case None        => ()
            case Some(range) => drawSelectedRange(canvas, range, cellPx)
        };
        gc.restore()
    }

    /// 選択範囲を半透明の青塗り + 青枠で表示する。
    def drawSelectedRange(canvas: Canvas, range: (Int32, Int32, Int32, Int32),
                            cellPx: Int32): Unit \ IO = {
        let (c1, r1, c2, r2) = range;
        let minC = Int32.min(c1, c2);
        let maxC = Int32.max(c1, c2);
        let minR = Int32.min(r1, r2);
        let maxR = Int32.max(r1, r2);
        let cs = Int32.toFloat64(cellPx);
        let x = Int32.toFloat64(minC) * cs;
        let y = Int32.toFloat64(minR) * cs;
        let w = Int32.toFloat64(maxC - minC + 1) * cs;
        let h = Int32.toFloat64(maxR - minR + 1) * cs;
        let gc = canvas.getGraphicsContext2D();
        gc.setFill(Color.rgb(80, 160, 240, 0.25));
        gc.fillRect(x, y, w, h);
        gc.setStroke(Color.rgb(80, 160, 240));
        gc.setLineWidth(2.0);
        gc.strokeRect(x, y, w, h)
    }

    /// 選択中キー (4-trit "EWFW" or 旧 4-bit "0101") に一致する壁セルを紫半透明で塗る。
    /// 4-trit 判定はそのまま、4-bit は trblKeyAt で照合 (旧形式マップとの互換)。
    def drawTrblPreview(canvas: Canvas, wallCells: Set[(Int32, Int32)],
                          floorMask: Set[(Int32, Int32)],
                          key: String, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let cs = Int32.toFloat64(cellPx);
        gc.setFill(Color.rgb(160, 64, 200, 0.5));
        // key が 4-trit (W/F/E のみ) か旧 4-bit (0/1) かで一致判定方法を切り替える
        let isTrit = String.length(key) == 4 and isTritKey(key);
        Set.forEach(coord -> {
            let (col, row) = coord;
            let matched =
                if (isTrit) trblTritKeyAt(wallCells, floorMask, col, row) == key
                else        trblKeyAt(wallCells, col, row) == key;
            if (matched)
                gc.fillRect(Int32.toFloat64(col) * cs,
                             Int32.toFloat64(row) * cs, cs, cs)
            else ()
        }, wallCells)
    }

    /// "EWFW" のような 4-trit キーかどうかを判定 (先頭文字で W/F/E を判定)。
    /// 旧 4-bit キーは "0" or "1" で始まるので区別可能。
    def isTritKey(key: String): Bool =
        if (String.length(key) == 0) false
        else {
            let c = String.charAt(0, key);
            c == 'W' or c == 'F' or c == 'E'
        }

    /// decorTiles のセルから床マスクを作る。
    pub def floorMaskOf(d: MapResource.LevelData): Set[(Int32, Int32)] =
        d#decorTiles |> List.map(t -> (t#x, t#y)) |> List.toSet

    /// 自動壁セル: 床なし + 8 近傍に床が 1 つでもある (ldtk AutoLayer 流)。
    pub def computeWallCells(floorMask: Set[(Int32, Int32)],
                              width: Int32, height: Int32): Set[(Int32, Int32)] =
        List.range(0, width * height)
            |> List.filterMap(idx -> {
                let col = Int32.remainder(idx, width);
                let row = idx / width;
                if (Set.memberOf((col, row), floorMask)) None
                else if (any8NeighborIsFloor(floorMask, col, row)) Some((col, row))
                else None
            })
            |> List.toSet

    def any8NeighborIsFloor(floorMask: Set[(Int32, Int32)], col: Int32, row: Int32): Bool =
        Set.memberOf((col - 1, row - 1), floorMask) or
        Set.memberOf((col,     row - 1), floorMask) or
        Set.memberOf((col + 1, row - 1), floorMask) or
        Set.memberOf((col - 1, row    ), floorMask) or
        Set.memberOf((col + 1, row    ), floorMask) or
        Set.memberOf((col - 1, row + 1), floorMask) or
        Set.memberOf((col,     row + 1), floorMask) or
        Set.memberOf((col + 1, row + 1), floorMask)

    /// 自動壁: wallCells をループして 4-trit → 4-bit の順で wallMap を引いて描画する。
    def drawAutoLayerWalls(canvas: Canvas, wallCells: Set[(Int32, Int32)],
                            floorMask: Set[(Int32, Int32)],
                            mat: MapResource.MaterialData, image: Image,
                            tileSize: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        let ts = Int32.toFloat64(tileSize);
        let cs = Int32.toFloat64(cellPx);
        Set.forEach(coord -> {
            let (col, row) = coord;
            match lookupWallTile(wallCells, floorMask, mat#wallMap, col, row) {
                case None              => ()
                case Some((srcX, srcY)) => {
                    let sx = Int32.toFloat64(srcX);
                    let sy = Int32.toFloat64(srcY);
                    let dx = Int32.toFloat64(col) * cs;
                    let dy = Int32.toFloat64(row) * cs;
                    gc.drawImage(image, sx, sy, ts, ts, dx, dy, cs, cs)
                }
            }
        }, wallCells)
    }

    /// 4-trit (壁/床/空) → 4-bit のフォールバック lookup。
    pub def lookupWallTile(wallCells: Set[(Int32, Int32)],
                             floorMask: Set[(Int32, Int32)],
                             wallMap: Map[String, (Int32, Int32)],
                             col: Int32, row: Int32): Option[(Int32, Int32)] = {
        let trit = trblTritKeyAt(wallCells, floorMask, col, row);
        match Map.get(trit, wallMap) {
            case Some(v) => Some(v)
            case None    => Map.get(trblKeyAt(wallCells, col, row), wallMap)
        }
    }

    /// (col, row) の TRBL 4-bit キー。隣セルが wallCells に含まれるなら 1。
    pub def trblKeyAt(wallCells: Set[(Int32, Int32)], col: Int32, row: Int32): String = {
        let t = if (Set.memberOf((col,     row - 1), wallCells)) "1" else "0";
        let r = if (Set.memberOf((col + 1, row    ), wallCells)) "1" else "0";
        let b = if (Set.memberOf((col,     row + 1), wallCells)) "1" else "0";
        let l = if (Set.memberOf((col - 1, row    ), wallCells)) "1" else "0";
        t + r + b + l
    }

    /// (col, row) の TRBL 4-trit キー。各方向 W=壁, F=床, E=空 (マップ外含む)。
    pub def trblTritKeyAt(wallCells: Set[(Int32, Int32)],
                            floorMask: Set[(Int32, Int32)],
                            col: Int32, row: Int32): String =
        tritAt(wallCells, floorMask, col,     row - 1)
        + tritAt(wallCells, floorMask, col + 1, row    )
        + tritAt(wallCells, floorMask, col,     row + 1)
        + tritAt(wallCells, floorMask, col - 1, row    )

    def tritAt(wallCells: Set[(Int32, Int32)],
                floorMask: Set[(Int32, Int32)],
                col: Int32, row: Int32): String =
        if      (Set.memberOf((col, row), wallCells)) "W"
        else if (Set.memberOf((col, row), floorMask)) "F"
        else                                          "E"

    /// IntGrid を再構築: 0=空, 1=床, 2=自動壁。
    pub def buildIntGrid(floorMask: Set[(Int32, Int32)],
                           wallCells: Set[(Int32, Int32)],
                           width: Int32, height: Int32): Vector[Int32] =
        List.range(0, width * height)
            |> List.map(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                if      (Set.memberOf((col, row), floorMask)) 1i32
                else if (Set.memberOf((col, row), wallCells)) 2i32
                else                                          0i32
            })
            |> List.toVector

    /// AutoRule リストを各セルに適用して描画する (engine 側の buildAutoRuleTiles と同じロジック)。
    def drawAutoRuleTiles(canvas: Canvas, intGrid: Vector[Int32],
                            width: Int32, height: Int32,
                            rules: List[MapResource.AutoRule], image: Image,
                            tileSize: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        let ts = Int32.toFloat64(tileSize);
        let cs = Int32.toFloat64(cellPx);
        List.forEach(i -> {
            let col = Int32.remainder(i, width);
            let row = i / width;
            match applyFirstMatchingRule(intGrid, width, height, col, row, rules) {
                case None              => ()
                case Some((srcX, srcY)) => {
                    let sx = Int32.toFloat64(srcX);
                    let sy = Int32.toFloat64(srcY);
                    let dx = Int32.toFloat64(col) * cs;
                    let dy = Int32.toFloat64(row) * cs;
                    gc.drawImage(image, sx, sy, ts, ts, dx, dy, cs, cs)
                }
            }
        }, List.range(0, width * height))
    }

    def applyFirstMatchingRule(intGrid: Vector[Int32], width: Int32, height: Int32,
                                 col: Int32, row: Int32,
                                 rules: List[MapResource.AutoRule]):
            Option[(Int32, Int32)] = match rules {
        case Nil       => None
        case r :: rest =>
            if (ruleMatches(intGrid, width, height, col, row, r))
                Some((r#srcX, r#srcY))
            else
                applyFirstMatchingRule(intGrid, width, height, col, row, rest)
    }

    /// Pattern セル値:
    ///   -1 = 装飾 (中央のみ、マッチ条件なし)
    ///    0 = 任意 (どんな値でも OK、マッチ条件なし)
    ///    1 = 床 (intGrid 値 1 を要求)
    ///    2 = 壁 (intGrid 値 != 1 = 空・自動壁・map 外をまとめて壁扱い)
    pub def ruleMatches(intGrid: Vector[Int32], width: Int32, height: Int32,
                          col: Int32, row: Int32, rule: MapResource.AutoRule): Bool = {
        let size = rule#size;
        let half = size / 2;
        let n = size * size;
        List.range(0, n)
            |> List.forAll(idx -> {
                let pc = Int32.remainder(idx, size);
                let pr = idx / size;
                let cc = col + pc - half;
                let cr = row + pr - half;
                let cellVal = intGridAt(intGrid, width, height, cc, cr);
                let want = match Vector.nth(idx, rule#pattern) {
                    case Some(v) => v
                    case None    => 0i32
                };
                if (want == -1i32) true
                else if (want == 0i32) true
                else if (want == 1i32) cellVal == 1i32
                else if (want == 2i32) cellVal != 1i32
                else false
            })
    }

    def intGridAt(intGrid: Vector[Int32], width: Int32, height: Int32,
                    col: Int32, row: Int32): Int32 =
        if (col < 0 or col >= width or row < 0 or row >= height) 0i32
        else match Vector.nth(row * width + col, intGrid) {
            case Some(v) => v
            case None    => 0i32
        }

    /// Entity を「シアン円 + identifier テキスト」で描画する。
    /// セルの中心に円、その下に小さくラベル。
    def drawEntities(canvas: Canvas, entities: List[MapResource.Entity], cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let cs = Int32.toFloat64(cellPx);
        let radius = cs * 0.30;
        List.forEach(e -> {
            let cx = (Int32.toFloat64(e#x) + 0.5) * cs;
            let cy = (Int32.toFloat64(e#y) + 0.5) * cs;
            // 円 (中: シアン半透明, 縁: 濃シアン)
            gc.setFill(Color.rgb(60, 200, 230, 0.7));
            gc.fillOval(cx - radius, cy - radius, radius * 2.0, radius * 2.0);
            gc.setStroke(Color.rgb(0, 120, 160));
            gc.setLineWidth(1.5);
            gc.strokeOval(cx - radius, cy - radius, radius * 2.0, radius * 2.0);
            // identifier テキスト (小さく)
            gc.setFill(Color.rgb(255, 255, 255));
            gc.fillText(e#identifier, cx - radius, cy + radius + 10.0)
        }, entities)
    }

    /// Canvas を Level サイズ × zoom にリサイズし、背景塗りつぶし。
    /// gc.scale は呼び元 (drawLevel) で別途かけるので、ここでは塗りに base 座標は使わず
    /// 物理 pixel で fillRect する。
    def resizeAndFill(canvas: Canvas, width: Int32, height: Int32, cellPx: Int32,
                       zoom: Float64): Unit \ IO = {
        let pixelW = Int32.toFloat64(width * cellPx) * zoom;
        let pixelH = Int32.toFloat64(height * cellPx) * zoom;
        canvas.setWidth(pixelW);
        canvas.setHeight(pixelH);
        let gc = canvas.getGraphicsContext2D();
        gc.setFill(Color.rgb(40, 40, 45));
        gc.fillRect(0.0, 0.0, pixelW, pixelH)
    }

    /// ManualTile のリストを実 tileset Image を切り出して Canvas に描く。
    /// srcX/srcY (ピクセル) はそのまま使い、flipH/flipV は GraphicsContext の
    /// translate + scale で実現する。
    def drawTiles(canvas: Canvas, tiles: List[MapResource.ManualTile],
                   image: Image, tileSize: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        let ts = Int32.toFloat64(tileSize);
        let cs = Int32.toFloat64(cellPx);
        List.forEach(t -> {
            let sx = Int32.toFloat64(t#srcX);
            let sy = Int32.toFloat64(t#srcY);
            let dx = Int32.toFloat64(t#x) * cs;
            let dy = Int32.toFloat64(t#y) * cs;
            drawTileFlipped(gc, image, sx, sy, ts, dx, dy, cs, t#flipH, t#flipV)
        }, tiles)
    }

    /// 1 タイルを必要に応じて flip して描画する。flip しないなら drawImage 直呼び。
    def drawTileFlipped(gc: GraphicsContext, image: Image,
                         srcX: Float64, srcY: Float64, srcSize: Float64,
                         dstX: Float64, dstY: Float64, dstSize: Float64,
                         flipH: Bool, flipV: Bool): Unit \ IO =
        if (not flipH and not flipV)
            gc.drawImage(image, srcX, srcY, srcSize, srcSize, dstX, dstY, dstSize, dstSize)
        else {
            gc.save();
            let tx = if (flipH) dstX + dstSize else dstX;
            let ty = if (flipV) dstY + dstSize else dstY;
            let sxScale = if (flipH) -1.0f64 else 1.0f64;
            let syScale = if (flipV) -1.0f64 else 1.0f64;
            gc.translate(tx, ty);
            gc.scale(sxScale, syScale);
            gc.drawImage(image, srcX, srcY, srcSize, srcSize, 0.0, 0.0, dstSize, dstSize);
            gc.restore()
        }

    /// grid 線を Canvas 全面に引く。
    def drawGridLines(canvas: Canvas, width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let pixelW = Int32.toFloat64(width * cellPx);
        let pixelH = Int32.toFloat64(height * cellPx);
        let gc = canvas.getGraphicsContext2D();
        gc.setStroke(Color.rgb(80, 80, 90, 0.6));
        gc.setLineWidth(1.0);
        let cs = Int32.toFloat64(cellPx);
        List.forEach(c -> {
            let x = Int32.toFloat64(c) * cs;
            gc.strokeLine(x, 0.0, x, pixelH)
        }, List.range(0, width + 1));
        List.forEach(r -> {
            let y = Int32.toFloat64(r) * cs;
            gc.strokeLine(0.0, y, pixelW, y)
        }, List.range(0, height + 1))
    }

    /// Canvas を空の状態に戻す (Level 未選択時用)。
    pub def clear(canvas: Canvas): Unit \ IO = {
        canvas.setWidth(0.0);
        canvas.setHeight(0.0)
    }

    /// Map canvas に Mouse / Zoom / Key handler をまとめて配線する。
    ///   - クリック : place/remove (左) or 削除 (右) を実行し undo に押して自動保存
    ///   - ピンチ   : mapZoom を倍率更新して再描画
    ///   - Ctrl/Cmd+Z : undo (canvas にフォーカスが必要なのでクリックで requestFocus する)
    pub def wireMapCanvas(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setFocusTraversable(true);
        // MousePressed: EditTool に応じて分岐
        //   Pencil      → 配置/削除 (handleClick) + dragStart に「最後にペイントしたセル」記録
        //   RangeSelect → 範囲ドラッグ開始
        canvas.setOnMousePressed(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                canvas.requestFocus();
                let (col, row) = eventToCell(state, event);
                match MapEditorState.getEditTool(state#mapEditor) {
                    case MapEditorState.EditTool.Pencil      => {
                        MapEditorState.setSelectedRange(state#mapEditor, None);
                        handleClick(state, event);
                        MapEditorState.setDragStart(state#mapEditor, Some((col, row)))
                    }
                    case MapEditorState.EditTool.RangeSelect => {
                        MapEditorState.setDragStart(state#mapEditor, Some((col, row)));
                        MapEditorState.setIsDragging(state#mapEditor, false);
                        MapEditorState.setSelectedRange(state#mapEditor, None);
                        MapEditorPanel.redrawCanvas(state)
                    }
                }
            }
        });
        // MouseDragged: Pencil は連続ペイント、RangeSelect は範囲更新
        canvas.setOnMouseDragged(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let (col, row) = eventToCell(state, event);
                match MapEditorState.getEditTool(state#mapEditor) {
                    case MapEditorState.EditTool.Pencil      => {
                        // 直前と違うセルに移動したときだけ追加配置 (連続ペイント)
                        match MapEditorState.getDragStart(state#mapEditor) {
                            case Some((lc, lr)) =>
                                if (lc == col and lr == row) ()
                                else {
                                    handleClick(state, event);
                                    MapEditorState.setDragStart(
                                        state#mapEditor, Some((col, row)))
                                }
                            case None => ()
                        }
                    }
                    case MapEditorState.EditTool.RangeSelect => {
                        match MapEditorState.getDragStart(state#mapEditor) {
                            case None         => ()
                            case Some((sc, sr)) => {
                                MapEditorState.setIsDragging(state#mapEditor, true);
                                MapEditorState.setSelectedRange(state#mapEditor,
                                    Some((sc, sr, col, row)));
                                MapEditorPanel.redrawCanvas(state)
                            }
                        }
                    }
                }
            }
        });
        // MouseReleased: ドラッグ終了処理。Pencil は記録クリアだけ、RangeSelect は範囲確定。
        canvas.setOnMouseReleased(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], _event: MouseEvent): Unit \ IO = {
                match MapEditorState.getEditTool(state#mapEditor) {
                    case MapEditorState.EditTool.Pencil      => {
                        MapEditorState.setDragStart(state#mapEditor, None)
                    }
                    case MapEditorState.EditTool.RangeSelect => {
                        let dragging = MapEditorState.getIsDragging(state#mapEditor);
                        if (dragging) {
                            // 範囲選択確定 (selectedRange は維持)
                            ()
                        } else {
                            // 単純クリックでは範囲を作らない
                            MapEditorState.setSelectedRange(state#mapEditor, None)
                        };
                        MapEditorState.setDragStart(state#mapEditor, None);
                        MapEditorState.setIsDragging(state#mapEditor, false);
                        MapEditorPanel.redrawCanvas(state)
                    }
                };
                // ドラッグ/クリック後も BackSpace 等のキー入力を受け取れるよう
                // Canvas にフォーカスを保持しておく
                canvas.requestFocus()
            }
        });
        canvas.setOnZoom(new EventHandler[ZoomEvent] {
            def handle(_this: EventHandler[ZoomEvent], event: ZoomEvent): Unit \ IO = {
                let factor = event.getZoomFactor();
                let cur = MapEditorState.getMapZoom(state#mapEditor);
                MapEditorState.setMapZoom(state#mapEditor, cur * factor);
                MapEditorPanel.redrawCanvas(state);
                event.consume()
            }
        });
        canvas.setOnKeyPressed(new EventHandler[KeyEvent] {
            def handle(_this: EventHandler[KeyEvent], event: KeyEvent): Unit \ IO = {
                let code = event.getCode().toString();
                // isShortcutDown() = Cmd (macOS) または Ctrl (Win/Linux)
                if (event.isShortcutDown() and code == "Z") {
                    doUndo(state);
                    event.consume()
                } else if (code == "BACK_SPACE") {
                    deleteSelectedRange(state);
                    event.consume()
                } else if (code == "ENTER") {
                    fillSelectedRange(state);
                    event.consume()
                } else if (code == "ESCAPE") {
                    MapEditorState.setSelectedRange(state#mapEditor, None);
                    MapEditorPanel.redrawCanvas(state);
                    event.consume()
                } else ()
            }
        });
        // ScrollPane が間に挟まる構造のため、フォーカスが Canvas でなく ScrollPane に
        // 行くことがある。Scene 上のキーイベントを捕捉し、Map Canvas 領域 (Canvas または
        // その祖先である ScrollPane / VBox) が focus を持つときのみ反応させる。
        canvas.sceneProperty().addListener(new ChangeListener[Scene] {
            def changed(_cThis: ChangeListener[Scene],
                          _obs: ObservableValue[JObject],
                          _old: Scene, newScene: Scene): Unit \ IO = {
                if (Object.isNull(newScene)) ()
                else {
                    newScene.addEventFilter(KeyEvent.KEY_PRESSED,
                        new EventHandler[KeyEvent] {
                            def handle(_this: EventHandler[KeyEvent],
                                         event: KeyEvent): Unit \ IO = {
                                if (isMapCanvasFocused(canvas)) {
                                    let code = event.getCode().toString();
                                    if (event.isShortcutDown() and code == "Z") {
                                        doUndo(state);
                                        event.consume()
                                    } else if (code == "BACK_SPACE") {
                                        deleteSelectedRange(state);
                                        event.consume()
                                    } else if (code == "ENTER") {
                                        fillSelectedRange(state);
                                        event.consume()
                                    } else if (code == "ESCAPE") {
                                        MapEditorState.setSelectedRange(
                                            state#mapEditor, None);
                                        MapEditorPanel.redrawCanvas(state);
                                        event.consume()
                                    } else ()
                                } else ()
                            }
                        })
                }
            }
        })
    }

    /// 現在の Scene focus owner が canvas、または canvas の祖先 (ScrollPane / VBox) で
    /// あれば true。これにより「Map Canvas 領域に focus が入っている状態」を判定する。
    def isMapCanvasFocused(canvas: Canvas): Bool \ IO = {
        let scene = canvas.getScene();
        if (Object.isNull(scene)) false
        else {
            let focused: Node = scene.getFocusOwner();
            if (Object.isNull(focused)) false
            else {
                // canvas もしくは canvas の祖先のいずれかに focus owner が一致するか
                let canvasNode: Node = checked_cast(canvas);
                isAncestorOrSelf(focused, canvasNode)
            }
        }
    }

    /// `target` が `node` か、`node` の祖先のいずれかに等しいかを判定する。
    /// (つまり node→parent→...→root の中に target があるか)
    def isAncestorOrSelf(target: Node, node: Node): Bool \ IO = {
        if (Object.isNull(node)) false
        else if (target.equals(node)) true
        else {
            // Parent は Node のサブクラスなので checked_cast で上方向にキャスト
            let parent = node.getParent();
            let parentNode: Node = checked_cast(parent);
            isAncestorOrSelf(target, parentNode)
        }
    }

    /// MouseEvent の x/y から grid 座標 (col, row) を取り出す。
    /// mapZoom と cellPx を考慮する。
    def eventToCell(state: IdeState.IdeState, event: MouseEvent): (Int32, Int32) \ IO = {
        let cellPx = defaultCellPx();
        let zoom = MapEditorState.getMapZoom(state#mapEditor);
        let cs = Int32.toFloat64(cellPx) * zoom;
        let col = Float64.truncateToInt32(event.getX() / cs);
        let row = Float64.truncateToInt32(event.getY() / cs);
        (col, row)
    }

    /// 選択範囲を「現在 Palette で選択中のタイル」で塗りつぶす。
    /// Floor / Walls のみ対応 (Entities は palette を持たないので no-op)。
    /// 範囲未選択、または Palette 未選択のときは no-op。
    def fillSelectedRange(state: IdeState.IdeState): Unit \ IO = {
        match (MapEditorState.getSelectedRange(state#mapEditor),
               MapEditorState.getEditingLevel(state#mapEditor),
               MapEditorState.getSelectedSrc(state#mapEditor)) {
            case (Some(range), Some(level), Some((srcX, srcY))) => {
                let (c1, r1, c2, r2) = range;
                let minC = Int32.max(0, Int32.min(c1, c2));
                let maxC = Int32.min(MapResource.levelData(level)#width - 1,
                                       Int32.max(c1, c2));
                let minR = Int32.max(0, Int32.min(r1, r2));
                let maxR = Int32.min(MapResource.levelData(level)#height - 1,
                                       Int32.max(r1, r2));
                let mode = MapEditorState.getLayerMode(state#mapEditor);
                // 範囲内の (col, row) 列を生成
                let cols = List.range(minC, maxC + 1);
                let rows = List.range(minR, maxR + 1);
                let allCells: List[(Int32, Int32)] =
                    List.flatMap(c -> List.map(r -> (c, r), rows), cols);
                // 各セルに place* を fold で重ね適用 (maybeFinalizeTileSize は最後に一度だけ)
                let prevD = MapResource.levelData(level);
                let placed = List.foldLeft((acc, cr) -> {
                    let (c, r) = cr;
                    let ad = MapResource.levelData(acc);
                    match mode {
                        case MapEditorState.LayerMode.Floor    =>
                            placeFloorTileAt(acc, ad, c, r, srcX, srcY)
                        case MapEditorState.LayerMode.Walls    =>
                            placeWallTileAt(acc, ad, c, r, srcX, srcY)
                        case MapEditorState.LayerMode.Entities => acc
                    }
                }, level, allCells);
                match mode {
                    case MapEditorState.LayerMode.Entities => ()  // 何も配置していないので skip
                    case _ => {
                        let finalLevel = maybeFinalizeTileSize(state, placed, prevD, mode);
                        MapEditorState.pushUndo(state#mapEditor, level);
                        MapEditorState.setEditingLevel(state#mapEditor, Some(finalLevel));
                        MapEditorState.setSelectedRange(state#mapEditor, None);
                        MapEditorPanel.redrawCanvas(state);
                        MapEditorPanel.autoSave(state)
                    }
                }
            }
            case _ => ()
        }
    }

    /// 選択範囲内のタイルを現 LayerMode に応じて削除する。
    def deleteSelectedRange(state: IdeState.IdeState): Unit \ IO = {
        match (MapEditorState.getSelectedRange(state#mapEditor),
               MapEditorState.getEditingLevel(state#mapEditor)) {
            case (Some(range), Some(level)) => {
                let (c1, r1, c2, r2) = range;
                let minC = Int32.min(c1, c2);
                let maxC = Int32.max(c1, c2);
                let minR = Int32.min(r1, r2);
                let maxR = Int32.max(r1, r2);
                let d = MapResource.levelData(level);
                let mode = MapEditorState.getLayerMode(state#mapEditor);
                let inRange = (x, y) ->
                    x >= minC and x <= maxC and y >= minR and y <= maxR;
                let newLevel = match mode {
                    case MapEditorState.LayerMode.Floor    => {
                        let newDecor = List.filter(t -> not inRange(t#x, t#y), d#decorTiles);
                        let newD: MapResource.LevelData = {decorTiles = newDecor | d};
                        MapResource.Level.Level(newD)
                    }
                    case MapEditorState.LayerMode.Walls    => {
                        let newManual = List.filter(t -> not inRange(t#x, t#y), d#manualTiles);
                        let newD: MapResource.LevelData = {manualTiles = newManual | d};
                        MapResource.Level.Level(newD)
                    }
                    case MapEditorState.LayerMode.Entities => {
                        let newEnt = List.filter(e -> not inRange(e#x, e#y), d#entities);
                        let newD: MapResource.LevelData = {entities = newEnt | d};
                        MapResource.Level.Level(newD)
                    }
                };
                MapEditorState.pushUndo(state#mapEditor, level);
                MapEditorState.setEditingLevel(state#mapEditor, Some(newLevel));
                MapEditorState.setSelectedRange(state#mapEditor, None);
                MapEditorPanel.redrawCanvas(state);
                MapEditorPanel.autoSave(state)
            }
            case _ => ()
        }
    }

    /// Undo: スタック head の Level を editingLevel に戻し、再描画 + 自動保存。
    /// スタックが空なら no-op。
    def doUndo(state: IdeState.IdeState): Unit \ IO =
        match MapEditorState.popUndo(state#mapEditor) {
            case None       => ()
            case Some(prev) => {
                MapEditorState.setEditingLevel(state#mapEditor, Some(prev));
                MapEditorPanel.redrawCanvas(state);
                MapEditorPanel.autoSave(state)
            }
        }

    def handleClick(state: IdeState.IdeState, event: MouseEvent): Unit \ IO =
        match MapEditorState.getEditingLevel(state#mapEditor) {
            case None        => ()
            case Some(level) =>
                let d = MapResource.levelData(level);
                let cellPx = defaultCellPx();
                let zoom = MapEditorState.getMapZoom(state#mapEditor);
                let cs = Int32.toFloat64(cellPx) * zoom;
                let col = Float64.truncateToInt32(event.getX() / cs);
                let row = Float64.truncateToInt32(event.getY() / cs);
                if (col < 0 or col >= d#width or row < 0 or row >= d#height) ()
                else {
                    let mode = MapEditorState.getLayerMode(state#mapEditor);
                    // MouseButton enum 比較は Eq instance が無いので toString() でやる
                    let isRight = event.getButton().toString() == "SECONDARY";
                    let newLevelOpt = match mode {
                        case MapEditorState.LayerMode.Floor =>
                            if (isRight) Some(removeFloorTileAt(level, d, col, row))
                            else placeFloorWithSelectedSrc(state, level, d, col, row)
                        case MapEditorState.LayerMode.Walls =>
                            if (isRight) Some(removeWallTileAt(level, d, col, row))
                            else placeWallWithSelectedSrc(state, level, d, col, row)
                        case MapEditorState.LayerMode.Entities =>
                            if (isRight) Some(removeEntityAt(level, d, col, row))
                            else placeEntityAt(state, level, d, col, row)
                    };
                    match newLevelOpt {
                        case None           => ()
                        case Some(newLevel) =>
                            // 編集前の Level を undo スタックに退避してから差し替え、自動保存
                            MapEditorState.pushUndo(state#mapEditor, level);
                            MapEditorState.setEditingLevel(state#mapEditor, Some(newLevel));
                            redrawCurrent(state, newLevel, cellPx);
                            MapEditorPanel.autoSave(state)
                    }
                }
        }

    // ────────────────────────────────────────────────────────
    // Pure place/remove ヘルパー (副作用なし、テスト容易)
    // ────────────────────────────────────────────────────────

    /// Walls レイヤーへの配置: manualTiles に追加 (自動壁の上書き、衝突は変化しない)。
    /// 同セルに既存タイルがあれば置換する。
    pub def placeWallTileAt(level: MapResource.Level, d: MapResource.LevelData,
                              col: Int32, row: Int32, srcX: Int32, srcY: Int32):
            MapResource.Level =
        let _ = level;
        let newTile = ({
            x = col, y = row,
            srcX = srcX, srcY = srcY,
            flipH = false, flipV = false
        }: MapResource.ManualTile);
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#manualTiles);
        let newTiles = List.append(filtered, newTile :: Nil);
        let newData: MapResource.LevelData = {manualTiles = newTiles | d};
        MapResource.Level.Level(newData)

    /// Walls レイヤーからの除去: manualTiles の同セル全消去。
    pub def removeWallTileAt(level: MapResource.Level, d: MapResource.LevelData,
                               col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#manualTiles);
        let newData: MapResource.LevelData = {manualTiles = filtered | d};
        MapResource.Level.Level(newData)

    /// Floor レイヤーへの配置: decorTiles に追加 (wallMask は変えない)。
    /// 同セルに既存タイルがあれば置換する。
    pub def placeFloorTileAt(level: MapResource.Level, d: MapResource.LevelData,
                               col: Int32, row: Int32, srcX: Int32, srcY: Int32):
            MapResource.Level =
        let _ = level;
        let newTile = ({
            x = col, y = row,
            srcX = srcX, srcY = srcY,
            flipH = false, flipV = false
        }: MapResource.ManualTile);
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#decorTiles);
        let newTiles = List.append(filtered, newTile :: Nil);
        let newData: MapResource.LevelData = {decorTiles = newTiles | d};
        MapResource.Level.Level(newData)

    /// Floor レイヤーからの除去: decorTiles の同セル全消去 (wallMask は変えない)。
    pub def removeFloorTileAt(level: MapResource.Level, d: MapResource.LevelData,
                                col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#decorTiles);
        let newData: MapResource.LevelData = {decorTiles = filtered | d};
        MapResource.Level.Level(newData)

    // ────────────────────────────────────────────────────────
    // IO ラッパ (state からパレット選択値を読んで pure 関数に渡す)
    // ────────────────────────────────────────────────────────

    def placeWallWithSelectedSrc(state: IdeState.IdeState, level: MapResource.Level,
                                   d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        match MapEditorState.getSelectedSrc(state#mapEditor) {
            case None               => None
            case Some((srcX, srcY)) =>
                let placed = placeWallTileAt(level, d, col, row, srcX, srcY);
                Some(maybeFinalizeTileSize(state, placed, d, MapEditorState.LayerMode.Walls))
        }

    def placeFloorWithSelectedSrc(state: IdeState.IdeState, level: MapResource.Level,
                                    d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        match MapEditorState.getSelectedSrc(state#mapEditor) {
            case None               => None
            case Some((srcX, srcY)) =>
                let placed = placeFloorTileAt(level, d, col, row, srcX, srcY);
                Some(maybeFinalizeTileSize(state, placed, d, MapEditorState.LayerMode.Floor))
        }

    /// Floor/Walls いずれかで「これまで何も配置されていなかった Level」に初めて
    /// タイルを置いたとき、その Palette の cellW を Level.tileSize にコピーして確定する。
    /// 既にタイルが 1 つでもあった場合は元の tileSize を維持する。
    /// `prevD` は配置前の LevelData (= 初回判定のソース)、`placed` は配置後の Level。
    def maybeFinalizeTileSize(state: IdeState.IdeState, placed: MapResource.Level,
                                prevD: MapResource.LevelData,
                                mode: MapEditorState.LayerMode): MapResource.Level \ IO = {
        let wasEmpty = List.isEmpty(prevD#decorTiles) and List.isEmpty(prevD#manualTiles);
        if (not wasEmpty) {
            println("[MapEditor] tileSize finalize skip (already has tiles): tileSize=${prevD#tileSize}");
            placed
        } else {
            let cw = match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                case Some(p) => p#cellW
                case None    => prevD#tileSize
            };
            let placedD = MapResource.levelData(placed);
            println("[MapEditor] tileSize finalized: ${prevD#tileSize} -> ${cw} (mode=${mode}, layer cellW)");
            let newD: MapResource.LevelData = {tileSize = cw | placedD};
            MapResource.Level.Level(newD)
        }
    }

    /// Entities モードでの配置: identifier フィールドのテキストで新 Entity を追加。
    /// 既存セルに Entity があれば置換 (同セル 1 Entity ルール)。
    /// identifier が空文字なら何もしない。
    def placeEntityAt(state: IdeState.IdeState, level: MapResource.Level,
                       d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        let _ = level;
        match Array.get(0, state#widgets#mapEntityIdField) {
            case None         => None
            case Some(field)  =>
                let id = field.getText();
                if (Object.isNull(id) or id == "") None
                else {
                    let newEntity = ({
                        identifier = id,
                        x = col, y = row,
                        fields = (Map.empty(): Map[String, MapResource.FieldValue])
                    }: MapResource.Entity);
                    let filtered = List.filter(e -> not (e#x == col and e#y == row), d#entities);
                    let newEntities = List.append(filtered, newEntity :: Nil);
                    let newData: MapResource.LevelData = {entities = newEntities | d};
                    Some(MapResource.Level.Level(newData))
                }
        }

    /// Entities モードでの右クリック: 指定セルの Entity を全て除去。
    def removeEntityAt(level: MapResource.Level, d: MapResource.LevelData,
                        col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let filtered = List.filter(e -> not (e#x == col and e#y == row), d#entities);
        let newData: MapResource.LevelData = {entities = filtered | d};
        MapResource.Level.Level(newData)

    /// 編集中 Level を canvas に再描画する (Layer visibility と mapZoom を参照)。
    def redrawCurrent(state: IdeState.IdeState, level: MapResource.Level, cellPx: Int32): Unit \ IO =
        match Array.get(0, state#widgets#mapGridCanvas) {
            case Some(c) => {
                let wImg = Array.get(0, state#widgets#mapWallsImage);
                let fImg = Array.get(0, state#widgets#mapFloorImage);
                let vis = MapEditorState.getLayerVisibility(state#mapEditor);
                let zoom = MapEditorState.getMapZoom(state#mapEditor);
                let mat = MapEditorState.getEditingMaterial(state#mapEditor);
                let selTrbl = MapEditorState.getSelectedTrbl(state#mapEditor);
                let selRange = MapEditorState.getSelectedRange(state#mapEditor);
                drawLevel(c, level, cellPx, wImg, fImg, vis, zoom, mat, selTrbl, selRange)
            }
            case None => ()
        }
}
