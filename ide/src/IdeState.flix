// IdeState — IDE のグローバル状態 (Ref 群) を 1 か所にまとめる
//
// EDT 上の UI イベントが Ref に書き、メインループ (Main.flix の renderLoop) が読む構造。
// 状態の定義と初期化、薄い IO アクセサを集約することで、view 層 (IdeUI / SwingUi / SceneTreeView /
// InspectorView) から「どのフィールドが書き換わるか」を機械的に追えるようにする。
//
// 注意: ここに置くのは「state の形」と「Ref を 1 つ取り出す/書き戻す」レベルの薄いラッパーまで。
// Swing 構築・Inspector 再描画・JSON 整形のような複雑な処理は view 層に置く

mod IdeState {
    import javax.swing.JFrame
    import javax.swing.JPanel
    import javax.swing.JTree
    import javax.swing.tree.DefaultTreeModel
    // JavaFX 移行用: customize で取得した fx:id ノード参照を持つ。
    // Phase 2 では TreeView と Stage のみ。Inspector 等は後続 Phase で追加
    import javafx.scene.control.TreeView
    import javafx.scene.control.ListView
    import javafx.scene.control.Label
    import javafx.scene.control.TextField
    import javafx.scene.layout.VBox
    import javafx.stage.Stage

    /// IDE のグローバル状態。EDT 上の UI イベントが Refs に書き、
    /// メインループ (Main.flix) と renderLoop が読む。
    ///   pendingProjectRef:    File → Open Project... で選ばれたディレクトリ。Main の reload で消費。
    ///   pendingSceneRef:      scene リストで選ばれた scene の絶対パス。renderLoop が毎フレーム消費。
    ///                         Inspector で値を変更した直後にもセットされ、canvas を即時 reload する。
    ///   sceneFilesRef:        現プロジェクトの (絶対パス, 表示用相対パス) のペアリスト。
    ///   sceneTreeRef:         左パネル JTree 本体。preview クリックで選択が変わったとき
    ///                         setSelectionPath で見た目を同期させるために保持する。
    ///   sceneTreeModelRef:    左パネル JTree の TreeModel。シーン選択時に root を差し替える。
    ///   nodePathMapRef:       tree ノードの identityHashCode → ルートからの子インデックス列。
    ///                         Tree 選択時にこの path で currentSceneJson を歩いて
    ///                         最新の JsonElement を取り、Inspector に渡す。
    ///                         commit 時に「JSON のどこを書き換えるか」も同じ path で判断する。
    ///   inspectorContentRef:  Inspector 本体の JPanel (BoxLayout)。ノード選択ごとに
    ///                         removeAll → 再構築する。
    ///   currentScenePathRef:  現在 IDE が表示中の scene.json の絶対パス。Inspector commit で
    ///                         書き出し先 + reload トリガに使う。
    ///   currentSceneJsonRef:  現在 scene の root JsonElement。commit のたびに新 root に差し替え、
    ///                         Tree 再選択時の Inspector 表示にも使われる (常に最新)。
    ///   selectedNodePathRef:  Tree で選択中ノードの子インデックス列。commit が key と新値を
    ///                         どこに当てるかを示す。
    ///   textureNamesRef:      現プロジェクトの project.json で宣言された texture 名のリスト。
    ///                         Inspector の Sprite2D "texture" フィールドを dropdown 化するのに使う。
    ///                         プロジェクト未ロード時は空。
    ///   pendingTreeSelectionRef:
    ///                         scene-tree (JTree) でユーザーがノードをクリックした直後に
    ///                         「次フレームで editor 側へ選択を伝える」シグナルとして使う。
    ///                         renderLoop が SelectionBridge 経由で消費する。
    ///                         プログラム側から JTree.setSelectionPath を呼んだ場合は積まない
    ///                         (treeListenerMuteRef で抑止)
    ///   treeListenerMuteRef:  preview→tree 同期で setSelectionPath を呼ぶ際に立てるフラグ。
    ///                         TreeSelectionListener はこのフラグが true のとき何もしない。
    ///                         「preview クリック → editor 選択変更 → tree ハイライト更新 →
    ///                         listener 発火 → editor へ往復」 のループを切るのに使う
    pub type alias IdeState = {
        pendingProjectRef        = Array[Option[String], Static],
        pendingSceneRef          = Array[Option[String], Static],
        sceneFilesRef            = Array[List[(String, String)], Static],
        loadingSplashRef         = Array[Option[JFrame], Static],
        sceneTreeRef             = Array[Option[JTree], Static],
        sceneTreeModelRef        = Array[Option[DefaultTreeModel], Static],
        nodePathMapRef           = Array[Map[Int32, List[Int32]], Static],
        inspectorContentRef      = Array[Option[JPanel], Static],
        currentScenePathRef      = Array[Option[String], Static],
        currentSceneJsonRef      = Array[Option[Json.JsonElement], Static],
        selectedNodePathRef      = Array[Option[List[Int32]], Static],
        textureNamesRef          = Array[List[String], Static],
        texturePathMapRef        = Array[Map[String, String], Static],
        pendingTreeSelectionRef  = Array[Option[List[Int32]], Static],
        treeListenerMuteRef      = Array[Bool, Static],
        // JavaFX 移行用: FXML から取得した fx:id ノード参照。
        // customize 時に Some を入れ、main thread から Platform.runLater 経由で参照する
        fxSceneTreeRef           = Array[Option[TreeView[String]], Static],
        fxResourcesListRef       = Array[Option[ListView[String]], Static],
        fxStageRef               = Array[Option[Stage], Static],
        // ステータスバー (現シーン/マウス/選択/FPS)。AnimationTimer から polling 更新される
        fxStatusSceneLabelRef    = Array[Option[Label], Static],
        fxStatusMouseLabelRef    = Array[Option[Label], Static],
        fxStatusSelectionLabelRef = Array[Option[Label], Static],
        fxStatusFpsLabelRef      = Array[Option[Label], Static],
        // 診断用: renderLoop が Editor.EditorState.get()#selected を毎フレーム文字列化して
        // 書き込み、AnimationTimer が選択ラベルに反映する。currentSceneJsonRef 経由の
        // selectedNodePathRef 変換に頼らず Editor 側の真の選択状態が即座に見える
        fxEditorSelDisplayRef    = Array[String, Static],
        // Inspector pane: 選択ノードのプロパティを並べる VBox と、前回反映した selection 文字列。
        // AnimationTimer が選択変化を検知して再構築する
        fxInspectorContentRef    = Array[Option[VBox], Static],
        fxInspectorLastSelRef    = Array[String, Static],
        // Inspector の各ラベル参照と、renderLoop が毎フレーム書き込む選択ノードの値。
        // 選択変化時に Label を作って参照を覚え、毎フレーム AnimationTimer が setText で更新する
        fxInspectorPosLabelRef      = Array[Option[Label], Static],
        fxInspectorLocalPosLabelRef = Array[Option[Label], Static],
        fxInspectorScaleLabelRef    = Array[Option[Label], Static],
        fxInspectorRotationLabelRef = Array[Option[Label], Static],
        fxInspectorWorldPosRef      = Array[Option[(Float64, Float64)], Static],
        fxInspectorLocalPosRef      = Array[Option[(Float64, Float64)], Static],
        fxInspectorScaleRef         = Array[Option[(Float64, Float64)], Static],
        fxInspectorRotationRef      = Array[Option[Float64], Static],
        // Local position / Scale / Rotation はすべて編集可能 TextField で表示する。
        // AnimationTimer は focus が無いときだけ setText し、Enter で commit
        fxInspectorLocalXFieldRef   = Array[Option[TextField], Static],
        fxInspectorLocalYFieldRef   = Array[Option[TextField], Static],
        fxInspectorScaleXFieldRef   = Array[Option[TextField], Static],
        fxInspectorScaleYFieldRef   = Array[Option[TextField], Static],
        fxInspectorRotationFieldRef = Array[Option[TextField], Static],
        // TextField commit から renderLoop に渡される編集値。
        // renderLoop が SceneSerializer.update* に流して JSON 書込み → HotReload 経由再 load
        fxPendingLocalPosEditRef    = Array[Option[(Float64, Float64)], Static],
        fxPendingScaleEditRef       = Array[Option[(Float64, Float64)], Static],
        // Rotation 編集値は degree で受けて radian に変換して保存
        fxPendingRotationEditRef    = Array[Option[Float64], Static],
        // Project 切替時に新 config を積む。JavaFXLayer.paintGL が消費して texture/font/
        // projection/audio を再初期化する
        fxPendingConfigRef       = Array[Option[GameEngine.EngineConfig], Static],
        // HotReload watcher (Open Project ごとに新規 spawn) が channel 経由でセットする
        // 「現シーンの再読込が必要」フラグ。renderLoop が消費して pendingSceneRef に積み直す。
        // Editor 本体の watcher は cwd 基準 ("./src/scenes") なので IDE では機能しない
        fxReloadFlagRef          = Array[Bool, Static],
        // Open Project 後に「config swap が完了したら先頭シーンを auto-load する」希望を立てる。
        // 直接 pendingSceneRef を積むと swap 前にロードされ getFontAtlas で bug! になるため、
        // renderLoop が fxPendingConfigRef の状態 (None = swap 完了) を polling して promote する
        wantsAutoLoadFirstSceneRef = Array[Bool, Static],
        resource                 = ResourceState.ResourceState
    }

