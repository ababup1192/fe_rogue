// IdeState — IDE のグローバル状態 (Ref 群) を 1 か所にまとめる
//
// FX EDT 上の UI イベントが Ref に書き、メインループ (Main.flix の renderLoop) が読む構造。
// 状態の定義と初期化、薄い IO アクセサのみここに置き、UI 構築・JSON 整形のような
// 複雑な処理は view 層 (JavaFXIdeUI) に置く。
//
// 命名規約: JavaFX widget 参照は fx* プレフィックス。framework 非依存のドメインデータは
// 無印 (pendingProjectRef, sceneFilesRef, etc)。framework 移植時は fx* だけ書き換える

mod IdeState {
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.layout.VBox
    import javafx.scene.layout.StackPane
    import javafx.stage.Stage

    /// IDE 全体の状態。Ref 群を 1 か所にまとめて持つ。
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
    ///   fxResourcePreviewPaneRef, fxStageRef, ステータスバー Label 4 個
    ///
    /// Inspector pane:
    ///   fxInspectorContentRef:   コンテナ VBox
    ///   fxInspectorLastSelRef:   前回反映 selection。AnimationTimer が選択変化を検知して rebuild
    ///   fxInspectorPosLabelRef:  World position 表示 Label (read-only)
    ///   fxInspectorWorldPosRef:  毎フレーム書き込まれる world position 値
    ///   fxInspectorLocalPosRef / fxInspectorScaleRef / fxInspectorRotationRef:
    ///                            現値の Ref。AnimationTimer が focus 無しのときだけ TextField に setText
    ///   fxInspectorLocalXFieldRef ほか TextField 参照
    ///   fxPendingLocalPosEditRef / fxPendingScaleEditRef / fxPendingRotationEditRef:
    ///                            TextField commit から renderLoop に渡される編集値
    ///
    /// Resources 編集状態:
    ///   resource: ResourceState (別 module)
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
        fxStatusSceneLabelRef      = Array[Option[Label], Static],
        fxStatusMouseLabelRef      = Array[Option[Label], Static],
        fxStatusSelectionLabelRef  = Array[Option[Label], Static],
        fxStatusFpsLabelRef        = Array[Option[Label], Static],
        fxInspectorContentRef      = Array[Option[VBox], Static],
        fxInspectorLastSelRef      = Array[String, Static],
        fxInspectorPosLabelRef     = Array[Option[Label], Static],
        fxInspectorWorldPosRef     = Array[Option[(Float64, Float64)], Static],
        fxInspectorLocalPosRef     = Array[Option[(Float64, Float64)], Static],
        fxInspectorScaleRef        = Array[Option[(Float64, Float64)], Static],
        fxInspectorRotationRef     = Array[Option[Float64], Static],
        fxInspectorLocalXFieldRef  = Array[Option[TextField], Static],
        fxInspectorLocalYFieldRef  = Array[Option[TextField], Static],
        fxInspectorScaleXFieldRef  = Array[Option[TextField], Static],
        fxInspectorScaleYFieldRef  = Array[Option[TextField], Static],
        fxInspectorRotationFieldRef= Array[Option[TextField], Static],
        fxPendingLocalPosEditRef   = Array[Option[(Float64, Float64)], Static],
        fxPendingScaleEditRef      = Array[Option[(Float64, Float64)], Static],
        fxPendingRotationEditRef   = Array[Option[Float64], Static],
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
            fxStatusSceneLabelRef      = Array#{(None: Option[Label])} @ Static,
            fxStatusMouseLabelRef      = Array#{(None: Option[Label])} @ Static,
            fxStatusSelectionLabelRef  = Array#{(None: Option[Label])} @ Static,
            fxStatusFpsLabelRef        = Array#{(None: Option[Label])} @ Static,
            fxInspectorContentRef      = Array#{(None: Option[VBox])} @ Static,
            fxInspectorLastSelRef      = Array#{""} @ Static,
            fxInspectorPosLabelRef     = Array#{(None: Option[Label])} @ Static,
            fxInspectorWorldPosRef     = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorLocalPosRef     = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorScaleRef        = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorRotationRef     = Array#{(None: Option[Float64])} @ Static,
            fxInspectorLocalXFieldRef  = Array#{(None: Option[TextField])} @ Static,
            fxInspectorLocalYFieldRef  = Array#{(None: Option[TextField])} @ Static,
            fxInspectorScaleXFieldRef  = Array#{(None: Option[TextField])} @ Static,
            fxInspectorScaleYFieldRef  = Array#{(None: Option[TextField])} @ Static,
            fxInspectorRotationFieldRef= Array#{(None: Option[TextField])} @ Static,
            fxPendingLocalPosEditRef   = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxPendingScaleEditRef      = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxPendingRotationEditRef   = Array#{(None: Option[Float64])} @ Static,
            resource                   = ResourceState.newState()
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
