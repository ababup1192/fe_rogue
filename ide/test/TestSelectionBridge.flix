// Tests for SelectionBridge — scene-tree ↔ editor 選択の双方向同期
//
// 検証の観点:
//   - JTree のクリック (pendingTreeSelectionRef) が Editor.EditorState の selected に乗るか
//   - 何もない (pending 無し / scene パス無し) ときは editor を壊さないか
//   - editor 側で selected が変わったときに IdeState.selectedNodePathRef に追従するか
//   - 値が変わっていないときは IdeState を上書きしないか

mod TestSelectionBridge {

    /// テスト用に「ぴったり 1 回 EditorState を扱える」スコープを作る薄いヘルパ。
    /// 初期 EditorStateData は initialState(Map.empty()) で組み、Array に乗せて
    /// 各テスト本体で観察できるようにする
    def withMockEditorState(thunk: Unit -> a \ ef + Editor.EditorState,
                            stateRef: Array[Editor.EditorStateData, Static]): a \ ef + IO =
        run thunk() with handler Editor.EditorState {
            def get(k) = k(Array.get(0, stateRef))
            def put(stateData, k) = { Array.put(stateData, 0, stateRef); k() }
            def pollReload(k) = k(false)
        }

    /// テスト用の初期 EditorStateData (空の索引で起動した状態)。
    /// Selection が None、editor は OFF (on = false)
    def emptyEditorState(): Editor.EditorStateData =
        Editor.initialState(Map.empty())