    /// 空の IDE 状態を作る。Static 領域の Ref を全フィールド分用意する。
    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef        = Array#{(None: Option[String])} @ Static,
            pendingSceneRef          = Array#{(None: Option[String])} @ Static,
            sceneFilesRef            = Array#{(Nil: List[(String, String)])} @ Static,
            loadingSplashRef         = Array#{(None: Option[JFrame])} @ Static,
            sceneTreeRef             = Array#{(None: Option[JTree])} @ Static,
            sceneTreeModelRef        = Array#{(None: Option[DefaultTreeModel])} @ Static,
            nodePathMapRef           = Array#{(Map.empty(): Map[Int32, List[Int32]])} @ Static,
            inspectorContentRef      = Array#{(None: Option[JPanel])} @ Static,
            currentScenePathRef      = Array#{(None: Option[String])} @ Static,
            currentSceneJsonRef      = Array#{(None: Option[Json.JsonElement])} @ Static,
            selectedNodePathRef      = Array#{(None: Option[List[Int32]])} @ Static,
            textureNamesRef          = Array#{(Nil: List[String])} @ Static,
            texturePathMapRef        = Array#{(Map.empty(): Map[String, String])} @ Static,
            pendingTreeSelectionRef  = Array#{(None: Option[List[Int32]])} @ Static,
            treeListenerMuteRef      = Array#{false} @ Static,
            fxSceneTreeRef           = Array#{(None: Option[TreeView[String]])} @ Static,
            fxResourcesListRef       = Array#{(None: Option[ListView[String]])} @ Static,
            fxStageRef               = Array#{(None: Option[Stage])} @ Static,
            fxStatusSceneLabelRef    = Array#{(None: Option[Label])} @ Static,
            fxStatusMouseLabelRef    = Array#{(None: Option[Label])} @ Static,
            fxStatusSelectionLabelRef = Array#{(None: Option[Label])} @ Static,
            fxStatusFpsLabelRef      = Array#{(None: Option[Label])} @ Static,
            fxEditorSelDisplayRef    = Array#{"-"} @ Static,
            fxInspectorContentRef    = Array#{(None: Option[VBox])} @ Static,
            fxInspectorLastSelRef    = Array#{""} @ Static,
            fxInspectorPosLabelRef      = Array#{(None: Option[Label])} @ Static,
            fxInspectorLocalPosLabelRef = Array#{(None: Option[Label])} @ Static,
            fxInspectorScaleLabelRef    = Array#{(None: Option[Label])} @ Static,
            fxInspectorRotationLabelRef = Array#{(None: Option[Label])} @ Static,
            fxInspectorWorldPosRef      = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorLocalPosRef      = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorScaleRef         = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxInspectorRotationRef      = Array#{(None: Option[Float64])} @ Static,
            fxInspectorLocalXFieldRef   = Array#{(None: Option[TextField])} @ Static,
            fxInspectorLocalYFieldRef   = Array#{(None: Option[TextField])} @ Static,
            fxInspectorScaleXFieldRef   = Array#{(None: Option[TextField])} @ Static,
            fxInspectorScaleYFieldRef   = Array#{(None: Option[TextField])} @ Static,
            fxInspectorRotationFieldRef = Array#{(None: Option[TextField])} @ Static,
            fxPendingLocalPosEditRef    = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxPendingScaleEditRef       = Array#{(None: Option[(Float64, Float64)])} @ Static,
            fxPendingRotationEditRef    = Array#{(None: Option[Float64])} @ Static,
            fxPendingConfigRef       = Array#{(None: Option[GameEngine.EngineConfig])} @ Static,
            fxReloadFlagRef          = Array#{false} @ Static,
            wantsAutoLoadFirstSceneRef = Array#{false} @ Static,
            resource                 = ResourceState.newState()
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

