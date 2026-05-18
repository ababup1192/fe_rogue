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
    import javafx.scene.layout.VBox
    import javafx.scene.layout.StackPane
    import javafx.stage.Stage

    /// FXML の fx:id 経由で取得した主要 widget 参照。customize で全フィールドに値が入る
    pub type alias WidgetRefs = {
        sceneTree           = Array[Option[TreeView[String]], Static],
        resourcesList       = Array[Option[ListView[String]], Static],
        subEntriesList      = Array[Option[ListView[String]], Static],
        propertyPanel       = Array[Option[VBox], Static],
        resourcePreviewPane = Array[Option[StackPane], Static],
        stage               = Array[Option[Stage], Static]
    }

    /// 描画ループと FX レイヤーを橋渡しする ref 群。
    ///   editorSelDisplay: renderLoop が毎フレーム書き込む editor#selected の文字列表現
    ///   reloadFlag:       HotReload watcher が立てる「現シーン再 load 必要」フラグ
    ///   pendingConfig:    Project 切替時に新 config を積む (JavaFXLayer.paintGL が消費)
    pub type alias RuntimeRefs = {
        editorSelDisplay = Array[String, Static],
        reloadFlag       = Array[Bool, Static],
        pendingConfig    = Array[Option[GameEngine.EngineConfig], Static]
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
    ///   wantsAutoLoadFirstSceneRef: Open Project 後の deferred auto-load 希望フラグ
    ///
    /// Sub records (framework 寄りデータ):
    ///   widgets:   FXML 由来の主要 widget 参照 (WidgetRefs)
    ///   runtime:   描画ループ橋渡し用 ref (RuntimeRefs)
    ///   statusBar: ステータスバーの 4 Label
    ///   inspector: Inspector pane の状態 (詳細は InspectorRefs)
    ///   resource:  Resources 編集状態 (ResourceState module)
    pub type alias IdeState = {
        pendingProjectRef          = Array[Option[String], Static],
        pendingSceneRef            = Array[Option[String], Static],
        sceneFilesRef              = Array[List[(String, String)], Static],
        currentScenePathRef        = Array[Option[String], Static],
        textureNamesRef            = Array[List[String], Static],
        texturePathMapRef          = Array[Map[String, String], Static],
        wantsAutoLoadFirstSceneRef = Array[Bool, Static],
        widgets                    = WidgetRefs,
        runtime                    = RuntimeRefs,
        statusBar                  = StatusBarRefs,
        inspector                  = InspectorRefs,
        resource                   = ResourceState.ResourceState
    }

    /// 空の IDE 状態を作る。Static 領域の Ref を全フィールド分用意する。
    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef          = Array#{(None: Option[String])} @ Static,
            pendingSceneRef            = Array#{(None: Option[String])} @ Static,
            sceneFilesRef              = Array#{(Nil: List[(String, String)])} @ Static,
            currentScenePathRef        = Array#{(None: Option[String])} @ Static,
            textureNamesRef            = Array#{(Nil: List[String])} @ Static,
            texturePathMapRef          = Array#{(Map.empty(): Map[String, String])} @ Static,
            wantsAutoLoadFirstSceneRef = Array#{false} @ Static,
            widgets                    = newWidgets(),
            runtime                    = newRuntime(),
            statusBar                  = newStatusBar(),
            inspector                  = newInspector(),
            resource                   = ResourceState.newState()
        }

    def newWidgets(): WidgetRefs \ IO =
        {
            sceneTree           = Array#{(None: Option[TreeView[String]])} @ Static,
            resourcesList       = Array#{(None: Option[ListView[String]])} @ Static,
            subEntriesList      = Array#{(None: Option[ListView[String]])} @ Static,
            propertyPanel       = Array#{(None: Option[VBox])} @ Static,
            resourcePreviewPane = Array#{(None: Option[StackPane])} @ Static,
            stage               = Array#{(None: Option[Stage])} @ Static
        }

    def newRuntime(): RuntimeRefs \ IO =
        {
            editorSelDisplay = Array#{"-"} @ Static,
            reloadFlag       = Array#{false} @ Static,
            pendingConfig    = Array#{(None: Option[GameEngine.EngineConfig])} @ Static
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

    /// texture 名 → 絶対パスのマップを登録する。preview の画像読込で使う
    pub def setTexturePathMap(state: IdeState, m: Map[String, String]): Unit \ IO =
        Array.put(m, 0, state#texturePathMapRef)

    /// 登録済みの texture 名 → 絶対パスマップを返す。未ロード時は空 Map
    pub def getTexturePathMap(state: IdeState): Map[String, String] \ IO =
        Array.get(0, state#texturePathMapRef)

    /// 現在開いている scene.json の絶対パスを返す。プロジェクト未ロード時や未選択時は None
    pub def getCurrentScenePath(state: IdeState): Option[String] \ IO =
        Array.get(0, state#currentScenePathRef)
}
