// IdeState — IDE のグローバル状態 (Ref 群) を 1 か所にまとめる
//
// FX EDT 上の UI イベントが Ref に書き、メインループ (Main.flix の renderLoop) が読む構造。
// 状態の定義と初期化、薄い IO アクセサのみここに置き、UI 構築・JSON 整形のような
// 複雑な処理は view 層 (JavaFXIdeUI / ResourcePanel / ScenePanel) に置く。
//
// 設計方針: top-level は framework 非依存のドメイン Ref のみ。JavaFX に依存する Ref は
// 全て sub record (widgets / runtime / statusBar / inspector / resource) にまとめる。
// framework 移植時は sub record の中身だけ書き換え、ドメインデータと acceesor 関数は不変。

mod IdeState {
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.control.TextArea
    import java.lang.Integer
    import javafx.scene.control.CheckBox
    import javafx.scene.control.Button
    import javafx.scene.control.ToggleButton
    import javafx.scene.control.ComboBox
    import javafx.scene.control.Spinner
    import javafx.scene.control.ProgressBar
    import javafx.scene.layout.VBox
    import javafx.scene.layout.HBox
    import javafx.scene.layout.StackPane
    import javafx.scene.canvas.Canvas
    import javafx.scene.image.Image
    import javafx.scene.control.TabPane
    import javafx.stage.Stage

    /// FXML の fx:id 経由で取得した主要 widget 参照。customize で全フィールドに値が入る
    pub type alias WidgetRefs = {
        sceneTree                     = Array[Option[TreeView[String]], Static],
        resourcesList                 = Array[Option[ListView[String]], Static],
        subEntriesList                = Array[Option[ListView[String]], Static],
        subEntryAddBtn                = Array[Option[Button], Static],
        subEntryRemoveBtn             = Array[Option[Button], Static],
        propertyPanel                 = Array[Option[VBox], Static],
        resourcePreviewPane           = Array[Option[StackPane], Static],
        resourcePreviewZoomLbl        = Array[Option[Label], Static],
        resourcePreviewGridChk        = Array[Option[CheckBox], Static],
        resourcePreviewFrameAdjustChk = Array[Option[CheckBox], Static],
        resourceStatusLabel           = Array[Option[Label], Static],
        sceneDescriptionArea          = Array[Option[TextArea], Static],
        // TextArea に表示中の description がどの scene.json 由来かを追う。
        // シーン切替直後の blur で「新シーンに前シーンの内容が書き込まれる」事故を防ぐ
        sceneDescriptionEditingPath   = Array[Option[String], Static],
        stage                         = Array[Option[Stage], Static],
        loadingOverlay                = Array[Option[VBox], Static],
        loadingLabel                  = Array[Option[Label], Static],
        loadingBar                    = Array[Option[ProgressBar], Static],
        // Maps タブの Level リスト
        mapsList                      = Array[Option[ListView[String]], Static],
        // Maps タブの中央 Canvas (ピンチズーム + 自動保存対応)
        mapGridCanvas                 = Array[Option[Canvas], Static],
        // Maps タブ用 tileset PNG キャッシュ (S13 で manualTiles / decorTiles 描画に使う)。
        // 現状は texture 名を inca_tileset / tilemap_floor でハードコード参照する。
        // Material 概念を導入したら Level → Material → texture name の引き直しに置換予定。
        mapWallsImage                 = Array[Option[Image], Static],
        mapFloorImage                 = Array[Option[Image], Static],
        // Maps タブの Layer リスト行 (HBox) — クリックで選択、styleClass の付け外しで選択 highlight
        mapLayerRowFloor              = Array[Option[HBox], Static],
        mapLayerRowWalls              = Array[Option[HBox], Static],
        mapLayerRowEntities           = Array[Option[HBox], Static],
        // 各 Layer の visibility 目玉トグル (ToggleButton)
        mapLayerVisibleFloor          = Array[Option[ToggleButton], Static],
        mapLayerVisibleWalls          = Array[Option[ToggleButton], Static],
        mapLayerVisibleEntities       = Array[Option[ToggleButton], Static],
        // Maps タブの tile パレット (S15)
        mapPaletteCanvas              = Array[Option[Canvas], Static],
        mapPaletteStatus              = Array[Option[Label], Static],
        // Maps タブのパレット見出し (Layer 切替で "Palette (Floor/Walls)" 等に書き換える)
        mapPaletteLabel               = Array[Option[Label], Static],
        // Palette の SpriteSheet 選択 ComboBox と セル px 入力 Spinner
        mapPaletteTextureCombo        = Array[Option[ComboBox[String]], Static],
        mapPaletteCellWSpinner        = Array[Option[Spinner[Integer]], Static],
        mapPaletteCellHSpinner        = Array[Option[Spinner[Integer]], Static],
        // タイル間マージン (タイルセットによってはタイル間に隙間 px がある)
        mapPaletteMarginXSpinner      = Array[Option[Spinner[Integer]], Static],
        mapPaletteMarginYSpinner      = Array[Option[Spinner[Integer]], Static],
        // Floor/Walls 用 Palette セクション と Entities 用 Entity Id セクション (visible 切替)
        mapPaletteSection             = Array[Option[VBox], Static],
        mapEntitySection              = Array[Option[VBox], Static],
        // Maps タブの Entity identifier 入力 (S16)
        mapEntityIdField              = Array[Option[TextField], Static],
        // Maps タブの「+ New」ボタン (S17: 新規 Level 作成)
        mapNewBtn                     = Array[Option[Button], Static],
        // Materials サブタブ (wallMap 編集)
        mapRightTabs                  = Array[Option[TabPane], Static],
        mapMaterialsWallMapBox        = Array[Option[VBox], Static],
        mapMaterialsStatus            = Array[Option[Label], Static],
        mapMaterialsTilesetCanvas     = Array[Option[Canvas], Static]
    }

