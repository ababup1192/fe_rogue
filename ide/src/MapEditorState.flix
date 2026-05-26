// MapEditorState — Maps タブの編集状態 (Ref 群)
//
// Maps ListView / Grid Canvas / WallMask 編集が書き、描画ループが読む。
// IdeState の mapEditor フィールドとして保持する (ResourceState と同形)。
//
// S8 時点ではまだ ListView と現選択しか扱わない。S9 以降で editingLevel / dirty 等が増える。

mod MapEditorState {

    /// 編集レイヤーモード。
    ///   Floor    = decorTiles 配置/消去 (パレット = tilemap_floor)
    ///   Walls    = manualTiles 配置/消去 + wallMask 自動同期 (パレット = inca_tileset)
    ///   Entities = Entity 配置/削除 (identifier テキスト入力)
    pub enum LayerMode with Eq, ToString {
        case Floor
        case Walls
        case Entities
    }

    /// 各レイヤーの canvas 上での表示 ON/OFF。
    /// 目玉トグルで切り替え、描画時 (MapGridCanvas.drawLevel) が参照する。
    pub type alias LayerVisibility = {
        floor    = Bool,
        walls    = Bool,
        entities = Bool
    }

    /// 1 レイヤー分の Palette 設定 (SpriteSheet + セル px)。
    ///   textureName: ComboBox 選択中の texture 論理名 (None なら何も表示しない)
    ///   cellW/cellH: Palette グリッドの 1 マスの px (Spinner 値)
    pub type alias LayerPalette = {
        textureName = Option[String],
        cellW       = Int32,
        cellH       = Int32
    }

    /// Floor / Walls 各レイヤーの Palette 設定。Entities は palette を使わない。
    pub type alias PaletteSettings = {
        floor = LayerPalette,
        walls = LayerPalette
    }

    /// デフォルト Palette 設定 (Material 概念導入までのハードコード fallback)。
    pub def defaultPaletteSettings(): PaletteSettings =
        {
            floor = {textureName = Some("tilemap_floor"), cellW = 16, cellH = 16},
            walls = {textureName = Some("inca_tileset"), cellW = 16, cellH = 16}
        }

    /// Maps モード全体の状態。
    ///   levelFilesRef:        assets/maps/*.map.json の絶対パスリスト (Open Project 時に更新)
    ///   selectedLevelPathRef: 現在選択中の Level の絶対パス。未選択は None
    ///   editingLevelRef:      選択中 Level の読み込み済みデータ
    ///   layerModeRef:         現在の編集レイヤー (Floor / Walls / Entities)
    ///   selectedSrcRef:       Manual モードで配置するタイルの (srcX, srcY) ピクセル
    ///   layerVisibilityRef:   レイヤーの表示 ON/OFF (目玉トグル状態、初期は全 true)
    ///   paletteSettingsRef:   Floor / Walls 各々の Palette 設定 (SpriteSheet + セル px)
    ///   paletteZoomRef:       Palette canvas の表示倍率 (ピンチ操作で更新、1.0=等倍)
    ///   mapZoomRef:           Map canvas の表示倍率 (ピンチ操作で更新、1.0=等倍)
    ///   undoStackRef:         編集前の Level スナップショット (head=直近)。Ctrl+Z で pop する
    pub type alias MapEditorState = {
        levelFilesRef        = Array[List[String], Static],
        selectedLevelPathRef = Array[Option[String], Static],
        editingLevelRef      = Array[Option[MapResource.Level], Static],
        layerModeRef         = Array[LayerMode, Static],
        selectedSrcRef       = Array[Option[(Int32, Int32)], Static],
        layerVisibilityRef   = Array[LayerVisibility, Static],
        paletteSettingsRef   = Array[PaletteSettings, Static],
        paletteZoomRef       = Array[Float64, Static],
        mapZoomRef           = Array[Float64, Static],
        undoStackRef         = Array[List[MapResource.Level], Static]
    }

    /// 空の MapEditorState を作る。
    pub def newState(): MapEditorState \ IO =
        {
            levelFilesRef        = Array#{(Nil: List[String])} @ Static,
            selectedLevelPathRef = Array#{(None: Option[String])} @ Static,
            editingLevelRef      = Array#{(None: Option[MapResource.Level])} @ Static,
            layerModeRef         = Array#{LayerMode.Walls} @ Static,
            selectedSrcRef       = Array#{(None: Option[(Int32, Int32)])} @ Static,
            layerVisibilityRef   = Array#{allVisible()} @ Static,
            paletteSettingsRef   = Array#{defaultPaletteSettings()} @ Static,
            paletteZoomRef       = Array#{1.0f64} @ Static,
            mapZoomRef           = Array#{1.0f64} @ Static,
            undoStackRef         = Array#{(Nil: List[MapResource.Level])} @ Static
        }

    /// 全レイヤー visible の初期値。
    pub def allVisible(): LayerVisibility =
        {floor = true, walls = true, entities = true}

