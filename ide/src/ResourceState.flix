// ResourceState — Resources タブの編集状態 (Ref 群)
//
// Resources ListView / Sub-entries ListView / Property Panel が書き、
// 描画ループ・Sprite preview が読む。IdeState の resource フィールドとして保持する。

mod ResourceState {
    use ResourceDiscovery.ResourceEntry

    /// Resources モード全体の状態。
    ///   discoveredRef:        resources/ 走査結果 (Open Project 時に更新)
    ///   selectedDataPathRef:  現在選択中の Resource の絶対 dataPath。未選択は None
    ///   selectedSubEntryRef:  catalog 形式時に選択中の sub-entry キー。single 形式では None
    ///   editingJsonRef:       Resource 選択時にメモリにロードした data JSON。
    ///                         widget の commit でこの Ref が更新される
    ///   editingSchemaRef:     Resource 選択時にロードした ResourceSchema
    ///   editingSchemaJsonRef: schema の生 Json。metaHints の直接 parse 用
    ///   dirtyRef:             現在の editingJson が未保存変更を持つか。即時書込モードでは
    ///                         Phase 10f 以降ファイル書込時に false にリセット
    ///   previewZoomRef:       Preview の拡大率 (パーセント)。100% = ネイティブ等倍 (1 image px = 1 logical px)
    pub type alias ResourceState = {
        discoveredRef          = Array[List[ResourceEntry], Static],
        selectedDataPathRef    = Array[Option[String], Static],
        selectedSubEntryRef    = Array[Option[String], Static],
        editingJsonRef         = Array[Option[Util.Json.Json], Static],
        editingSchemaRef       = Array[Option[Resource.ResourceSchema], Static],
        editingSchemaJsonRef   = Array[Option[Util.Json.Json], Static],
        dirtyRef               = Array[Bool, Static],
        previewZoomRef         = Array[PropertyWidgets.ZoomMode, Static],
        previewGridRef         = Array[Bool, Static],
        previewFrameAdjustRef  = Array[Bool, Static],
        previewPanRef          = Array[(Float64, Float64), Static],
        // Ref widget の ComboBox 候補 (`{catalog containerKey → sub-entry id 一覧}`) のキャッシュ。
        // resource 一覧ロード時に 1 回計算し、sub-entries を変える commit でのみ再計算する。
        // Property Panel 再構築のたびに全 catalog を読み直さないための I/O 回避用。
        // `None` = 未計算 (= 初回 / 無効化後)、`Some(map)` = 計算済み (空 Map も計算済みとして扱う)。
        // 呼出順序に依存せず、参照側が未計算なら lazy に計算できるようにするため Option で持つ。
        refOptionsRef          = Array[Option[Map[String, List[String]]], Static]
    }

    /// 空の ResourceState を作る
    pub def newState(): ResourceState \ IO =
        {
            discoveredRef          = Array#{(Nil: List[ResourceEntry])} @ Static,
            selectedDataPathRef    = Array#{(None: Option[String])} @ Static,
            selectedSubEntryRef    = Array#{(None: Option[String])} @ Static,
            editingJsonRef         = Array#{(None: Option[Util.Json.Json])} @ Static,
            editingSchemaRef       = Array#{(None: Option[Resource.ResourceSchema])} @ Static,
            editingSchemaJsonRef   = Array#{(None: Option[Util.Json.Json])} @ Static,
            dirtyRef               = Array#{false} @ Static,
            previewZoomRef         = Array#{PropertyWidgets.defaultZoom()} @ Static,
            previewGridRef         = Array#{false} @ Static,
            previewFrameAdjustRef  = Array#{false} @ Static,
            previewPanRef          = Array#{(0.0, 0.0)} @ Static,
            refOptionsRef          = Array#{(None: Option[Map[String, List[String]]])} @ Static
        }