    /// テスト用の JSON シーン。root に hero (Sprite2D) + tree (Sprite2D) の 2 兄弟を持つ。
    /// indices = [0] → "hero", indices = [1] → "tree"
    def sampleSceneJson(): Json.JsonElement =
        let hero = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Sprite2D"),
            "name" => Json.JsonElement.JsonString("hero")});
        let tree = Json.JsonElement.JsonObject(Map#{
            "type" => Json.JsonElement.JsonString("Sprite2D"),
            "name" => Json.JsonElement.JsonString("tree")});
        Json.JsonElement.JsonObject(Map#{
            "type"     => Json.JsonElement.JsonString("Node2D"),
            "name"     => Json.JsonElement.JsonString("root"),
            "children" => Json.JsonElement.JsonArray(Vector#{hero, tree})})

    // ========================================================================
    // applyTreeSelectionToEditor — tree クリック → editor selected
    // ========================================================================

    /// JTree がクリックされて pendingTreeSelectionRef に [1] (= tree 兄弟の 2 件目) が
    /// 積まれている。現シーンパスも sampleSceneJson も入っているので、
    /// Editor.EditorState#selected に nodePath = ["root", "tree"] の Selection が乗る
    /// (sampleSceneJson は単一オブジェクトルート "root" を持つので、engine NodePath は
    /// その name から始まる)。
    /// 同時に editor は ON にする (F1 OFF のままだと preview に選択枠が出ないため)
    @Test
    def testApplyTreeSelectionWritesSelectionAndTurnsEditorOn(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        IdeState.setPendingTreeSelection(state, Some(1i32 :: Nil));
        Array.put(Some("/tmp/MyScene.scene.json"), 0, state#currentScenePathRef);
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);

        let editorRef = Array#{emptyEditorState()} @ Static;
        withMockEditorState(() -> SelectionBridge.applyTreeSelectionToEditor(state), editorRef);

        let after = Array.get(0, editorRef);
        match after#selected {
            case Some(sel) =>
                Assert.assertEq(
                    expected = (true, "/tmp/MyScene.scene.json",
                                "root" :: "tree" :: Nil,
                                "root" :: "tree" :: Nil),
                    (after#on, sel#jsonPath, sel#nodePath, sel#jsonNodePath))
            case None => bug!("expected EditorState#selected to be Some after tree click")
        }

    /// pendingTreeSelectionRef が消費された後は空になる (連続フレームで同じ選択が
    /// 何度も editor に流れ込まないように 1 回限り)
    @Test
    def testApplyTreeSelectionDrainsPending(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        IdeState.setPendingTreeSelection(state, Some(0i32 :: Nil));
        Array.put(Some("/tmp/X.scene.json"), 0, state#currentScenePathRef);
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);

        let editorRef = Array#{emptyEditorState()} @ Static;
        withMockEditorState(() -> SelectionBridge.applyTreeSelectionToEditor(state), editorRef);

        Assert.assertEq(
            expected = (None: Option[List[Int32]]),
            Array.get(0, state#pendingTreeSelectionRef))

    /// 現シーンパスが未確定 (プロジェクト未ロード / シーン未選択) の場合、
    /// pending があっても editor を壊さない (selected は None のまま、editor は OFF のまま)
    @Test
    def testApplyTreeSelectionNoOpWhenScenePathMissing(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        IdeState.setPendingTreeSelection(state, Some(0i32 :: Nil));
        // currentScenePathRef は newState 直後で None

        let editorRef = Array#{emptyEditorState()} @ Static;
        withMockEditorState(() -> SelectionBridge.applyTreeSelectionToEditor(state), editorRef);

        let after = Array.get(0, editorRef);
        // Selection 型は ToString/Eq 未定義のため、nodePath まで降ろして比較する
        let selectedNodePath = after#selected |> Option.map(sel -> sel#nodePath);
        Assert.assertEq(
            expected = ((None: Option[List[String]]), false),
            (selectedNodePath, after#on))

    /// pendingTreeSelectionRef が空ならば何もせず、editor は変化しない
    @Test
    def testApplyTreeSelectionNoOpWhenNoPending(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        Array.put(Some("/tmp/X.scene.json"), 0, state#currentScenePathRef);
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);
        // pendingTreeSelectionRef は newState 直後で None

        let editorRef = Array#{emptyEditorState()} @ Static;
        withMockEditorState(() -> SelectionBridge.applyTreeSelectionToEditor(state), editorRef);

        let after = Array.get(0, editorRef);
        let selectedNodePath = after#selected |> Option.map(sel -> sel#nodePath);
        Assert.assertEq(
            expected = ((None: Option[List[String]]), false),
            (selectedNodePath, after#on))

    // ========================================================================
    // syncEditorSelectionToTree — editor selected → IdeState.selectedNodePathRef
    // ========================================================================

    /// editor 側で Selection が立っている (nodePath = ["root", "tree"]) 状態で
    /// sync を呼ぶと、root を消費して残りを children で辿り [1] というインデックス列に
    /// 変換され、IdeState.selectedNodePathRef にその値が乗る
    @Test
    def testSyncEditorSelectionWritesNodePathToIdeState(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);

        let selected = Some({jsonPath     = "/tmp/X.scene.json",
                             nodePath     = "root" :: "tree" :: Nil,
                             jsonNodePath = "root" :: "tree" :: Nil});
        let editorRef = Array#{({selected = selected | emptyEditorState()})} @ Static;
        discard withMockEditorState(() -> SelectionBridge.syncEditorSelectionToTree(state), editorRef);

        Assert.assertEq(
            expected = Some(1i32 :: Nil),
            IdeState.getSelectedNodePath(state))

    /// editor 側で Selection が外れた (None) 状態でも、IdeState 側に None を反映する
    @Test
    def testSyncEditorSelectionPropagatesNone(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);
        // IdeState 側に古い選択 [0] が残っているケースから始める
        Array.put(Some(0i32 :: Nil), 0, state#selectedNodePathRef);

        // editor の selected は None (deselect された)
        let editorRef = Array#{emptyEditorState()} @ Static;
        discard withMockEditorState(() -> SelectionBridge.syncEditorSelectionToTree(state), editorRef);

        Assert.assertEq(
            expected = (None: Option[List[Int32]]),
            IdeState.getSelectedNodePath(state))

    /// editor の selected が IdeState 側と等しいときは何も書き戻さない (idempotent)。
    /// ["root", "hero"] → [0] が現 JSON で対応し、IdeState 側にも同じ値が乗っている
    /// 状態を確認する
    @Test
    def testSyncEditorSelectionNoOpWhenSame(): Unit \ {Assert, IO} =
        let state = IdeState.newState();
        Array.put(Some(sampleSceneJson()), 0, state#currentSceneJsonRef);
        Array.put(Some(0i32 :: Nil), 0, state#selectedNodePathRef);

        let selected = Some({jsonPath     = "/tmp/X.scene.json",
                             nodePath     = "root" :: "hero" :: Nil,
                             jsonNodePath = "root" :: "hero" :: Nil});
        let editorRef = Array#{({selected = selected | emptyEditorState()})} @ Static;
        discard withMockEditorState(() -> SelectionBridge.syncEditorSelectionToTree(state), editorRef);

        Assert.assertEq(
            expected = Some(0i32 :: Nil),
            IdeState.getSelectedNodePath(state))
}
