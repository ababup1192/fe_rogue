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
    ///   editingSchemaJsonRef: schema の生 JsonElement。metaHints の直接 parse 用
    ///   dirtyRef:             現在の editingJson が未保存変更を持つか。即時書込モードでは
    ///                         Phase 10f 以降ファイル書込時に false にリセット
    ///   previewZoomRef:       Preview の拡大率 (パーセント)。100% = ネイティブ等倍 (1 image px = 1 logical px)
    pub type alias ResourceState = {
        discoveredRef          = Array[List[ResourceEntry], Static],
        selectedDataPathRef    = Array[Option[String], Static],
        selectedSubEntryRef    = Array[Option[String], Static],
        editingJsonRef         = Array[Option[Json.JsonElement], Static],
        editingSchemaRef       = Array[Option[Resource.ResourceSchema], Static],
        editingSchemaJsonRef   = Array[Option[Json.JsonElement], Static],
        dirtyRef               = Array[Bool, Static],
        previewZoomRef         = Array[PropertyWidgets.ZoomMode, Static],
        previewGridRef         = Array[Bool, Static]
    }

    /// 空の ResourceState を作る
    pub def newState(): ResourceState \ IO =
        {
            discoveredRef          = Array#{(Nil: List[ResourceEntry])} @ Static,
            selectedDataPathRef    = Array#{(None: Option[String])} @ Static,
            selectedSubEntryRef    = Array#{(None: Option[String])} @ Static,
            editingJsonRef         = Array#{(None: Option[Json.JsonElement])} @ Static,
            editingSchemaRef       = Array#{(None: Option[Resource.ResourceSchema])} @ Static,
            editingSchemaJsonRef   = Array#{(None: Option[Json.JsonElement])} @ Static,
            dirtyRef               = Array#{false} @ Static,
            previewZoomRef         = Array#{PropertyWidgets.defaultZoom()} @ Static,
            previewGridRef         = Array#{false} @ Static
        }

    pub def setDiscovered(state: ResourceState, entries: List[ResourceEntry]): Unit \ IO =
        Array.put(entries, 0, state#discoveredRef)

    pub def getDiscovered(state: ResourceState): List[ResourceEntry] \ IO =
        Array.get(0, state#discoveredRef)

    pub def setSelectedDataPath(state: ResourceState, path: Option[String]): Unit \ IO =
        Array.put(path, 0, state#selectedDataPathRef)

    pub def getSelectedDataPath(state: ResourceState): Option[String] \ IO =
        Array.get(0, state#selectedDataPathRef)

    pub def setSelectedSubEntry(state: ResourceState, key: Option[String]): Unit \ IO =
        Array.put(key, 0, state#selectedSubEntryRef)

    pub def getSelectedSubEntry(state: ResourceState): Option[String] \ IO =
        Array.get(0, state#selectedSubEntryRef)

    pub def setEditingJson(state: ResourceState, json: Option[Json.JsonElement]): Unit \ IO =
        Array.put(json, 0, state#editingJsonRef)

    pub def getEditingJson(state: ResourceState): Option[Json.JsonElement] \ IO =
        Array.get(0, state#editingJsonRef)

    pub def setEditingSchema(state: ResourceState, schema: Option[Resource.ResourceSchema]): Unit \ IO =
        Array.put(schema, 0, state#editingSchemaRef)

    pub def getEditingSchema(state: ResourceState): Option[Resource.ResourceSchema] \ IO =
        Array.get(0, state#editingSchemaRef)

    /// schema の生 JsonElement を保持。engine 側 fpkg がまだ MetaHint を含まないため、
    /// IDE 内で metaHints セクションを直接 JSON から parse する用途
    pub def setEditingSchemaJson(state: ResourceState, json: Option[Json.JsonElement]): Unit \ IO =
        Array.put(json, 0, state#editingSchemaJsonRef)

    pub def getEditingSchemaJson(state: ResourceState): Option[Json.JsonElement] \ IO =
        Array.get(0, state#editingSchemaJsonRef)

    pub def setDirty(state: ResourceState, dirty: Bool): Unit \ IO =
        Array.put(dirty, 0, state#dirtyRef)

    pub def isDirty(state: ResourceState): Bool \ IO =
        Array.get(0, state#dirtyRef)

    pub def setPreviewZoom(state: ResourceState, mode: PropertyWidgets.ZoomMode): Unit \ IO =
        Array.put(mode, 0, state#previewZoomRef)

    pub def getPreviewZoom(state: ResourceState): PropertyWidgets.ZoomMode \ IO =
        Array.get(0, state#previewZoomRef)

    pub def setPreviewGrid(state: ResourceState, show: Bool): Unit \ IO =
        Array.put(show, 0, state#previewGridRef)

    pub def getPreviewGrid(state: ResourceState): Bool \ IO =
        Array.get(0, state#previewGridRef)
}
