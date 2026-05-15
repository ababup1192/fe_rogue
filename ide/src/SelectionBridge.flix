// SelectionBridge — scene-tree (左パネルの JTree) と scene-preview の選択状態を双方向に橋渡しする
//
// 役割:
//   - tree ↔ editor の選択を「片方の変化を 1 方向だけ反映する」関数に分け、ループしないように
//     treeListenerMuteRef を立てる
//
// 流れ:
//   ・ユーザーが JTree でノードをクリック
//       → TreeSelectionListener が selectedNodePathRef と pendingTreeSelectionRef を更新
//       → renderLoop の次フレーム冒頭で applyTreeSelectionToEditor が pending を消費し、
//         Editor.EditorState の selected に Selection を立てる
//   ・ユーザーが preview 上でノードをクリック (editor がマウス処理)
//       → Editor.EditorState の selected が更新される
//       → renderLoop の末尾で syncEditorSelectionToTree が前フレームとの差分を検出し、
//         IdeState.selectedNodePathRef を更新する (JTree のハイライト更新は view 層が行う)
//
// 表現の不一致への対応:
//   - IDE の selectedNodePathRef は「JSON ツリー上の子インデックス列」 (List[Int32])
//   - engine の NodePath は「ノード名の列」 (List[String])
//   いずれも「同じノードを指す」点で対応するが、変換には現在の scene JSON を歩く必要がある。
//   JsonOps.extractNodeNames が両方向の橋渡し本体

mod SelectionBridge {