    pub def setDiscovered(state: ResourceState, entries: List[ResourceEntry]): Unit \ IO =
        Array.put(entries, 0, state#discoveredRef)

    pub def setSelectedDataPath(state: ResourceState, path: Option[String]): Unit \ IO =
        Array.put(path, 0, state#selectedDataPathRef)

    pub def getSelectedDataPath(state: ResourceState): Option[String] \ IO =
        Array.get(0, state#selectedDataPathRef)

    pub def setSelectedSubEntry(state: ResourceState, key: Option[String]): Unit \ IO =
        Array.put(key, 0, state#selectedSubEntryRef)

    pub def getSelectedSubEntry(state: ResourceState): Option[String] \ IO =
        Array.get(0, state#selectedSubEntryRef)

    pub def setEditingJson(state: ResourceState, json: Option[Util.Json.Json]): Unit \ IO =
        Array.put(json, 0, state#editingJsonRef)

    pub def getEditingJson(state: ResourceState): Option[Util.Json.Json] \ IO =
        Array.get(0, state#editingJsonRef)

    pub def setEditingSchema(state: ResourceState, schema: Option[Resource.ResourceSchema]): Unit \ IO =
        Array.put(schema, 0, state#editingSchemaRef)

    pub def getEditingSchema(state: ResourceState): Option[Resource.ResourceSchema] \ IO =
        Array.get(0, state#editingSchemaRef)

    /// schema の生 Json を保持。engine 側 fpkg がまだ MetaHint を含まないため、
    /// IDE 内で metaHints セクションを直接 JSON から parse する用途
    pub def setEditingSchemaJson(state: ResourceState, json: Option[Util.Json.Json]): Unit \ IO =
        Array.put(json, 0, state#editingSchemaJsonRef)

    pub def setDirty(state: ResourceState, dirty: Bool): Unit \ IO =
        Array.put(dirty, 0, state#dirtyRef)

    pub def setPreviewZoom(state: ResourceState, mode: PropertyWidgets.ZoomMode): Unit \ IO =
        Array.put(mode, 0, state#previewZoomRef)

    pub def getPreviewZoom(state: ResourceState): PropertyWidgets.ZoomMode \ IO =
        Array.get(0, state#previewZoomRef)

    pub def setPreviewGrid(state: ResourceState, show: Bool): Unit \ IO =
        Array.put(show, 0, state#previewGridRef)

    pub def getPreviewGrid(state: ResourceState): Bool \ IO =
        Array.get(0, state#previewGridRef)

    /// フレーム調整モード ON のとき texture 全体を表示し、選択フレーム以外をディマー表示する。
    /// hframes/vframes の検証用 UI として使う。グリッドとは独立に併用可能
    pub def setPreviewFrameAdjust(state: ResourceState, on: Bool): Unit \ IO =
        Array.put(on, 0, state#previewFrameAdjustRef)

    pub def getPreviewFrameAdjust(state: ResourceState): Bool \ IO =
        Array.get(0, state#previewFrameAdjustRef)

    /// フレーム調整モード中のドラッグで蓄積する pan offset (canvas pixel 単位、transient)。
    /// resource / sub-entry 切替時や frame-adjust toggle 時に (0,0) にリセットする
    pub def setPreviewPan(state: ResourceState, pan: (Float64, Float64)): Unit \ IO =
        Array.put(pan, 0, state#previewPanRef)

    pub def getPreviewPan(state: ResourceState): (Float64, Float64) \ IO =
        Array.get(0, state#previewPanRef)

    pub def resetPreviewPan(state: ResourceState): Unit \ IO =
        Array.put((0.0, 0.0), 0, state#previewPanRef)

    /// Ref widget の ComboBox 候補キャッシュを上書きする (計算済みとしてマーク)。
    /// resource 一覧ロード時 / sub-entries を変える commit 後に ResourcePanel が呼ぶ
    pub def setRefOptions(state: ResourceState, options: Map[String, List[String]]): Unit \ IO =
        Array.put(Some(options), 0, state#refOptionsRef)

    /// キャッシュ済みの Ref widget 候補を返す。`None` = 未計算。
    /// 参照側は None なら自分で計算 (refreshRefOptions) してから再取得する。
    pub def getRefOptions(state: ResourceState): Option[Map[String, List[String]]] \ IO =
        Array.get(0, state#refOptionsRef)
}
