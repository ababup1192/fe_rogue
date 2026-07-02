/// CharacterSelectState — 出撃メンバー選択画面の選択状態を保持する effect
///
/// `CharacterSelectScene`（起動直後のパーティ編成画面）が持つ選択状態
/// （注目カード・選択リスト・サブモード・リーダー候補・カルーセル横位置）をまとめて持つ。
/// 見た目（カード列・カウンタ・ボタン・説明）は `CharacterSelectScene` の view が
/// `writeVisuals` で描き、この resource は「いま誰を選んでいるか」等の状態だけを持つ。
///
/// `onKeyPressed` が押下ごとに読み書きし、`step` が毎フレーム carousel を寄せて書き戻す。
/// TurnPhase / SelectedPlayer / CursorState と同じ Ref-based handler 注入パターンに揃える。
mod CharacterSelectState {

    /// `withState` が提供する handler 1 つで処理する。状態の実体型は
    /// `CharacterSelectScene.Data`（表示候補・選択・サブモード等）。
    pub eff State {
        def get(): CharacterSelectScene.Data
        def put(target: CharacterSelectScene.Data): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    /// 初期値は候補ゼロの空状態。`CharacterSelectScene.add` が本物の候補一覧で put し直す。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref = Ref.fresh(rc, CharacterSelectScene.emptyState());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(ref))
                def put(target, k) = {
                    Ref.put(target, ref);
                    k()
                }
            }
        }
}