    /// 描画ループと FX レイヤーを橋渡しする ref 群。
    ///   editorSelDisplay: renderLoop が毎フレーム書き込む editor#selected の文字列表現
    ///   reloadFlag:       HotReload watcher が立てる「現シーン再 load 必要」フラグ
    ///   pendingConfig:    Project 切替時に新 config を積む (JavaFXLayer.paintGL が消費)
    pub type alias RuntimeRefs = {
        editorSelDisplay     = Array[String, Static],
        reloadFlag           = Array[Bool, Static],
        pendingConfig        = Array[Option[GameEngine.EngineConfig], Static],
        sceneTree            = Array[List[NodeInspector.SceneTreeNode], Static],
        pendingNodeSelection = Array[Option[Editor.Selection], Static],
        currentSceneJson     = Array[Option[Json.JsonElement], Static]
    }

    /// ステータスバーに並ぶ 4 つの Label。FX EDT 上の AnimationTimer (ScenePanel) が
    /// 毎フレーム setText する
    pub type alias StatusBarRefs = {
        sceneLabel     = Array[Option[Label], Static],
        mouseLabel     = Array[Option[Label], Static],
        selectionLabel = Array[Option[Label], Static],
        fpsLabel       = Array[Option[Label], Static]
    }

    /// Inspector pane の状態 (schema 駆動)。
    ///   content:          pane VBox 参照
    ///   lastSel:          前回反映 selection 文字列 (変化時に rebuild trigger)
    ///   schema:           現選択 node 用 FieldDef リスト (Main が selection 変化時に更新)
    ///   currentSelection: 現在の Selection (rebuild 時 commit closure が capture する)
    ///   currentValues:    name → 現値 JSON のスナップ (Main が毎フレーム書く)
    ///   pendingEdits:     widget commit から積まれる pending 更新 (Main が consume)
    ///   widgetUpdaters:   field name → widget 値更新 closure (rebuild 時に登録)
    ///   posLabel:         World position 表示用 Label (read-only)
    ///   worldPos:         毎フレーム書き込まれる world position 値
    pub type alias InspectorRefs = {
        content          = Array[Option[VBox], Static],
        lastSel          = Array[String, Static],
        schema           = Array[List[NodeInspector.FieldSection], Static],
        currentSelection = Array[Option[Editor.Selection], Static],
        currentValues    = Array[Map[String, Json.JsonElement], Static],
        pendingEdits     = Array[List[NodeInspector.PendingEdit], Static],
        widgetUpdaters   = Array[Map[String, Json.JsonElement -> Unit \ IO], Static],
        posLabel         = Array[Option[Label], Static],
        worldPos         = Array[Option[(Float64, Float64)], Static]
    }

