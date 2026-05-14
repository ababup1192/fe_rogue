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
    /// 実際の JTree のハイライト更新は view 層 (SceneTreeView) の責任で、本関数は
    /// Ref 同期だけを担う
    pub def syncEditorSelectionToTree(state: IdeState.IdeState):
            Unit \ {IO, Editor.EditorState} =
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
        if (editorIndices == storedIndices) ()
        else
            Array.put(editorIndices, 0, state#selectedNodePathRef)

    /// ノード名のリスト (engine NodePath 相当) を、現 JSON ツリー上の子インデックス列に
    /// 変換する。各ステップで現ノードの children を走査し、name が一致する子を探す。
    /// 途中で見つからなければ None
    def namesToIndices(root: Json.JsonElement, names: List[String]): Option[List[Int32]] =
        namesToIndicesRec(root, names, Nil)

    def namesToIndicesRec(root: Json.JsonElement, names: List[String],
                          acc: List[Int32]): Option[List[Int32]] =
        match names {
            case Nil => Some(List.reverse(acc))
            case headName :: restNames =>
                match findChildIndexByName(root, headName) {
                    case None => None
                    case Some((idx, child)) =>
                        namesToIndicesRec(child, restNames, idx :: acc)
                }
        }

    /// root の子リスト ("children" 配列もしくは root 自身が配列) を走査して、
    /// 指定された name を持つ最初の子の (index, child) を返す。見つからなければ None
    def findChildIndexByName(root: Json.JsonElement, targetName: String):
            Option[(Int32, Json.JsonElement)] =
        let children = match root {
            case Json.JsonElement.JsonObject(map) =>
                match Map.get("children", map) {
                    case Some(Json.JsonElement.JsonArray(arr)) => Vector.toList(arr)
                    case _ => Nil
                }
            case Json.JsonElement.JsonArray(arr) => Vector.toList(arr)
            case _ => Nil
        };
        findIndexedNameMatch(children, targetName, 0i32)

    def findIndexedNameMatch(items: List[Json.JsonElement], targetName: String, idx: Int32):
            Option[(Int32, Json.JsonElement)] =
        match items {
            case Nil => None
            case head :: rest =>
                match nameOf(head) {
                    case Some(name) =>
                        if (name == targetName) Some((idx, head))
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
