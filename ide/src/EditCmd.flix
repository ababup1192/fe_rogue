// EditCmd — 統一 Edit Command 層（拡張性リファクタ Phase B）
//
// 各「編集の確定」を **データとしての命令**で表す。命令は
//   - applyTo: live scene を変異し JSON へ書き戻す（前方適用＝undo の実体にも使う）
//   - inverseOf: 適用前の現在状態を捕捉した逆命令（undo 用。将来 redo で対称に使う）
// を持つ。これにより「変異＋JSON書込」を1経路へ集約し、Move/Resize/… の各所で再発明していた
// パターンを置き換える土台になる。
//
// 依存方向：EditCmd → Scene / SceneSerializer / Node2D（下向き）。EditHistory.Entry が
// `CommandEntry(EditCmd.Command)` でこれを内包し、Editor.applyUndo が applyTo で適用する。
mod EditCmd {

    /// 1 編集を表す命令。順次拡張する。
    pub enum Command {
        /// ノードのグローバル位置を pos に設定する（live + JSON）。
        case SetGlobalPos({jsonPath = String, nodePath = NodePath,
                           jsonNodePath = NodePath, pos = Vec2.Vec2})
        /// ノードの回転(rad)を設定する。
        case SetRotation({jsonPath = String, nodePath = NodePath,
                          jsonNodePath = NodePath, rotation = Float64})
        /// 1〜複数ノードを snapshot の状態へ戻す（リサイズ）。snapshot が目標状態。
        case Resize({jsonPath = String,
                     snapshots = List[EditableNode.NodeResizeSnapshot]})
    }

    /// 適用前の「現在状態」を捕捉した逆命令を返す（undo/redo 用）。
    pub def inverseOf(cmd: Command, scene: Scene[t]): Command =
        match cmd {
            case Command.SetGlobalPos(c) =>
                let cur = Scene.globalPositionAt(c#nodePath, scene);
                Command.SetGlobalPos({pos = cur | c})
            case Command.SetRotation(c) =>
                let cur = match Scene.getEngineNode(c#nodePath, scene) {
                    case Some(en) => Node2D.getRotation(en)
                    case None     => c#rotation
                };
                Command.SetRotation({rotation = cur | c})
            case Command.Resize(c) =>
                // 現在状態を snapshot し直して逆命令にする
                let curSnaps = List.filterMap(snap ->
                    match Scene.getEngineNode(snap#nodePath, scene) {
                        case Some(en) => Some(EditableNode.snapshotForResize(snap#nodePath, en))
                        case None     => None
                    }, c#snapshots);
                Command.Resize({snapshots = curSnaps | c})
        }

    /// 命令を「live 変異」と「永続化」に分離して合成する（applyTo = applyLive →(その scene を)persist）。
    /// この分離が重要：将来の構造命令（delete/duplicate）は live を直接変異せず JSON 書込＋reload で
    /// 反映する。その種別は applyLive=恒等／persist=insertSubtree 等、と実装できる（live+Fs 密結合を回避）。
    pub def applyTo(cmd: Command, scene: Scene[t]):
            Scene[t] \ {Fs.FileRead, Fs.FileWrite} =
        let moved = applyLive(cmd, scene);
        persist(cmd, moved);
        moved

    /// live scene だけ変異する（JSON は書かない）。テスト/プレビュー兼、applyTo の前半。
    /// local 位置は丸める（前方書込/ドラッグ/nudge と同じ整数化。undo 経路も同様に丸めるため
    /// 旧 MoveEntry undo〔丸めなし〕と厳密一致はしないが、差が出るのは「親が小数 global の入れ子
    /// ノード」のみで、丸める方が全経路と整合し正しい。意図的収束）。
    pub def applyLive(cmd: Command, scene: Scene[t]): Scene[t] =
        match cmd {
            case Command.SetGlobalPos(c) =>
                scene
                    |> Scene.setGlobalPositionAt(c#nodePath, c#pos)
                    |> Scene.mapEngineNode(c#nodePath, engineNode ->
                        Node2D.setPosition(Vec2.round(Node2D.getPosition(engineNode)), engineNode))
            case Command.SetRotation(c) =>
                Scene.mapEngineNode(c#nodePath, Node2D.setRotation(c#rotation), scene)
            case Command.Resize(c) =>
                List.foldLeft((acc, snap) ->
                    Scene.mapEngineNode(snap#nodePath,
                        n -> EditableNode.restoreFromSnapshot(snap, n), acc),
                    scene, c#snapshots)
        }

    /// 命令の結果を JSON へ書き戻す（scene は applyLive 済みの状態を渡す）。
    /// 構造命令はここを insertSubtree/removeChild 等で実装する（live は触らない）。
    pub def persist(cmd: Command, scene: Scene[t]): Unit \ {Fs.FileRead, Fs.FileWrite} =
        match cmd {
            case Command.SetGlobalPos(c) =>
                let localPos = match Scene.getEngineNode(c#nodePath, scene) {
                    case Some(engineNode) => Node2D.getPosition(engineNode)
                    case None             => Vec2.zero()
                };
                SceneSerializer.updatePos(c#jsonPath, c#jsonNodePath, localPos)
            case Command.SetRotation(c) =>
                SceneSerializer.updateRotation(c#jsonPath, c#jsonNodePath, c#rotation)
            case Command.Resize(c) =>
                let nodeUpdates = List.map(snap -> ({
                    nodePath = EditableNode.toJsonNodePath(snap#nodePath, scene),
                    updates = EditableNode.snapshotToFieldUpdates(snap)
                }: SceneSerializer.NodeUpdate), c#snapshots);
                SceneSerializer.updateMany(c#jsonPath, nodeUpdates)
        }
}