    /// IDE 全体の状態。
    ///
    /// ドメイン状態 (framework 非依存):
    ///   pendingProjectRef:          File → Open Project... で予約された次プロジェクトディレクトリ
    ///   pendingSceneRef:            scene リストで予約された次シーンの絶対パス
    ///   sceneFilesRef:              現プロジェクトの (絶対パス, 表示用相対パス) のペアリスト
    ///   currentScenePathRef:        現在 IDE が表示中の scene.json の絶対パス
    ///   textureNamesRef:            現プロジェクトの texture 名一覧 (TexturePathT の ComboBox 候補)
    ///   texturePathMapRef:          texture 名 → 絶対パス。preview の画像読込で使う
    ///   soundNamesRef:              現プロジェクトの sound 論理名一覧 (AudioStreamPlayer.stream の ComboBox 候補)
    ///   pendingAudioCommandRef:     Inspector の Play/Stop ボタンが積む音声コマンド。
    ///                               renderLoop が GameEngine.Audio handler で消化する。
    ///                               JavaFX EDT 上の click handler は effect スコープ外なので、
    ///                               Ref に書いて render loop に橋渡しする
    ///   wantsAutoLoadFirstSceneRef: Open Project 後の deferred auto-load 希望フラグ
    ///
    /// Sub records (framework 寄りデータ):
    ///   widgets:   FXML 由来の主要 widget 参照 (WidgetRefs)
    ///   runtime:   描画ループ橋渡し用 ref (RuntimeRefs)
    ///   statusBar: ステータスバーの 4 Label
    ///   inspector: Inspector pane の状態 (詳細は InspectorRefs)
    ///   resource:  Resources 編集状態 (ResourceState module)
    /// Inspector の Play/Stop ボタンが renderLoop に依頼する音声コマンド。
    /// Play は `(stream, volume, loop)` を伴い、再生前に OpenAL に
    /// setVolume / setLooping を反映してから play する。Inspector で volume / loop を
    /// 編集してから Play を押せばそれが効く挙動になる。
    pub enum AudioCommand with Eq {
        case Play(String, Float32, Bool)
        case Stop(String)
    }

    pub type alias IdeState = {
        pendingProjectRef          = Array[Option[String], Static],
        pendingSceneRef            = Array[Option[String], Static],
        sceneFilesRef              = Array[List[(String, String)], Static],
        currentScenePathRef        = Array[Option[String], Static],
        // 現在ロード中のプロジェクトルート絶対パス (新規ファイル作成等で必要)
        currentProjectRootRef      = Array[Option[String], Static],
        textureNamesRef            = Array[List[String], Static],
        texturePathMapRef          = Array[Map[String, String], Static],
        soundNamesRef              = Array[List[String], Static],
        pendingAudioCommandRef     = Array[Option[AudioCommand], Static],
        wantsAutoLoadFirstSceneRef = Array[Bool, Static],
        loadingActiveRef           = Array[Bool, Static],
        widgets                    = WidgetRefs,
        runtime                    = RuntimeRefs,
        statusBar                  = StatusBarRefs,
        inspector                  = InspectorRefs,
        resource                   = ResourceState.ResourceState,
        mapEditor                  = MapEditorState.MapEditorState
    }

