// MapGridCanvas — Maps タブ中央の JavaFX Canvas に Level の中身を描く。
//
// 描画レイヤー (下から上):
//   1. 背景 (ダークグレー)
//   2. decorTiles (Floor 層) — tilemap_floor PNG から実タイル描画
//   3. AutoLayerWalls — wallMask + Material.wallMap から自動補完したタイル
//   4. manualTiles (Walls 層) — AutoLayerWalls の上書きとして実タイル描画
//   5. grid 線 (薄い色)
//   6. Entities (シアン円 + identifier ラベル)
//
// 衝突判定は wallMask のみから生成される (Walls の manualTiles は装飾)。
// Layer モード切替時の左/右クリック挙動:
//   Floor          : decorTiles に追加 / 削除
//   AutoLayerWalls : wallMask[idx] を 1 / 0 にトグル (タイル絵は自動)
//   Walls          : manualTiles に追加 / 削除 (wallMask には触らない)
//   Entities       : identifier テキストで Entity 追加 / 削除

mod MapGridCanvas {
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.paint.Color
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ZoomEvent
    import javafx.scene.input.KeyEvent
    import javafx.event.EventHandler

    /// 1 セルの表示ピクセル数。tileSize (=16 等) と独立に「IDE 上で見やすい大きさ」で持つ。
    pub def defaultCellPx(): Int32 = 24

