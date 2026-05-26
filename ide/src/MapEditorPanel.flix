// MapEditorPanel — Maps タブ専用の wiring と Level リスト管理。
//
// JavaFXIdeUI.customize から wireMapSelection が呼ばれ、ListView 選択時に
// `editingLevelRef` を更新する (今は最小構成、S9 以降で Canvas 描画と連携)。
// Main.flix の Open Project ロード時に findMapFiles → setLevelFiles → populateMapList を回す。
//
// 雛形: ResourcePanel.wireResourceSelection / populateResourcesList と同じパターン。

mod MapEditorPanel {
    import java.lang.{Object => JObject}
    import java.lang.Integer
    import java.io.File
    import javafx.scene.control.ListView
    import javafx.scene.control.Button
    import javafx.scene.control.ToggleButton
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.control.SpinnerValueFactory
    import javafx.scene.control.SpinnerValueFactory$IntegerSpinnerValueFactory
    import javafx.scene.control.TextField
    import javafx.scene.control.TextInputDialog
    import javafx.scene.control.Label
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ZoomEvent
    import javafx.scene.paint.Color
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javafx.event.ActionEvent
    import javafx.event.EventHandler

    /// Floor / Walls 各 layer の現在の textureName で Image を引いて cache に積む。
    /// Open Project / reloadProject 時、および ComboBox で texture が切り替えられた時に呼ぶ。
    pub def loadTilesetImages(state: IdeState.IdeState): Unit \ IO = {
        loadImageForLayer(state, MapEditorState.LayerMode.Floor);
        loadImageForLayer(state, MapEditorState.LayerMode.Walls)
    }

