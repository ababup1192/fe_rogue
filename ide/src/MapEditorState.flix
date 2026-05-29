// MapEditorState — Maps タブの編集状態 (Ref 群)
//
// Maps ListView / Grid Canvas / WallMask 編集が書き、描画ループが読む。
// IdeState の mapEditor フィールドとして保持する (ResourceState と同形)。
//
// S8 時点ではまだ ListView と現選択しか扱わない。S9 以降で editingLevel / dirty 等が増える。

mod MapEditorState {

    /// 編集レイヤーモード。
    ///   Floor    = decorTiles 配置/消去 (床)。自動的に床のないセルに壁が立つ
    ///   Walls    = manualTiles 配置/消去 (自動壁の上書き、衝突は持たない)
    ///   Entities = Entity 配置/削除 (identifier テキスト入力)
    pub enum LayerMode with Eq, ToString {
        case Floor
        case Walls
        case Entities
    }

    /// Map Canvas の操作モード。
    ///   Pencil      = 鉛筆 (クリック/ドラッグでタイルを置く・消す)
    ///   RangeSelect = 範囲選択 (ドラッグで矩形範囲を選び、BackSpace で削除)
    pub enum EditTool with Eq, ToString {
        case Pencil
        case RangeSelect
    }

    /// 各レイヤーの canvas 上での表示 ON/OFF。
    /// 目玉トグルで切り替え、描画時 (MapGridCanvas.drawLevel) が参照する。
    /// Walls visibility は「自動壁 + manualTiles 上書き」両方をまとめて制御。
    pub type alias LayerVisibility = {
        floor    = Bool,
        walls    = Bool,
        entities = Bool
    }

    /// 1 レイヤー分の Palette 設定 (SpriteSheet + セル px + 周囲マージン)。
    ///   textureName: ComboBox 選択中の texture 論理名 (None なら何も表示しない)
    ///   cellW/cellH: Palette グリッドの 1 マスの px (Spinner 値)
    ///   marginX/Y  : タイル間の隙間 px。`col*(cellW+marginX)` のように位置計算に使う
    pub type alias LayerPalette = {
        textureName = Option[String],
        cellW       = Int32,
        cellH       = Int32,
        marginX     = Int32,
        marginY     = Int32
    }

    /// Floor / Walls 各レイヤーの Palette 設定。Entities は palette を使わない。
    pub type alias PaletteSettings = {
        floor = LayerPalette,
        walls = LayerPalette
    }