    /// Level の中身を Canvas に描く。
    /// Canvas は Level サイズ × zoom にリサイズされ、gc.scale で内部 draw を拡縮する。
    /// tileset Image が無い場合は単に絵が描かれない (オレンジ overlay 等は使わない)。
    /// `vis` は目玉トグルの状態。false のレイヤーは draw をスキップする。
    /// `zoom=1.0` で等倍。`MapEditorState.mapZoomRef` がピンチで更新される。
    /// `material` が `Some` のとき、AutoLayerWalls 層を wallMask + Material.wallMap から
    /// 自動補完して描画する。`None` のときは AutoLayerWalls 描画はスキップ。
    pub def drawLevel(canvas: Canvas, level: MapResource.Level, cellPx: Int32,
                       wallsImg: Option[Image], floorImg: Option[Image],
                       vis: MapEditorState.LayerVisibility, zoom: Float64,
                       material: Option[MapResource.Material]): Unit \ IO = {
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
        if (vis#autoLayerWalls) {
            match (wallsImg, material) {
                case (Some(img), Some(mat)) =>
                    drawAutoLayerWalls(canvas, d, MapResource.materialData(mat), img, cellPx)
                case _ => ()
            }
        } else ();
        if (vis#walls) {
            match wallsImg {
                case Some(img) => drawTiles(canvas, d#manualTiles, img, d#tileSize, cellPx)
                case None      => ()
            }
        } else ();
        drawGridLines(canvas, d#width, d#height, cellPx);
        if (vis#entities) drawEntities(canvas, d#entities, cellPx) else ();
        gc.restore()
    }

    /// AutoLayerWalls 層: wallMask[idx]=1 のセルを 4 近傍のマスクから TRBL を計算し、
    /// Material.wallMap[trbl] のタイル座標で tileset を切り出して描画する。
    /// マップ外は壁扱い (LDTKRules と同じ慣習)。
    def drawAutoLayerWalls(canvas: Canvas, d: MapResource.LevelData,
                            mat: MapResource.MaterialData, image: Image,
                            cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        let ts = Int32.toFloat64(d#tileSize);
        let cs = Int32.toFloat64(cellPx);
        List.forEach(idx -> {
            let col = Int32.remainder(idx, d#width);
            let row = idx / d#width;
            if (cellIsWall(d#wallMask, d#width, d#height, col, row)) {
                let key = trblKeyAt(d#wallMask, d#width, d#height, col, row);
                match Map.get(key, mat#wallMap) {
                    case None              => ()
                    case Some((srcX, srcY)) => {
                        let sx = Int32.toFloat64(srcX);
                        let sy = Int32.toFloat64(srcY);
                        let dx = Int32.toFloat64(col) * cs;
                        let dy = Int32.toFloat64(row) * cs;
                        gc.drawImage(image, sx, sy, ts, ts, dx, dy, cs, cs)
                    }
                }
            } else ()
        }, List.range(0, d#width * d#height))
    }

    /// (col, row) の TRBL 4-bit キー文字列 ("TRBL" 順)。
    /// マップ外は壁扱い (1)。隣接セルの wallMask=1 を 1、=0 を 0 とする。
    pub def trblKeyAt(mask: Vector[Int32], width: Int32, height: Int32,
                        col: Int32, row: Int32): String = {
        let t = if (neighborIsWall(mask, width, height, col,     row - 1)) "1" else "0";
        let r = if (neighborIsWall(mask, width, height, col + 1, row    )) "1" else "0";
        let b = if (neighborIsWall(mask, width, height, col,     row + 1)) "1" else "0";
        let l = if (neighborIsWall(mask, width, height, col - 1, row    )) "1" else "0";
        t + r + b + l
    }

    /// 隣接セル判定。マップ外は壁扱い (true)。
    def neighborIsWall(mask: Vector[Int32], width: Int32, height: Int32,
                        col: Int32, row: Int32): Bool =
        if (col < 0 or col >= width or row < 0 or row >= height) true
        else cellIsWall(mask, width, height, col, row)

    /// (col, row) のセルが壁か (wallMask=1) を返す。範囲外は false (壁ではない素のセル)。
    def cellIsWall(mask: Vector[Int32], width: Int32, _height: Int32,
                    col: Int32, row: Int32): Bool = {
        let idx = row * width + col;
        match Vector.nth(idx, mask) {
            case Some(v) => v != 0i32
            case None    => false
        }
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
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                canvas.requestFocus();
                handleClick(state, event)
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
                // isShortcutDown() = Cmd (macOS) または Ctrl (Win/Linux)
                if (event.isShortcutDown() and event.getCode().toString() == "Z") {
                    doUndo(state);
                    event.consume()
                } else ()
            }
        })
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
                        case MapEditorState.LayerMode.AutoLayerWalls =>
                            if (isRight) Some(removeAutoLayerWallAt(level, d, col, row))
                            else Some(placeAutoLayerWallAt(level, d, col, row))
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

    /// Walls レイヤーへの配置: manualTiles に追加のみ (wallMask には触らない)。
    /// 衝突は AutoLayerWalls 層の wallMask で決まり、Walls は AutoLayerWalls の上書き装飾。
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

    /// Walls レイヤーからの除去: manualTiles の同セル全消去 (wallMask には触らない)。
    pub def removeWallTileAt(level: MapResource.Level, d: MapResource.LevelData,
                               col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#manualTiles);
        let newData: MapResource.LevelData = {manualTiles = filtered | d};
        MapResource.Level.Level(newData)

    /// AutoLayerWalls レイヤーへの配置: wallMask[idx]=1。manualTiles は触らない。
    /// タイル絵は Material.wallMap から実行時に解決されるので Level には書き込まない。
    pub def placeAutoLayerWallAt(level: MapResource.Level, d: MapResource.LevelData,
                                   col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let newMask = setMaskAt(d#wallMask, d#width, col, row, 1i32);
        let newData: MapResource.LevelData = {wallMask = newMask | d};
        MapResource.Level.Level(newData)

    /// AutoLayerWalls レイヤーからの除去: wallMask[idx]=0。manualTiles は触らない。
    pub def removeAutoLayerWallAt(level: MapResource.Level, d: MapResource.LevelData,
                                    col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let newMask = setMaskAt(d#wallMask, d#width, col, row, 0i32);
        let newData: MapResource.LevelData = {wallMask = newMask | d};
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

    /// wallMask の (col, row) を指定値にセットして新 Vector を返す。
    def setMaskAt(mask: Vector[Int32], width: Int32, col: Int32, row: Int32, value: Int32):
            Vector[Int32] =
        let idx = row * width + col;
        Vector.toList(mask)
            |> List.mapWithIndex((i, v) -> if (i == idx) value else v)
            |> List.toVector

    // ────────────────────────────────────────────────────────
    // IO ラッパ (state からパレット選択値を読んで pure 関数に渡す)
    // ────────────────────────────────────────────────────────

    def placeWallWithSelectedSrc(state: IdeState.IdeState, level: MapResource.Level,
                                   d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        match MapEditorState.getSelectedSrc(state#mapEditor) {
            case None               => None
            case Some((srcX, srcY)) => Some(placeWallTileAt(level, d, col, row, srcX, srcY))
        }

    def placeFloorWithSelectedSrc(state: IdeState.IdeState, level: MapResource.Level,
                                    d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        match MapEditorState.getSelectedSrc(state#mapEditor) {
            case None               => None
            case Some((srcX, srcY)) => Some(placeFloorTileAt(level, d, col, row, srcX, srcY))
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
                drawLevel(c, level, cellPx, wImg, fImg, vis, zoom, mat)
            }
            case None => ()
        }
}
