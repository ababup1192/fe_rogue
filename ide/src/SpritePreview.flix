// SpritePreview — Resources タブで texture アトラスのプレビューを描画するクラスタ。
// PropertyWidgets から切り出した「スプライトアトラスのプレビュー描画」専用 module。
//
// 提供するもの:
//   - SpriteRef: TexturePath 値 + sprite ブロック (frame/hframes/vframes/offset) の抽出結果
//   - findFirstSpriteRef / extractSpriteRefHere: record JSON から SpriteRef を見つける
//   - updateSpritePreview: SpriteRef から Image をロードしてセルを切り抜き Canvas に描画
//
// ズームモード (ZoomMode) は PropertyWidgets 側に残っているため、引数で受け取り
// PropertyWidgets.ZoomMode / PropertyWidgets.zoomModeLabel を参照する。

mod SpritePreview {
    import java.io.File
    import java.lang.{Object => JObject}
    import javafx.scene.image.Image
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.layout.StackPane
    import javafx.event.EventHandler
    import javafx.scene.input.MouseEvent
    import java.lang.Double
    import java.lang.Integer

    /// Sprite preview に渡す表示情報。
    ///   - texture:  textureNames に登録されている texture 名
    ///   - frame / hframes / vframes: 同じオブジェクト内に sibling として並ぶ
    ///     アトラス分割情報。sprite ブロックが無く texture だけの record では
    ///     全て None になり、preview 側で 1, 1, 0 にフォールバックして
    ///     画像全体を表示する。
    ///   - offsetX / offsetY: 同じ object 内に `"offset": {"x": ..., "y": ...}`
    ///     としてあれば取り出す。preview ではセルクロップ後の描画位置にオフセットを
    ///     image-pixel 単位で加算する（zoom と同じスケールで拡大される）。
    pub type alias SpriteRef = {
        texture  = String,
        frame    = Option[Int32],
        hframes  = Option[Int32],
        vframes  = Option[Int32],
        offsetX  = Float64,
        offsetY  = Float64
    }

    /// アトラス preview の描画状態をまとめた record。
    /// wirePanDrag と drawFullSheetWithSelection の共通引数集合
    /// (gc/image/hframes/vframes/frame/imgW/imgH/canvasW/canvasH/zoomMode/showGrid)。
    /// imgW/imgH/canvasW/canvasH の Float64 4 連続を名前付きで束ねて取り違えを防ぐ。
    /// canvas (wirePanDrag のみ) と panX/panY (drawFullSheetWithSelection のみ) は
    /// 共通でないため各関数の別引数として残す。
    type alias AtlasDrawState = {
        gc       = GraphicsContext,
        image    = Image,
        hframes  = Int32,
        vframes  = Int32,
        frame    = Int32,
        imgW     = Float64,
        imgH     = Float64,
        canvasW  = Float64,
        canvasH  = Float64,
        zoomMode = PropertyWidgets.ZoomMode,
        showGrid = Bool
    }

    /// record JSON を DFS で walk して、textureNames に含まれる文字列値を持つ
    /// 最初のオブジェクトを見つけ、その texture と sibling の frame/hframes/vframes
    /// (もし存在すれば) をまとめて SpriteRef として返す。
    /// sprite ブロックを持たない bare texture record では frame 系が全て None に
    /// なり、updateSpritePreview のフォールバックで全体表示と等価になる。
    pub def findFirstSpriteRef(record: Json.JsonElement, textureNames: List[String]):
            Option[SpriteRef] = {
        let names = List.toSet(textureNames);
        scanForSpriteRef(record, names)
    }

    def scanForSpriteRef(elem: Json.JsonElement, textureNames: Set[String]):
            Option[SpriteRef] =
        match elem {
            case Json.JsonElement.JsonObject(m) =>
                // この object 自身が texture フィールドを持っていれば
                // sibling (frame/hframes/vframes) を一緒に拾って即返す
                match extractSpriteRefHere(m, textureNames) {
                    case Some(spriteRef) => Some(spriteRef)
                    case None            =>
                        Map.foldLeftWithKey((acc, _k, v) -> match acc {
                            case Some(_) => acc
                            case None    => scanForSpriteRef(v, textureNames)
                        }, None, m)
                }
            case _ => None
        }

