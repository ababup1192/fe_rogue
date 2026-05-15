// ResourceState — Resources タブの編集状態 (Ref 群)
//
// EDT 上の Resource 一覧 / sub-entry 一覧 / プロパティパネルが書き、
// Save ボタンと Sprite preview が読む。IdeState の resource フィールドとして保持する。
//
// preview キャッシュは Map[String, BufferedImage]。
// 同じ texture を複数 sub-entry が参照する場合に再ロードを避ける。

mod ResourceState {
    import javax.swing.JList
    import javax.swing.JPanel
    import javax.swing.JLabel
    import javax.swing.DefaultListModel
    import java.awt.image.BufferedImage

    use ResourceDiscovery.ResourceEntry

    /// Resources モード全体の状態。
    ///   discoveredRef:     resources/ 走査結果 (起動時 + Open Project で更新)
    ///   selectedDataPathRef: 現在選択中の Resource の絶対 dataPath。未選択は None
    ///   selectedSubEntryRef: catalog 形式時に選択中の sub-entry キー (例: "knight")。
    ///                        single 形式の Resource では使わず None。
    ///   editingJsonRef:    Resource 選択時にメモリにロードした data JSON。
    ///                      widget の commit でこの Ref が更新される。Save でこれを書き戻す。
    ///   editingSchemaRef:  Resource 選択時にロードした ResourceSchema。
    ///                      schema 違反 Resource は None で残し、UI が read-only fallback に切替える。
    ///   dirtyRef:          現在の editingJson が未保存変更を持つかどうか。
    ///                      Save 後 false にリセット。Resource 切替時には false から始める。
    ///   listRef / subListRef / propertyPanelRef / previewLabelRef:
    ///                      ResourceEditorUI が組み立てた Swing コンポーネント。
    ///                      Resource 切替時に外部から removeAll → rebuild するために保持。
    ///   bufferedImageCacheRef:
    ///                      texture 絶対パス → BufferedImage。SpritePreview が使う。
    pub type alias ResourceState = {
        discoveredRef          = Array[List[ResourceEntry], Static],
        selectedDataPathRef    = Array[Option[String], Static],
        selectedSubEntryRef    = Array[Option[String], Static],
        editingJsonRef         = Array[Option[Json.JsonElement], Static],
        editingSchemaRef       = Array[Option[Resource.ResourceSchema], Static],
        dirtyRef               = Array[Bool, Static],
        listRef                = Array[Option[JList[String]], Static],
        listModelRef           = Array[Option[DefaultListModel[String]], Static],
        subListRef             = Array[Option[JList[String]], Static],
        subListModelRef        = Array[Option[DefaultListModel[String]], Static],
        propertyPanelRef       = Array[Option[JPanel], Static],
        previewLabelRef        = Array[Option[JLabel], Static],
        bufferedImageCacheRef  = Array[Map[String, BufferedImage], Static]
    }

    /// 空の ResourceState を作る。
    pub def newState(): ResourceState \ IO =
        {
            discoveredRef          = Array#{(Nil: List[ResourceEntry])} @ Static,
            selectedDataPathRef    = Array#{(None: Option[String])} @ Static,
            selectedSubEntryRef    = Array#{(None: Option[String])} @ Static,
            editingJsonRef         = Array#{(None: Option[Json.JsonElement])} @ Static,
            editingSchemaRef       = Array#{(None: Option[Resource.ResourceSchema])} @ Static,
            dirtyRef               = Array#{false} @ Static,
            listRef                = Array#{(None: Option[JList[String]])} @ Static,
            listModelRef           = Array#{(None: Option[DefaultListModel[String]])} @ Static,
            subListRef             = Array#{(None: Option[JList[String]])} @ Static,
            subListModelRef        = Array#{(None: Option[DefaultListModel[String]])} @ Static,
            propertyPanelRef       = Array#{(None: Option[JPanel])} @ Static,
            previewLabelRef        = Array#{(None: Option[JLabel])} @ Static,
            bufferedImageCacheRef  = Array#{(Map.empty(): Map[String, BufferedImage])} @ Static
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

    pub def setDirty(state: ResourceState, dirty: Bool): Unit \ IO =
        Array.put(dirty, 0, state#dirtyRef)

    pub def isDirty(state: ResourceState): Bool \ IO =
        Array.get(0, state#dirtyRef)

    pub def setListRef(state: ResourceState, list: Option[JList[String]]): Unit \ IO =
        Array.put(list, 0, state#listRef)

    pub def getListRef(state: ResourceState): Option[JList[String]] \ IO =
        Array.get(0, state#listRef)

    pub def setListModelRef(state: ResourceState, m: Option[DefaultListModel[String]]): Unit \ IO =
        Array.put(m, 0, state#listModelRef)

    pub def getListModelRef(state: ResourceState): Option[DefaultListModel[String]] \ IO =
        Array.get(0, state#listModelRef)

    pub def setSubListRef(state: ResourceState, list: Option[JList[String]]): Unit \ IO =
        Array.put(list, 0, state#subListRef)

    pub def getSubListRef(state: ResourceState): Option[JList[String]] \ IO =
        Array.get(0, state#subListRef)

    pub def setSubListModelRef(state: ResourceState, m: Option[DefaultListModel[String]]): Unit \ IO =
        Array.put(m, 0, state#subListModelRef)

    pub def getSubListModelRef(state: ResourceState): Option[DefaultListModel[String]] \ IO =
        Array.get(0, state#subListModelRef)

    pub def setPropertyPanelRef(state: ResourceState, panel: Option[JPanel]): Unit \ IO =
        Array.put(panel, 0, state#propertyPanelRef)

    pub def getPropertyPanelRef(state: ResourceState): Option[JPanel] \ IO =
        Array.get(0, state#propertyPanelRef)

    pub def setPreviewLabelRef(state: ResourceState, label: Option[JLabel]): Unit \ IO =
        Array.put(label, 0, state#previewLabelRef)

    pub def getPreviewLabelRef(state: ResourceState): Option[JLabel] \ IO =
        Array.get(0, state#previewLabelRef)
}
