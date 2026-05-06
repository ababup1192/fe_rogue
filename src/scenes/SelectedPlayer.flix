/// SelectedPlayer — 操作中プレイヤー id を保持する effect
///
/// 3 人パーティ制では「いま誰を動かしているか」をフェーズと別に持つ必要がある。
/// PlayerCursor で Z を押した瞬間に `Some(id)` がセットされ、
/// PlayerMoving / PlayerAttack を抜けるとき（行動完了 or キャンセル）に `None` に戻す。
///
/// `Camera` / `MoveRangeScene` / `PlayerAttackRangeScene` / `CursorScene.snapToPlayer`
/// など複数のシーンが「いまの選択駒」を読みたいので、TurnPhase と同じ Ref-based
/// handler 注入パターンに揃える。
mod SelectedPlayer {

    /// 選択中プレイヤー id の読み書き effect。
    pub eff State {
        /// 選択 id を返す。未選択（PlayerCursor / EnemyTurn）なら None。
        def get(): Option[Int32]
        /// 選択 id を上書きする。`Some(id)` で選択開始 / `None` で解除。
        def put(target: Option[Int32]): Unit
    }

    /// `TurnPhase.withState` と同じ流儀の handler 注入。
    /// 内部 `selectedRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let selectedRef: Ref[Option[Int32], r] = Ref.fresh(rc, None);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(selectedRef))
                def put(target, k) = {
                    Ref.put(target, selectedRef);
                    k()
                }
            }
        }
}
