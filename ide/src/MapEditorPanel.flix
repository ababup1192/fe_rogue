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
    import java.lang.Number
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
    import javafx.scene.input.KeyEvent
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
                let rawMatOpt: Option[MapResource.Material] = Persistence.load(path);
                // 旧 4-bit キー ("0101" 等) は UI に出ないので、ロード時にクリーンアップ
                let matOpt = Option.map(stripLegacyWallMapKeys, rawMatOpt);
                MapEditorState.setEditingMaterial(state#mapEditor, matOpt);
                MapEditorState.setEditingMaterialPath(state#mapEditor,
                    if (Option.isEmpty(matOpt)) None else Some(path));
                match matOpt {
                    case None    => println("[MapEditor] material not found: ${path}")
                    case Some(_) => {
                        // 旧キーが除去されたなら JSON にも反映 (wallMap サイズが減ったかで判定)
                        let beforeSize = match rawMatOpt {
                            case Some(m) => Map.size(MapResource.materialData(m)#wallMap)
                            case None    => 0
                        };
                        let afterSize = match matOpt {
                            case Some(m) => Map.size(MapResource.materialData(m)#wallMap)
                            case None    => 0
                        };
                        if (beforeSize > afterSize) {
                            saveMaterial(state);
                            println("[MapEditor] cleaned ${beforeSize - afterSize} legacy 4-bit wallMap key(s): ${materialId}")
                        } else ();
                        println("[MapEditor] material loaded: ${materialId}")
                    }
                }
            }
        }

    /// Material.wallMap から旧 4-bit キー (例: "0101", "1111") を除去する。
    /// 4-bit キーは Phase 1 の 4-trit システムへ移行する前のフォールバック仕様。
    /// 新しい UI には現れないため、ロード時にクリーンアップして見えない残骸を防ぐ。
    def stripLegacyWallMapKeys(mat: MapResource.Material): MapResource.Material = {
        let md = MapResource.materialData(mat);
        let cleaned = Map.filterWithKey((k, _) -> not isLegacy4BitKey(k), md#wallMap);
        let newMd: MapResource.MaterialData = {wallMap = cleaned | md};
        MapResource.Material.Material(newMd)
    }

    /// 4-bit キー判定: 1 文字目が '0' or '1' なら旧仕様 (4-trit は W/F/E で始まる)。
    def isLegacy4BitKey(key: String): Bool =
        if (String.length(key) == 0) false
        else {
            let c = String.charAt(0, key);
            c == '0' or c == '1'
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
                let selTrbl = MapEditorState.getSelectedTrbl(state#mapEditor);
                let selRange = MapEditorState.getSelectedRange(state#mapEditor);
                MapGridCanvas.drawLevel(canvas, level, MapGridCanvas.defaultCellPx(),
                                          wImg, fImg, vis, zoom, mat, selTrbl, selRange)
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
        // Palette canvas のピンチズーム配線 (paletteZoom を更新 + Palette/Materials 両方再描画)
        match Array.get(0, state#widgets#mapPaletteCanvas) {
            case Some(canvas) => wireTilesetZoom(state, canvas)
            case None         => ()
        };
        // 起動直後の widget 値を現 layer の設定と同期 (Entities なら disable)
        let mode = MapEditorState.getLayerMode(state#mapEditor);
        syncPaletteWidgetsForLayer(state, mode);
        // Palette / Entity セクションの表示も現 layer に合わせる
        updateSideSection(state, mode)
    }

    /// Palette / Materials の tileset Canvas どちらに貼っても良い共通ピンチハンドラ。
    /// macOS trackpad の pinch in/out で `event.getZoomFactor()` (incremental) が来るので、
    /// 現 paletteZoom に乗算してクランプ → Palette と Materials 両方の tileset 表示を再描画。
    /// 同じ paletteZoom を共有するため、どちらの canvas でピンチしても両方が連動する。
    def wireTilesetZoom(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnZoom(new EventHandler[ZoomEvent] {
            def handle(_this: EventHandler[ZoomEvent], event: ZoomEvent): Unit \ IO = {
                let factor = event.getZoomFactor();
                let cur = MapEditorState.getPaletteZoom(state#mapEditor);
                MapEditorState.setPaletteZoom(state#mapEditor, cur * factor);
                redrawAllTilesetViews(state);
                event.consume()
            }
        })
    }

    /// Palette / Materials 両方の tileset プレビューを再描画する。
    /// paletteZoom や Walls Palette の cellW/cellH/marginX/marginY を変更したあとに呼ぶ。
    pub def redrawAllTilesetViews(state: IdeState.IdeState): Unit \ IO = {
        drawPalette(state);
        drawMaterialsTileset(state)
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
    /// setOnAction を使う (ChangeListener だと初回 null → 値の遷移で発火しないケースがある)。
    def wirePaletteTextureCombo(state: IdeState.IdeState, combo: ComboBox[String]): Unit \ IO = {
        combo.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                let newVal = combo.getValue();
                if (Object.isNull(newVal)) ()
                else {
                    let mode = MapEditorState.getLayerMode(state#mapEditor);
                    match MapEditorState.getPaletteForLayer(state#mapEditor, mode) {
                        case None    => ()
                        case Some(p) => {
                            // 既に同じ Sheet が選ばれていたら no-op
                            // (Map 切替 / clearSelection → setValue の連鎖で onAction が空打ちされるのを防ぐ)
                            let alreadySame = match p#textureName {
                                case Some(cur) => cur == newVal
                                case None      => false
                            };
                            if (alreadySame) ()
                            else {
                                let next: MapEditorState.LayerPalette =
                                    {textureName = Some(newVal) | p};
                                MapEditorState.setPaletteForLayer(state#mapEditor, mode, next);
                                MapEditorState.setSelectedSrc(state#mapEditor, None);
                                match Array.get(0, state#widgets#mapPaletteStatus) {
                                    case Some(label) => label.setText("未選択")
                                    case None        => ()
                                };
                                loadImageForLayer(state, mode);
                                redrawAllTilesetViews(state);
                                redrawCanvas(state);
                                autoSave(state);
                                println("[MapEditor] palette sheet (${mode}) = ${newVal}")
                            }
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
                            redrawAllTilesetViews(state);
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
                            redrawAllTilesetViews(state);
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
                        case None    => cb.getSelectionModel().clearSelection()
                    }
                    case None    => cb.getSelectionModel().clearSelection()
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

    /// 「- Delete」ボタン: 選択中の Map と関連 Material を削除する。
    pub def wireDeleteLevelButton(state: IdeState.IdeState, btn: Button): Unit \ IO = {
        btn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                promptAndDeleteCurrent(state)
        })
    }

    /// Map Canvas 上の Pencil / RangeSelect トグルボタン配線。
    /// 一方を押すともう一方は非選択になる (排他)。MapEditorState の editTool を更新する。
    pub def wireToolButtons(state: IdeState.IdeState,
                              pencilBtn: ToggleButton,
                              rangeBtn: ToggleButton): Unit \ IO = {
        // 初期表示: 現在の editTool に合わせる (default = Pencil)
        let tool = MapEditorState.getEditTool(state#mapEditor);
        pencilBtn.setSelected(MapEditorState.EditTool.Pencil == tool);
        rangeBtn.setSelected(MapEditorState.EditTool.RangeSelect == tool);
        pencilBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                // 排他: もう一方を解除し、Pencil を選択状態に固定
                MapEditorState.setEditTool(state#mapEditor,
                    MapEditorState.EditTool.Pencil);
                pencilBtn.setSelected(true);
                rangeBtn.setSelected(false);
                // モード切替で範囲選択は解除
                MapEditorState.setSelectedRange(state#mapEditor, None);
                redrawCanvas(state)
            }
        });
        rangeBtn.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO = {
                MapEditorState.setEditTool(state#mapEditor,
                    MapEditorState.EditTool.RangeSelect);
                pencilBtn.setSelected(false);
                rangeBtn.setSelected(true);
                redrawCanvas(state)
            }
        })
    }

    /// 削除フロー: 選択中 Map → 確認ダイアログ → ファイル削除 (map + material) → ListView refresh。
    def promptAndDeleteCurrent(state: IdeState.IdeState): Unit \ IO = {
        match (IdeState.getCurrentProjectRoot(state),
               MapEditorState.getSelectedLevelPath(state#mapEditor)) {
            case (Some(root), Some(mapPath)) => {
                let mapName = stripMapJsonExt(displayName(mapPath));
                let dialog: Dialog[ButtonType] = new Dialog();
                dialog.setTitle("Delete Map");
                dialog.setHeaderText("「${mapName}」を削除しますか？");
                let pane = dialog.getDialogPane();
                let buttonTypes = pane.getButtonTypes();
                discard buttonTypes.add(ButtonType.OK);
                discard buttonTypes.add(ButtonType.CANCEL);
                pane.setContentText(
                    "以下のファイルを削除します:\n"
                    + "  - assets/maps/${mapName}.map.json\n"
                    + "  - assets/materials/${mapName}.material.json (もしあれば)\n\n"
                    + "この操作は取り消せません。"
                );
                let result = dialog.showAndWait();
                if (result.isPresent()) {
                    let bt = result.get();
                    let okBt = ButtonType.OK;
                    if (okBt.equals(bt))
                        deleteMapAndMaterial(state, root, mapPath, mapName)
                    else ()
                } else ()
            }
            case _ => showAlert("削除する Map が選択されていません")
        }
    }

    /// `.map.json` 拡張子を除いた名前を返す ("new_room.map.json" → "new_room")。
    def stripMapJsonExt(filename: String): String = {
        let suffix = ".map.json";
        let len = String.length(filename);
        let sufLen = String.length(suffix);
        if (len > sufLen and String.endsWith(suffix = suffix, filename))
            filename.substring(0, len - sufLen)
        else filename
    }

    /// map.json と関連する material.json を削除し、ListView を refresh する。
    def deleteMapAndMaterial(state: IdeState.IdeState, root: String,
                                mapPath: String, mapName: String): Unit \ IO = {
        let matPath = root + "/assets/materials/" + mapName + ".material.json";
        let mapDeleted = deleteFileQuietly(mapPath);
        let matDeleted = deleteFileQuietly(matPath);
        if (mapDeleted) println("[MapEditor] deleted: ${mapPath}") else ();
        if (matDeleted) println("[MapEditor] deleted: ${matPath}") else ();
        // 選択解除 + editingLevel/Material をクリア
        MapEditorState.setSelectedLevelPath(state#mapEditor, None);
        MapEditorState.setEditingLevel(state#mapEditor, None);
        MapEditorState.setEditingMaterial(state#mapEditor, None);
        MapEditorState.setEditingMaterialPath(state#mapEditor, None);
        MapEditorState.clearUndoStack(state#mapEditor);
        // Map Canvas をクリア + ListView 再 glob
        match Array.get(0, state#widgets#mapGridCanvas) {
            case Some(c) => MapGridCanvas.clear(c)
            case None    => ()
        };
        let mapFiles = run {
            findMapFiles(root)
        } with Fs.Glob.runWithIO;
        MapEditorState.setLevelFiles(state#mapEditor, mapFiles);
        populateMapList(state);
        refreshMaterialsTab(state)
    }

    /// ファイルを削除する。失敗しても例外を投げず、結果を Bool で返す。
    def deleteFileQuietly(path: String): Bool \ IO = {
        let f = new File(path);
        if (f.exists()) f.delete()
        else false
    }

    /// 新規 Level 作成 UI フロー。Custom Dialog で名前 + 幅 + 高さを取得。
    /// tileSize は空マップから始まり、最初のタイル配置時にその Palette cellW で自動確定する。
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

                let grid = new GridPane();
                grid.setHgap(8.0);
                grid.setVgap(8.0);
                grid.add(unchecked_cast(new Label("名前:") as Node),         0i32, 0i32);
                grid.add(unchecked_cast(nameField as Node),                  1i32, 0i32);
                grid.add(unchecked_cast(new Label("幅 (タイル数):") as Node),  0i32, 1i32);
                grid.add(unchecked_cast(widthSpinner as Node),               1i32, 1i32);
                grid.add(unchecked_cast(new Label("高さ (タイル数):") as Node), 0i32, 2i32);
                grid.add(unchecked_cast(heightSpinner as Node),              1i32, 2i32);
                pane.setContent(unchecked_cast(grid as Node));

                let result = dialog.showAndWait();
                if (result.isPresent()) {
                    let bt = result.get();
                    let okBt = ButtonType.OK;
                    if (okBt.equals(bt)) {
                        let name = nameField.getText();
                        let widthV    = widthSpinner.getValue().intValue();
                        let heightV   = heightSpinner.getValue().intValue();
                        if (Object.isNull(name) or name == "")
                            showAlert("名前を入力してください")
                        else createNewAt(state, root, name, widthV, heightV)
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
                      width: Int32, height: Int32): Unit \ IO = {
        let mapPath = root + "/assets/maps/" + name + ".map.json";
        let matPath = root + "/assets/materials/" + name + ".material.json";
        if (fileExists(mapPath))
            showAlert("ファイルが既に存在します: ${name}.map.json")
        else
            saveAndRefresh(state, root, mapPath, matPath, name, width, height)
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

    /// 空 Level + 空 Material をそれぞれ path に保存して ListView を refresh する。
    /// Map と同名の Material を生成 (materialId = name) して完全分離する。
    def saveAndRefresh(state: IdeState.IdeState, root: String,
                         mapPath: String, matPath: String, name: String,
                         width: Int32, height: Int32): Unit \ IO = {
        let level = buildBlankLevel(name, width, height);
        let material = buildBlankMaterial();
        let saveResult = run {
            match Persistence.save(matPath, material) {
                case Err(msg) => Err(msg)
                case Ok(_)    => Persistence.save(mapPath, level)
            }
        } with Fs.FileWrite.runWithIO;
        match saveResult {
            case Err(msg) => showAlert("保存失敗: ${msg}")
            case Ok(_)    => {
                println("[MapEditor] created: ${mapPath} (${width}x${height})");
                println("[MapEditor] created: ${matPath}");
                refreshLevelListAndSelect(state, root, mapPath)
            }
        }
    }

    /// 指定サイズの空 Level: タイル無し / 壁無し / entity 無し。
    /// materialId は `name` (Map 名と同じ) を採用 → assets/materials/{name}.material.json を参照。
    /// 最初に Floor / Walls どちらかでタイルを置いた瞬間に Palette の cellW が
    /// `Level.tileSize` に反映される (MapGridCanvas の placeWithSelectedSrc を参照)。
    /// それまでは仮の tileSize=16 を入れておく。
    def buildBlankLevel(name: String, width: Int32, height: Int32): MapResource.Level = {
        let data: MapResource.LevelData = {
            tileSize      = 16,
            width         = width,
            height        = height,
            materialId    = name,
            manualTiles   = (Nil: List[MapResource.ManualTile]),
            decorTiles    = (Nil: List[MapResource.ManualTile]),
            entities      = (Nil: List[MapResource.Entity]),
            editorPalette = (None: Option[MapResource.EditorPalette]),
            intGrid       = (Vector#{}: Vector[Int32])
        };
        MapResource.Level.Level(data)
    }

    /// 新規 Map 用の空 Material: wallMap は完全に空 (Map.empty) で、ユーザが Materials タブで
    /// 1 つずつ確定していく。tileset は仮の "inca_tileset" (Materials タブで Sheet を選び直すと
    /// その時点で walls Palette の textureName が wallMap への保存に使われる)。
    def buildBlankMaterial(): MapResource.Material = {
        let data: MapResource.MaterialData = {
            tileset      = "inca_tileset",
            tileSize     = 16,
            wallMap      = (Map.empty(): Map[String, (Int32, Int32)]),
            floorPalette = (Nil: List[(Int32, Int32)]),
            decorPalette = (Nil: List[(Int32, Int32)]),
            autoRules    = (Nil: List[MapResource.AutoRule])
        };
        MapResource.Material.Material(data)
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
        match Array.get(0, state#widgets#mapMaterialsWallMapBox) {
            case None      => ()
            case Some(box) => buildWallMapGrid(state, box)
        };
        match Array.get(0, state#widgets#mapMaterialsTilesetCanvas) {
            case None         => ()
            case Some(canvas) => {
                wireMaterialsTilesetClick(state, canvas);
                // ピンチでも Palette と同じ paletteZoom を更新する (連動)
                wireTilesetZoom(state, canvas)
            }
        };
        initRulesEditor(state);
        refreshMaterialsTab(state)
    }

    /// AutoRule エディタの初期化: ListView 選択、Add/Remove ボタン、Pattern grid、
    /// Name field、Chance Spinner のリスナーを配線する。
    def initRulesEditor(state: IdeState.IdeState): Unit \ IO = {
        // Pattern 3×3 grid を構築
        match Array.get(0, state#widgets#mapRulePatternGrid) {
            case None       => ()
            case Some(grid) => buildPatternGrid(state, grid)
        };
        // Chance Spinner の factory
        match Array.get(0, state#widgets#mapRuleChanceSpinner) {
            case None     => ()
            case Some(sp) => {
                let f = new SpinnerValueFactory$IntegerSpinnerValueFactory(0i32, 100i32, 100i32);
                sp.setValueFactory(unchecked_cast(f as SpinnerValueFactory[Integer]));
                sp.valueProperty().addListener(new ChangeListener[Integer] {
                    def changed(_cThis: ChangeListener[Integer],
                                  _obs: ObservableValue[JObject],
                                  _old: Integer, newVal: Integer): Unit \ IO = {
                        if (Object.isNull(newVal)) ()
                        else updateRuleField(state, "chance", newVal.intValue())
                    }
                })
            }
        };
        // Name field のリスナー
        match Array.get(0, state#widgets#mapRuleNameField) {
            case None     => ()
            case Some(tf) => {
                tf.textProperty().addListener(new ChangeListener[String] {
                    def changed(_cThis: ChangeListener[String],
                                  _obs: ObservableValue[JObject],
                                  _old: String, newVal: String): Unit \ IO = {
                        if (Object.isNull(newVal)) ()
                        else updateRuleName(state, newVal)
                    }
                })
            }
        };
        // Add / Remove ボタン
        match Array.get(0, state#widgets#mapRuleAddBtn) {
            case None     => ()
            case Some(btn) => btn.setOnAction(new EventHandler[ActionEvent] {
                def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                    addRule(state)
            })
        };
        match Array.get(0, state#widgets#mapRuleRemoveBtn) {
            case None     => ()
            case Some(btn) => btn.setOnAction(new EventHandler[ActionEvent] {
                def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                    removeSelectedRule(state)
            })
        };
        // ListView 選択リスナー
        match Array.get(0, state#widgets#mapRuleList) {
            case None     => ()
            case Some(lv) => {
                let prop = lv.getSelectionModel().selectedIndexProperty();
                prop.addListener(new ChangeListener[Number] {
                    def changed(_cThis: ChangeListener[Number],
                                  _obs: ObservableValue[JObject],
                                  _old: Number, newVal: Number): Unit \ IO = {
                        if (Object.isNull(newVal)) ()
                        else {
                            let i = newVal.intValue();
                            if (i < 0i32) MapEditorState.setEditingRuleIndex(state#mapEditor, None)
                            else MapEditorState.setEditingRuleIndex(state#mapEditor, Some(i));
                            refreshRulesUI(state)
                        }
                    }
                })
            }
        }
    }

    /// Pattern 3×3 grid のセル (9 個) を構築し、クリックで値サイクルさせる。
    def buildPatternGrid(state: IdeState.IdeState, grid: GridPane): Unit \ IO = {
        grid.getChildren().clear();
        List.forEach(idx -> {
            let r = idx / 3;
            let c = Int32.remainder(idx, 3);
            let pane = makePatternCell(state, idx);
            grid.add(unchecked_cast(pane as Node), c, r)
        }, List.range(0, 9))
    }

    /// 1 セル: 32x32 の Canvas、クリックで値サイクル (-1=任意 → 0=空 → 1=床 → 2=壁 → -1...)。
    /// 中央セル (idx=4) は常に「自セル」表示で編集不可。
    def makePatternCell(state: IdeState.IdeState, idx: Int32): StackPane \ IO = {
        let pane = new StackPane();
        let canvas = new Canvas(32.0, 32.0);
        drawPatternCellValue(canvas, -1i32, idx == 4i32);
        pane.getChildren().add(unchecked_cast(canvas as Node));
        pane.setPrefSize(32.0, 32.0);
        pane.setMinSize(32.0, 32.0);
        pane.setUserData(unchecked_cast(canvas as JObject));
        if (idx == 4i32) ()  // 中央は編集不可
        else {
            pane.setStyle("-fx-cursor: hand;");
            pane.setOnMouseClicked(new EventHandler[MouseEvent] {
                def handle(_this: EventHandler[MouseEvent], _e: MouseEvent): Unit \ IO =
                    cyclePatternCell(state, idx)
            })
        };
        pane
    }

    /// パターンセルの色: -1=灰 (任意), 0=暗 (空), 1=茶 (床), 2=明灰 (壁), 中央=黄 (自セル)。
    def drawPatternCellValue(canvas: Canvas, value: Int32, isCenter: Bool): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let w = canvas.getWidth();
        let h = canvas.getHeight();
        gc.clearRect(0.0, 0.0, w, h);
        let fill = if (isCenter)        Color.rgb(255, 230, 60)   // 黄
                   else if (value == 0i32) Color.rgb(60, 60, 70)  // 空
                   else if (value == 1i32) Color.rgb(140, 100, 60) // 床
                   else if (value == 2i32) Color.rgb(180, 180, 200) // 壁
                   else                    Color.rgb(100, 100, 110); // 任意 (-1)
        gc.setFill(fill);
        gc.fillRect(1.0, 1.0, w - 2.0, h - 2.0);
        gc.setStroke(Color.rgb(80, 80, 90));
        gc.setLineWidth(1.0);
        gc.strokeRect(0.5, 0.5, w - 1.0, h - 1.0)
    }

    /// パターンセルの値を -1 → 0 → 1 → 2 → -1 ... と循環させ、Rule を更新する。
    def cyclePatternCell(state: IdeState.IdeState, idx: Int32): Unit \ IO = {
        match MapEditorState.getEditingRuleIndex(state#mapEditor) {
            case None        => ()
            case Some(ruleI) => {
                match MapEditorState.getEditingMaterial(state#mapEditor) {
                    case None      => ()
                    case Some(mat) => {
                        let md = MapResource.materialData(mat);
                        match List.nth(ruleI, md#autoRules) {
                            case None       => ()
                            case Some(rule) => {
                                let curVal = match Vector.nth(idx, rule#pattern) {
                                    case Some(v) => v
                                    case None    => -1i32
                                };
                                let nextVal = if (curVal == -1i32) 0i32
                                              else if (curVal == 0i32) 1i32
                                              else if (curVal == 1i32) 2i32
                                              else -1i32;
                                let newPattern = Vector.toList(rule#pattern)
                                    |> List.mapWithIndex((i, v) ->
                                          if (i == idx) nextVal else v)
                                    |> List.toVector;
                                let newRule = {pattern = newPattern | rule};
                                replaceRule(state, ruleI, newRule);
                                refreshRulesUI(state);
                                MapEditorPanel.redrawCanvas(state)
                            }
                        }
                    }
                }
            }
        }
    }

    def updateRuleField(state: IdeState.IdeState, fieldName: String, value: Int32): Unit \ IO = {
        match MapEditorState.getEditingRuleIndex(state#mapEditor) {
            case None        => ()
            case Some(ruleI) => {
                match MapEditorState.getEditingMaterial(state#mapEditor) {
                    case None      => ()
                    case Some(mat) => {
                        let md = MapResource.materialData(mat);
                        match List.nth(ruleI, md#autoRules) {
                            case None       => ()
                            case Some(rule) =>
                                let newRule = if (fieldName == "chance")
                                                 {chance = Int32.toFloat64(value) / 100.0f64 | rule}
                                              else rule;
                                replaceRule(state, ruleI, newRule);
                                MapEditorPanel.redrawCanvas(state)
                        }
                    }
                }
            }
        }
    }

    def updateRuleName(state: IdeState.IdeState, name: String): Unit \ IO = {
        match MapEditorState.getEditingRuleIndex(state#mapEditor) {
            case None        => ()
            case Some(ruleI) => {
                match MapEditorState.getEditingMaterial(state#mapEditor) {
                    case None      => ()
                    case Some(mat) => {
                        let md = MapResource.materialData(mat);
                        match List.nth(ruleI, md#autoRules) {
                            case None       => ()
                            case Some(rule) => {
                                let newRule = {name = name | rule};
                                replaceRule(state, ruleI, newRule);
                                refreshRuleListItems(state)
                            }
                        }
                    }
                }
            }
        }
    }

    def addRule(state: IdeState.IdeState): Unit \ IO = {
        match MapEditorState.getEditingMaterial(state#mapEditor) {
            case None      => ()
            case Some(mat) => {
                let md = MapResource.materialData(mat);
                let newRule: MapResource.AutoRule = {
                    name    = "Rule ${List.length(md#autoRules) + 1}",
                    size    = 3i32,
                    pattern = Vector#{-1i32, -1i32, -1i32, -1i32, -1i32, -1i32, -1i32, -1i32, -1i32},
                    srcX    = 0i32,
                    srcY    = 0i32,
                    chance  = 1.0f64
                };
                let newRules = List.append(md#autoRules, newRule :: Nil);
                let newMd = {autoRules = newRules | md};
                let newMat = MapResource.Material.Material(newMd);
                MapEditorState.setEditingMaterial(state#mapEditor, Some(newMat));
                let newIdx = List.length(newRules) - 1;
                MapEditorState.setEditingRuleIndex(state#mapEditor, Some(newIdx));
                saveMaterial(state);
                refreshRulesUI(state);
                MapEditorPanel.redrawCanvas(state)
            }
        }
    }

    def removeSelectedRule(state: IdeState.IdeState): Unit \ IO = {
        match MapEditorState.getEditingRuleIndex(state#mapEditor) {
            case None        => ()
            case Some(ruleI) => {
                match MapEditorState.getEditingMaterial(state#mapEditor) {
                    case None      => ()
                    case Some(mat) => {
                        let md = MapResource.materialData(mat);
                        let newRules = md#autoRules
                            |> List.mapWithIndex((i, r) -> (i, r))
                            |> List.filterMap(pair -> {
                                let (i, r) = pair;
                                if (i == ruleI) None else Some(r)
                            });
                        let newMd = {autoRules = newRules | md};
                        let newMat = MapResource.Material.Material(newMd);
                        MapEditorState.setEditingMaterial(state#mapEditor, Some(newMat));
                        MapEditorState.setEditingRuleIndex(state#mapEditor, None);
                        saveMaterial(state);
                        refreshRulesUI(state);
                        MapEditorPanel.redrawCanvas(state)
                    }
                }
            }
        }
    }

    /// 指定 index の rule を新しいものに置換し、Material を保存する。
    def replaceRule(state: IdeState.IdeState, idx: Int32,
                      newRule: MapResource.AutoRule): Unit \ IO = {
        match MapEditorState.getEditingMaterial(state#mapEditor) {
            case None      => ()
            case Some(mat) => {
                let md = MapResource.materialData(mat);
                let newRules = List.mapWithIndex((i, r) ->
                    if (i == idx) newRule else r, md#autoRules);
                let newMd = {autoRules = newRules | md};
                let newMat = MapResource.Material.Material(newMd);
                MapEditorState.setEditingMaterial(state#mapEditor, Some(newMat));
                saveMaterial(state)
            }
        }
    }

    /// Rules UI 全体を再描画する: ListView, Editor の visibility, 値, Pattern grid。
    pub def refreshRulesUI(state: IdeState.IdeState): Unit \ IO = {
        refreshRuleListItems(state);
        let idxOpt = MapEditorState.getEditingRuleIndex(state#mapEditor);
        // Editor の visible 切替
        match Array.get(0, state#widgets#mapRuleEditor) {
            case None     => ()
            case Some(ed) => {
                let visible = Option.nonEmpty(idxOpt);
                ed.setVisible(visible);
                ed.setManaged(visible)
            }
        };
        // Editor 内の値を更新
        match idxOpt {
            case None   => ()
            case Some(i) => {
                match MapEditorState.getEditingMaterial(state#mapEditor) {
                    case None      => ()
                    case Some(mat) => {
                        let md = MapResource.materialData(mat);
                        match List.nth(i, md#autoRules) {
                            case None       => ()
                            case Some(rule) => updateRuleEditorWidgets(state, rule)
                        }
                    }
                }
            }
        }
    }

    def refreshRuleListItems(state: IdeState.IdeState): Unit \ IO =
        match (Array.get(0, state#widgets#mapRuleList),
               MapEditorState.getEditingMaterial(state#mapEditor)) {
            case (Some(lv), Some(mat)) => {
                let items = lv.getItems();
                items.clear();
                let md = MapResource.materialData(mat);
                List.forEach(r -> discard items.add(r#name), md#autoRules)
            }
            case _ => ()
        }

    def updateRuleEditorWidgets(state: IdeState.IdeState,
                                  rule: MapResource.AutoRule): Unit \ IO = {
        match Array.get(0, state#widgets#mapRuleNameField) {
            case Some(tf) => if (tf.getText() != rule#name) tf.setText(rule#name) else ()
            case None     => ()
        };
        match Array.get(0, state#widgets#mapRuleTileLabel) {
            case Some(lb) => lb.setText("Tile: (${rule#srcX}, ${rule#srcY}) | tileset クリックで変更")
            case None     => ()
        };
        match Array.get(0, state#widgets#mapRuleChanceSpinner) {
            case Some(sp) =>
                let pct = Float64.tryToInt32(rule#chance * 100.0f64) |> Option.getWithDefault(100i32);
                let factory = sp.getValueFactory();
                if (Object.isNull(factory)) ()
                else factory.setValue(Integer.valueOf(pct))
            case None     => ()
        };
        // Pattern grid のセル色を更新
        match Array.get(0, state#widgets#mapRulePatternGrid) {
            case None       => ()
            case Some(grid) => {
                let cells = grid.getChildren();
                let n = cells.size();
                List.forEach(idx -> {
                    if (idx < n) {
                        let nodeObj = cells.get(idx);
                        let pane: StackPane = unchecked_cast(nodeObj as StackPane);
                        let userData = pane.getUserData();
                        if (Object.isNull(userData)) ()
                        else {
                            let canvas: Canvas = unchecked_cast(userData as Canvas);
                            let v = match Vector.nth(idx, rule#pattern) {
                                case Some(x) => x
                                case None    => -1i32
                            };
                            drawPatternCellValue(canvas, v, idx == 4i32)
                        }
                    } else ()
                }, List.range(0, 9))
            }
        }
    }

    /// 4-trit (壁/床/空) パターンを「使用頻度別セクション」で VBox 内に構築する。
    /// 最初のセクションはトグル無しで常に展開、それ以外はトグルで折りたたみ可。
    /// 余白クリック (Box 直接) は選択解除。
    def buildWallMapGrid(state: IdeState.IdeState, box: VBox): Unit \ IO = {
        box.getChildren().clear();
        let sections = MapResource.wallMapSections();
        let n = List.length(sections);
        List.forEach(idx -> {
            match List.nth(idx, sections) {
                case None            => ()
                case Some((_, keys)) =>
                    if (idx == 0) addAlwaysOpenSection(state, box, keys)
                    else          addSection(state, box, keys, false)
            }
        }, List.range(0, n));
        // 余白クリック (Box 自体) で選択解除
        box.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], _e: MouseEvent): Unit \ IO = {
                MapEditorState.setSelectedTrbl(state#mapEditor, None);
                refreshMaterialsTab(state)
            }
        })
    }

    /// Section 1 用: トグル無しで常に展開された GridPane を直接 VBox に追加。
    def addAlwaysOpenSection(state: IdeState.IdeState, parentBox: VBox,
                                keys: List[String]): Unit \ IO = {
        let grid = buildSectionGrid(state, keys);
        discard parentBox.getChildren().add(unchecked_cast(grid as Node))
    }

    /// Section 2 以降用: disclosure 三角 (▾/▸) + GridPane を内 VBox で 1 セクションにラップ。
    /// エクスプローラ風: 背景透明・左寄せ。
    def addSection(state: IdeState.IdeState, parentBox: VBox,
                     keys: List[String], defaultOpen: Bool): Unit \ IO = {
        let sectionBox = new VBox();
        sectionBox.setSpacing(2.0);

        // テキストだとフォント高さに応じてベースラインの余白が出るので、Canvas で三角形を直接描画。
        // 20×20 px の領域内に三角形を fillPolygon で配置 → 余白完全コントロール。
        let toggleCanvas = new Canvas(20.0, 20.0);
        drawToggleTriangle(toggleCanvas, defaultOpen);
        toggleCanvas.setStyle("-fx-cursor: hand;");

        let grid = buildSectionGrid(state, keys);
        grid.setVisible(defaultOpen);
        grid.setManaged(defaultOpen);

        // 開閉状態を保持する Ref (mutable 不要、Array で代用)
        let openRef: Array[Bool, Static] = Array#{defaultOpen} @ Static;
        toggleCanvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], _e: MouseEvent): Unit \ IO = {
                let nowOpen = Array.get(0, openRef);
                let next = not nowOpen;
                Array.put(next, 0, openRef);
                grid.setVisible(next);
                grid.setManaged(next);
                drawToggleTriangle(toggleCanvas, next)
            }
        });

        discard sectionBox.getChildren().add(unchecked_cast(toggleCanvas as Node));
        discard sectionBox.getChildren().add(unchecked_cast(grid as Node));
        discard parentBox.getChildren().add(unchecked_cast(sectionBox as Node))
    }

    /// 20×20 Canvas に「▾ (開いた) / ▸ (閉じた)」三角形を描画する。
    def drawToggleTriangle(canvas: Canvas, open: Bool): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let w = canvas.getWidth();
        let h = canvas.getHeight();
        gc.clearRect(0.0, 0.0, w, h);
        gc.setFill(Color.rgb(204, 204, 204));
        let margin = 4.0;
        if (open) {
            // ▾ 下向き: 上辺の左右端と下辺の中央が頂点
            let xs = Vector#{margin, w - margin, w / 2.0};
            let ys = Vector#{margin, margin, h - margin};
            gc.fillPolygon(xs, ys, 3)
        } else {
            // ▸ 右向き: 左辺の上下端と右辺の中央が頂点
            let xs = Vector#{margin, margin, w - margin};
            let ys = Vector#{margin, h - margin, h / 2.0};
            gc.fillPolygon(xs, ys, 3)
        }
    }

    /// 4 列の GridPane に各セルを配置して返す (セクション内の共通レイアウト)。
    def buildSectionGrid(state: IdeState.IdeState, keys: List[String]): GridPane \ IO = {
        let grid = new GridPane();
        grid.setHgap(2.0);
        grid.setVgap(2.0);
        let nKeys = List.length(keys);
        List.forEach(idx -> {
            match List.nth(idx, keys) {
                case None     => ()
                case Some(k)  => {
                    let r = idx / 4;
                    let c = Int32.remainder(idx, 4);
                    let cell = makeWallMapCell(state, k);
                    grid.add(unchecked_cast(cell as Node), c, r)
                }
            }
        }, List.range(0, nKeys));
        grid
    }

    /// 1 個の TRBL セル (StackPane + Canvas アイコン + Label) を作る。
    /// userData に key を保存し、refresh 時の照合に使う。
    def makeWallMapCell(state: IdeState.IdeState, key: String): StackPane \ IO = {
        let pane = new StackPane();
        pane.setUserData(unchecked_cast(key as JObject));
        let iconCanvas = new Canvas(36.0, 36.0);
        drawTrblIcon(iconCanvas, key);
        let label = new Label(key);
        label.setStyle("-fx-text-fill: #ffe; -fx-font-size: 9px;");
        // 網掛け用 overlay (最前面、確定時に updateWallMapGridHighlight から描画/クリア)
        let overlay = new Canvas(56.0, 56.0);
        overlay.setMouseTransparent(true);
        StackPane.setAlignment(unchecked_cast(label as Node), Pos.BOTTOM_CENTER);
        StackPane.setAlignment(unchecked_cast(iconCanvas as Node), Pos.TOP_CENTER);
        pane.getChildren().add(unchecked_cast(iconCanvas as Node));   // index 0
        pane.getChildren().add(unchecked_cast(label as Node));        // index 1
        pane.getChildren().add(unchecked_cast(overlay as Node));      // index 2 (top)
        pane.setPrefSize(56.0, 56.0);
        pane.setMinSize(56.0, 56.0);
        pane.setStyle(cellStyleNormal());
        // セル自身を focusable にして、クリック後の BackSpace を確実に受け取る
        pane.setFocusTraversable(true);
        pane.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], e: MouseEvent): Unit \ IO = {
                MapEditorState.setSelectedTrbl(state#mapEditor, Some(key));
                pane.requestFocus();
                refreshMaterialsTab(state);
                // 親 GridPane の余白クリックハンドラに伝播させない
                e.consume()
            }
        });
        pane.setOnKeyPressed(new EventHandler[KeyEvent] {
            def handle(_this: EventHandler[KeyEvent], event: KeyEvent): Unit \ IO = {
                let code = event.getCode().toString();
                if (code == "ESCAPE") {
                    // 選択解除のみ (wallMap は触らない)
                    MapEditorState.setSelectedTrbl(state#mapEditor, None);
                    refreshMaterialsTab(state);
                    event.consume()
                } else if (code == "BACK_SPACE") {
                    // 1. wallMap からこの key の割り当てを削除 (確定取消)
                    match MapEditorState.getEditingMaterial(state#mapEditor) {
                        case None      => ()
                        case Some(mat) => {
                            let md = MapResource.materialData(mat);
                            if (Map.memberOf(key, md#wallMap)) {
                                let newWallMap = Map.remove(key, md#wallMap);
                                let newMd: MapResource.MaterialData =
                                    {wallMap = newWallMap | md};
                                let newMat = MapResource.Material.Material(newMd);
                                MapEditorState.setEditingMaterial(state#mapEditor, Some(newMat));
                                saveMaterial(state);
                                redrawCanvas(state)
                            } else ()
                        }
                    };
                    // 2. UI 選択も解除
                    MapEditorState.setSelectedTrbl(state#mapEditor, None);
                    refreshMaterialsTab(state);
                    event.consume()
                } else ()
            }
        });
        pane
    }

    def cellStyleNormal(): String =
        "-fx-background-color: #2b2b30; -fx-border-color: #555; -fx-border-width: 1;"

    /// 未選択 + wallMap に確定タイルあり: 暗背景 + 緑枠 2px
    /// (網掛けパターンは overlay Canvas で別途最前面に描画する)
    def cellStyleConfirmed(): String =
        "-fx-background-color: #2b2b30; -fx-border-color: #50dc64; -fx-border-width: 2; -fx-border-radius: 2;"

    /// 確定済みセル用の網掛けパターンを overlay Canvas 全体に描画する。
    /// 45° の緑半透明斜線を一定間隔で繰り返す (アイコンや Label より前面に出る)。
    def drawHatchPattern(canvas: Canvas): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let w = canvas.getWidth();
        let h = canvas.getHeight();
        gc.setStroke(Color.rgb(80, 220, 100, 0.45));
        gc.setLineWidth(1.5);
        let spacing = 5.0f64;
        let limit = Float64.tryToInt32((w + h) / spacing)
                  |> Option.getWithDefault(24i32);
        List.forEach(i -> {
            let offset = Int32.toFloat64(i) * spacing;
            // 左下から右上に向かう斜線群 (range が大きくても Canvas が clip するので OK)
            gc.strokeLine(offset, 0.0f64, 0.0f64, offset);
            gc.strokeLine(w, offset, offset, h)
        }, List.range(0, limit + 4i32))
    }

    def cellStyleSelected(): String =
        "-fx-background-color: #5d8fc7; -fx-border-color: #ffe63c; -fx-border-width: 3; -fx-border-radius: 2; -fx-background-radius: 2;"

    /// TRBL アイコンを 3x3 ミニグリッドで描画する (4-trit + 旧 4-bit 両対応)。
    ///   中央 = 選択中の壁 (黄)
    ///   T/R/B/L = W or '1' なら壁色 / F なら床色 / E or '0' なら空色
    ///   4 隅 = neutral 灰色
    def drawTrblIcon(canvas: Canvas, key: String): Unit \ IO = {
        let gc = canvas.getGraphicsContext2D();
        let w = canvas.getWidth();
        let h = canvas.getHeight();
        let cs = w / 3.0;
        gc.clearRect(0.0, 0.0, w, h);
        let len = String.length(key);
        let t = if (len > 0) String.charAt(0, key) else 'E';
        let r = if (len > 1) String.charAt(1, key) else 'E';
        let b = if (len > 2) String.charAt(2, key) else 'E';
        let l = if (len > 3) String.charAt(3, key) else 'E';
        drawIconCell(gc, 0.0, 0.0, cs, IconCell.Corner);
        drawIconCell(gc, 2.0, 0.0, cs, IconCell.Corner);
        drawIconCell(gc, 0.0, 2.0, cs, IconCell.Corner);
        drawIconCell(gc, 2.0, 2.0, cs, IconCell.Corner);
        drawIconCell(gc, 1.0, 1.0, cs, IconCell.Center);
        drawIconCell(gc, 1.0, 0.0, cs, dirKindOf(t));
        drawIconCell(gc, 2.0, 1.0, cs, dirKindOf(r));
        drawIconCell(gc, 1.0, 2.0, cs, dirKindOf(b));
        drawIconCell(gc, 0.0, 1.0, cs, dirKindOf(l))
    }

    def dirKindOf(c: Char): IconCell =
        if      (c == 'W' or c == '1') IconCell.Wall
        else if (c == 'F')             IconCell.Floor
        else                           IconCell.Empty

    enum IconCell with Eq {
        case Center    // 中央: 選択中の壁 (黄)
        case Wall      // 隣接: 壁 (明灰)
        case Floor     // 隣接: 床 (茶)
        case Empty     // 隣接: 空 (暗)
        case Corner    // 4 隅: neutral
    }

    def drawIconCell(gc: GraphicsContext, col: Float64, row: Float64, cs: Float64,
                       kind: IconCell): Unit \ IO = {
        let x = col * cs;
        let y = row * cs;
        let fill = match kind {
            case IconCell.Center => Color.rgb(255, 230, 60)  // 黄: 選択中
            case IconCell.Wall   => Color.rgb(180, 180, 200) // 明灰: 壁
            case IconCell.Floor  => Color.rgb(140, 100, 60)  // 茶: 床
            case IconCell.Empty  => Color.rgb(60, 60, 70)    // 暗: 空
            case IconCell.Corner => Color.rgb(40, 40, 50)    // ほぼ黒: neutral
        };
        gc.setFill(fill);
        gc.fillRect(x, y, cs, cs)
    }

    /// Tileset Canvas クリック: Walls Palette の cellW/cellH/marginX/Y と paletteZoom を使い、
    /// 選択中タイルの (srcX, srcY) を計算する。
    /// AutoRule 選択中なら Rule.srcX/srcY を更新、そうでなく TRBL 選択中なら wallMap 更新。
    def wireMaterialsTilesetClick(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let matOpt = MapEditorState.getEditingMaterial(state#mapEditor);
                match matOpt {
                    case None      => ()
                    case Some(mat) => {
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
                            // Rule 選択中 ? それとも TRBL 選択中 ?
                            let ruleIdxOpt = MapEditorState.getEditingRuleIndex(state#mapEditor);
                            let trblOpt = MapEditorState.getSelectedTrbl(state#mapEditor);
                            match ruleIdxOpt {
                                case Some(ri) => {
                                    let md = MapResource.materialData(mat);
                                    match List.nth(ri, md#autoRules) {
                                        case None       => ()
                                        case Some(rule) => {
                                            let newRule = {srcX = srcX, srcY = srcY | rule};
                                            replaceRule(state, ri, newRule);
                                            refreshMaterialsTab(state);
                                            redrawCanvas(state)
                                        }
                                    }
                                }
                                case None => match trblOpt {
                                    case None      => ()
                                    case Some(key) => {
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
                            }
                        }
                    }
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
        updateWallMapGridHighlight(state);
        updateMaterialsStatus(state);
        drawMaterialsTileset(state);
        refreshRulesUI(state);
        // 選択中 TRBL の紫プレビューを Map Canvas に反映
        redrawCanvas(state)
    }

    /// GridPane の各 StackPane を巡って 3 状態でスタイル切替:
    ///   selected   : 黄太枠 + 青背景 (最優先)
    ///   confirmed  : 緑枠 (wallMap にタイルが割当てられている)
    ///   normal     : 灰枠 (未割当)
    def updateWallMapGridHighlight(state: IdeState.IdeState): Unit \ IO = {
        let sel = MapEditorState.getSelectedTrbl(state#mapEditor);
        let matOpt = MapEditorState.getEditingMaterial(state#mapEditor);
        forEachCell(state, (key, pane) -> {
            let isSelected = match sel {
                case Some(s) => s == key
                case None    => false
            };
            let isConfirmed = match matOpt {
                case None      => false
                case Some(mat) =>
                    Map.memberOf(key, MapResource.materialData(mat)#wallMap)
            };
            if (isSelected)         pane.setStyle(cellStyleSelected())
            else if (isConfirmed)   pane.setStyle(cellStyleConfirmed())
            else                    pane.setStyle(cellStyleNormal());
            // 最前面 overlay (index 2) に網掛け描画 (確定 & 未選択時のみ)
            let paneChildren = pane.getChildren();
            if (paneChildren.size() >= 3i32) {
                let overlayNode = paneChildren.get(2i32);
                let overlay: Canvas = unchecked_cast(overlayNode as Canvas);
                let gc = overlay.getGraphicsContext2D();
                gc.clearRect(0.0f64, 0.0f64,
                              overlay.getWidth(), overlay.getHeight());
                if (isConfirmed and not isSelected)
                    drawHatchPattern(overlay)
                else ()
            } else ()
        })
    }

    /// VBox 内の全 TRBL セル (各セクション GridPane の子 StackPane) を巡回して f を呼ぶ。
    /// box の直接の子に GridPane (Section 1) と VBox (Section 2-4) が混在するので両対応。
    def forEachCell(state: IdeState.IdeState,
                      f: (String, StackPane) -> Unit \ IO): Unit \ IO =
        match Array.get(0, state#widgets#mapMaterialsWallMapBox) {
            case None      => ()
            case Some(box) => {
                let topChildren = box.getChildren();
                let n = topChildren.size();
                List.forEach(i -> {
                    let child = topChildren.get(i);
                    let cls = child.getClass().getSimpleName();
                    if (cls == "GridPane") {
                        // Section 1: 直接 GridPane
                        scanGridCells(unchecked_cast(child as GridPane), f)
                    } else if (cls == "VBox") {
                        // Section 2-4: sectionBox 内に GridPane が入っている
                        let sectionBox: VBox = unchecked_cast(child as VBox);
                        let subChildren = sectionBox.getChildren();
                        let nSub = subChildren.size();
                        List.forEach(j -> {
                            let sub = subChildren.get(j);
                            if (sub.getClass().getSimpleName() == "GridPane")
                                scanGridCells(unchecked_cast(sub as GridPane), f)
                            else ()
                        }, List.range(0, nSub))
                    } else ()
                }, List.range(0, n))
            }
        }

    def scanGridCells(grid: GridPane,
                        f: (String, StackPane) -> Unit \ IO): Unit \ IO = {
        let cells = grid.getChildren();
        let nc = cells.size();
        List.forEach(j -> {
            let cellNode = cells.get(j);
            if (cellNode.getClass().getSimpleName() == "StackPane") {
                let pane: StackPane = unchecked_cast(cellNode as StackPane);
                let ud = pane.getUserData();
                if (Object.isNull(ud)) ()
                else {
                    let key: String = unchecked_cast(ud as String);
                    f(key, pane)
                }
            } else ()
        }, List.range(0, nc))
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

    /// TRBL キーごとのタイル種別の説明文 (4-trit + 旧 4-bit 両対応)。
    /// 4-trit: W=壁, F=床, E=空。順序は T (上) R (右) B (下) L (左)。
    def trblDescription(key: String): String = match key {
        // 4-trit (新仕様)
        case "EWFW" => "上辺 (床が真下、左右が壁)"
        case "FWEW" => "下辺 (床が真上、左右が壁)"
        case "WFWE" => "左辺 (床が真右、上下が壁)"
        case "WEWF" => "右辺 (床が真左、上下が壁)"
        case "EWWE" => "左上 外コーナー (右と下が壁)"
        case "EEWW" => "右上 外コーナー (下と左が壁)"
        case "WWEE" => "左下 外コーナー (上と右が壁)"
        case "WEEW" => "右下 外コーナー (上と左が壁)"
        case "WWWW" => "壁の中央 (上下左右すべて壁)"
        case "EWWW" => "壁の上端 (上が空、他壁)"
        case "WEWW" => "壁の右端 (右が空、他壁)"
        case "WWEW" => "壁の下端 (下が空、他壁)"
        case "WWWE" => "壁の左端 (左が空、他壁)"
        case "FWWW" => "上から床に降りる T 字 (床が上、他壁)"
        case "WFWW" => "右から床に降りる T 字"
        case "WWFW" => "下から床に降りる T 字"
        case "WWWF" => "左から床に降りる T 字"
        case "WEEE" => "上にだけ壁が続く (行き止まり)"
        case "EWEE" => "右にだけ壁が続く"
        case "EEWE" => "下にだけ壁が続く"
        case "EEEW" => "左にだけ壁が続く"
        case "EEEE" => "孤立した壁"
        case "FEEE" => "床が上、他空"
        case "EFEE" => "床が右、他空"
        // 4-bit (旧仕様、フォールバック)
        case "0000" => "孤立 (旧)"
        case "0101" => "横一直線 (旧)"
        case "1010" => "縦一直線 (旧)"
        case "0110" => "左上入隅 (旧)"
        case "0011" => "右上入隅 (旧)"
        case "1100" => "左下入隅 (旧)"
        case "1001" => "右下入隅 (旧)"
        case "1111" => "中央壁 (旧)"
        case _      => "(${key})"
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
                                        // 確定 (wallMap に保存済み) のタイル枠は緑 (細め)
                                        // — TRBL grid の「選択中 (黄)」との区別のため
                                        gc.setStroke(Color.rgb(80, 220, 100));
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
