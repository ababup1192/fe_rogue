/// SelectedPlayer — 操作中プレイヤー id と「選択時の原点」を保持する effect
///
/// 3 人パーティ制では「いま誰を動かしているか」をフェーズと別に持つ必要がある。
/// PlayerCursor で Z を押した瞬間に `Some(id)` がセットされ、PlayerMoving / PlayerAttack
/// を抜けるとき（行動完了 or キャンセル）に `None` に戻す。
///
/// 加えて、PlayerMoving 中の **キャンセル戻し** に使う「選択時のグリッド位置」も
/// ここで管理する。Z 押下時の位置を `origin` として記録しておき、X が押されたら
/// その位置にスナップで戻すことで「キャンセル → 再選択 → 移動 → キャンセル」の
/// 無限移動を防ぐ。
///
/// `id` と `origin` は常に同じタイミングで書き換えられる（選択開始で両方 Some、
/// 解除・確定で両方 None）。そのため 1 つの record `Selection` にまとめて、
/// `get` / `put` のペアだけで読み書きする。
///
/// `Camera` / `MoveRangeScene` / `PlayerAttackRangeScene` / `CursorScene.snapToPlayer`
/// など複数のシーンが「いまの選択駒」を読みたいので、TurnPhase と同じ Ref-based
/// handler 注入パターンに揃える。
mod SelectedPlayer {

    /// 選択中プレイヤーの状態。`id` と `origin` は常に揃って Some / None を取る。
    pub type alias Selection = {
        id     = Option[Int32],
        origin = Option[Vec2.Vec2i]
    }

    /// 未選択を表す Selection（id・origin ともに None）。
    /// 解除時に `put(cleared())` と書ける。
    pub def cleared(): Selection = {id = None, origin = None}

    /// 選択状態の読み書き effect。
    pub eff State {
        /// 現在の選択状態を返す。未選択（PlayerCursor / EnemyTurn 等）なら
        /// `cleared()` 相当（id・origin ともに None）。
        def get(): Selection
        /// 選択状態を上書きする。`Some/Some` で選択開始 / `cleared()` で解除。
        def put(target: Selection): Unit
    }

    /// `TurnPhase.withState` と同じ流儀の handler 注入。
    /// 内部 `selectionRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let selectionRef: Ref[Selection, r] = Ref.fresh(rc, cleared());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(selectionRef))
                def put(target, k) = {
                    Ref.put(target, selectionRef);
                    k()
                }
            }
        }
}