    /// JsonObject 内で「textureNames に含まれる文字列値を持つフィールド」を 1 つ
    /// 見つけたら、その object 自身の frame/hframes/vframes (整数) も sibling
    /// として抜き出して SpriteRef を作る。
    /// texture を保持しているキーの名前は問わない (sprite ブロック内なら "texture"
    /// だが key 名に依存しない設計)。frame/hframes/vframes が無い、または整数で
    /// ない場合はそれぞれ None として返す。
    pub def extractSpriteRefHere(m: Map[String, Json.JsonElement], textureNames: Set[String]):
            Option[SpriteRef] =
        let entries = Map.toList(m);
        let textureOpt = List.findMap(entry -> {
            let (_k, v) = entry;
            match v {
                case Json.JsonElement.JsonString(s) =>
                    if (Set.memberOf(s, textureNames)) Some(s) else None
                case _ => None
            }
        }, entries);
        match textureOpt {
            case None          => None
            case Some(texture) =>
                let frame   = Map.get("frame",   m) |> Option.flatMap(NodeInspector.jsonToInt);
                let hframes = Map.get("hframes", m) |> Option.flatMap(NodeInspector.jsonToInt);
                let vframes = Map.get("vframes", m) |> Option.flatMap(NodeInspector.jsonToInt);
                let (ox, oy) = extractOffset(m);
                Some({
                    texture = texture,
                    frame   = frame,
                    hframes = hframes,
                    vframes = vframes,
                    offsetX = ox,
                    offsetY = oy
                })
        }

    /// `"offset": {"x": Float, "y": Float}` の sibling から (offsetX, offsetY) を抜き出す。
    /// 無ければ (0, 0)。
    def extractOffset(m: Map[String, Json.JsonElement]): (Float64, Float64) =
        match Map.get("offset", m) {
            case Some(Json.JsonElement.JsonObject(om)) =>
                let x = Map.get("x", om) |> Option.flatMap(NodeInspector.jsonToFloat)
                          |> Option.getWithDefault(0.0);
                let y = Map.get("y", om) |> Option.flatMap(NodeInspector.jsonToFloat)
                          |> Option.getWithDefault(0.0);
                (x, y)
            case _ => (0.0, 0.0)
        }

