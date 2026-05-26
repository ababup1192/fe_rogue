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
    import javafx.scene.control.Dialog
    import javafx.scene.control.DialogPane
    import javafx.scene.control.ButtonType
    import javafx.scene.control.Label
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.input.MouseEvent
    import javafx.scene.input.ZoomEvent
    import javafx.scene.paint.Color
    import javafx.scene.layout.HBox
    import javafx.scene.layout.VBox
    import javafx.scene.layout.GridPane
    import javafx.scene.layout.StackPane
    import javafx.scene.layout.Region
    import javafx.scene.Node
    import javafx.geometry.Pos
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
            case MapEditorState.LayerMode.Walls    => {
                Array.put(img, 0, state#widgets#mapWallsImage);
                // Materials タブの tileset プレビューも Walls 画像を使うので更新
                drawMaterialsTileset(state)
            }
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
    /// materialId から対応する Material JSON もロードし、Materials タブを更新する。
    def onLevelSelected(state: IdeState.IdeState, absPath: String):
            Unit \ {IO, Fs.FileRead} = {
        let levelOpt: Option[MapResource.Level] = Persistence.load(absPath);
        MapEditorState.setEditingLevel(state#mapEditor, levelOpt);
        match levelOpt {
            case None        =>
                println("[MapEditor] failed to load ${absPath}");
                MapEditorState.setEditingMaterial(state#mapEditor, None);
                MapEditorState.setEditingMaterialPath(state#mapEditor, None);
                match Array.get(0, state#widgets#mapGridCanvas) {
                    case Some(c) => MapGridCanvas.clear(c)
                    case None    => ()
                }
            case Some(level) => {
                let d = MapResource.levelData(level);
                // 別 Level に切替えたら Undo スタックは古いデータが残っているので捨てる
                MapEditorState.clearUndoStack(state#mapEditor);
                // Map 固有の Palette 設定を読み込んで PaletteSettings に積む
                applyEditorPaletteFromLevel(state, d#editorPalette);
                loadMaterialForLevel(state, d#materialId);
                // ComboBox / Spinner と画像キャッシュを Palette 設定に同期
                loadTilesetImages(state);
                let mode = MapEditorState.getLayerMode(state#mapEditor);
                syncPaletteWidgetsForLayer(state, mode);
                drawPalette(state);
                redrawCanvas(state);
                refreshMaterialsTab(state);
                println("[MapEditor] loaded: ${displayName(absPath)} (${d#width}x${d#height})")
            }
        }
    }

    /// Level の materialId に対応する Material JSON をロードして state に積む。
    /// パスは <projectRoot>/assets/materials/<id>.material.json。
    /// ファイルが無ければ None を積む (AutoLayerWalls 描画はスキップされる)。
    /// Palette 設定は Level.editorPalette が優先されるので、ここでは画像のみ反映。
    def loadMaterialForLevel(state: IdeState.IdeState, materialId: String):
            Unit \ {IO, Fs.FileRead} =
        match IdeState.getCurrentProjectRoot(state) {
            case None       => {
                MapEditorState.setEditingMaterial(state#mapEditor, None);
                MapEditorState.setEditingMaterialPath(state#mapEditor, None)
            }
            case Some(root) => {
                let path = root + "/assets/materials/" + materialId + ".material.json";
                let matOpt: Option[MapResource.Material] = Persistence.load(path);
                MapEditorState.setEditingMaterial(state#mapEditor, matOpt);
                MapEditorState.setEditingMaterialPath(state#mapEditor,
                    if (Option.isEmpty(matOpt)) None else Some(path));
                match matOpt {
                    case None    => println("[MapEditor] material not found: ${path}")
                    case Some(_) => println("[MapEditor] material loaded: ${materialId}")
                }
            }
        }

    /// Level.editorPalette を MapEditorState.PaletteSettings に反映する。
    /// `None` ならデフォルト値 (defaultPaletteSettings) を採用 (新規 Level や旧 Level 用)。
    def applyEditorPaletteFromLevel(state: IdeState.IdeState,
                                       ep: Option[MapResource.EditorPalette]): Unit \ IO = {
        let settings: MapEditorState.PaletteSettings = match ep {
            case None    => MapEditorState.defaultPaletteSettings()
            case Some(p) => ({
                floor = toLayerPalette(p#floor),
                walls = toLayerPalette(p#walls)
            }: MapEditorState.PaletteSettings)
        };
        Array.put(settings, 0, state#mapEditor#paletteSettingsRef)
    }

    def toLayerPalette(lp: MapResource.EditorLayerPalette): MapEditorState.LayerPalette =
        ({
            textureName = lp#textureName,
            cellW       = lp#cellW,
            cellH       = lp#cellH,
            marginX     = lp#marginX,
            marginY     = lp#marginY
        }: MapEditorState.LayerPalette)

    /// MapEditorState.PaletteSettings から Level.editorPalette を構築する (save 時に使う)。
    def buildEditorPaletteForLevel(state: IdeState.IdeState):
            MapResource.EditorPalette \ IO = {
        let s = MapEditorState.getPaletteSettings(state#mapEditor);
        ({
            floor = fromLayerPalette(s#floor),
            walls = fromLayerPalette(s#walls)
        }: MapResource.EditorPalette)
    }

    def fromLayerPalette(lp: MapEditorState.LayerPalette): MapResource.EditorLayerPalette =
        ({
            textureName = lp#textureName,
            cellW       = lp#cellW,
            cellH       = lp#cellH,
            marginX     = lp#marginX,
            marginY     = lp#marginY
        }: MapResource.EditorLayerPalette)

    /// 編集後に呼ぶ自動保存。editingLevel を selectedLevelPath に書き戻す。
    /// 失敗時は println のみ (Dialog は出さない、ユーザー操作を妨げない)。
    pub def autoSave(state: IdeState.IdeState): Unit \ IO =
        run {
            saveCurrent(state)
        } with Fs.FileWrite.runWithIO

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
    /// mapZoom を反映するため drawLevel に zoom を渡す。
    pub def redrawCanvas(state: IdeState.IdeState): Unit \ IO =
        match (MapEditorState.getEditingLevel(state#mapEditor),
               Array.get(0, state#widgets#mapGridCanvas)) {
            case (Some(level), Some(canvas)) => {
                let wImg = Array.get(0, state#widgets#mapWallsImage);
                let fImg = Array.get(0, state#widgets#mapFloorImage);
                let vis = MapEditorState.getLayerVisibility(state#mapEditor);
                let zoom = MapEditorState.getMapZoom(state#mapEditor);
                let mat = MapEditorState.getEditingMaterial(state#mapEditor);
                MapGridCanvas.drawLevel(canvas, level, MapGridCanvas.defaultCellPx(),
                                          wImg, fImg, vis, zoom, mat)
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
    /// "layer-row-selected" の add/remove を全行に対して同期させる。
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

    /// 現 layer の (cellW, cellH, marginX, marginY) を返す。フォールバックは (16,16,0,0)。
    def currentPaletteCellAndMargin(state: IdeState.IdeState):
            (Int32, Int32, Int32, Int32) \ IO = {
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
            case Some(p) => (p#cellW, p#cellH, p#marginX, p#marginY)
            case None    => (16i32, 16i32, 0i32, 0i32)
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
    /// per-layer の cellW × cellH + marginX × marginY を使ってタイル位置を決める。
    /// ピンチズーム中は canvas が拡縮されているため、event の x/y を zoom で割って画像座標に戻す。
    pub def wirePaletteClick(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let (cw, ch, mx, my) = currentPaletteCellAndMargin(state);
                if (cw <= 0i32 or ch <= 0i32) ()
                else {
                    let zoom = MapEditorState.getPaletteZoom(state#mapEditor);
                    let imgX = event.getX() / zoom;
                    let imgY = event.getY() / zoom;
                    let strideX = cw + mx;
                    let strideY = ch + my;
                    let col = Float64.truncateToInt32(imgX / Int32.toFloat64(strideX));
                    let row = Float64.truncateToInt32(imgY / Int32.toFloat64(strideY));
                    let srcX = col * strideX;
                    let srcY = row * strideY;
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
                let (cw, ch, mx, my) = currentPaletteCellAndMargin(state);
                let strideX = cw + mx;
                let strideY = ch + my;
                let col = if (strideX > 0i32) srcX / strideX else 0i32;
                let row = if (strideY > 0i32) srcY / strideY else 0i32;
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
        match Array.get(0, state#widgets#mapPaletteMarginXSpinner) {
            case Some(sp) => sp.setValueFactory(makeMarginFactory(0i32))
            case None     => ()
        };
        match Array.get(0, state#widgets#mapPaletteMarginYSpinner) {
            case Some(sp) => sp.setValueFactory(makeMarginFactory(0i32))
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
        match Array.get(0, state#widgets#mapPaletteMarginXSpinner) {
            case Some(sp) => wireMarginSpinner(state, sp, true)
            case None     => ()
        };
        match Array.get(0, state#widgets#mapPaletteMarginYSpinner) {
            case Some(sp) => wireMarginSpinner(state, sp, false)
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
    ///   Entities      → Entity 入力セクション
    ///   Floor / Walls → Palette セクション
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

    /// Margin 用 IntegerSpinnerValueFactory(min=0, max=64, init=initVal)。
    /// タイル間スペースは 0 が普通、大きくても 8 程度を想定 (上限 64 で余裕)。
    def makeMarginFactory(initVal: Int32): SpinnerValueFactory[Integer] \ IO = {
        let f = new SpinnerValueFactory$IntegerSpinnerValueFactory(0i32, 64i32, initVal);
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
                            redrawCanvas(state);
                            autoSave(state)
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
                            drawPalette(state);
                            autoSave(state)
                        }
                    }
                }
            }
        })
    }

    /// Margin Spinner 値変化: 現 layer の marginX / marginY を更新、パレット再描画。
    def wireMarginSpinner(state: IdeState.IdeState, spinner: Spinner[Integer],
                            isX: Bool): Unit \ IO = {
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
                                if (isX) {marginX = v | p} else {marginY = v | p};
                            MapEditorState.setPaletteForLayer(state#mapEditor, mode, next);
                            drawPalette(state);
                            autoSave(state)
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
        syncCellSpinner(state, state#widgets#mapPaletteCellHSpinner, mode, false, disabled);
        syncMarginSpinner(state, state#widgets#mapPaletteMarginXSpinner, mode, true, disabled);
        syncMarginSpinner(state, state#widgets#mapPaletteMarginYSpinner, mode, false, disabled)
    }

    def syncMarginSpinner(state: IdeState.IdeState,
                            spRef: Array[Option[Spinner[Integer]], Static],
                            mode: MapEditorState.LayerMode, isX: Bool,
                            disabled: Bool): Unit \ IO =
        match Array.get(0, spRef) {
            case None     => ()
            case Some(sp) => {
                sp.setDisable(disabled);
                match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                    case None    => ()
                    case Some(p) =>
                        let v = if (isX) p#marginX else p#marginY;
                        sp.getValueFactory().setValue(Integer.valueOf(v))
                }
            }
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

    /// 新規 Level 作成 UI フロー。Custom Dialog で名前 + 幅 + 高さ + タイルサイズを取得。
    /// 1. Dialog 表示 (ESC / Cancel → 何もしない)
    /// 2. projectRoot 配下に `assets/maps/{name}.map.json` を作成
    /// 3. 既存ファイルがあれば Alert で警告して中止
    /// 4. 成功したら levelFilesRef を再 glob して ListView 更新
    def promptAndCreateNew(state: IdeState.IdeState): Unit \ IO = {
        match IdeState.getCurrentProjectRoot(state) {
            case None       => showAlert("プロジェクトが開かれていません")
            case Some(root) => {
                let dialog: Dialog[ButtonType] = new Dialog();
                dialog.setTitle("New Level");
                dialog.setHeaderText("新 Level のサイズを入力");
                let pane = dialog.getDialogPane();
                let buttonTypes = pane.getButtonTypes();
                discard buttonTypes.add(ButtonType.OK);
                discard buttonTypes.add(ButtonType.CANCEL);

                let nameField = new TextField("new_room");
                let widthSpinner: Spinner[Integer] = new Spinner();
                widthSpinner.setValueFactory(makeGridSizeFactory(13i32));
                widthSpinner.setEditable(true);
                let heightSpinner: Spinner[Integer] = new Spinner();
                heightSpinner.setValueFactory(makeGridSizeFactory(13i32));
                heightSpinner.setEditable(true);
                let tileSizeSpinner: Spinner[Integer] = new Spinner();
                tileSizeSpinner.setValueFactory(makeCellSizeFactory(16i32));
                tileSizeSpinner.setEditable(true);

                let grid = new GridPane();
                grid.setHgap(8.0);
                grid.setVgap(8.0);
                grid.add(unchecked_cast(new Label("名前:") as Node),         0i32, 0i32);
                grid.add(unchecked_cast(nameField as Node),                  1i32, 0i32);
                grid.add(unchecked_cast(new Label("幅 (タイル数):") as Node),  0i32, 1i32);
                grid.add(unchecked_cast(widthSpinner as Node),               1i32, 1i32);
                grid.add(unchecked_cast(new Label("高さ (タイル数):") as Node), 0i32, 2i32);
                grid.add(unchecked_cast(heightSpinner as Node),              1i32, 2i32);
                grid.add(unchecked_cast(new Label("タイルサイズ (px):") as Node), 0i32, 3i32);
                grid.add(unchecked_cast(tileSizeSpinner as Node),            1i32, 3i32);
                pane.setContent(unchecked_cast(grid as Node));

                let result = dialog.showAndWait();
                if (result.isPresent()) {
                    let bt = result.get();
                    let okBt = ButtonType.OK;
                    if (okBt.equals(bt)) {
                        let name = nameField.getText();
                        let widthV    = widthSpinner.getValue().intValue();
                        let heightV   = heightSpinner.getValue().intValue();
                        let tileSize  = tileSizeSpinner.getValue().intValue();
                        if (Object.isNull(name) or name == "")
                            showAlert("名前を入力してください")
                        else createNewAt(state, root, name, widthV, heightV, tileSize)
                    } else ()
                } else ()
            }
        }
    }

    /// グリッドサイズ用 IntegerSpinnerValueFactory(min=1, max=256, init=initVal)。
    def makeGridSizeFactory(initVal: Int32): SpinnerValueFactory[Integer] \ IO = {
        let f = new SpinnerValueFactory$IntegerSpinnerValueFactory(1i32, 256i32, initVal);
        unchecked_cast(f as SpinnerValueFactory[Integer])
    }

    def createNewAt(state: IdeState.IdeState, root: String, name: String,
                      width: Int32, height: Int32, tileSize: Int32): Unit \ IO = {
        let path = root + "/assets/maps/" + name + ".map.json";
        if (fileExists(path))
            showAlert("ファイルが既に存在します: ${name}.map.json")
        else
            saveAndRefresh(state, root, path, width, height, tileSize)
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
    def saveAndRefresh(state: IdeState.IdeState, root: String, path: String,
                         width: Int32, height: Int32, tileSize: Int32): Unit \ IO = {
        let level = buildBlankLevel(width, height, tileSize);
        let saveResult = run {
            Persistence.save(path, level)
        } with Fs.FileWrite.runWithIO;
        match saveResult {
            case Err(msg) => showAlert("保存失敗: ${msg}")
            case Ok(_)    => {
                println("[MapEditor] created: ${path} (${width}x${height}, tileSize=${tileSize})");
                refreshLevelListAndSelect(state, root, path)
            }
        }
    }

    /// 指定サイズの空 Level: 全セルに床 (decorTiles)、壁・装飾なし、entity なし。
    /// 新仕様では「Floor で床を削ると周囲が自動的に壁になる」運用なので、
    /// 起点として全部床にしておきユーザが内側を削っていく形にする。
    /// materialId は "inca_stone" 固定、Floor タイルの srcX/srcY は Material.floorPalette の
    /// 先頭である (0, 0) を採用。
    def buildBlankLevel(width: Int32, height: Int32, tileSize: Int32): MapResource.Level = {
        let floorTiles = List.range(0, width * height)
            |> List.map(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                ({
                    x = col, y = row,
                    srcX = 0i32, srcY = 0i32,
                    flipH = false, flipV = false
                }: MapResource.ManualTile)
            });
        let data: MapResource.LevelData = {
            tileSize      = tileSize,
            width         = width,
            height        = height,
            materialId    = "inca_stone",
            manualTiles   = (Nil: List[MapResource.ManualTile]),
            decorTiles    = floorTiles,
            entities      = (Nil: List[MapResource.Entity]),
            editorPalette = (None: Option[MapResource.EditorPalette])
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
    /// 保存時に現在の PaletteSettings を Level.editorPalette として書き込む (Map ごとに分離)。
    def saveCurrent(state: IdeState.IdeState): Unit \ {IO, Fs.FileWrite} =
        match (MapEditorState.getSelectedLevelPath(state#mapEditor),
               MapEditorState.getEditingLevel(state#mapEditor)) {
            case (Some(path), Some(level)) => {
                let d = MapResource.levelData(level);
                let ep = buildEditorPaletteForLevel(state);
                let newData: MapResource.LevelData = {editorPalette = Some(ep) | d};
                let newLevel = MapResource.Level.Level(newData);
                MapEditorState.setEditingLevel(state#mapEditor, Some(newLevel));
                match Persistence.save(path, newLevel) {
                    case Ok(_)    => println("[MapEditor] auto-saved: ${displayName(path)}")
                    case Err(msg) => println("[MapEditor] save failed (${displayName(path)}): ${msg}")
                }
            }
            case _ => ()
        }

    // ────────────────────────────────────────────────────────
    // Materials サブタブ (wallMap 編集 UI)
    // ────────────────────────────────────────────────────────

    /// Materials サブタブの初期化。GridPane に 4x4 セルを生成し、Tileset Canvas に
    /// クリック handler を貼る。タイルサイズ/マージン/ズームは Walls Palette と共有するため
    /// Materials タブ専用の設定 UI は持たない。JavaFXIdeUI.customize から 1 度だけ呼ぶ。
    pub def initMaterialsTab(state: IdeState.IdeState): Unit \ IO = {
        match Array.get(0, state#widgets#mapMaterialsWallMapGrid) {
            case None       => ()
            case Some(grid) => buildWallMapGrid(state, grid)
        };
        match Array.get(0, state#widgets#mapMaterialsTilesetCanvas) {
            case None         => ()
            case Some(canvas) => wireMaterialsTilesetClick(state, canvas)
        };
        refreshMaterialsTab(state)
    }

    /// 4x4 = 16 セルを GridPane に追加する。各セルは StackPane に Label "TRBL" を載せ、
    /// クリックで selectedTrblRef を更新し、grid を再描画する。
    def buildWallMapGrid(state: IdeState.IdeState, grid: GridPane): Unit \ IO = {
        grid.getChildren().clear();
        let keys = MapResource.wallMapKeys() |> List.toVector;
        List.forEach(idx -> {
            let r = idx / 4;
            let c = Int32.remainder(idx, 4);
            let key = match Vector.nth(idx, keys) {
                case Some(k) => k
                case None    => "0000"
            };
            let cell = makeWallMapCell(state, key);
            grid.add(unchecked_cast(cell as Node), c, r)
        }, List.range(0, 16))
    }

    /// 1 個の TRBL セル (StackPane + Canvas アイコン + Label) を作る。
    /// Canvas は 3x3 ミニグリッドで TRBL を視覚化 (中央=選択中の壁、隣接 4 方向の壁有無)。
    /// クリックで selectedTrbl 更新。
    def makeWallMapCell(state: IdeState.IdeState, key: String): StackPane \ IO = {
        let pane = new StackPane();
        let iconCanvas = new Canvas(36.0, 36.0);
        drawTrblIcon(iconCanvas, key);
        let label = new Label(key);
        label.setStyle("-fx-text-fill: #ffe; -fx-font-size: 9px;");
        StackPane.setAlignment(unchecked_cast(label as Node), Pos.BOTTOM_CENTER);
        StackPane.setAlignment(unchecked_cast(iconCanvas as Node), Pos.TOP_CENTER);
        pane.getChildren().add(unchecked_cast(iconCanvas as Node));
        pane.getChildren().add(unchecked_cast(label as Node));
        pane.setPrefSize(56.0, 56.0);
        pane.setMinSize(56.0, 56.0);
        pane.setStyle(cellStyleNormal());
        pane.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], _e: MouseEvent): Unit \ IO = {
                MapEditorState.setSelectedTrbl(state#mapEditor, Some(key));
                refreshMaterialsTab(state)
            }
        });
        pane
    }

    def cellStyleNormal(): String =
        "-fx-background-color: #2b2b30; -fx-border-color: #555; -fx-border-width: 1;"

    def cellStyleSelected(): String =
        "-fx-background-color: #4d6a8f; -fx-border-color: #ffe63c; -fx-border-width: 2;"

    /// TRBL アイコンを 3x3 ミニグリッドで描画する。
    ///   中央セル = 選択中の壁 (薄い色)
    ///   T/R/B/L  = key の対応ビットが 1 なら壁色、0 なら空セル色
    ///   4 隅     = neutral 灰色 (TRBL に出てこない斜め方向)
    /// 例:
    ///   "1111" = 中央 + 上下左右の 5 マスが壁 → 壁ブロックの中央
    ///   "0000" = 中央のみ壁 → 孤立した柱
    ///   "0110" = 中央 + 右と下が壁     → 左上コーナー
    def drawTrblIcon(canvas: Canvas, key: String): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let w = canvas.getWidth();
        let h = canvas.getHeight();
        let cs = w / 3.0;
        gc.clearRect(0.0, 0.0, w, h);
        let t = String.charAt(0, key) == '1';
        let r = String.charAt(1, key) == '1';
        let b = String.charAt(2, key) == '1';
        let l = String.charAt(3, key) == '1';
        // 4 隅 (灰、neutral)
        drawIconCell(gc, 0.0, 0.0, cs, IconCell.Corner);
        drawIconCell(gc, 2.0, 0.0, cs, IconCell.Corner);
        drawIconCell(gc, 0.0, 2.0, cs, IconCell.Corner);
        drawIconCell(gc, 2.0, 2.0, cs, IconCell.Corner);
        // 中央 (常に壁=この TRBL を選択中のセル)
        drawIconCell(gc, 1.0, 1.0, cs, IconCell.Center);
        // 上下左右
        drawIconCell(gc, 1.0, 0.0, cs, if (t) IconCell.Wall else IconCell.Empty);
        drawIconCell(gc, 2.0, 1.0, cs, if (r) IconCell.Wall else IconCell.Empty);
        drawIconCell(gc, 1.0, 2.0, cs, if (b) IconCell.Wall else IconCell.Empty);
        drawIconCell(gc, 0.0, 1.0, cs, if (l) IconCell.Wall else IconCell.Empty)
    }

    enum IconCell with Eq {
        case Center    // 中央: 選択中の壁
        case Wall      // 隣接: 壁あり (キーの bit=1)
        case Empty     // 隣接: 壁なし (キーの bit=0)
        case Corner    // 4 隅: neutral
    }

    def drawIconCell(gc: GraphicsContext, col: Float64, row: Float64, cs: Float64,
                       kind: IconCell): Unit \ IO = {
        let x = col * cs;
        let y = row * cs;
        let fill = match kind {
            case IconCell.Center => Color.rgb(255, 230, 60)  // 黄: 選択中
            case IconCell.Wall   => Color.rgb(180, 180, 200) // 明灰: 壁
            case IconCell.Empty  => Color.rgb(60, 60, 70)    // 暗: 空セル
            case IconCell.Corner => Color.rgb(40, 40, 50)    // ほぼ黒: neutral
        };
        gc.setFill(fill);
        gc.fillRect(x, y, cs, cs)
    }

    /// Tileset Canvas クリック: Walls Palette の cellW/cellH/marginX/Y と paletteZoom を使い、
    /// 選択中タイルの (srcX, srcY) を計算して、選択中 TRBL に割当てて Material を保存。
    def wireMaterialsTilesetClick(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let trblOpt = MapEditorState.getSelectedTrbl(state#mapEditor);
                let matOpt = MapEditorState.getEditingMaterial(state#mapEditor);
                match (trblOpt, matOpt) {
                    case (Some(key), Some(mat)) => {
                        let (cw, ch, mx, my) = wallsPaletteCellAndMargin(state);
                        let strideX = cw + mx;
                        let strideY = ch + my;
                        if (strideX <= 0i32 or strideY <= 0i32) ()
                        else {
                            let zoom = MapEditorState.getPaletteZoom(state#mapEditor);
                            let imgX = event.getX() / zoom;
                            let imgY = event.getY() / zoom;
                            let col = Float64.truncateToInt32(imgX / Int32.toFloat64(strideX));
                            let row = Float64.truncateToInt32(imgY / Int32.toFloat64(strideY));
                            let srcX = col * strideX;
                            let srcY = row * strideY;
                            let md = MapResource.materialData(mat);
                            let newWallMap = Map.insert(key, (srcX, srcY), md#wallMap);
                            let newMd: MapResource.MaterialData = {wallMap = newWallMap | md};
                            let newMat = MapResource.Material.Material(newMd);
                            MapEditorState.setEditingMaterial(state#mapEditor, Some(newMat));
                            saveMaterial(state);
                            refreshMaterialsTab(state);
                            redrawCanvas(state)
                        }
                    }
                    case _ => ()
                }
            }
        })
    }

    /// Walls Palette の (cellW, cellH, marginX, marginY)。未設定時は (16,16,0,0)。
    /// Materials タブからも参照するため pub にしてある。
    pub def wallsPaletteCellAndMargin(state: IdeState.IdeState):
            (Int32, Int32, Int32, Int32) \ IO =
        match MapEditorState.getPaletteForLayer(state#mapEditor,
                                                  MapEditorState.LayerMode.Walls) {
            case Some(p) => (p#cellW, p#cellH, p#marginX, p#marginY)
            case None    => (16i32, 16i32, 0i32, 0i32)
        }

    /// 編集中 Material を editingMaterialPath に保存する。
    def saveMaterial(state: IdeState.IdeState): Unit \ IO =
        run {
            saveMaterialIO(state)
        } with Fs.FileWrite.runWithIO

    def saveMaterialIO(state: IdeState.IdeState): Unit \ {IO, Fs.FileWrite} =
        match (MapEditorState.getEditingMaterialPath(state#mapEditor),
               MapEditorState.getEditingMaterial(state#mapEditor)) {
            case (Some(path), Some(mat)) =>
                match Persistence.save(path, mat) {
                    case Ok(_)    => println("[MapEditor] material saved: ${displayName(path)}")
                    case Err(msg) => println("[MapEditor] material save failed: ${msg}")
                }
            case _ => ()
        }

    /// Materials タブ全体の表示を更新する。Material 名 / セル選択ハイライト / tileset プレビュー。
    /// Level 選択時 / TRBL セル選択時 / wallMap 更新時に呼ぶ。
    pub def refreshMaterialsTab(state: IdeState.IdeState): Unit \ IO = {
        updateMaterialsLabel(state);
        updateWallMapGridHighlight(state);
        updateMaterialsStatus(state);
        drawMaterialsTileset(state)
    }

    def updateMaterialsLabel(state: IdeState.IdeState): Unit \ IO =
        match Array.get(0, state#widgets#mapMaterialsLabel) {
            case None        => ()
            case Some(label) => {
                let text = match MapEditorState.getEditingLevel(state#mapEditor) {
                    case None        => "Material: (未選択)"
                    case Some(level) =>
                        let id = MapResource.levelData(level)#materialId;
                        let suffix = match MapEditorState.getEditingMaterial(state#mapEditor) {
                            case None    => " (見つかりません)"
                            case Some(_) => ""
                        };
                        "Material: ${id}${suffix}"
                };
                label.setText(text)
            }
        }

    /// GridPane の各 StackPane を巡って、selectedTrbl のセルだけハイライト色にする。
    def updateWallMapGridHighlight(state: IdeState.IdeState): Unit \ IO =
        match Array.get(0, state#widgets#mapMaterialsWallMapGrid) {
            case None       => ()
            case Some(grid) => {
                let sel = MapEditorState.getSelectedTrbl(state#mapEditor);
                let keys = MapResource.wallMapKeys() |> List.toVector;
                let children = grid.getChildren();
                let n = children.size();
                List.forEach(idx -> {
                    if (idx < n) {
                        let nodeObj = children.get(idx);
                        let pane: StackPane = unchecked_cast(nodeObj as StackPane);
                        let key = match Vector.nth(idx, keys) {
                            case Some(k) => k
                            case None    => ""
                        };
                        let isSelected = match sel {
                            case Some(s) => s == key
                            case None    => false
                        };
                        if (isSelected) pane.setStyle(cellStyleSelected())
                        else pane.setStyle(cellStyleNormal())
                    } else ()
                }, List.range(0, 16))
            }
        }

    /// 選択中 TRBL の意味を Materials タブの Status Label に表示する。
    /// 未選択時は空欄。
    def updateMaterialsStatus(state: IdeState.IdeState): Unit \ IO =
        match Array.get(0, state#widgets#mapMaterialsStatus) {
            case None        => ()
            case Some(label) => {
                let text = match MapEditorState.getSelectedTrbl(state#mapEditor) {
                    case None      => ""
                    case Some(key) => "${key}: ${trblDescription(key)}"
                };
                label.setText(text)
            }
        }

    /// TRBL キーごとのタイル種別の説明文。Materials タブで TRBL セルを選んだ時に表示する。
    /// 慣習: 1 = その方向が壁、0 = その方向が床 or マップ外 でない空。
    /// 順序は T (上), R (右), B (下), L (左)。
    def trblDescription(key: String): String = match key {
        case "0000" => "孤立した壁 (周囲に壁なし)"
        case "0001" => "左端 (左にだけ壁が続く)"
        case "0010" => "上端 (下にだけ壁が続く)"
        case "0011" => "右上の入隅 (下と左に壁)"
        case "0100" => "右端 (右にだけ壁が続く)"
        case "0101" => "横一直線 (左右に壁)"
        case "0110" => "左上の入隅 (右と下に壁)"
        case "0111" => "上端 T 字 (上以外に壁)"
        case "1000" => "下端 (上にだけ壁が続く)"
        case "1001" => "右下の入隅 (上と左に壁)"
        case "1010" => "縦一直線 (上下に壁)"
        case "1011" => "右端 T 字 (右以外に壁)"
        case "1100" => "左下の入隅 (上と右に壁)"
        case "1101" => "下端 T 字 (下以外に壁)"
        case "1110" => "左端 T 字 (左以外に壁)"
        case "1111" => "壁の中央 (上下左右すべて壁)"
        case _      => "不明"
    }

    /// Materials タブの tileset プレビュー Canvas を Walls Palette 設定で描画する。
    /// paletteZoom 倍率で拡縮、選択中 TRBL の割当タイルを (cellW × cellH) の黄色枠で表示。
    def drawMaterialsTileset(state: IdeState.IdeState): Unit \ IO = {
        let canvasOpt = Array.get(0, state#widgets#mapMaterialsTilesetCanvas);
        let imgOpt = Array.get(0, state#widgets#mapWallsImage);
        match canvasOpt {
            case None         => ()
            case Some(canvas) => {
                let gc = canvas.getGraphicsContext2D();
                gc.setImageSmoothing(false);
                let zoom = MapEditorState.getPaletteZoom(state#mapEditor);
                match imgOpt {
                    case None      => {
                        gc.clearRect(0.0, 0.0, canvas.getWidth(), canvas.getHeight())
                    }
                    case Some(img) => {
                        let iw = img.getWidth();
                        let ih = img.getHeight();
                        let dw = iw * zoom;
                        let dh = ih * zoom;
                        canvas.setWidth(dw);
                        canvas.setHeight(dh);
                        gc.clearRect(0.0, 0.0, dw, dh);
                        gc.drawImage(img, 0.0, 0.0, iw, ih, 0.0, 0.0, dw, dh);
                        // 選択中 TRBL の割当タイルを枠で表示 (Walls Palette の cellW × cellH)
                        match (MapEditorState.getSelectedTrbl(state#mapEditor),
                               MapEditorState.getEditingMaterial(state#mapEditor)) {
                            case (Some(key), Some(mat)) => {
                                let md = MapResource.materialData(mat);
                                match Map.get(key, md#wallMap) {
                                    case Some((sx, sy)) => {
                                        let (cw, ch, _, _) = wallsPaletteCellAndMargin(state);
                                        let cwF = Int32.toFloat64(cw);
                                        let chF = Int32.toFloat64(ch);
                                        gc.setStroke(Color.rgb(255, 230, 60));
                                        gc.setLineWidth(2.0);
                                        gc.strokeRect(Int32.toFloat64(sx) * zoom,
                                                       Int32.toFloat64(sy) * zoom,
                                                       cwF * zoom, chF * zoom)
                                    }
                                    case None => ()
                                }
                            }
                            case _ => ()
                        }
                    }
                }
            }
        }
    }
}
