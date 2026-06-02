// SpriteFramesEditor — AnimatedSprite2D 用の spriteFrames アニメ編集 widget クラスタ。
// PropertyWidgets から切り出した。dispatch は PropertyWidgets.buildFieldWidget の
// SpriteFramesT ケースから buildSpriteFramesEditorWidget を呼ぶ。
//
// 編集対象 JSON 形式（authoring 形式）:
//   {
//     "idle":      { "loop": true, "speed": 4.0,
//                    "frames": [{ "frame": 0, "duration": 1.0 }] },
//     "walk_down": { ... }
//   }
//
// 各 frame は `sprite.hframes × sprite.vframes` 分割の格子に対する
// 0-origin row-major インデックス。texture は sprite.texture を共有。
//
// 共有ヘルパー (roundTo3 / roundedDoubleConverter / Commit) は PropertyWidgets 側に残り、
// ここからは PropertyWidgets. で修飾して参照する。

mod SpriteFramesEditor {
    import java.io.File
    import java.lang.{Object => JObject}
    import java.math.{BigDecimal => JBigDecimal}
    import javafx.scene.Node
    import javafx.scene.image.Image
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.control.Label
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.paint.{Color => FxColor}
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.geometry.Pos
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import java.lang.Double
    import java.lang.Integer

    /// spriteFrames anim の 1 フレーム分 (frame index と表示秒数)。
    /// currentFrame / parseFrameJson / currentFramesList の共通戻り値型。
    type alias FrameEntry = {frame = Int32, duration = Float64}

    // ════════════════════════════════════════════════════════════════════════
    // SpriteFramesT widget — grid インデックス形式の AnimatedSprite2D エディタ
    //
    // UI 構成:
    //   ┌──────────────────────────────┐
    //   │ アニメ: [idle ▼] [+] [-]        │
    //   │ ループ: ☑   速度: [4.0]          │
    //   │ フレーム: [+] [-]                │
    //   │   ┌──────────────┐              │
    //   │   │ frame 0 (1.0)│              │
    //   │   │ frame 1 (1.0)│              │
    //   │   └──────────────┘              │
    //   │ 選択中: frame [0] duration [1.0]│
    //   │ [Atlas preview: 選択 cell 強調]  │
    //   └──────────────────────────────┘
    //
    // sibling 参照: rootRecord から sprite.{texture, hframes, vframes} を読む。
    // ════════════════════════════════════════════════════════════════════════

