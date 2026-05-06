/// SelectedPlayer — 操作中プレイヤー id と「選択時の原点」を保持する effect
///
/// 3 人パーティ制では「いま誰を動かしているか」をフェーズと別に持つ必要がある。
/// PlayerCursor で Z を押した瞬間に `Some(id)` がセットされ、PlayerMoving / PlayerAttack
/// を抜けるとき（行動完了 or キャンセル）に `None` に戻す。
///
/// 加えて、PlayerMoving 中の **キャンセル戻し** に使う「選択時のグリッド位置」も
/// ここで管理する。Z 押下時の位置を `origin` として put しておき、X が押されたら
/// その位置にスナップで戻すことで「キャンセル → 再選択 → 移動 → キャンセル」の
/// 無限移動を防ぐ。
///
/// `Camera` / `MoveRangeScene` / `PlayerAttackRangeScene` / `CursorScene.snapToPlayer`
/// など複数のシーンが「いまの選択駒」を読みたいので、TurnPhase と同じ Ref-based
/// handler 注入パターンに揃える。
mod SelectedPlayer {

    /// 選択中プレイヤー id と「選択時の原点」の読み書き effect。
    pub eff State {
        /// 選択 id を返す。未選択（PlayerCursor / EnemyTurn 等）なら None。
        def get(): Option[Int32]
        /// 選択 id を上書きする。`Some(id)` で選択開始 / `None` で解除。
        def put(target: Option[Int32]): Unit
        /// 選択時のグリッド位置を返す。未選択なら None。
        def getOrigin(): Option[Vec2.Vec2i]
        /// 選択時のグリッド位置を上書きする。`Some(pos)` で記録 / `None` で解除。
        def putOrigin(target: Option[Vec2.Vec2i]): Unit
    }

    /// `TurnPhase.withState` と同じ流儀の handler 注入。
    /// 内部 `selectedRef` / `originRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let selectedRef: Ref[Option[Int32], r] = Ref.fresh(rc, None);
            let originRef:   Ref[Option[Vec2.Vec2i], r] = Ref.fresh(rc, None);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(selectedRef))
                def put(target, k) = {
                    Ref.put(target, selectedRef);
                    k()
                }
                def getOrigin(k) = k(Ref.get(originRef))
                def putOrigin(target, k) = {
                    Ref.put(target, originRef);
                    k()
                }
            }
        }
}