    /// texture 名 → 絶対パスのマップを登録する。SpritePreview が BufferedImage を
    /// 読み込むときに texture 名から絶対パスを引くために使う。
    pub def setTexturePathMap(state: IdeState, m: Map[String, String]): Unit \ IO =
        Array.put(m, 0, state#texturePathMapRef)

    /// 登録済みの texture 名 → 絶対パスマップを返す。未ロード時は空 Map。
    pub def getTexturePathMap(state: IdeState): Map[String, String] \ IO =
        Array.get(0, state#texturePathMapRef)

    /// 現在開いている scene.json の絶対パスを返す。プロジェクト未ロード時や未選択時は None
    pub def getCurrentScenePath(state: IdeState): Option[String] \ IO =
        Array.get(0, state#currentScenePathRef)

    /// 現在 Tree で選択中のノードの子インデックス列を返す。未選択なら None
    pub def getSelectedNodePath(state: IdeState): Option[List[Int32]] \ IO =
        Array.get(0, state#selectedNodePathRef)

    /// プログラム側から JTree.setSelectionPath を呼ぶときに True にして、
    /// TreeSelectionListener が pendingTreeSelectionRef に書き戻すのを止める
    pub def setTreeListenerMuted(state: IdeState, muted: Bool): Unit \ IO =
        Array.put(muted, 0, state#treeListenerMuteRef)

    /// TreeSelectionListener から「自分が抑止状態か」を読む。プログラム由来更新中なら True
    pub def isTreeListenerMuted(state: IdeState): Bool \ IO =
        Array.get(0, state#treeListenerMuteRef)

    /// TreeSelectionListener が「ユーザーが tree でクリックした」事実を伝えるための
    /// 1 フレームキュー。renderLoop が SelectionBridge 経由で消費する
    pub def setPendingTreeSelection(state: IdeState, path: Option[List[Int32]]): Unit \ IO =
        Array.put(path, 0, state#pendingTreeSelectionRef)

    /// pendingTreeSelectionRef を取り出して None でクリアする。
    /// 連続フレームで同じ選択が複数回 editor に流れ込まないようにする
    pub def takePendingTreeSelection(state: IdeState): Option[List[Int32]] \ IO =
        let pending = Array.get(0, state#pendingTreeSelectionRef);
        Array.put(None, 0, state#pendingTreeSelectionRef);
        pending
}