    /// 指定 layer の Palette 設定から textureName を読み、Image cache を更新する。
    /// Entities は palette を使わないので no-op。textureName が None や未登録なら None をキャッシュ。
    pub def loadImageForLayer(state: IdeState.IdeState, mode: MapEditorState.LayerMode):
            Unit \ IO = {
        let pathMap = IdeState.getTexturePathMap(state);
        let img = match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
            case None    => None
            case Some(p) => match p#textureName {
                case None       => None
                case Some(name) => loadImageFor(name, pathMap)
            }
        };
        match mode {
            case MapEditorState.LayerMode.Floor    =>
                Array.put(img, 0, state#widgets#mapFloorImage)
            case MapEditorState.LayerMode.Walls    =>
                Array.put(img, 0, state#widgets#mapWallsImage)
            case MapEditorState.LayerMode.Entities => ()
        }
    }

    def loadImageFor(textureName: String, pathMap: Map[String, String]): Option[Image] \ IO =
        match Map.get(textureName, pathMap) {
            case None    => None
            case Some(p) =>
                let url = new File(p).toURI().toString();
                Some(new Image(url))
        }

    /// プロジェクトの assets/maps/*.map.json を絶対パスのリストで返す。
    /// 該当ディレクトリが無い場合は空リスト (エラー扱いはしない)。
    pub def findMapFiles(rootDir: String): List[String] \ Fs.Glob =
        Fs.Glob.glob(rootDir, "assets/maps/*.map.json")
            |> Result.getWithDefault(Nil)

    /// 絶対パスから表示用 basename を取り出す ("/path/level_0.map.json" → "level_0.map.json")。
    pub def displayName(absPath: String): String =
        basenameRec(absPath, String.length(absPath) - 1)

    def basenameRec(path: String, idx: Int32): String =
        if (idx < 0) path
        else if (String.charAt(idx, path) == '/') path.substring(idx + 1, String.length(path))
        else basenameRec(path, idx - 1)

    /// Maps ListView を MapEditorState.levelFilesRef から populate する。
    /// FX EDT で呼ぶ (FXMLLoader.load 直後 or schedulePopulateTree から)。
    pub def populateMapList(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#mapsList) {
            case None => ()
            case Some(listView) => {
                let paths = MapEditorState.getLevelFiles(state#mapEditor);
                let items = listView.getItems();
                items.clear();
                List.forEach(p -> discard items.add(displayName(p)), paths)
            }
        }
    }

    /// Maps ListView の選択イベントを listen し、選択された Level の `.map.json` を
    /// `Persistence.load` で読んで editingLevelRef に積み、Canvas に grid を描く (S9)。
    pub def wireMapSelection(state: IdeState.IdeState, listView: ListView[String]): Unit \ IO = {
        let prop = listView.getSelectionModel().selectedItemProperty();
        let listener = new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String],
                         _obs: ObservableValue[JObject],
                         _old: String, newSel: String): Unit \ IO = {
                if (Object.isNull(newSel)) ()
                else {
                    let paths = MapEditorState.getLevelFiles(state#mapEditor);
                    let target = newSel;
                    match List.find(p -> displayName(p) == target, paths) {
                        case None      => ()
                        case Some(abs) =>
                            MapEditorState.setSelectedLevelPath(state#mapEditor, Some(abs));
                            run {
                                onLevelSelected(state, abs)
                            } with Fs.FileRead.runWithIO
                    }
                }
            }
        };
        prop.addListener(listener)
    }

    /// Level を絶対パスからロードして editingLevelRef に積み、Canvas に grid を描く。
    def onLevelSelected(state: IdeState.IdeState, absPath: String):
            Unit \ {IO, Fs.FileRead} = {
        let levelOpt: Option[MapResource.Level] = Persistence.load(absPath);
        MapEditorState.setEditingLevel(state#mapEditor, levelOpt);
        match levelOpt {
            case None        =>
                println("[MapEditor] failed to load ${absPath}");
                match Array.get(0, state#widgets#mapGridCanvas) {
                    case Some(c) => MapGridCanvas.clear(c)
                    case None    => ()
                }
            case Some(level) => {
                let d = MapResource.levelData(level);
                redrawCanvas(state);
                // 新規 Level に切替えたら dirty をリセットしてラベル反映
                MapEditorState.setDirty(state#mapEditor, false);
                updateDirtyLabel(state);
                println("[MapEditor] loaded: ${displayName(absPath)} (${d#width}x${d#height})")
            }
        }
    }

    /// dirty 状態を Label に反映する。dirty なら "* 未保存"、clean なら空。
    /// MapGridCanvas.handleClick (toggle 後) や saveCurrent (保存後) から呼ぶ。
    pub def updateDirtyLabel(state: IdeState.IdeState): Unit \ IO =
        match Array.get(0, state#widgets#mapDirtyLabel) {
            case None        => ()
            case Some(label) => {
                let dirty = MapEditorState.isDirty(state#mapEditor);
                label.setText(if (dirty) "* 未保存" else "")
            }
        }

    /// 保存ボタンに ActionEvent handler を登録する。
    /// クリック時に Persistence.save で `.map.json` を書き戻し、dirty をリセット。
    pub def wireSaveButton(state: IdeState.IdeState, btn: Button): Unit \ IO = {
        btn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                run {
                    saveCurrent(state)
                } with Fs.FileWrite.runWithIO
        })
    }

    // ────────────────────────────────────────────────────────
    // S15: Layer mode radio + tile パレット
    // ────────────────────────────────────────────────────────

    /// Layer リスト UI (Photoshop/Tiled 風) を配線する。
    /// - 行クリックで選択 (現編集レイヤーを更新、styleClass で highlight 切替)
    /// - 目玉トグル (ToggleButton) で当該 Layer の visibility を ON/OFF し canvas を再描画
    /// FXML から取得済みの widget は state#widgets から引く。
    pub def wireLayerList(state: IdeState.IdeState): Unit \ IO = {
        wireRowClick(state, state#widgets#mapLayerRowFloor, MapEditorState.LayerMode.Floor);
        wireRowClick(state, state#widgets#mapLayerRowWalls, MapEditorState.LayerMode.Walls);
        wireRowClick(state, state#widgets#mapLayerRowEntities, MapEditorState.LayerMode.Entities);
        wireEyeToggle(state, state#widgets#mapLayerVisibleFloor, MapEditorState.LayerMode.Floor);
        wireEyeToggle(state, state#widgets#mapLayerVisibleWalls, MapEditorState.LayerMode.Walls);
        wireEyeToggle(state, state#widgets#mapLayerVisibleEntities, MapEditorState.LayerMode.Entities);
        // 初期 highlight を現 LayerMode と同期 (FXML の静的 styleClass と Flix state の食い違い防止)
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        updateRowHighlight(state, mode)
    }

    /// 行 (HBox) のマウスクリックで対応する Layer に選択を切り替える。
    /// 目玉トグルの上で発生したクリックも HBox にバブルするので、
    /// target が ToggleButton かをチェックして二重切替を避ける。
    def wireRowClick(state: IdeState.IdeState,
                       rowRef: Array[Option[HBox], Static],
                       mode: MapEditorState.LayerMode): Unit \ IO =
        match Array.get(0, rowRef) {
            case None      => ()
            case Some(row) =>
                row.setOnMouseClicked(new EventHandler[MouseEvent] {
                    def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                        let target = event.getTarget();
                        let isToggle =
                            if (Object.isNull(target)) false
                            else String.startsWith(prefix = "ToggleButton",
                                                     target.getClass().getSimpleName());
                        if (isToggle) ()
                        else onLayerChanged(state, mode)
                    }
                })
        }

    /// 目玉トグル ON/OFF で visibility を更新し、canvas を再描画する。
    def wireEyeToggle(state: IdeState.IdeState,
                       btnRef: Array[Option[ToggleButton], Static],
                       mode: MapEditorState.LayerMode): Unit \ IO =
        match Array.get(0, btnRef) {
            case None      => ()
            case Some(btn) =>
                btn.setOnAction(new EventHandler[ActionEvent] {
                    def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                        MapEditorState.setLayerVisible(state#mapEditor, mode, btn.isSelected());
                        redrawCanvas(state)
                    }
                })
        }

    /// 編集中 Level を canvas に再描画する。Level 未選択なら何もしない。
    pub def redrawCanvas(state: IdeState.IdeState): Unit \ IO =
        match (MapEditorState.getEditingLevel(state#mapEditor),
               Array.get(0, state#widgets#mapGridCanvas)) {
            case (Some(level), Some(canvas)) => {
                let wImg = Array.get(0, state#widgets#mapWallsImage);
                let fImg = Array.get(0, state#widgets#mapFloorImage);
                let vis = MapEditorState.getLayerVisibility(state#mapEditor);
                MapGridCanvas.drawLevel(canvas, level, MapGridCanvas.defaultCellPx(),
                                          wImg, fImg, vis)
            }
            case _ => ()
        }

    /// レイヤー切替の共通処理: state 更新 → selectedSrc リセット → 行 highlight 切替
    /// → Palette widget 同期 (ComboBox/Spinner) → 右パネルのセクション切替
    /// → パレット再描画 → ラベル更新。
    def onLayerChanged(state: IdeState.IdeState, mode: MapEditorState.LayerMode): Unit \ IO = {
        MapEditorState.setLayerMode(state#mapEditor, mode);
        MapEditorState.setSelectedSrc(state#mapEditor, None);
        match Array.get(0, state#widgets#mapPaletteStatus) {
            case Some(label) => label.setText("未選択")
            case None        => ()
        };
        updateRowHighlight(state, mode);
        updatePaletteLabel(state, mode);
        syncPaletteWidgetsForLayer(state, mode);
        updateSideSection(state, mode);
        drawPalette(state)
    }

    /// Layer 行の選択 highlight 用 styleClass を 1 行だけにつける。
    /// "layer-row-selected" の add/remove を 3 行に対して同期させる。
    def updateRowHighlight(state: IdeState.IdeState, mode: MapEditorState.LayerMode):
            Unit \ IO = {
        setRowSelected(state#widgets#mapLayerRowFloor,
                       mode == MapEditorState.LayerMode.Floor);
        setRowSelected(state#widgets#mapLayerRowWalls,
                       mode == MapEditorState.LayerMode.Walls);
        setRowSelected(state#widgets#mapLayerRowEntities,
                       mode == MapEditorState.LayerMode.Entities)
    }

    def setRowSelected(rowRef: Array[Option[HBox], Static], selected: Bool): Unit \ IO =
        match Array.get(0, rowRef) {
            case None      => ()
            case Some(row) => {
                let classes = row.getStyleClass();
                let cls = "layer-row-selected";
                if (selected) {
                    if (not classes.contains(cls)) discard classes.add(cls) else ()
                } else {
                    discard classes.remove(cls)
                }
            }
        }

    /// パレット見出し ("Palette (Floor)" 等) を現レイヤーに合わせる。
    /// Entities レイヤーはパレット不使用なので明示する。
    def updatePaletteLabel(state: IdeState.IdeState, mode: MapEditorState.LayerMode): Unit \ IO =
        match Array.get(0, state#widgets#mapPaletteLabel) {
            case None        => ()
            case Some(label) => {
                let text = match mode {
                    case MapEditorState.LayerMode.Floor    => "Palette (Floor)"
                    case MapEditorState.LayerMode.Walls    => "Palette (Walls)"
                    case MapEditorState.LayerMode.Entities => "Palette (なし)"
                };
                label.setText(text)
            }
        }

    /// 現 layer の Palette 設定 (cellW, cellH) を返す。Entities / 未設定時のフォールバックは (16, 16)。
    def currentPaletteCellSize(state: IdeState.IdeState): (Int32, Int32) \ IO = {
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
            case Some(p) => (p#cellW, p#cellH)
            case None    => (16i32, 16i32)
        }
    }

    /// 現在の LayerMode に応じてパレット canvas に tileset PNG を描画する。
    /// Image は per-layer の cache (`mapWallsImage` / `mapFloorImage`) を読み、
    /// 選択枠は per-layer の cellW × cellH で描く。Entities は canvas をクリア。
    /// `paletteZoom` を掛けて canvas サイズ・描画サイズ・選択枠を拡縮する (ピンチ操作)。
    pub def drawPalette(state: IdeState.IdeState): Unit \ IO = {
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        let imgOpt = match mode {
            case MapEditorState.LayerMode.Floor    => Array.get(0, state#widgets#mapFloorImage)
            case MapEditorState.LayerMode.Walls    => Array.get(0, state#widgets#mapWallsImage)
            case MapEditorState.LayerMode.Entities => None
        };
        let zoom = MapEditorState.getPaletteZoom(state#mapEditor);
        match (Array.get(0, state#widgets#mapPaletteCanvas), imgOpt) {
            case (Some(canvas), Some(image)) => {
                let iw = image.getWidth();
                let ih = image.getHeight();
                let dw = iw * zoom;
                let dh = ih * zoom;
                canvas.setWidth(dw);
                canvas.setHeight(dh);
                let gc = canvas.getGraphicsContext2D();
                gc.setImageSmoothing(false);
                gc.clearRect(0.0f64, 0.0f64, dw, dh);
                gc.drawImage(image, 0.0f64, 0.0f64, iw, ih, 0.0f64, 0.0f64, dw, dh);
                match MapEditorState.getSelectedSrc(state#mapEditor) {
                    case None             => ()
                    case Some((srcX, srcY)) => {
                        let (cw, ch) = currentPaletteCellSize(state);
                        gc.setStroke(Color.rgb(255, 230, 60));
                        gc.setLineWidth(2.0);
                        gc.strokeRect(Int32.toFloat64(srcX) * zoom,
                                       Int32.toFloat64(srcY) * zoom,
                                       Int32.toFloat64(cw) * zoom,
                                       Int32.toFloat64(ch) * zoom)
                    }
                }
            }
            case (Some(canvas), None) => {
                // Entities レイヤー or 画像未ロード: canvas をクリアして空表示にする
                let gc = canvas.getGraphicsContext2D();
                gc.clearRect(0.0f64, 0.0f64, canvas.getWidth(), canvas.getHeight())
            }
            case _ => ()
        }
    }

    /// Palette canvas のクリックで src を選択する handler を 1 度だけ登録する。
    /// per-layer の cellW × cellH を使って col * cellW, row * cellH を srcX/srcY に換算。
    /// ピンチズーム中は canvas が拡縮されているため、event の x/y を zoom で割って画像座標に戻す。
    pub def wirePaletteClick(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let (cw, ch) = currentPaletteCellSize(state);
                if (cw <= 0i32 or ch <= 0i32) ()
                else {
                    let zoom = MapEditorState.getPaletteZoom(state#mapEditor);
                    let imgX = event.getX() / zoom;
                    let imgY = event.getY() / zoom;
                    let col = Float64.truncateToInt32(imgX / Int32.toFloat64(cw));
                    let row = Float64.truncateToInt32(imgY / Int32.toFloat64(ch));
                    let srcX = col * cw;
                    let srcY = row * ch;
                    MapEditorState.setSelectedSrc(state#mapEditor, Some((srcX, srcY)));
                    updatePaletteStatus(state, srcX, srcY);
                    drawPalette(state)
                }
            }
        })
    }

    def updatePaletteStatus(state: IdeState.IdeState, srcX: Int32, srcY: Int32): Unit \ IO =
        match Array.get(0, state#widgets#mapPaletteStatus) {
            case Some(label) => {
                let (cw, ch) = currentPaletteCellSize(state);
                let col = if (cw > 0i32) srcX / cw else 0i32;
                let row = if (ch > 0i32) srcY / ch else 0i32;
                label.setText("選択中: (${col}, ${row})  src=(${srcX}, ${srcY})")
            }
            case None => ()
        }

    // ────────────────────────────────────────────────────────
    // Palette 設定 widget (Sheet ComboBox + Cell Spinner ×2)
    // ────────────────────────────────────────────────────────

    /// FXML から取得した Spinner に IntegerSpinnerValueFactory をセットし、
    /// ComboBox / Spinner のリスナーを配線する。JavaFXIdeUI.customize 末尾で 1 度だけ呼ぶ。
    pub def initPaletteWidgets(state: IdeState.IdeState): Unit \ IO = {
        // Spinner の value factory を後付け (FXML では宣言しづらいため)
        match Array.get(0, state#widgets#mapPaletteCellWSpinner) {
            case Some(sp) => sp.setValueFactory(makeCellSizeFactory(16i32))
            case None     => ()
        };
        match Array.get(0, state#widgets#mapPaletteCellHSpinner) {
            case Some(sp) => sp.setValueFactory(makeCellSizeFactory(16i32))
            case None     => ()
        };
        // ComboBox / Spinner の値変化リスナーを配線
        match Array.get(0, state#widgets#mapPaletteTextureCombo) {
            case Some(cb) => wirePaletteTextureCombo(state, cb)
            case None     => ()
        };
        match Array.get(0, state#widgets#mapPaletteCellWSpinner) {
            case Some(sp) => wireCellSpinner(state, sp, true)
            case None     => ()
        };
        match Array.get(0, state#widgets#mapPaletteCellHSpinner) {
            case Some(sp) => wireCellSpinner(state, sp, false)
            case None     => ()
        };
        // Palette canvas のピンチズーム配線
        match Array.get(0, state#widgets#mapPaletteCanvas) {
            case Some(canvas) => wirePaletteZoom(state, canvas)
            case None         => ()
        };
        // 起動直後の widget 値を現 layer の設定と同期 (Entities なら disable)
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        syncPaletteWidgetsForLayer(state, mode);
        // Palette / Entity セクションの表示も現 layer に合わせる
        updateSideSection(state, mode)
    }

    /// Palette canvas にピンチイベント (ZoomEvent) ハンドラを登録する。
    /// macOS trackpad の pinch in/out で `event.getZoomFactor()` (incremental) が来るので、
    /// 現 zoom に乗算してクランプ → drawPalette で反映。
    def wirePaletteZoom(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnZoom(new EventHandler[ZoomEvent] {
            def handle(_this: EventHandler[ZoomEvent], event: ZoomEvent): Unit \ IO = {
                let factor = event.getZoomFactor();
                let cur = MapEditorState.getPaletteZoom(state#mapEditor);
                MapEditorState.setPaletteZoom(state#mapEditor, cur * factor);
                drawPalette(state);
                event.consume()
            }
        })
    }

    /// 現 LayerMode に応じて右パネルの Palette / Entity セクションの可視性を切り替える。
    /// Entities → Entity 入力セクション / Floor or Walls → Palette セクション。
    pub def updateSideSection(state: IdeState.IdeState,
                                mode: MapEditorState.LayerMode): Unit \ IO = {
        let isEntities = mode == MapEditorState.LayerMode.Entities;
        setSectionVisible(state#widgets#mapPaletteSection, not isEntities);
        setSectionVisible(state#widgets#mapEntitySection, isEntities)
    }

    def setSectionVisible(ref: Array[Option[VBox], Static], visible: Bool): Unit \ IO =
        match Array.get(0, ref) {
            case None      => ()
            case Some(box) => {
                box.setVisible(visible);
                box.setManaged(visible)
            }
        }

    /// IntegerSpinnerValueFactory(min=1, max=256, init=initVal)。
    /// Cell px の妥当な範囲。super-large な tile は使わない想定。
    def makeCellSizeFactory(initVal: Int32): SpinnerValueFactory[Integer] \ IO = {
        let f = new SpinnerValueFactory$IntegerSpinnerValueFactory(1i32, 256i32, initVal);
        unchecked_cast(f as SpinnerValueFactory[Integer])
    }

    /// ComboBox 値変化: 現 layer の Palette 設定を更新し、image cache 再ロード →
    /// パレットと map canvas を再描画。
    def wirePaletteTextureCombo(state: IdeState.IdeState, combo: ComboBox[String]): Unit \ IO = {
        combo.valueProperty().addListener(new ChangeListener[String] {
            def changed(_cThis: ChangeListener[String], _obs: ObservableValue[JObject],
                         _old: String, newVal: String): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let mode = MapEditorState.getLayerMode(state#mapEditor);
                    match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                        case None    => ()
                        case Some(p) => {
                            let next: MapEditorState.LayerPalette =
                                {textureName = Some(newVal) | p};
                            MapEditorState.setPaletteForLayer(state#mapEditor, mode, next);
                            // Sheet が変わったら以前の選択は意味を失うのでクリア
                            MapEditorState.setSelectedSrc(state#mapEditor, None);
                            match Array.get(0, state#widgets#mapPaletteStatus) {
                                case Some(label) => label.setText("未選択")
                                case None        => ()
                            };
                            loadImageForLayer(state, mode);
                            drawPalette(state);
                            redrawCanvas(state)
                        }
                    }
                }
            }
        })
    }

    /// Spinner 値変化: 現 layer の cellW / cellH を更新し、パレットを再描画。
    /// `isWidth=true` なら cellW、false なら cellH を更新する。
    def wireCellSpinner(state: IdeState.IdeState, spinner: Spinner[Integer],
                          isWidth: Bool): Unit \ IO = {
        spinner.valueProperty().addListener(new ChangeListener[Integer] {
            def changed(_cThis: ChangeListener[Integer], _obs: ObservableValue[JObject],
                         _old: Integer, newVal: Integer): Unit \ IO = {
                if (Object.isNull(newVal)) ()
                else {
                    let v: Int32 = newVal.intValue();
                    let mode = MapEditorState.getLayerMode(state#mapEditor);
                    match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                        case None    => ()
                        case Some(p) => {
                            let next: MapEditorState.LayerPalette =
                                if (isWidth) {cellW = v | p} else {cellH = v | p};
                            MapEditorState.setPaletteForLayer(state#mapEditor, mode, next);
                            drawPalette(state)
                        }
                    }
                }
            }
        })
    }

    /// プロジェクト読込後に ComboBox の選択肢を texturePathMap の keys で埋める。
    /// その上で現 layer の textureName が候補に含まれていれば選択状態にする。
    /// `Main.loadTilesetImages` 呼び出しの隣で呼ぶ想定。
    pub def populatePaletteTextureCombo(state: IdeState.IdeState): Unit \ IO =
        match Array.get(0, state#widgets#mapPaletteTextureCombo) {
            case None       => ()
            case Some(combo) => {
                let items = combo.getItems();
                items.clear();
                let names = IdeState.getTexturePathMap(state) |> Map.keysOf |> Set.toList;
                List.forEach(n -> discard items.add(n), names);
                let mode = MapEditorState.getLayerMode(state#mapEditor);
                syncPaletteWidgetsForLayer(state, mode)
            }
        }

    /// 指定 layer の Palette 設定で ComboBox / Spinner の表示値を同期する。
    /// JavaFX ChangeListener は value 変化時のみ発火するので、同じ値なら no-op になる。
    /// Entities レイヤー時は ComboBox / Spinner を setDisable(true) でグレーアウト。
    pub def syncPaletteWidgetsForLayer(state: IdeState.IdeState,
                                          mode: MapEditorState.LayerMode): Unit \ IO = {
        let disabled = mode == MapEditorState.LayerMode.Entities;
        match Array.get(0, state#widgets#mapPaletteTextureCombo) {
            case Some(cb) => {
                cb.setDisable(disabled);
                match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                    case Some(p) => match p#textureName {
                        case Some(n) => cb.setValue(n)
                        case None    => ()
                    }
                    case None    => ()
                }
            }
            case None     => ()
        };
        syncCellSpinner(state, state#widgets#mapPaletteCellWSpinner, mode, true, disabled);
        syncCellSpinner(state, state#widgets#mapPaletteCellHSpinner, mode, false, disabled)
    }

    def syncCellSpinner(state: IdeState.IdeState,
                          spRef: Array[Option[Spinner[Integer]], Static],
                          mode: MapEditorState.LayerMode, isWidth: Bool,
                          disabled: Bool): Unit \ IO =
        match Array.get(0, spRef) {
            case None     => ()
            case Some(sp) => {
                sp.setDisable(disabled);
                match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                    case None    => ()
                    case Some(p) =>
                        let v = if (isWidth) p#cellW else p#cellH;
                        sp.getValueFactory().setValue(Integer.valueOf(v))
                }
            }
        }

    // ────────────────────────────────────────────────────────
    // S17: 新規 Level 作成
    // ────────────────────────────────────────────────────────

    /// 「+ New」ボタンに ActionEvent handler を登録する。
    /// TextInputDialog で名前を聞き、assets/maps/{name}.map.json を空 Level で生成する。
    pub def wireNewLevelButton(state: IdeState.IdeState, btn: Button): Unit \ IO = {
        btn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                promptAndCreateNew(state)
        })
    }

    /// 新規 Level 作成 UI フロー。
    /// 1. TextInputDialog で名前を取得 (ESC キャンセル → 何もしない)
    /// 2. projectRoot 配下に `assets/maps/{name}.map.json` を作成
    /// 3. 既存ファイルがあれば Alert で警告して中止
    /// 4. 成功したら levelFilesRef を再 glob して ListView 更新 + 新ファイルを選択
    def promptAndCreateNew(state: IdeState.IdeState): Unit \ IO = {
        match IdeState.getCurrentProjectRoot(state) {
            case None        => showAlert("プロジェクトが開かれていません")
            case Some(root)  => {
                let dialog = new TextInputDialog("new_room");
                dialog.setTitle("New Level");
                dialog.setHeaderText("新 Level の名前を入力");
                dialog.setContentText("名前 (.map.json は自動付与):");
                let result = dialog.showAndWait();
                if (result.isPresent()) {
                    let name = result.get();
                    if (name == "") showAlert("名前を入力してください")
                    else createNewAt(state, root, name)
                } else ()
            }
        }
    }

    def createNewAt(state: IdeState.IdeState, root: String, name: String): Unit \ IO = {
        let path = root + "/assets/maps/" + name + ".map.json";
        if (fileExists(path))
            showAlert("ファイルが既に存在します: ${name}.map.json")
        else
            saveAndRefresh(state, root, path)
    }

    /// パスにファイルが存在するか確認する (Fs.FileRead 経由)。
    def fileExists(path: String): Bool \ IO =
        run {
            existsViaReadFile(path)
        } with Fs.FileRead.runWithIO

    def existsViaReadFile(path: String): Bool \ Fs.FileRead =
        run {
            match Fs.ReadFile.read(path) {
                case Ok(_)  => true
                case Err(_) => false
            }
        } with Fs.ReadFile.runWithFileRead

    /// 空 Level を path に保存して ListView を refresh する。
    def saveAndRefresh(state: IdeState.IdeState, root: String, path: String): Unit \ IO = {
        let level = buildBlankLevel(13i32, 13i32);
        let saveResult = run {
            Persistence.save(path, level)
        } with Fs.FileWrite.runWithIO;
        match saveResult {
            case Err(msg) => showAlert("保存失敗: ${msg}")
            case Ok(_)    => {
                println("[MapEditor] created: ${path}");
                refreshLevelListAndSelect(state, root, path)
            }
        }
    }

    /// 13×13 デフォルト Level: 外周 wall (wallMask=1 + manualTiles に inca_tileset 壁絵)、
    /// 内部は空 (Floor は未配置)、entity 無し。
    /// materialId は "inca_stone" 固定 (Material 概念導入まで)。
    /// 壁絵は単一の (176, 16) を使用。コーナーの flip 等はユーザーが Walls レイヤーで上書き配置する。
    def buildBlankLevel(width: Int32, height: Int32): MapResource.Level = {
        let outerCells = List.range(0, width * height)
            |> List.filter(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                col == 0 or col == width - 1 or row == 0 or row == height - 1
            });
        let mask = List.range(0, width * height)
            |> List.map(i -> if (List.memberOf(i, outerCells)) 1i32 else 0i32)
            |> List.toVector;
        let wallTiles = outerCells
            |> List.map(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                ({
                    x = col, y = row,
                    srcX = 176i32, srcY = 16i32,
                    flipH = false, flipV = false
                }: MapResource.ManualTile)
            });
        let data: MapResource.LevelData = {
            tileSize    = 16,
            width       = width,
            height      = height,
            materialId  = "inca_stone",
            wallMask    = mask,
            manualTiles = wallTiles,
            decorTiles  = (Nil: List[MapResource.ManualTile]),
            entities    = (Nil: List[MapResource.Entity])
        };
        MapResource.Level.Level(data)
    }

    /// 新ファイル作成後に levelFilesRef を再 glob し、ListView を更新する。
    /// (ListView の自動選択は overload 解決が難しいため省略 — ユーザーが新ファイルをクリックして開く)
    def refreshLevelListAndSelect(state: IdeState.IdeState, root: String, newPath: String): Unit \ IO = {
        let mapFiles = run {
            findMapFiles(root)
        } with Fs.Glob.runWithIO;
        MapEditorState.setLevelFiles(state#mapEditor, mapFiles);
        populateMapList(state);
        println("[MapEditor] new level added to list: ${displayName(newPath)}")
    }

    /// 簡易エラー表示。現状は println のみ (JavaFX Alert は AlertType ネストクラス
    /// import が動かないため未使用)。将来 dirty Label を流用する余地あり。
    def showAlert(message: String): Unit \ IO =
        println("[MapEditor] ${message}")

    /// 現在の editingLevel を selectedLevelPath に書き戻す。
    /// editingLevel が無い or selectedPath が無いときは何もしない。
    def saveCurrent(state: IdeState.IdeState): Unit \ {IO, Fs.FileWrite} =
        match (MapEditorState.getSelectedLevelPath(state#mapEditor),
               MapEditorState.getEditingLevel(state#mapEditor)) {
            case (Some(path), Some(level)) =>
                match Persistence.save(path, level) {
                    case Ok(_)    => {
                        MapEditorState.setDirty(state#mapEditor, false);
                        updateDirtyLabel(state);
                        println("[MapEditor] saved: ${displayName(path)}")
                    }
                    case Err(msg) => println("[MapEditor] save failed (${displayName(path)}): ${msg}")
                }
            case _ => ()
        }
}
