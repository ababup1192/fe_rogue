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
    /// `drafts` は「この移動中に scene へ加えた可逆な副作用」のスタック（新しい順）。
    /// 移動開始で `MovedFrom`、拾得で `PickedUp` を積み、`cancelSelection` で先頭から
    /// 逆操作、行動確定（`cleared()`）や次の選択開始で破棄する（FE 移動の仮確定モデル）。
    pub type alias Selection = {
        id           = Option[Int32],
        drafts       = List[MoveDraft.DraftAction],
        gatherActive = Bool
    }

    /// 未選択を表す Selection（選択なし・ドラフト空・集合中でない）。
    /// 解除時に `put(cleared())` と書ける。行動確定後の解除では drafts の巻き戻しは不要で、
    /// このゼロ値で上書きするだけで済む。
    pub def cleared(): Selection = {id = None, drafts = Nil, gatherActive = false}

    /// `withState` が提供する handler 1 つで処理し、入れ子ハンドラは想定しない。
    pub eff State {
        /// 現在の選択状態を返す。未選択（PlayerCursor / EnemyTurn 等）なら
        /// `cleared()` 相当（id None・drafts 空）。
        def get(): Selection
        /// 選択状態を上書きする。`Some` で選択開始 / `cleared()` で解除。
        def put(target: Selection): Unit
    }

    /// 巻き戻しドラフトを 1 件スタック先頭へ積む（新しい順）。移動中の可逆操作
    /// （拾得 / 装備 / 捨てる / こうかん）を行った各所から呼ぶ。`cancelSelection` が
    /// この順に逆操作して巻き戻す。
    pub def pushDraft(action: MoveDraft.DraftAction): Unit \ State =
        let sel = State.get();
        State.put({drafts = action :: sel#drafts | sel})

    /// 内部 `selectionRef` は closure に閉じ込めることで外部から直接変更できない。
    /// 読み書きはすべて `State.get` / `State.put` 経由に強制されるため、
    /// `id` と `drafts` の整合性（常に同じ選択文脈に属する）を崩せない。
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