    pub def buildSpriteFramesEditorWidget(value: Option[Json.JsonElement],
                                            rootRecord: Json.JsonElement,
                                            texturePathMap: Map[String, String],
                                            commit: PropertyWidgets.Commit): Node \ IO = {
        // sibling sprite.{texture, hframes, vframes} を読む（preview と frame max のため）
        let sib = extractSpriteSiblings(rootRecord);
        let hframes = sib#hframes;
        let vframes = sib#vframes;
        let textureName = sib#texture;
        let maxFrameIdx =
            if (hframes > 0 and vframes > 0) hframes * vframes - 1
            else 9999;

        // 可変 state
        let initialAnims = parseAnimsMap(value);
        let initialNames = Set.toList(Map.keysOf(initialAnims));
        let initialSelected = match List.head(initialNames) {
            case Some(n) => n
            case None    => ""
        };
        let animsRef: Array[Map[String, Json.JsonElement], Static] =
            Array.empty(Static, 1);
        Array.put(initialAnims, 0, animsRef);
        let selectedRef: Array[String, Static] = Array.empty(Static, 1);
        Array.put(initialSelected, 0, selectedRef);

        // UI 構築
        let outer = new VBox(4.0);
        outer.setMaxWidth(280.0);
        // (1) アニメ選択 ComboBox
        let animCombo: ComboBox[String] = new ComboBox();
        let comboItems = animCombo.getItems();
        List.forEach(n -> discard comboItems.add(n), initialNames);
        animCombo.setEditable(false);
        animCombo.setPrefWidth(180.0);
        if (String.length(initialSelected) > 0) animCombo.setValue(initialSelected) else ();
        let animComboNode: Node = checked_cast(animCombo);
        let comboRow = labeledRow("アニメ:", animComboNode);
        let comboRowNode: Node = checked_cast(comboRow);
        discard outer.getChildren().add(comboRowNode);

        // (2) 編集 row: frame index (Spinner[Integer]) + duration (Spinner[Double])
        // 先頭フレーム (frames[0]) のみを GUI で編集する MVP。
        // 多フレームアニメを使いたい場合は JSON を直接編集する。
        let init = currentFirstFrame(initialAnims, initialSelected);
        let frameSpinner: Spinner[Integer] =
            new Spinner(0i32, maxFrameIdx, init#frame);
        frameSpinner.setEditable(true);
        frameSpinner.setPrefWidth(80.0);
        let durSpinner: Spinner[Double] = new Spinner(0.0, 99.0, init#duration, 0.5);
        durSpinner.setEditable(true);
        durSpinner.setPrefWidth(80.0);
        durSpinner.getValueFactory().setConverter(PropertyWidgets.roundedDoubleConverter());

        let editRow = new HBox(6.0);
        editRow.setAlignment(Pos.CENTER_LEFT);
        let editChildren = editRow.getChildren();
        let frameLabelNode: Node = checked_cast(new Label("frame"));
        let frameSpinnerNode: Node = checked_cast(frameSpinner);
        let durLabelNode: Node = checked_cast(new Label("dur"));
        let durSpinnerNode: Node = checked_cast(durSpinner);
        discard editChildren.add(frameLabelNode);
        discard editChildren.add(frameSpinnerNode);
        discard editChildren.add(durLabelNode);
        discard editChildren.add(durSpinnerNode);
        let editRowNode: Node = checked_cast(editRow);
        discard outer.getChildren().add(editRowNode);

        // (3) preview canvas: 選択フレームのセルを黄色枠でハイライト
        let canvas = new Canvas(260.0, 100.0);
        let canvasNode: Node = checked_cast(canvas);
        discard outer.getChildren().add(canvasNode);

        // 描画ヘルパ
        let redraw = () -> {
            let anims = Array.get(0, animsRef);
            let sel   = Array.get(0, selectedRef);
            let f     = currentFirstFrame(anims, sel);
            drawSpriteGridPreview(canvas, texturePathMap, textureName,
                                    hframes, vframes, f#frame)
        };
        // anim 選択変更時: spinner 値を新 anim の先頭 frame に合わせ、canvas 再描画
        animCombo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_t: ChangeListener[String], _o: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    Array.put(newVal, 0, selectedRef);
                    let anims = Array.get(0, animsRef);
                    let f     = currentFirstFrame(anims, newVal);
                    frameSpinner.getValueFactory().setValue(Integer.valueOf(f#frame));
                    durSpinner.getValueFactory().setValue(Double.valueOf(f#duration));
                    redraw()
                }
            }
        });
        // frame index 変更時: 選択 anim の frames[0].frame を書き換え、commit + redraw
        frameSpinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_t: ChangeListener[Integer], _o: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let sel = Array.get(0, selectedRef);
                    if (String.length(sel) == 0) ()
                    else {
                        let anims = Array.get(0, animsRef);
                        let v: Int32 = newVal.intValue();
                        let updated = setFrameField(anims, sel, 0i32, "frame",
                                                      Json.JsonElement.JsonNumber(intToBd(v)));
                        Array.put(updated, 0, animsRef);
                        commit(Json.JsonElement.JsonObject(updated));
                        redraw()
                    }
                }
            }
        });
        // duration 変更時: 選択 anim の frames[0].duration を書き換え、commit
        durSpinner.valueProperty().addListener(new ChangeListener[Double] {
            def changed(_t: ChangeListener[Double], _o: ObservableValue[JObject],
                         _old: Double, newVal: Double): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let sel = Array.get(0, selectedRef);
                    if (String.length(sel) == 0) ()
                    else {
                        let anims = Array.get(0, animsRef);
                        let v = PropertyWidgets.roundTo3(newVal.doubleValue());
                        let updated = setFrameField(anims, sel, 0i32, "duration",
                                                      Json.JsonElement.JsonNumber(floatToBdRounded(v)));
                        Array.put(updated, 0, animsRef);
                        commit(Json.JsonElement.JsonObject(updated))
                    }
                }
            }
        });

        // 初回描画
        redraw();
        checked_cast(outer)
    }

    /// HBox に [Label][widget] を並べる小ヘルパー
    def labeledRow(label: String, widget: Node): HBox \ IO = {
        let row = new HBox(6.0);
        row.setAlignment(Pos.CENTER_LEFT);
        let children = row.getChildren();
        let labelNode: Node = checked_cast(new Label(label));
        discard children.add(labelNode);
        discard children.add(widget);
        row
    }

    /// 選択 anim の frames[0] を取り出す。frames が空 / anim が無いなら {frame=0, duration=1.0}。
    def currentFirstFrame(anims: Map[String, Json.JsonElement], sel: String):
            FrameEntry =
        currentFrame(anims, sel, 0i32)

    /// spriteFrames JSON object を anim 名 → JSON の Map に解す。
    /// JsonObject 以外は空 Map (= 編集不能だが widget は表示される)。
    def parseAnimsMap(v: Option[Json.JsonElement]): Map[String, Json.JsonElement] =
        match v {
            case Some(Json.JsonElement.JsonObject(m)) => m
            case _                                     => Map.empty()
        }

    /// rootRecord (ユニット全体の JSON) から `sprite.{texture, hframes, vframes}` を抽出。
    /// 欠落時は空文字列 / 0 を埋める。
    def extractSpriteSiblings(rootRecord: Json.JsonElement):
            {texture = String, hframes = Int32, vframes = Int32} =
        match rootRecord {
            case Json.JsonElement.JsonObject(rec) =>
                match Map.get("sprite", rec) {
                    case Some(Json.JsonElement.JsonObject(sp)) =>
                        let tex = match Map.get("texture", sp) {
                            case Some(Json.JsonElement.JsonString(s)) => s
                            case _ => ""
                        };
                        let hf = match Map.get("hframes", sp) {
                            case Some(Json.JsonElement.JsonNumber(bd)) =>
                                BigDecimal.tryToFloat64(bd)
                                    |> Option.flatMap(Float64.tryToInt32)
                                    |> Option.getWithDefault(0i32)
                            case _ => 0i32
                        };
                        let vf = match Map.get("vframes", sp) {
                            case Some(Json.JsonElement.JsonNumber(bd)) =>
                                BigDecimal.tryToFloat64(bd)
                                    |> Option.flatMap(Float64.tryToInt32)
                                    |> Option.getWithDefault(0i32)
                            case _ => 0i32
                        };
                        {texture = tex, hframes = hf, vframes = vf}
                    case _ => {texture = "", hframes = 0i32, vframes = 0i32}
                }
            case _ => {texture = "", hframes = 0i32, vframes = 0i32}
        }

    /// 選択 anim の frames を `{frame, duration}` のリストとして取り出す。
    def currentFramesList(anims: Map[String, Json.JsonElement], sel: String):
            List[FrameEntry] =
        match Map.get(sel, anims) {
            case Some(Json.JsonElement.JsonObject(animMap)) =>
                match Map.get("frames", animMap) {
                    case Some(Json.JsonElement.JsonArray(arr)) =>
                        Vector.toList(arr) |> List.map(parseFrameJson)
                    case _ => Nil
                }
            case _ => Nil
        }

    def parseFrameJson(frameJson: Json.JsonElement): FrameEntry =
        match frameJson {
            case Json.JsonElement.JsonObject(fm) =>
                let fIdx = match Map.get("frame", fm) {
                    case Some(Json.JsonElement.JsonNumber(bd)) =>
                        BigDecimal.tryToFloat64(bd)
                            |> Option.flatMap(Float64.tryToInt32)
                            |> Option.getWithDefault(0i32)
                    case _ => 0i32
                };
                let dur = match Map.get("duration", fm) {
                    case Some(Json.JsonElement.JsonNumber(bd)) =>
                        BigDecimal.tryToFloat64(bd) |> Option.getWithDefault(1.0)
                    case _ => 1.0
                };
                {frame = fIdx, duration = dur}
            case _ => {frame = 0i32, duration = 1.0}
        }

    /// 選択 anim の frames[idx] を取り出す。範囲外なら {frame=0, duration=1.0}。
    def currentFrame(anims: Map[String, Json.JsonElement], sel: String, idx: Int32):
            FrameEntry =
        let frames = currentFramesList(anims, sel);
        match List.nth(idx, frames) {
            case Some(f) => f
            case None    => {frame = 0i32, duration = 1.0}
        }

    /// 指定 anim の frames[idx].key を上書きする。
    /// 多フレーム対応用に idx 引数を取るが、MVP widget では idx=0 固定で呼ぶ。
    def setFrameField(anims: Map[String, Json.JsonElement], sel: String, idx: Int32,
                        key: String, newVal: Json.JsonElement): Map[String, Json.JsonElement] =
        match Map.get(sel, anims) {
            case Some(Json.JsonElement.JsonObject(animMap)) =>
                match Map.get("frames", animMap) {
                    case Some(Json.JsonElement.JsonArray(arr)) =>
                        if (idx < 0i32 or idx >= Vector.length(arr)) anims
                        else {
                            let frameElem = Vector.get(idx, arr);
                            let newFrame = match frameElem {
                                case Json.JsonElement.JsonObject(fm) =>
                                    Json.JsonElement.JsonObject(Map.insert(key, newVal, fm))
                                case _ => frameElem
                            };
                            let newArr = Vector.update(idx, newFrame, arr);
                            let updatedAnim = Json.JsonElement.JsonObject(
                                Map.insert("frames", Json.JsonElement.JsonArray(newArr), animMap));
                            Map.insert(sel, updatedAnim, anims)
                        }
                    case _ => anims
                }
            case _ => anims
        }

    def intToBd(v: Int32): BigDecimal =
        unsafe IO {
            let stripped = JBigDecimal.valueOf(Int32.toFloat64(v)).stripTrailingZeros();
            if (stripped.scale() < 0) stripped.setScale(0) else stripped
        }

    /// Float64 → BigDecimal。3 桁で四捨五入し末尾 0 を取り除く（`1.0` → `1`、`0.5` → `0.5`）。
    def floatToBdRounded(v: Float64): BigDecimal =
        unsafe IO {
            JBigDecimal.valueOf(PropertyWidgets.roundTo3(v)).stripTrailingZeros()
        }

    /// アトラスを canvas に fit-scale で描画し、`hframes × vframes` の格子線と、
    /// 選択中フレーム index に対応するセルだけを黄色枠でハイライトする。
    /// texture 未登録 / hframes×vframes が 0 のときはプレースホルダ背景のみ。
    def drawSpriteGridPreview(canvas: Canvas, pathMap: Map[String, String],
                                textureName: String,
                                hframes: Int32, vframes: Int32, selFrame: Int32):
                              Unit \ IO = {
        let gc: GraphicsContext = canvas.getGraphicsContext2D();
        let cw = canvas.getWidth();
        let ch = canvas.getHeight();
        gc.setImageSmoothing(false);
        gc.setFill(FxColor.color(0.12, 0.12, 0.12));
        gc.fillRect(0.0, 0.0, cw, ch);
        match Map.get(textureName, pathMap) {
            case None => ()
            case Some(absPath) => {
                let url = new File(absPath).toURI().toString();
                let image = new Image(url);
                let imgW = image.getWidth();
                let imgH = image.getHeight();
                if (imgW <= 0.0 or imgH <= 0.0) ()
                else if (hframes <= 0i32 or vframes <= 0i32) ()
                else {
                    let sx = cw / imgW;
                    let sy = ch / imgH;
                    let s = if (sx < sy) sx else sy;
                    let dstW = imgW * s;
                    let dstH = imgH * s;
                    let dstX0 = (cw - dstW) / 2.0;
                    let dstY0 = (ch - dstH) / 2.0;
                    // アトラス描画
                    gc.drawImage(image, 0.0, 0.0, imgW, imgH, dstX0, dstY0, dstW, dstH);
                    // 格子線（薄いグレー）
                    let cellW = dstW / Int32.toFloat64(hframes);
                    let cellH = dstH / Int32.toFloat64(vframes);
                    gc.setStroke(FxColor.color(0.5, 0.5, 0.5));
                    gc.setLineWidth(1.0);
                    drawGridLines(gc, dstX0, dstY0, dstW, dstH, hframes, vframes, cellW, cellH);
                    // 選択 cell ハイライト
                    let total = hframes * vframes;
                    if (selFrame >= 0i32 and selFrame < total) {
                        let col = Int32.remainder(selFrame, hframes);
                        let row = selFrame / hframes;
                        let rx = dstX0 + Int32.toFloat64(col) * cellW;
                        let ry = dstY0 + Int32.toFloat64(row) * cellH;
                        gc.setStroke(FxColor.color(1.0, 0.9, 0.0));
                        gc.setLineWidth(2.0);
                        gc.strokeRect(rx, ry, cellW, cellH)
                    } else ()
                }
            }
        }
    }

    /// `hframes × vframes` 分の縦横格子線を描画する。
    def drawGridLines(gc: GraphicsContext, x0: Float64, y0: Float64, w: Float64, h: Float64,
                       hframes: Int32, vframes: Int32, cellW: Float64, cellH: Float64): Unit \ IO = {
        drawVerticalLines(gc, x0, y0, h, hframes, cellW, 0i32);
        drawHorizontalLines(gc, x0, y0, w, vframes, cellH, 0i32);
        // 外枠
        gc.strokeRect(x0, y0, w, h)
    }

    def drawVerticalLines(gc: GraphicsContext, x0: Float64, y0: Float64, h: Float64,
                            hframes: Int32, cellW: Float64, i: Int32): Unit \ IO =
        if (i >= hframes) ()
        else {
            let x = x0 + Int32.toFloat64(i) * cellW;
            gc.strokeLine(x, y0, x, y0 + h);
            drawVerticalLines(gc, x0, y0, h, hframes, cellW, i + 1i32)
        }

    def drawHorizontalLines(gc: GraphicsContext, x0: Float64, y0: Float64, w: Float64,
                             vframes: Int32, cellH: Float64, i: Int32): Unit \ IO =
        if (i >= vframes) ()
        else {
            let y = y0 + Int32.toFloat64(i) * cellH;
            gc.strokeLine(x0, y, x0 + w, y);
            drawHorizontalLines(gc, x0, y0, w, vframes, cellH, i + 1i32)
        }
}