    /// IdeState の pendingTreeSelectionRef に積まれた tree クリックを消費し、
    /// Editor.EditorState の selected に書き戻して editor 側で選択枠を出させる。
    /// 1 フレーム 1 件だけ処理する。
    /// プレハブ未使用の素直なシーンを想定し、jsonNodePath は nodePath と同値にする。
    /// pending が無い・現シーンパスや JSON が未確定・index から name への変換に失敗したときは
    /// 何もしない
    pub def applyTreeSelectionToEditor(state: IdeState.IdeState):
            Unit \ {IO, Editor.EditorState} =
        match IdeState.takePendingTreeSelection(state) {
            case None => ()
            case Some(indices) =>
                match (IdeState.getCurrentScenePath(state),
                       Array.get(0, state#currentSceneJsonRef)) {
                    case (Some(scenePath), Some(sceneRoot)) =>
                        match JsonOps.extractNodeNames(sceneRoot, indices) {
                            case None => ()
                            case Some(names) =>
                                let cur = Editor.EditorState.get();
                                let selection = {jsonPath     = scenePath,
                                                 nodePath     = names,
                                                 jsonNodePath = names};
                                // tree から選択するときは editor を ON にする
                                // (F1 OFF だと preview に選択枠が出ないため)
                                Editor.EditorState.put({selected = Some(selection),
                                                        on       = true | cur})
                        }
                    case _ => ()
                }
        }

    /// editor 側で選択ノードが (主にマウスクリックで) 変化したとき、
    /// IdeState.selectedNodePathRef を最新化する。
    /// editor 側は List[String] (名前列) で持つので、現 JSON を walk してインデックス列に
    /// 変換する。変換に失敗した (該当名のノードが現 JSON に無い) ケースは None として扱う。
    /// 値が前回と同じなら何もしない (フレーム毎の不要な書き込みを抑制)。
    /// 戻り値: 選択が前フレームと変化したか。true なら呼び出し側 (view 層) が
    /// JTree のハイライトと Inspector を最新の selectedNodePath で再構築する
    pub def syncEditorSelectionToTree(state: IdeState.IdeState):
            Bool \ {IO, Editor.EditorState} =
        let editorData = Editor.EditorState.get();
        let editorIndices = match editorData#selected {
            case None      => None
            case Some(sel) =>
                match Array.get(0, state#currentSceneJsonRef) {
                    case None       => None
                    case Some(root) => namesToIndices(root, sel#nodePath)
                }
        };
        let storedIndices = IdeState.getSelectedNodePath(state);
        if (editorIndices == storedIndices) false
        else {
            Array.put(editorIndices, 0, state#selectedNodePathRef);
            true
        }

    /// ノード名のリスト (engine NodePath 相当) を、現 JSON ツリー上の子インデックス列に
    /// 変換する。各ステップで現ノードの children を走査し、name が一致する子を探す。
    /// 途中で見つからなければ None。
    ///
    /// ルートの扱いは extractNodeNames と対応する:
    ///   - JsonObject root: NodePath 先頭は root の name に一致しているはず。
    ///     一致したらそれを消費し、残りを children の中で辿る。
    ///   - JsonArray root: NodePath 先頭が配列要素の name に一致するように辿る (通常通り)
    def namesToIndices(root: Json.JsonElement, names: List[String]): Option[List[Int32]] =
        match root {
            case Json.JsonElement.JsonObject(_) =>
                match (nameOf(root), names) {
                    case (Some(rootName), head :: rest) =>
                        if (head == rootName) namesToIndicesRec(root, rest, Nil)
                        else None
                    case (Some(_), Nil) =>
                        // ルートの name はあるが engine NodePath が空 → 無効
                        None
                    case (None, _) =>
                        // ルートに name が無いオブジェクト → 児童直下から辿る
                        namesToIndicesRec(root, names, Nil)
                }
            case _ => namesToIndicesRec(root, names, Nil)
        }

    def namesToIndicesRec(root: Json.JsonElement, names: List[String],
                          acc: List[Int32]): Option[List[Int32]] =
        match names {
            case Nil => Some(List.reverse(acc))
            case headName :: restNames =>
                match findChildIndexByName(root, headName) {
                    case None => None
                    case Some((idxPath, child)) =>
                        // idxPath は tree 上の親→子への複数 index (Container 経由で 2 段以上に
                        // なる場合あり)。acc は逆順なので reverse して prepend する
                        namesToIndicesRec(child, restNames, List.reverse(idxPath) ::: acc)
                }
        }

    /// root の子リスト ("children" 配列もしくは root 自身が配列) を走査して、
    /// 指定された name を持つ最初の子の (treeIndexPath, child) を返す。
    /// Container は scene tree 上のノードだが engine では透過なので、
    /// その内部 (layout 配下) も同名探索の対象に含める。Container 経由で見つかった
    /// ときの index path は [container_idx, inner_idx] のように 2 段になる
    def findChildIndexByName(root: Json.JsonElement, targetName: String):
            Option[(List[Int32], Json.JsonElement)] =
        let children = directChildrenOf(root);
        findIndexedNameMatch(children, targetName, 0i32)

    /// findChildIndexByName 用の「直接の子」列挙。
    /// - 透過 JsonObject (Container / Panel / HBox / VBox / Margin / Center) は
    ///   transparentInnerChildren で潜った実ノード列を返す
    /// - その他は "children" 配列、または root 自身が JsonArray の場合は配列要素
    def directChildrenOf(root: Json.JsonElement): List[Json.JsonElement] =
        match root {
            case Json.JsonElement.JsonObject(map) =>
                if (JsonOps.isTransparentJson(root))
                    JsonOps.transparentInnerChildren(map)
                else
                    match Map.get("children", map) {
                        case Some(Json.JsonElement.JsonArray(arr)) => Vector.toList(arr)
                        case _ => Nil
                    }
            case Json.JsonElement.JsonArray(arr) => Vector.toList(arr)
            case _ => Nil
        }

    def findIndexedNameMatch(items: List[Json.JsonElement], targetName: String, idx: Int32):
            Option[(List[Int32], Json.JsonElement)] =
        match items {
            case Nil => None
            case head :: rest =>
                // head が透過ノード (Container / Layout primitive) なら、その内側に
                // 対しても再帰的に同名探索。見つかれば idx を path に prepend
                if (JsonOps.isTransparentJson(head)) {
                    let innerItems = match head {
                        case Json.JsonElement.JsonObject(m) => JsonOps.transparentInnerChildren(m)
                        case _                              => Nil
                    };
                    match findIndexedNameMatch(innerItems, targetName, 0i32) {
                        case Some((innerPath, child)) => Some((idx :: innerPath, child))
                        case None                     =>
                            findIndexedNameMatch(rest, targetName, idx + 1i32)
                    }
                } else
                    match nameOf(head) {
                        case Some(name) =>
                            if (name == targetName) Some((idx :: Nil, head))
                            else findIndexedNameMatch(rest, targetName, idx + 1i32)
                        case None =>
                            findIndexedNameMatch(rest, targetName, idx + 1i32)
                    }
        }

    def nameOf(elem: Json.JsonElement): Option[String] =
        match elem {
            case Json.JsonElement.JsonObject(map) =>
                match Map.get("name", map) {
                    case Some(Json.JsonElement.JsonString(s)) => Some(s)
                    case _ => None
                }
            case _ => None
        }
}