    /// SpriteRef から絶対パスを引いて JavaFX Image をロードし、frame/hframes/vframes
    /// が指定されていればその 1 セル分だけを Canvas にコピーして表示する。
    /// None なら "(no preview)" 表示。`pathMap` は texture 名 → 絶対パスの解決マップ。
    /// 切り抜き式は engine 側の Sprite2D.computeUv と同じ:
    ///   cellW = imgW / hframes, cellH = imgH / vframes,
    ///   col = frame % hframes,  row = frame / hframes,
    ///   srcRect = (col * cellW, row * cellH, cellW, cellH)
    /// frame 系が None または不正値のときは画像全体を表示する (sprite ブロックなしの
    /// bare texture record も同じ経路でフォールバック)。
    /// Canvas を使うのは GraphicsContext.setImageSmoothing(false) で
    /// nearest-neighbor 描画を明示的に効かせるため (ImageView.setSmooth(false) は
    /// JavaFX の Prism レンダラ環境で効かないケースがあるため避ける)。
    /// 永続 canvas に preview を描画する。pane はピンチハンドラの target である canvas を
    /// scene graph に保持させたままにしたいので、ここでは pane.getChildren() を **触らない**。
    /// 「no preview」「path unknown」状態は status label で示す（canvas は空 = 暗背景になる）。
    pub def updateSpritePreview(pane: StackPane, persistentCanvas: Canvas,
                                 pathMap: Map[String, String],
                                 spriteRef: Option[SpriteRef],
                                 zoomMode: PropertyWidgets.ZoomMode,
                                 showGrid: Bool,
                                 frameAdjust: Bool,
                                 panOffset: (Float64, Float64),
                                 getCurrentPan: Unit -> (Float64, Float64) \ IO,
                                 onPanCommit: ((Float64, Float64)) -> Unit \ IO,
                                 onStatus: String -> Unit \ IO): Unit \ IO = {
        // canvas のサイズは pane に追従させる（window resize で見える範囲が増減）
        let paneW = pane.getWidth();
        let paneH = pane.getHeight();
        let canvasW = if (paneW > 16.0) paneW else 220.0;
        let canvasH = if (paneH > 16.0) paneH else 220.0;
        if (Float64.abs(persistentCanvas.getWidth() - canvasW) > 0.5)
            persistentCanvas.setWidth(canvasW)
        else ();
        if (Float64.abs(persistentCanvas.getHeight() - canvasH) > 0.5)
            persistentCanvas.setHeight(canvasH)
        else ();
        let gc: GraphicsContext = persistentCanvas.getGraphicsContext2D();
        gc.setImageSmoothing(false);
        gc.clearRect(0.0, 0.0, canvasW, canvasH);

        match spriteRef {
            case None => onStatus("(no preview)")
            case Some(sr) => {
                match Map.get(sr#texture, pathMap) {
                    case None => onStatus("(path unknown: ${sr#texture})")
                    case Some(absPath) => {
                        let url = new File(absPath).toURI().toString();
                        let image = new Image(url);
                        let hframes = sr#hframes |> Option.getWithDefault(1i32);
                        let vframes = sr#vframes |> Option.getWithDefault(1i32);
                        let frame   = sr#frame   |> Option.getWithDefault(0i32);
                        let imgW = image.getWidth();
                        let imgH = image.getHeight();
                        onStatus(formatSpriteStatus(imgW, imgH, hframes, vframes, zoomMode));
                        let (panX, panY) = panOffset;
                        let fullSheetMode = frameAdjust and hframes > 0i32 and vframes > 0i32
                                              and imgW > 0.0 and imgH > 0.0;
                        let atlasDraw = {
                            gc = gc, image = image, hframes = hframes, vframes = vframes,
                            frame = frame, imgW = imgW, imgH = imgH,
                            canvasW = canvasW, canvasH = canvasH,
                            zoomMode = zoomMode, showGrid = showGrid
                        };
                        if (fullSheetMode) {
                            drawFullSheetWithSelection(atlasDraw, panX, panY)
                        } else {
                            drawSingleCell(gc, image, sr, hframes, vframes, frame,
                                            imgW, imgH, canvasW, canvasH, zoomMode, showGrid)
                        };
                        // フレーム調整モードでのみドラッグ pan を有効化（毎回 set し直す = 直近フレームの座標で更新）。
                        // ピンチハンドラは ResourcePanel.wirePreviewPinchZoom で永続 canvas に 1 回だけ登録済み。
                        if (fullSheetMode) {
                            wirePanDrag(persistentCanvas, atlasDraw, getCurrentPan, onPanCommit)
                        } else ()
                    }
                }
            }
        }
    }

    /// Preview 下の status label に出す「セル native px / Zoom」文字列。
    /// resource に scale を持たせない方針なので、純粋にアトラスのピクセル情報のみ表示
    def formatSpriteStatus(imgW: Float64, imgH: Float64, hframes: Int32, vframes: Int32,
                            zoomMode: PropertyWidgets.ZoomMode): String = {
        let hfSafe = if (hframes > 0i32) hframes else 1i32;
        let vfSafe = if (vframes > 0i32) vframes else 1i32;
        let cellW = imgW / Int32.toFloat64(hfSafe);
        let cellH = imgH / Int32.toFloat64(vfSafe);
        let cellWi = Float64.tryToInt32(cellW) |> Option.getWithDefault(0i32);
        let cellHi = Float64.tryToInt32(cellH) |> Option.getWithDefault(0i32);
        let zoomStr = PropertyWidgets.zoomModeLabel(zoomMode);
        "セル: ${cellWi}×${cellHi} px ／ Zoom: ${zoomStr}"
    }

