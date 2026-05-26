// MapEditorState — Maps タブの編集状態 (Ref 群)
//
// Maps ListView / Grid Canvas / WallMask 編集が書き、描画ループが読む。
// IdeState の mapEditor フィールドとして保持する (ResourceState と同形)。
//
// S8 時点ではまだ ListView と現選択しか扱わない。S9 以降で editingLevel / dirty 等が増える。

mod MapEditorState {

    /// 編集レイヤーモード。
    ///   Walls    = WallMask toggle
    ///   Manual   = ManualTile 配置/消去 (パレットで src 選択)
    ///   Entities = Entity 配置/削除 (identifier テキスト入力)
    pub enum LayerMode with Eq, ToString {
        case Walls
        case Manual
        case Entities
    }

    /// Maps モード全体の状態。
    ///   levelFilesRef:        assets/maps/*.map.json の絶対パスリスト (Open Project 時に更新)
    ///   selectedLevelPathRef: 現在選択中の Level の絶対パス。未選択は None
    ///   editingLevelRef:      選択中 Level の読み込み済みデータ。S9 以降で grid 表示に使う
    ///   dirtyRef:             editingLevel が未保存変更を持つか (S11/S12 で使う)
    ///   layerModeRef:         現在の編集レイヤー (S15: Walls / Manual)
    ///   selectedSrcRef:       Manual モードで配置するタイルの (srcX, srcY) ピクセル
    pub type alias MapEditorState = {
        levelFilesRef        = Array[List[String], Static],
        selectedLevelPathRef = Array[Option[String], Static],
        editingLevelRef      = Array[Option[MapResource.Level], Static],
        dirtyRef             = Array[Bool, Static],
        layerModeRef         = Array[LayerMode, Static],
        selectedSrcRef       = Array[Option[(Int32, Int32)], Static]
    }

    /// 空の MapEditorState を作る。
    pub def newState(): MapEditorState \ IO =
        {
            levelFilesRef        = Array#{(Nil: List[String])} @ Static,
            selectedLevelPathRef = Array#{(None: Option[String])} @ Static,
            editingLevelRef      = Array#{(None: Option[MapResource.Level])} @ Static,
            dirtyRef             = Array#{false} @ Static,
            layerModeRef         = Array#{LayerMode.Walls} @ Static,
            selectedSrcRef       = Array#{(None: Option[(Int32, Int32)])} @ Static
        }

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

    pub def setDirty(state: MapEditorState, dirty: Bool): Unit \ IO =
        Array.put(dirty, 0, state#dirtyRef)

    pub def isDirty(state: MapEditorState): Bool \ IO =
        Array.get(0, state#dirtyRef)

    pub def setLayerMode(state: MapEditorState, mode: LayerMode): Unit \ IO =
        Array.put(mode, 0, state#layerModeRef)

    pub def getLayerMode(state: MapEditorState): LayerMode \ IO =
        Array.get(0, state#layerModeRef)

    pub def setSelectedSrc(state: MapEditorState, src: Option[(Int32, Int32)]): Unit \ IO =
        Array.put(src, 0, state#selectedSrcRef)

    pub def getSelectedSrc(state: MapEditorState): Option[(Int32, Int32)] \ IO =
        Array.get(0, state#selectedSrcRef)
}
