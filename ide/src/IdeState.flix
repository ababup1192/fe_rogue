// IdeState — IDE のグローバル状態 (Ref 群) を 1 か所にまとめる
//
// FX EDT 上の UI イベントが Ref に書き、メインループ (Main.flix の renderLoop) が読む構造。
// 状態の定義と初期化、薄い IO アクセサのみここに置き、UI 構築・JSON 整形のような
// 複雑な処理は view 層 (JavaFXIdeUI / ResourcePanel / ScenePanel) に置く。
//
// 命名規約: JavaFX widget 参照は fx* プレフィックス。framework 非依存のドメインデータは
// 無印 (pendingProjectRef, sceneFilesRef, etc)。framework 移植時は fx* だけ書き換える。
// 関連 Ref をまとめた sub record (statusBar / inspector / resource) を持ち、
// 大量の並列フィールドが top レベルに並ぶのを防ぐ。

mod IdeState {
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.layout.VBox
    import javafx.scene.layout.StackPane
    import javafx.stage.Stage

    /// ステータスバーに並ぶ 4 つの Label。FX EDT 上の AnimationTimer (ScenePanel) が
    /// 毎フレーム setText する
    pub type alias StatusBarRefs = {
        sceneLabel     = Array[Option[Label], Static],
        mouseLabel     = Array[Option[Label], Static],
        selectionLabel = Array[Option[Label], Static],
        fpsLabel       = Array[Option[Label], Static]
    }

    /// Inspector pane の状態。
    ///   content / lastSel:   pane VBox と前回反映 selection (変化時に rebuild)
    ///   posLabel / worldPos: read-only world position 表示
    ///   localPos / scale / rotation: 現値 Ref。renderLoop が毎フレーム書き込む
    ///   xxxField:            編集 TextField 参照。focus 無し時のみ setText
    ///   pendingXxx:          TextField commit → renderLoop の applyInspectorEdits に渡す
    pub type alias InspectorRefs = {
        content         = Array[Option[VBox], Static],
        lastSel         = Array[String, Static],
        posLabel        = Array[Option[Label], Static],
        worldPos        = Array[Option[(Float64, Float64)], Static],
        localPos        = Array[Option[(Float64, Float64)], Static],
        scale           = Array[Option[(Float64, Float64)], Static],
        rotation        = Array[Option[Float64], Static],
        localXField     = Array[Option[TextField], Static],
        localYField     = Array[Option[TextField], Static],
        scaleXField     = Array[Option[TextField], Static],
        scaleYField     = Array[Option[TextField], Static],
        rotationField   = Array[Option[TextField], Static],
        pendingLocalPos = Array[Option[(Float64, Float64)], Static],
        pendingScale    = Array[Option[(Float64, Float64)], Static],
        pendingRotation = Array[Option[Float64], Static]
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
    ///   fxEditorSelDisplayRef:      renderLoop が毎フレーム書き込む editor#selected の文字列表現
    ///   wantsAutoLoadFirstSceneRef: Open Project 後の deferred auto-load 希望フラグ
    ///   fxReloadFlagRef:            HotReload watcher が立てる「現シーン再 load 必要」フラグ
    ///   fxPendingConfigRef:         Project 切替時に新 config を積む (JavaFXLayer が消費)
    ///
    /// JavaFX widget 参照 (fx:id 経由で取得):
    ///   fxSceneTreeRef, fxResourcesListRef, fxSubEntriesListRef, fxPropertyPanelRef,
    ///   fxResourcePreviewPaneRef, fxStageRef
    ///
    /// Sub records:
    ///   statusBar: ステータスバーの 4 Label
    ///   inspector: Inspector pane の状態 (詳細は InspectorRefs を参照)
    ///   resource:  Resources 編集状態 (ResourceState module)
    pub type alias IdeState = {
        pendingProjectRef          = Array[Option[String], Static],
        pendingSceneRef            = Array[Option[String], Static],
        sceneFilesRef              = Array[List[(String, String)], Static],
        currentScenePathRef        = Array[Option[String], Static],
        textureNamesRef            = Array[List[String], Static],
        texturePathMapRef          = Array[Map[String, String], Static],
        fxEditorSelDisplayRef      = Array[String, Static],
        wantsAutoLoadFirstSceneRef = Array[Bool, Static],
        fxReloadFlagRef            = Array[Bool, Static],
        fxPendingConfigRef         = Array[Option[GameEngine.EngineConfig], Static],
        fxSceneTreeRef             = Array[Option[TreeView[String]], Static],
        fxResourcesListRef         = Array[Option[ListView[String]], Static],
        fxSubEntriesListRef        = Array[Option[ListView[String]], Static],
        fxPropertyPanelRef         = Array[Option[VBox], Static],
        fxResourcePreviewPaneRef   = Array[Option[StackPane], Static],
        fxStageRef                 = Array[Option[Stage], Static],
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
            fxEditorSelDisplayRef      = Array#{"-"} @ Static,
            wantsAutoLoadFirstSceneRef = Array#{false} @ Static,
            fxReloadFlagRef            = Array#{false} @ Static,
            fxPendingConfigRef         = Array#{(None: Option[GameEngine.EngineConfig])} @ Static,
            fxSceneTreeRef             = Array#{(None: Option[TreeView[String]])} @ Static,
            fxResourcesListRef         = Array#{(None: Option[ListView[String]])} @ Static,
            fxSubEntriesListRef        = Array#{(None: Option[ListView[String]])} @ Static,
            fxPropertyPanelRef         = Array#{(None: Option[VBox])} @ Static,
            fxResourcePreviewPaneRef   = Array#{(None: Option[StackPane])} @ Static,
            fxStageRef                 = Array#{(None: Option[Stage])} @ Static,
            statusBar                  = newStatusBar(),
            inspector                  = newInspector(),
            resource                   = ResourceState.newState()
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
            content         = Array#{(None: Option[VBox])} @ Static,
            lastSel         = Array#{""} @ Static,
            posLabel        = Array#{(None: Option[Label])} @ Static,
            worldPos        = Array#{(None: Option[(Float64, Float64)])} @ Static,
            localPos        = Array#{(None: Option[(Float64, Float64)])} @ Static,
            scale           = Array#{(None: Option[(Float64, Float64)])} @ Static,
            rotation        = Array#{(None: Option[Float64])} @ Static,
            localXField     = Array#{(None: Option[TextField])} @ Static,
            localYField     = Array#{(None: Option[TextField])} @ Static,
            scaleXField     = Array#{(None: Option[TextField])} @ Static,
            scaleYField     = Array#{(None: Option[TextField])} @ Static,
            rotationField   = Array#{(None: Option[TextField])} @ Static,
            pendingLocalPos = Array#{(None: Option[(Float64, Float64)])} @ Static,
            pendingScale    = Array#{(None: Option[(Float64, Float64)])} @ Static,
            pendingRotation = Array#{(None: Option[Float64])} @ Static
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
