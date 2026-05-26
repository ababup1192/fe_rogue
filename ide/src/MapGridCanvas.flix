// MapGridCanvas — Maps タブ中央の JavaFX Canvas に Level の中身を描く。
//
// 描画レイヤー (下から上):
//   1. 背景 (ダークグレー)
//   2. decorTiles (Floor 層) — tilemap_floor PNG から実タイル描画
//   3. manualTiles (Walls 層) — inca_tileset PNG から実タイル描画
//   4. WallMask=1 のセル (半透明オレンジオーバーレイ)
//   5. grid 線 (薄い色)
//
// S9: grid のみ
// S10: WallMask 可視化
// S11: クリックトグル + 再描画
// S12: 保存ボタン連動
// S13: 実 tileset PNG で manualTiles / decorTiles 描画 ← 今

mod MapGridCanvas {
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.paint.Color
    import javafx.scene.input.MouseEvent
    import javafx.event.EventHandler

    /// 1 セルの表示ピクセル数。tileSize (=16 等) と独立に「IDE 上で見やすい大きさ」で持つ。
    pub def defaultCellPx(): Int32 = 24

    /// Level の中身を Canvas に描く。tileset Image が無い場合は壁色フォールバック。
    /// Canvas は Level サイズに合わせて resize される。
    pub def drawLevel(canvas: Canvas, level: MapResource.Level, cellPx: Int32,
                       wallsImg: Option[Image], floorImg: Option[Image]): Unit \ IO = {
        let d = MapResource.levelData(level);
        resizeAndFill(canvas, d#width, d#height, cellPx);
        match floorImg {
            case Some(img) => drawTiles(canvas, d#decorTiles, img, d#tileSize, cellPx)
            case None      => ()
        };
        match wallsImg {
            case Some(img) => drawTiles(canvas, d#manualTiles, img, d#tileSize, cellPx)
            case None      =>
                // tileset 未ロード時は壁色 (オレンジ) で WallMask を塗るフォールバック
                drawWallMaskSolid(canvas, d#wallMask, d#width, d#height, cellPx)
        };
        drawWallMaskOverlay(canvas, d#wallMask, d#width, d#height, cellPx);
        drawGridLines(canvas, d#width, d#height, cellPx)
    }

    /// Canvas を Level サイズにリサイズし、背景塗りつぶし。
    def resizeAndFill(canvas: Canvas, width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let pixelW = Int32.toFloat64(width * cellPx);
        let pixelH = Int32.toFloat64(height * cellPx);
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

    /// 半透明オレンジで WallMask=1 セルを強調表示 (タイル絵の上に乗せる)。
    /// 編集中の collision を視認するためのオーバーレイ。
    def drawWallMaskOverlay(canvas: Canvas, mask: Vector[Int32],
                             width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setFill(Color.rgb(255, 100, 50, 0.30));
        forEachWallCell(mask, width, height, cellPx, (x, y, cs) -> gc.fillRect(x, y, cs, cs))
    }

    /// tileset 未ロード時のフォールバック (S10 と同じ orange 単色塗り)。
    def drawWallMaskSolid(canvas: Canvas, mask: Vector[Int32],
                           width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        gc.setFill(Color.rgb(180, 100, 60));
        forEachWallCell(mask, width, height, cellPx, (x, y, cs) -> gc.fillRect(x, y, cs, cs))
    }

    /// wallMask の各 wall セルに対して f(x, y, cellSize) を呼ぶ。
    def forEachWallCell(mask: Vector[Int32], width: Int32, height: Int32, cellPx: Int32,
                         f: (Float64, Float64, Float64) -> Unit \ IO): Unit \ IO = {
        let cs = Int32.toFloat64(cellPx);
        let cells = List.range(0, width * height);
        List.forEach(i -> {
            let v = match Vector.nth(i, mask) {
                case Some(n) => n
                case None    => 0i32
            };
            if (v != 0i32) {
                let col = Int32.remainder(i, width);
                let row = i / width;
                f(Int32.toFloat64(col) * cs, Int32.toFloat64(row) * cs, cs)
            } else ()
        }, cells)
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

    /// Canvas に MouseClick handler を 1 度だけ登録する。
    /// クリック位置の (col, row) を計算して WallMask を toggle し、再描画する。
    pub def wireClickToggle(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO =
                handleClick(state, event)
        })
    }

    def handleClick(state: IdeState.IdeState, event: MouseEvent): Unit \ IO =
        match MapEditorState.getEditingLevel(state#mapEditor) {
            case None        => ()
            case Some(level) =>
                let d = MapResource.levelData(level);
                let cellPx = defaultCellPx();
                let cs = Int32.toFloat64(cellPx);
                let col = Float64.truncateToInt32(event.getX() / cs);
                let row = Float64.truncateToInt32(event.getY() / cs);
                if (col < 0 or col >= d#width or row < 0 or row >= d#height) ()
                else {
                    let mode = MapEditorState.getLayerMode(state#mapEditor);
                    // MouseButton enum 比較は Eq instance が無いので toString() でやる
                    let isRight = event.getButton().toString() == "SECONDARY";
                    let newLevelOpt = match mode {
                        case MapEditorState.LayerMode.Walls  => Some(toggleWall(level, d, col, row))
                        case MapEditorState.LayerMode.Manual =>
                            if (isRight)
                                Some(removeManualAt(level, d, col, row))
                            else
                                placeManualAt(state, level, d, col, row)
                    };
                    match newLevelOpt {
                        case None           => ()
                        case Some(newLevel) =>
                            MapEditorState.setEditingLevel(state#mapEditor, Some(newLevel));
                            MapEditorState.setDirty(state#mapEditor, true);
                            MapEditorPanel.updateDirtyLabel(state);
                            redrawCurrent(state, newLevel, cellPx)
                    }
                }
        }

    /// Walls モードでのトグル: 指定セルの wallMask を 0↔1 反転。
    def toggleWall(level: MapResource.Level, d: MapResource.LevelData,
                    col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let idx = row * d#width + col;
        let oldVal = match Vector.nth(idx, d#wallMask) {
            case Some(v) => v
            case None    => 0i32
        };
        let newVal = if (oldVal == 0i32) 1i32 else 0i32;
        let newMask = Vector.toList(d#wallMask)
            |> List.mapWithIndex((i, v) -> if (i == idx) newVal else v)
            |> List.toVector;
        let newData: MapResource.LevelData = {wallMask = newMask | d};
        MapResource.Level.Level(newData)

    /// Manual モードでの配置: 選択中タイルを ManualTile として追加 (同セル既存があれば置換)。
    /// パレットで未選択なら何もしない (None を返す)。
    def placeManualAt(state: IdeState.IdeState, level: MapResource.Level,
                       d: MapResource.LevelData, col: Int32, row: Int32):
            Option[MapResource.Level] \ IO =
        let _ = level;
        match MapEditorState.getSelectedSrc(state#mapEditor) {
            case None             => None
            case Some((srcX, srcY)) => {
                let newTile = ({
                    x = col, y = row,
                    srcX = srcX, srcY = srcY,
                    flipH = false, flipV = false
                }: MapResource.ManualTile);
                // 既存の同セルタイルを除去してから追加
                let filtered = List.filter(t -> not (t#x == col and t#y == row), d#manualTiles);
                let newTiles = List.append(filtered, newTile :: Nil);
                let newData: MapResource.LevelData = {manualTiles = newTiles | d};
                Some(MapResource.Level.Level(newData))
            }
        }

    /// Manual モードでの右クリック: 指定セルの ManualTile を全て除去。
    def removeManualAt(level: MapResource.Level, d: MapResource.LevelData,
                        col: Int32, row: Int32): MapResource.Level =
        let _ = level;
        let filtered = List.filter(t -> not (t#x == col and t#y == row), d#manualTiles);
        let newData: MapResource.LevelData = {manualTiles = filtered | d};
        MapResource.Level.Level(newData)

    /// 編集中 Level を canvas に再描画する。
    def redrawCurrent(state: IdeState.IdeState, level: MapResource.Level, cellPx: Int32): Unit \ IO =
        match Array.get(0, state#widgets#mapGridCanvas) {
            case Some(c) => {
                let wImg = Array.get(0, state#widgets#mapWallsImage);
                let fImg = Array.get(0, state#widgets#mapFloorImage);
                drawLevel(c, level, cellPx, wImg, fImg)
            }
            case None => ()
        }
}
