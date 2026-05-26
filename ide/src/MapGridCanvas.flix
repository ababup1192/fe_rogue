// MapGridCanvas — Maps タブ中央の JavaFX Canvas に Level の grid を描く。
//
// 描画レイヤー (下から上):
//   1. 背景 (ダークグレー)
//   2. WallMask=1 のセル (solid color)
//   3. grid 線 (薄い色)
//
// S9: grid のみ
// S10: WallMask 可視化を追加 ← 今
// S11 以降: マウスクリックで WallMask トグル / 保存 / autotile プレビュー

mod MapGridCanvas {
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.paint.Color
    import javafx.scene.input.MouseEvent
    import javafx.event.EventHandler

    /// 1 セルの表示ピクセル数。tileSize (=16 等) と独立に「IDE 上で見やすい大きさ」で持つ。
    pub def defaultCellPx(): Int32 = 24

    /// Level の中身 (背景 + WallMask + grid 線) を Canvas に描く。
    /// Canvas は Level サイズに合わせて resize される。
    pub def drawLevel(canvas: Canvas, level: MapResource.Level, cellPx: Int32): Unit \ IO = {
        let d = MapResource.levelData(level);
        resizeAndFill(canvas, d#width, d#height, cellPx);
        drawWallMask(canvas, d#wallMask, d#width, d#height, cellPx);
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

    /// WallMask の非ゼロセルを壁色 (オレンジ系) で塗る。床セルは何も描かず透明。
    /// マスは行優先: `mask[y * width + x]`。
    def drawWallMask(canvas: Canvas, mask: Vector[Int32],
                      width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        // 壁色: LDtk の inca_tileset 風オレンジを少し沈めた色
        gc.setFill(Color.rgb(180, 100, 60));
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
                let x = Int32.toFloat64(col) * cs;
                let y = Int32.toFloat64(row) * cs;
                gc.fillRect(x, y, cs, cs)
            } else ()
        }, cells)
    }

    /// grid 線を Canvas 全面に引く。WallMask 描画の上に乗せる。
    def drawGridLines(canvas: Canvas, width: Int32, height: Int32, cellPx: Int32): Unit \ IO = {
        let pixelW = Int32.toFloat64(width * cellPx);
        let pixelH = Int32.toFloat64(height * cellPx);
        let gc = canvas.getGraphicsContext2D();
        gc.setStroke(Color.rgb(80, 80, 90));
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
    /// ファイル保存はしない (S12 で追加予定)。
    pub def wireClickToggle(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO =
                handleClick(state, event)
        })
    }

    /// クリック座標から (col, row) を求め、WallMask を toggle して再描画。
    /// Level 未選択 or 範囲外クリックは何もしない。
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
                    let newLevel = MapResource.Level.Level(newData);
                    MapEditorState.setEditingLevel(state#mapEditor, Some(newLevel));
                    MapEditorState.setDirty(state#mapEditor, true);
                    match Array.get(0, state#widgets#mapGridCanvas) {
                        case Some(c) => drawLevel(c, newLevel, cellPx)
                        case None    => ()
                    }
                }
        }
}