    /// フレーム調整モードの canvas にマウスドラッグ pan を貼る。
    /// 押下時の (mouse, pan) を closure-capture した Static Array に記録し、
    /// drag のたびに新 pan を計算して同じ canvas に直接 redraw する。
    /// onPanCommit は ResourceState を更新し、後続の updateSpritePreview 呼び出しが
    /// 新しい pan を反映できるようにする
    def wirePanDrag(canvas: Canvas, draw: AtlasDrawState,
                     getCurrentPan: Unit -> (Float64, Float64) \ IO,
                     onPanCommit: ((Float64, Float64)) -> Unit \ IO): Unit \ IO = {
        // ドラッグ起点: 押下時のマウス座標と pan 値を保持する。
        // 初期 0.0 はダミー — 実際の値は MOUSE_PRESSED で setReplace される
        let startMouseX = Array#{0.0} @ Static;
        let startMouseY = Array#{0.0} @ Static;
        let startPanX = Array#{0.0} @ Static;
        let startPanY = Array#{0.0} @ Static;
        canvas.setOnMousePressed(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                Array.put(e.getX(), 0, startMouseX);
                Array.put(e.getY(), 0, startMouseY);
                // 押下のたびに ResourceState から最新 pan を取り直す。
                // これで 2 回目以降のドラッグストロークでも累積した pan を起点にできる
                let (curX, curY) = getCurrentPan();
                Array.put(curX, 0, startPanX);
                Array.put(curY, 0, startPanY)
            }
        });
        canvas.setOnMouseDragged(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                let dx = e.getX() - Array.get(0, startMouseX);
                let dy = e.getY() - Array.get(0, startMouseY);
                let newPanX = Array.get(0, startPanX) + dx;
                let newPanY = Array.get(0, startPanY) + dy;
                onPanCommit((newPanX, newPanY));
                // 同じ canvas 上に直接 redraw (children.clear はしない)
                drawFullSheetWithSelection(draw, newPanX, newPanY)
            }
        })
    }

    /// 既存挙動: 選択フレーム 1 セルだけを切り抜いて中央描画。offset と zoom を反映。
    /// hframes/vframes が無効値のときは画像全体を表示するフォールバックを兼ねる
    def drawSingleCell(gc: GraphicsContext, image: Image, sr: SpriteRef,
                        hframes: Int32, vframes: Int32, frame: Int32,
                        imgW: Float64, imgH: Float64,
                        canvasW: Float64, canvasH: Float64,
                        zoomMode: PropertyWidgets.ZoomMode, showGrid: Bool): Unit \ IO = {
        gc.clearRect(0.0, 0.0, canvasW, canvasH);
        let (srcX, srcY, srcW, srcH) =
            if (hframes > 0i32 and vframes > 0i32 and imgW > 0.0 and imgH > 0.0) {
                let cellW = imgW / Int32.toFloat64(hframes);
                let cellH = imgH / Int32.toFloat64(vframes);
                let col   = Int32.modulo(frame, hframes);
                let row   = frame / hframes;
                (Int32.toFloat64(col) * cellW,
                 Int32.toFloat64(row) * cellH,
                 cellW, cellH)
            } else (0.0, 0.0, imgW, imgH);
        let scale = if (srcW <= 0.0 or srcH <= 0.0) 1.0 else
            match zoomMode {
                case PropertyWidgets.ZoomMode.Percent(p) => p / 100.0
            };
        let dstW = srcW * scale;
        let dstH = srcH * scale;
        let dstX = (canvasW - dstW) / 2.0 + sr#offsetX * scale;
        let dstY = (canvasH - dstH) / 2.0 + sr#offsetY * scale;
        gc.drawImage(image, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH);
        if (showGrid) drawPreviewGrid(gc, canvasW, canvasH, dstW, dstH)
        else ()
    }

    /// フレーム調整モード: texture 全体を fit-scale * zoom% で描画し、選択フレーム以外を
    /// 半透明黒でディマー、選択フレームを再描画して 100% 不透明に戻し、黄色枠でハイライト。
    /// offset は適用しない (アトラス上の物理セル位置を見せる用途のため)
    def drawFullSheetWithSelection(draw: AtlasDrawState,
                                    panX: Float64, panY: Float64): Unit \ IO = {
        let gc = draw#gc;
        let image = draw#image;
        let hframes = draw#hframes;
        let vframes = draw#vframes;
        let frame = draw#frame;
        let imgW = draw#imgW;
        let imgH = draw#imgH;
        let canvasW = draw#canvasW;
        let canvasH = draw#canvasH;
        let zoomMode = draw#zoomMode;
        let showGrid = draw#showGrid;
        gc.clearRect(0.0, 0.0, canvasW, canvasH);
        let fitScale = Float64.min(canvasW / imgW, canvasH / imgH);
        let zoomMul = match zoomMode {
            case PropertyWidgets.ZoomMode.Percent(p) => p / 100.0
        };
        let effScale = fitScale * zoomMul;
        let sheetW = imgW * effScale;
        let sheetH = imgH * effScale;

        let cellW = imgW / Int32.toFloat64(hframes);
        let cellH = imgH / Int32.toFloat64(vframes);
        let safeFrame = if (frame < 0i32) 0i32 else frame;
        let col = Int32.modulo(safeFrame, hframes);
        let row = safeFrame / hframes;
        let srcX = Int32.toFloat64(col) * cellW;
        let srcY = Int32.toFloat64(row) * cellH;
        let cellDstW = cellW * effScale;
        let cellDstH = cellH * effScale;
        // 選択セル中心 + ユーザーの drag pan を canvas 中心に配置する。
        // pan は canvas pixel 単位、zoom に応じて拡縮しない (ドラッグ感覚を保つため)
        let cellCx = (Int32.toFloat64(col) + 0.5) * cellW * effScale;
        let cellCy = (Int32.toFloat64(row) + 0.5) * cellH * effScale;
        let dstX0 = canvasW / 2.0 - cellCx + panX;
        let dstY0 = canvasH / 2.0 - cellCy + panY;
        let cellDstX = dstX0 + srcX * effScale;
        let cellDstY = dstY0 + srcY * effScale;

        // 1. full sheet
        gc.drawImage(image, 0.0, 0.0, imgW, imgH, dstX0, dstY0, sheetW, sheetH);
        // 2. dim overlay (~65% black)
        let dim = FxColor.color(0.0, 0.0, 0.0, 0.65);
        gc.setFill(dim);
        gc.fillRect(dstX0, dstY0, sheetW, sheetH);
        // 3. selected cell at full opacity (frame が grid 内に収まるときだけ)
        let frameInGrid = row < vframes;
        if (frameInGrid) {
            gc.drawImage(image, srcX, srcY, cellW, cellH, cellDstX, cellDstY, cellDstW, cellDstH)
        } else ();
        // 4. atlas grid lines (if showGrid)
        if (showGrid) drawAtlasGrid(gc, dstX0, dstY0, sheetW, sheetH, hframes, vframes)
        else ();
        // 5. selection outline (grid 内のときだけ)
        if (frameInGrid) {
            let yellow = FxColor.color(1.0, 0.85, 0.0);
            gc.setStroke(yellow);
            gc.setLineWidth(2.0);
            gc.strokeRect(cellDstX, cellDstY, cellDstW, cellDstH)
        } else ()
    }

    /// アトラス全体の hframes × vframes セル境界線を半透明白で描く。
    /// drawPreviewGrid (中央十字 + cell 単独) と用途が異なる: フレーム調整モードで
    /// 「全セルの分割位置」を可視化するためのもの
    def drawAtlasGrid(gc: GraphicsContext, dstX0: Float64, dstY0: Float64,
                       sheetW: Float64, sheetH: Float64,
                       hframes: Int32, vframes: Int32): Unit \ IO = {
        let line = FxColor.color(1.0, 1.0, 1.0, 0.4);
        gc.setStroke(line);
        gc.setLineWidth(1.0);
        let cellW = sheetW / Int32.toFloat64(hframes);
        let cellH = sheetH / Int32.toFloat64(vframes);
        // 縦線 (hframes - 1 本)
        List.range(1i32, hframes) |> List.forEach(i -> {
            let x = dstX0 + Int32.toFloat64(i) * cellW;
            gc.strokeLine(x, dstY0, x, dstY0 + sheetH)
        });
        // 横線 (vframes - 1 本)
        List.range(1i32, vframes) |> List.forEach(j -> {
            let y = dstY0 + Int32.toFloat64(j) * cellH;
            gc.strokeLine(dstX0, y, dstX0 + sheetW, y)
        })
    }

    /// プレビュー用の補助グリッド。canvas の中央十字（赤）と「offset=0 のときの
    /// セル矩形」（白）を上に重ねて描く。中央合わせの目視確認に使う。
    def drawPreviewGrid(gc: GraphicsContext, canvasW: Float64, canvasH: Float64,
                         cellW: Float64, cellH: Float64): Unit \ IO = {
        let red   = FxColor.color(1.0, 0.0, 0.0);
        let white = FxColor.color(1.0, 1.0, 1.0);
        let cx = canvasW / 2.0;
        let cy = canvasH / 2.0;
        // 1. cell 矩形（offset=0 で中央寄せした場合の位置）= 白
        gc.setStroke(white);
        gc.setLineWidth(1.0);
        let cellX = cx - cellW / 2.0;
        let cellY = cy - cellH / 2.0;
        gc.strokeRect(cellX, cellY, cellW, cellH);
        // 2. 中央十字 = 赤
        gc.setStroke(red);
        gc.setLineWidth(1.0);
        gc.strokeLine(0.0, cy, canvasW, cy);
        gc.strokeLine(cx, 0.0, cx, canvasH)
    }
}