    pub def setLevelFiles(state: MapEditorState, files: List[String]): Unit \ IO =
        Array.put(files, 0, state#levelFilesRef)

    pub def getLevelFiles(state: MapEditorState): List[String] \ IO =
        Array.get(0, state#levelFilesRef)

    pub def setSelectedLevelPath(state: MapEditorState, path: Option[String]): Unit \ IO =
        Array.put(path, 0, state#selectedLevelPathRef)

    pub def getSelectedLevelPath(state: MapEditorState): Option[String] \ IO =
        Array.get(0, state#selectedLevelPathRef)

    pub def setEditingLevel(state: MapEditorState, level: Option[MapResource.Level]): Unit \ IO =
        Array.put(level, 0, state#editingLevelRef)

    pub def getEditingLevel(state: MapEditorState): Option[MapResource.Level] \ IO =
        Array.get(0, state#editingLevelRef)

    pub def setLayerMode(state: MapEditorState, mode: LayerMode): Unit \ IO =
        Array.put(mode, 0, state#layerModeRef)

    pub def getLayerMode(state: MapEditorState): LayerMode \ IO =
        Array.get(0, state#layerModeRef)

    pub def setSelectedSrc(state: MapEditorState, src: Option[(Int32, Int32)]): Unit \ IO =
        Array.put(src, 0, state#selectedSrcRef)

    pub def getSelectedSrc(state: MapEditorState): Option[(Int32, Int32)] \ IO =
        Array.get(0, state#selectedSrcRef)

    pub def getLayerVisibility(state: MapEditorState): LayerVisibility \ IO =
        Array.get(0, state#layerVisibilityRef)

    /// 指定 LayerMode の visible フラグを更新する。他のレイヤーは現状維持。
    pub def setLayerVisible(state: MapEditorState, mode: LayerMode, visible: Bool): Unit \ IO = {
        let cur = Array.get(0, state#layerVisibilityRef);
        let next = match mode {
            case LayerMode.Floor    => {floor = visible | cur}
            case LayerMode.Walls    => {walls = visible | cur}
            case LayerMode.Entities => {entities = visible | cur}
        };
        Array.put(next, 0, state#layerVisibilityRef)
    }

    pub def getPaletteSettings(state: MapEditorState): PaletteSettings \ IO =
        Array.get(0, state#paletteSettingsRef)

    /// 指定 LayerMode の Palette 設定を返す。Entities は palette を使わないので
    /// `None` を返す呼び元側で参照しないこと前提だが、安全のため Walls の値を返す。
    pub def getPaletteForLayer(state: MapEditorState, mode: LayerMode):
            Option[LayerPalette] \ IO = {
        let cur = Array.get(0, state#paletteSettingsRef);
        match mode {
            case LayerMode.Floor    => Some(cur#floor)
            case LayerMode.Walls    => Some(cur#walls)
            case LayerMode.Entities => None
        }
    }

    /// 指定 LayerMode の Palette 設定を更新する。Entities への書き込みは無視。
    pub def setPaletteForLayer(state: MapEditorState, mode: LayerMode, p: LayerPalette):
            Unit \ IO = {
        let cur = Array.get(0, state#paletteSettingsRef);
        let next = match mode {
            case LayerMode.Floor    => {floor = p | cur}
            case LayerMode.Walls    => {walls = p | cur}
            case LayerMode.Entities => cur
        };
        Array.put(next, 0, state#paletteSettingsRef)
    }

    pub def getPaletteZoom(state: MapEditorState): Float64 \ IO =
        Array.get(0, state#paletteZoomRef)

    /// Palette zoom を [0.25, 8.0] にクランプして保存する。
    pub def setPaletteZoom(state: MapEditorState, zoom: Float64): Unit \ IO = {
        let clamped =
            if (zoom < 0.25f64) 0.25f64
            else if (zoom > 8.0f64) 8.0f64
            else zoom;
        Array.put(clamped, 0, state#paletteZoomRef)
    }

    pub def getMapZoom(state: MapEditorState): Float64 \ IO =
        Array.get(0, state#mapZoomRef)

    /// Map zoom を [0.25, 8.0] にクランプして保存する。
    pub def setMapZoom(state: MapEditorState, zoom: Float64): Unit \ IO = {
        let clamped =
            if (zoom < 0.25f64) 0.25f64
            else if (zoom > 8.0f64) 8.0f64
            else zoom;
        Array.put(clamped, 0, state#mapZoomRef)
    }

    /// Undo スタックの最大保持数 (古いものから捨てる)。
    def undoStackLimit(): Int32 = 50

    /// 編集前の Level を Undo スタックに push する (head=直近)。
    /// スタックが limit を超えたら末尾を切り捨て、最新 limit 件だけ保持する。
    pub def pushUndo(state: MapEditorState, level: MapResource.Level): Unit \ IO = {
        let cur = Array.get(0, state#undoStackRef);
        let next = level :: List.take(undoStackLimit() - 1, cur);
        Array.put(next, 0, state#undoStackRef)
    }

    /// Undo スタックの head を取り出す。空なら None。
    pub def popUndo(state: MapEditorState): Option[MapResource.Level] \ IO = {
        let cur = Array.get(0, state#undoStackRef);
        match cur {
            case Nil       => None
            case x :: rest => {
                Array.put(rest, 0, state#undoStackRef);
                Some(x)
            }
        }
    }

    /// Undo スタックをクリアする (別 Level に切替えるときに呼ぶ)。
    pub def clearUndoStack(state: MapEditorState): Unit \ IO =
        Array.put((Nil: List[MapResource.Level]), 0, state#undoStackRef)
}
