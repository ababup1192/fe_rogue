// MapEditorPanel — Maps タブ専用の wiring と Level リスト管理。
//
// JavaFXIdeUI.customize から wireMapSelection が呼ばれ、ListView 選択時に
// `editingLevelRef` を更新する (今は最小構成、S9 以降で Canvas 描画と連携)。
// Main.flix の Open Project ロード時に findMapFiles → setLevelFiles → populateMapList を回す。
//
// 雛形: ResourcePanel.wireResourceSelection / populateResourcesList と同じパターン。

mod MapEditorPanel {
    import java.lang.{Object => JObject}
    import java.io.File
    import javafx.scene.control.ListView
    import javafx.scene.control.Button
    import javafx.scene.control.RadioButton
    import javafx.scene.control.TextField
    import javafx.scene.control.TextInputDialog
    import javafx.scene.control.Label
    import javafx.scene.canvas.Canvas
    import javafx.scene.canvas.GraphicsContext
    import javafx.scene.image.Image
    import javafx.scene.input.MouseEvent
    import javafx.scene.paint.Color
    import javafx.beans.value.ChangeListener
    import javafx.beans.value.ObservableValue
    import javafx.event.ActionEvent
    import javafx.event.EventHandler

    /// Maps タブで描画に使う wall / floor の tileset 論理名。
    /// 将来 Material 概念に置き換えるまでハードコード。
    pub def wallsTextureName(): String = "inca_tileset"
    pub def floorTextureName(): String = "tilemap_floor"

    /// プロジェクトの texturePathMap から wall / floor tileset PNG を Image としてロードし、
    /// state にキャッシュする。Open Project / reloadProject 時に 1 度呼ぶ。
    pub def loadTilesetImages(state: IdeState.IdeState): Unit \ IO = {
        let pathMap = IdeState.getTexturePathMap(state);
        Array.put(loadImageFor(wallsTextureName(), pathMap), 0, state#widgets#mapWallsImage);
        Array.put(loadImageFor(floorTextureName(), pathMap), 0, state#widgets#mapFloorImage)
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
                match Array.get(0, state#widgets#mapGridCanvas) {
                    case None    => ()
                    case Some(c) =>
                        let wImg = Array.get(0, state#widgets#mapWallsImage);
                        let fImg = Array.get(0, state#widgets#mapFloorImage);
                        MapGridCanvas.drawLevel(c, level, MapGridCanvas.defaultCellPx(), wImg, fImg)
                };
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

    /// Layer mode radio (Walls / Manual / Entities) の click で
    /// MapEditorState.layerModeRef を更新する。
    /// ChangeListener[Bool] は Flix の primitive Bool ↔ Java Boxed Boolean ミスマッチで
    /// VerifyError になるため、ActionEvent + isSelected() で判定する。
    pub def wireLayerRadios(state: IdeState.IdeState,
                              wallsRadio: RadioButton,
                              manualRadio: RadioButton,
                              entitiesRadio: RadioButton): Unit \ IO = {
        wallsRadio.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                if (wallsRadio.isSelected())
                    MapEditorState.setLayerMode(state#mapEditor, MapEditorState.LayerMode.Walls)
                else ()
        });
        manualRadio.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                if (manualRadio.isSelected())
                    MapEditorState.setLayerMode(state#mapEditor, MapEditorState.LayerMode.Manual)
                else ()
        });
        entitiesRadio.setOnAction(new EventHandler[ActionEvent] {
            def handle(_this: EventHandler[ActionEvent], _e: ActionEvent): Unit \ IO =
                if (entitiesRadio.isSelected())
                    MapEditorState.setLayerMode(state#mapEditor, MapEditorState.LayerMode.Entities)
                else ()
        })
    }

    /// 1 パレット タイルの表示倍率 (パレット Canvas 上で 1 タイル = 何 px か)。
    /// inca_tileset (20×14 grid, 16px) を 2 倍で表示 → Canvas 640×448 程度。
    pub def paletteCellPx(): Int32 = 16

    /// 起動時とテクスチャ更新時に palette canvas へ inca_tileset PNG 全体を描画する。
    /// パレットは元 PNG 等倍 (1px = 1px) で表示し、Canvas サイズも画像に合わせる。
    pub def drawPalette(state: IdeState.IdeState): Unit \ IO =
        match (Array.get(0, state#widgets#mapPaletteCanvas),
               Array.get(0, state#widgets#mapWallsImage)) {
            case (Some(canvas), Some(image)) => {
                let w = image.getWidth();
                let h = image.getHeight();
                canvas.setWidth(w);
                canvas.setHeight(h);
                let gc = canvas.getGraphicsContext2D();
                gc.setImageSmoothing(false);
                gc.drawImage(image, 0.0f64, 0.0f64);
                // 選択中タイルのハイライト
                match MapEditorState.getSelectedSrc(state#mapEditor) {
                    case None             => ()
                    case Some((srcX, srcY)) => {
                        let ts = Int32.toFloat64(paletteCellPx());
                        gc.setStroke(Color.rgb(255, 230, 60));
                        gc.setLineWidth(2.0);
                        gc.strokeRect(Int32.toFloat64(srcX), Int32.toFloat64(srcY), ts, ts)
                    }
                }
            }
            case _ => ()
        }

    /// Palette canvas のクリックで src を選択する handler を 1 度だけ登録する。
    /// inca_tileset は spacing=0 / margin=0 なので col*16, row*16 で srcX/srcY が決まる。
    pub def wirePaletteClick(state: IdeState.IdeState, canvas: Canvas): Unit \ IO = {
        canvas.setOnMouseClicked(new EventHandler[MouseEvent] {
            def handle(_this: EventHandler[MouseEvent], event: MouseEvent): Unit \ IO = {
                let ts = Int32.toFloat64(paletteCellPx());
                let col = Float64.truncateToInt32(event.getX() / ts);
                let row = Float64.truncateToInt32(event.getY() / ts);
                let srcX = col * paletteCellPx();
                let srcY = row * paletteCellPx();
                MapEditorState.setSelectedSrc(state#mapEditor, Some((srcX, srcY)));
                updatePaletteStatus(state, srcX, srcY);
                drawPalette(state)
            }
        })
    }

    def updatePaletteStatus(state: IdeState.IdeState, srcX: Int32, srcY: Int32): Unit \ IO =
        match Array.get(0, state#widgets#mapPaletteStatus) {
            case Some(label) => {
                let col = srcX / paletteCellPx();
                let row = srcY / paletteCellPx();
                label.setText("選択中: (${col}, ${row})  src=(${srcX}, ${srcY})")
            }
            case None => ()
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

    /// 13×13 デフォルト Level: 外周のみ wall、内部床、entity 無し。
    /// materialId は "inca_stone" 固定 (Material 概念導入まで)。
    def buildBlankLevel(width: Int32, height: Int32): MapResource.Level = {
        let mask = List.range(0, width * height)
            |> List.map(i -> {
                let col = Int32.remainder(i, width);
                let row = i / width;
                if (col == 0 or col == width - 1 or row == 0 or row == height - 1) 1i32
                else 0i32
            })
            |> List.toVector;
        let data: MapResource.LevelData = {
            tileSize    = 16,
            width       = width,
            height      = height,
            materialId  = "inca_stone",
            wallMask    = mask,
            manualTiles = (Nil: List[MapResource.ManualTile]),
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