    /// デフォルト Palette 設定。
    /// 新規 Level・editorPalette 無し Level の起点として、Sheet は未選択で始める
    /// (ユーザが意識的に Sheet を選んでから配置に進む UX)。
    pub def defaultPaletteSettings(): PaletteSettings =
        {
            floor = {textureName = None, cellW = 16, cellH = 16,
                      marginX = 0, marginY = 0},
            walls = {textureName = None, cellW = 16, cellH = 16,
                      marginX = 0, marginY = 0}
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
    ///   editingMaterialRef:   現 Level の materialId に紐づく Material (wallMap など)
    ///   editingMaterialPathRef: editingMaterial の絶対パス (Materials タブの保存先)
    ///   selectedTrblRef:      Materials タブで選択中の TRBL キー ("0000" 〜 "1111")
    pub type alias MapEditorState = {
        levelFilesRef          = Array[List[String], Static],
        selectedLevelPathRef   = Array[Option[String], Static],
        editingLevelRef        = Array[Option[MapResource.Level], Static],
        layerModeRef           = Array[LayerMode, Static],
        selectedSrcRef         = Array[Option[(Int32, Int32)], Static],
        layerVisibilityRef     = Array[LayerVisibility, Static],
        paletteSettingsRef     = Array[PaletteSettings, Static],
        paletteZoomRef         = Array[Float64, Static],
        mapZoomRef             = Array[Float64, Static],
        undoStackRef           = Array[List[MapResource.Level], Static],
        editingMaterialRef     = Array[Option[MapResource.Material], Static],
        editingMaterialPathRef = Array[Option[String], Static],
        selectedTrblRef        = Array[Option[String], Static],
        editingRuleIndexRef    = Array[Option[Int32], Static],
        // Rules ComboBox でドロップダウン open 中にホバーしている項目の idx。
        // 紫プレビューを「選択中」より優先して表示するための一時 state。
        // ホバー外 / ドロップダウン closed では None。
        hoveredRuleIndexRef    = Array[Option[Int32], Static],
        // Rules タブの pattern grid でフォーカス中のセル idx (Krita のカラーパレットの
        // current color に相当する状態。grid セルをクリックするとここに idx が入る)
        focusedPatternIdxRef   = Array[Option[Int32], Static],
        // Map Canvas のドラッグ範囲選択
        selectedRangeRef       = Array[Option[(Int32, Int32, Int32, Int32)], Static],
        dragStartRef           = Array[Option[(Int32, Int32)], Static],
        isDraggingRef          = Array[Bool, Static],
        // Map Canvas の操作ツール (Pencil / RangeSelect)
        editToolRef            = Array[EditTool, Static],
        // Rules ListView をプログラム的に書き換え中フラグ。
        // selectedIndexProperty リスナー再入を防ぐ。
        isRefreshingRulesRef   = Array[Bool, Static],
        // Preview モード: ON のとき canvas をゲーム見え (dim/grid/overlay なし) で描く
        previewModeRef         = Array[Bool, Static]
    }

    /// 空の MapEditorState を作る。
    pub def newState(): MapEditorState \ IO =
        {
            levelFilesRef          = Array#{(Nil: List[String])} @ Static,
            selectedLevelPathRef   = Array#{(None: Option[String])} @ Static,
            editingLevelRef        = Array#{(None: Option[MapResource.Level])} @ Static,
            layerModeRef           = Array#{LayerMode.Floor} @ Static,
            selectedSrcRef         = Array#{(None: Option[(Int32, Int32)])} @ Static,
            layerVisibilityRef     = Array#{allVisible()} @ Static,
            paletteSettingsRef     = Array#{defaultPaletteSettings()} @ Static,
            paletteZoomRef         = Array#{1.7f64} @ Static,
            mapZoomRef             = Array#{1.0f64} @ Static,
            undoStackRef           = Array#{(Nil: List[MapResource.Level])} @ Static,
            editingMaterialRef     = Array#{(None: Option[MapResource.Material])} @ Static,
            editingMaterialPathRef = Array#{(None: Option[String])} @ Static,
            selectedTrblRef        = Array#{(None: Option[String])} @ Static,
            editingRuleIndexRef    = Array#{(None: Option[Int32])} @ Static,
            hoveredRuleIndexRef    = Array#{(None: Option[Int32])} @ Static,
            focusedPatternIdxRef   = Array#{(None: Option[Int32])} @ Static,
            selectedRangeRef       = Array#{(None: Option[(Int32, Int32, Int32, Int32)])} @ Static,
            dragStartRef           = Array#{(None: Option[(Int32, Int32)])} @ Static,
            isDraggingRef          = Array#{false} @ Static,
            editToolRef            = Array#{EditTool.Pencil} @ Static,
            isRefreshingRulesRef   = Array#{false} @ Static,
            previewModeRef         = Array#{false} @ Static
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
            case LayerMode.Floor    => {floor    = visible | cur}
            case LayerMode.Walls    => {walls    = visible | cur}
            case LayerMode.Entities => {entities = visible | cur}
        };
        Array.put(next, 0, state#layerVisibilityRef)
    }

    pub def getPaletteSettings(state: MapEditorState): PaletteSettings \ IO =
        Array.get(0, state#paletteSettingsRef)

    /// 指定 LayerMode の Palette 設定を返す。Entities は palette を使わないので `None`。
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

    // ─── Material (AutoLayerWalls の wallMap) ───

    pub def setEditingMaterial(state: MapEditorState,
                                 mat: Option[MapResource.Material]): Unit \ IO =
        Array.put(mat, 0, state#editingMaterialRef)

    pub def getEditingMaterial(state: MapEditorState): Option[MapResource.Material] \ IO =
        Array.get(0, state#editingMaterialRef)

    pub def setEditingMaterialPath(state: MapEditorState, path: Option[String]): Unit \ IO =
        Array.put(path, 0, state#editingMaterialPathRef)

    pub def getEditingMaterialPath(state: MapEditorState): Option[String] \ IO =
        Array.get(0, state#editingMaterialPathRef)

    pub def setSelectedTrbl(state: MapEditorState, key: Option[String]): Unit \ IO =
        Array.put(key, 0, state#selectedTrblRef)

    pub def getSelectedTrbl(state: MapEditorState): Option[String] \ IO =
        Array.get(0, state#selectedTrblRef)

    pub def setEditingRuleIndex(state: MapEditorState, idx: Option[Int32]): Unit \ IO =
        Array.put(idx, 0, state#editingRuleIndexRef)

    pub def getEditingRuleIndex(state: MapEditorState): Option[Int32] \ IO =
        Array.get(0, state#editingRuleIndexRef)

    pub def setHoveredRuleIndex(state: MapEditorState, idx: Option[Int32]): Unit \ IO =
        Array.put(idx, 0, state#hoveredRuleIndexRef)

    pub def getHoveredRuleIndex(state: MapEditorState): Option[Int32] \ IO =
        Array.get(0, state#hoveredRuleIndexRef)

    pub def setFocusedPatternIdx(state: MapEditorState, idx: Option[Int32]): Unit \ IO =
        Array.put(idx, 0, state#focusedPatternIdxRef)

    pub def getFocusedPatternIdx(state: MapEditorState): Option[Int32] \ IO =
        Array.get(0, state#focusedPatternIdxRef)

    // ─── Map Canvas のドラッグ範囲選択 ───

    pub def getSelectedRange(state: MapEditorState):
            Option[(Int32, Int32, Int32, Int32)] \ IO =
        Array.get(0, state#selectedRangeRef)

    pub def setSelectedRange(state: MapEditorState,
                                range: Option[(Int32, Int32, Int32, Int32)]):
            Unit \ IO =
        Array.put(range, 0, state#selectedRangeRef)

    pub def getDragStart(state: MapEditorState): Option[(Int32, Int32)] \ IO =
        Array.get(0, state#dragStartRef)

    pub def setDragStart(state: MapEditorState, p: Option[(Int32, Int32)]): Unit \ IO =
        Array.put(p, 0, state#dragStartRef)

    pub def getIsDragging(state: MapEditorState): Bool \ IO =
        Array.get(0, state#isDraggingRef)

    pub def setIsDragging(state: MapEditorState, dragging: Bool): Unit \ IO =
        Array.put(dragging, 0, state#isDraggingRef)

    pub def getEditTool(state: MapEditorState): EditTool \ IO =
        Array.get(0, state#editToolRef)

    pub def setEditTool(state: MapEditorState, tool: EditTool): Unit \ IO =
        Array.put(tool, 0, state#editToolRef)

    pub def getIsRefreshingRules(state: MapEditorState): Bool \ IO =
        Array.get(0, state#isRefreshingRulesRef)

    pub def setIsRefreshingRules(state: MapEditorState, b: Bool): Unit \ IO =
        Array.put(b, 0, state#isRefreshingRulesRef)

    pub def getPreviewMode(state: MapEditorState): Bool \ IO =
        Array.get(0, state#previewModeRef)

    pub def setPreviewMode(state: MapEditorState, enabled: Bool): Unit \ IO =
        Array.put(enabled, 0, state#previewModeRef)
}