    /// 空の IDE 状態を作る。Static 領域の Ref を全フィールド分用意する。
    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef          = Array#{(None: Option[String])} @ Static,
            pendingSceneRef            = Array#{(None: Option[String])} @ Static,
            sceneFilesRef              = Array#{(Nil: List[(String, String)])} @ Static,
            currentScenePathRef        = Array#{(None: Option[String])} @ Static,
            currentProjectRootRef      = Array#{(None: Option[String])} @ Static,
            textureNamesRef            = Array#{(Nil: List[String])} @ Static,
            texturePathMapRef          = Array#{(Map.empty(): Map[String, String])} @ Static,
            soundNamesRef              = Array#{(Nil: List[String])} @ Static,
            pendingAudioCommandRef     = Array#{(None: Option[AudioCommand])} @ Static,
            wantsAutoLoadFirstSceneRef = Array#{false} @ Static,
            loadingActiveRef           = Array#{false} @ Static,
            widgets                    = newWidgets(),
            runtime                    = newRuntime(),
            statusBar                  = newStatusBar(),
            inspector                  = newInspector(),
            resource                   = ResourceState.newState(),
            mapEditor                  = MapEditorState.newState()
        }

    def newWidgets(): WidgetRefs \ IO =
        {
            sceneTree                     = Array#{(None: Option[TreeView[String]])} @ Static,
            resourcesList                 = Array#{(None: Option[ListView[String]])} @ Static,
            subEntriesList                = Array#{(None: Option[ListView[String]])} @ Static,
            subEntryAddBtn                = Array#{(None: Option[Button])} @ Static,
            subEntryRemoveBtn             = Array#{(None: Option[Button])} @ Static,
            propertyPanel                 = Array#{(None: Option[VBox])} @ Static,
            resourcePreviewPane           = Array#{(None: Option[StackPane])} @ Static,
            resourcePreviewZoomLbl        = Array#{(None: Option[Label])} @ Static,
            resourcePreviewGridChk        = Array#{(None: Option[CheckBox])} @ Static,
            resourcePreviewFrameAdjustChk = Array#{(None: Option[CheckBox])} @ Static,
            resourceStatusLabel           = Array#{(None: Option[Label])} @ Static,
            sceneDescriptionArea          = Array#{(None: Option[TextArea])} @ Static,
            sceneDescriptionEditingPath   = Array#{(None: Option[String])} @ Static,
            stage                         = Array#{(None: Option[Stage])} @ Static,
            loadingOverlay                = Array#{(None: Option[VBox])} @ Static,
            loadingLabel                  = Array#{(None: Option[Label])} @ Static,
            loadingBar                    = Array#{(None: Option[ProgressBar])} @ Static,
            mapsList                      = Array#{(None: Option[ListView[String]])} @ Static,
            mapGridCanvas                 = Array#{(None: Option[Canvas])} @ Static,
            mapWallsImage                 = Array#{(None: Option[Image])} @ Static,
            mapFloorImage                 = Array#{(None: Option[Image])} @ Static,
            mapLayerRowFloor              = Array#{(None: Option[HBox])} @ Static,
            mapLayerRowWalls              = Array#{(None: Option[HBox])} @ Static,
            mapLayerRowEntities           = Array#{(None: Option[HBox])} @ Static,
            mapLayerVisibleFloor          = Array#{(None: Option[ToggleButton])} @ Static,
            mapLayerVisibleWalls          = Array#{(None: Option[ToggleButton])} @ Static,
            mapLayerVisibleEntities       = Array#{(None: Option[ToggleButton])} @ Static,
            mapPaletteCanvas              = Array#{(None: Option[Canvas])} @ Static,
            mapPaletteStatus              = Array#{(None: Option[Label])} @ Static,
            mapPaletteLabel               = Array#{(None: Option[Label])} @ Static,
            mapPaletteTextureCombo        = Array#{(None: Option[ComboBox[String]])} @ Static,
            mapPaletteCellWSpinner        = Array#{(None: Option[Spinner[Integer]])} @ Static,
            mapPaletteCellHSpinner        = Array#{(None: Option[Spinner[Integer]])} @ Static,
            mapPaletteMarginXSpinner      = Array#{(None: Option[Spinner[Integer]])} @ Static,
            mapPaletteMarginYSpinner      = Array#{(None: Option[Spinner[Integer]])} @ Static,
            mapPaletteSection             = Array#{(None: Option[VBox])} @ Static,
            mapEntitySection              = Array#{(None: Option[VBox])} @ Static,
            mapEntityIdField              = Array#{(None: Option[TextField])} @ Static,
            mapNewBtn                     = Array#{(None: Option[Button])} @ Static,
            mapRightTabs                  = Array#{(None: Option[TabPane])} @ Static,
            mapMaterialsWallMapBox        = Array#{(None: Option[VBox])} @ Static,
            mapMaterialsStatus            = Array#{(None: Option[Label])} @ Static,
            mapMaterialsTilesetCanvas     = Array#{(None: Option[Canvas])} @ Static
        }

    def newRuntime(): RuntimeRefs \ IO =
        {
            editorSelDisplay     = Array#{"-"} @ Static,
            reloadFlag           = Array#{false} @ Static,
            pendingConfig        = Array#{(None: Option[GameEngine.EngineConfig])} @ Static,
            sceneTree            = Array#{(Nil: List[NodeInspector.SceneTreeNode])} @ Static,
            pendingNodeSelection = Array#{(None: Option[Editor.Selection])} @ Static,
            currentSceneJson     = Array#{(None: Option[Json.JsonElement])} @ Static
        }

    def newStatusBar(): StatusBarRefs \ IO =
        {
            sceneLabel     = Array#{(None: Option[Label])} @ Static,
            mouseLabel     = Array#{(None: Option[Label])} @ Static,
            selectionLabel = Array#{(None: Option[Label])} @ Static,
            fpsLabel       = Array#{(None: Option[Label])} @ Static
        }

    def newInspector(): InspectorRefs \ IO =
        {
            content          = Array#{(None: Option[VBox])} @ Static,
            lastSel          = Array#{""} @ Static,
            schema           = Array#{(Nil: List[NodeInspector.FieldSection])} @ Static,
            currentSelection = Array#{(None: Option[Editor.Selection])} @ Static,
            currentValues    = Array#{(Map.empty(): Map[String, Json.JsonElement])} @ Static,
            pendingEdits     = Array#{(Nil: List[NodeInspector.PendingEdit])} @ Static,
            widgetUpdaters   = Array#{(Map.empty(): Map[String, Json.JsonElement -> Unit \ IO])} @ Static,
            posLabel         = Array#{(None: Option[Label])} @ Static,
            worldPos         = Array#{(None: Option[(Float64, Float64)])} @ Static
        }

    /// File → Open Project... で予約された次プロジェクトのパスを取り出し、Ref をクリアする
    pub def takePendingProject(state: IdeState): Option[String] \ IO =
        let pending = Array.get(0, state#pendingProjectRef);
        Array.put(None, 0, state#pendingProjectRef);
        pending

    /// Scenes リストで予約された次シーンの絶対パスを取り出し、Ref をクリアする
    pub def takePendingScene(state: IdeState): Option[String] \ IO =
        let pending = Array.get(0, state#pendingSceneRef);
        Array.put(None, 0, state#pendingSceneRef);
        pending

    /// 現プロジェクトの scene.json 群 (絶対パス, 表示用相対パス) を登録する
    pub def setSceneFiles(state: IdeState, files: List[(String, String)]): Unit \ IO =
        Array.put(files, 0, state#sceneFilesRef)

    /// 現プロジェクトで利用可能な texture 名を Inspector の dropdown 用に登録する。
    /// プロジェクト切替時は新しい名前リストで上書き、未ロード時は Nil で空にする
    pub def setTextureNames(state: IdeState, names: List[String]): Unit \ IO =
        Array.put(names, 0, state#textureNamesRef)

    /// 現プロジェクトで利用可能な sound 論理名を Inspector の dropdown 用に登録する。
    /// AudioStreamPlayer の stream プロパティの選択肢として使われる
    pub def setSoundNames(state: IdeState, names: List[String]): Unit \ IO =
        Array.put(names, 0, state#soundNamesRef)

    /// JavaFX click handler から音声コマンドを積む。renderLoop が次フレームで消化する
    pub def enqueueAudioCommand(state: IdeState, cmd: AudioCommand): Unit \ IO =
        Array.put(Some(cmd), 0, state#pendingAudioCommandRef)

    /// renderLoop が積まれた音声コマンドを 1 件取り出して Ref をクリアする
    pub def takeAudioCommand(state: IdeState): Option[AudioCommand] \ IO =
        let cur = Array.get(0, state#pendingAudioCommandRef);
        Array.put(None, 0, state#pendingAudioCommandRef);
        cur

    /// texture 名 → 絶対パスのマップを登録する。preview の画像読込で使う
    pub def setTexturePathMap(state: IdeState, m: Map[String, String]): Unit \ IO =
        Array.put(m, 0, state#texturePathMapRef)

    /// 登録済みの texture 名 → 絶対パスマップを返す。未ロード時は空 Map
    pub def getTexturePathMap(state: IdeState): Map[String, String] \ IO =
        Array.get(0, state#texturePathMapRef)

    /// 現在開いている scene.json の絶対パスを返す。プロジェクト未ロード時や未選択時は None
    pub def getCurrentScenePath(state: IdeState): Option[String] \ IO =
        Array.get(0, state#currentScenePathRef)

    /// 現在ロード中のプロジェクトルート絶対パスを保存する。
    pub def setCurrentProjectRoot(state: IdeState, path: Option[String]): Unit \ IO =
        Array.put(path, 0, state#currentProjectRootRef)

    /// 現在ロード中のプロジェクトルート絶対パスを返す。未ロード時は None
    pub def getCurrentProjectRoot(state: IdeState): Option[String] \ IO =
        Array.get(0, state#currentProjectRootRef)
}
