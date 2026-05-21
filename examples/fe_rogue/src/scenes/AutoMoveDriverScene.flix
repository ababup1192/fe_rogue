/// AutoMoveDriverScene — PlayerAutoMove フェーズの駆動 (旗追跡の自動移動)
///
/// 空マスで Z 押下 → 旗が立つ → `PlayerAutoMove` フェーズ突入 → 全アクティブ味方が
/// 旗に向かって 1 マスずつ歩く。scene tree 上の専用タグノード (`NodeTag.AutoMoveDriver`) が
/// `process` redef で phase を見て、`PlayerAutoMove` 中なら `AutoMove.step` (純粋寄り) を呼ぶ。
///
/// 公開 API:
///   - `add(scene)`    — `GameLifecycle.buildPlayingScene` で scene tree に常駐ノードを追加
///   - `process(...)`  — `Node[NodeTag]` instance から per-frame で呼ばれる。phase 判定。
///   - `cancel(scene)` — X / Esc 押下時のキャンセル: 旗を消し、moveStepsTaken を全員 0 に
///     戻し、PlayerCursor に復帰してカーソルを再表示する
mod AutoMoveDriverScene {

    /// 常駐タグ専用ノードの NodePath。Marker2D を World 配下に置く。
    def driverName(): String = "AutoMoveDriver"
    pub def driverPath(): NodePath =
        MapScene.worldName() :: driverName() :: Nil

    /// scene tree に常駐ノードを追加する。`GameLifecycle.buildPlayingScene` で 1 回だけ呼ぶ。
    /// engine の `Scene.processAll` が preorder で各ノードを巡回するとき、この driver の
    /// `process` redef が phase 判定 + `AutoMove.step` を起動する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let marker = Marker2D.make(Vec2.zero());
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(marker, NodeTag.AutoMoveDriver), scene)

    /// per-frame entry。phase=PlayerAutoMove のときだけ `AutoMove.step` を呼ぶ。
    /// それ以外は no-op。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameLogger.GameLogger,
                        EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        let next = match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerAutoMove => AutoMove.step(scene)
            case _                               => scene
        };
        (node, next)

    /// PlayerAutoMove 中 X/Esc キャンセル: 旗を消し、moveStepsTaken を全員 0 に戻し、
    /// PlayerCursor に復帰してカーソルを再表示する。`waited` 状態はそのまま残す
    /// (AutoMove 途中まで動いたキャラは既に waited になっている可能性がある)。
    pub def cancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              TurnPhase.State, SelectedPlayer.State} =
        GameLogger.playerLog("自動移動を中止");
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> FlagScene.clear
            |> PlayerScene.resetAllMoveStepsTaken
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer
}
