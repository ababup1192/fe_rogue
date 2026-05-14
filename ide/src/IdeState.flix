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
    import javax.swing.tree.DefaultTreeModel

    /// IDE のグローバル状態。EDT 上の UI イベントが Refs に書き、
    /// メインループ (Main.flix) と renderLoop が読む。
    ///   pendingProjectRef:    File → Open Project... で選ばれたディレクトリ。Main の reload で消費。
    ///   pendingSceneRef:      scene リストで選ばれた scene の絶対パス。renderLoop が毎フレーム消費。
    ///                         Inspector で値を変更した直後にもセットされ、canvas を即時 reload する。
    ///   sceneFilesRef:        現プロジェクトの (絶対パス, 表示用相対パス) のペアリスト。
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
        sceneTreeModelRef        = Array[Option[DefaultTreeModel], Static],
        nodePathMapRef           = Array[Map[Int32, List[Int32]], Static],
        inspectorContentRef      = Array[Option[JPanel], Static],
        currentScenePathRef      = Array[Option[String], Static],
        currentSceneJsonRef      = Array[Option[Json.JsonElement], Static],
        selectedNodePathRef      = Array[Option[List[Int32]], Static],
        textureNamesRef          = Array[List[String], Static],
        pendingTreeSelectionRef  = Array[Option[List[Int32]], Static],
        treeListenerMuteRef      = Array[Bool, Static]
    }

    /// 空の IDE 状態を作る。Static 領域の Ref を全フィールド分用意する。
    pub def newState(): IdeState \ IO =
        {
            pendingProjectRef        = Array#{(None: Option[String])} @ Static,
            pendingSceneRef          = Array#{(None: Option[String])} @ Static,
            sceneFilesRef            = Array#{(Nil: List[(String, String)])} @ Static,
            loadingSplashRef         = Array#{(None: Option[JFrame])} @ Static,
            sceneTreeModelRef        = Array#{(None: Option[DefaultTreeModel])} @ Static,
            nodePathMapRef           = Array#{(Map.empty(): Map[Int32, List[Int32]])} @ Static,
            inspectorContentRef      = Array#{(None: Option[JPanel])} @ Static,
            currentScenePathRef      = Array#{(None: Option[String])} @ Static,
            currentSceneJsonRef      = Array#{(None: Option[Json.JsonElement])} @ Static,
            selectedNodePathRef      = Array#{(None: Option[List[Int32]])} @ Static,
            textureNamesRef          = Array#{(Nil: List[String])} @ Static,
            pendingTreeSelectionRef  = Array#{(None: Option[List[Int32]])} @ Static,
            treeListenerMuteRef      = Array#{false} @ Static
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
