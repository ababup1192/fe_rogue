/// AutoMoveDriverScene — PlayerAutoMove フェーズの駆動 (旗追跡の自動移動)
///
/// 空マスで Z 押下 → 旗が立つ → `PlayerAutoMove` フェーズ突入 → 全アクティブ味方が
/// 旗に向かって 1 マスずつ歩く。1 step / 1 frame の駆動は `AutoMove.step` (純粋寄り)
/// が担い、この Scene は **キャンセル入口** と (Stage 7 以降) **process 経由の駆動** を持つ。
///
/// 公開 API:
///   - `cancel(scene)` — X / Esc 押下時のキャンセル: 旗を消し、moveStepsTaken を全員 0 に
///     戻し、PlayerCursor に復帰してカーソルを再表示する。
///     `waited` 状態はそのまま残す (途中まで動いた味方は既に waited の可能性がある)
///
/// Stage 7 で scene tree に専用ノード (`NodeTag.AutoMoveDriver`) を追加し、`process` redef
/// 経由で `AutoMove.step` を呼ぶ形に切り替える予定。現状は `GameManager.tickAutoMoveFrame`
/// が `AutoMove.step` を直接呼ぶ。
mod AutoMoveDriverScene {

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
