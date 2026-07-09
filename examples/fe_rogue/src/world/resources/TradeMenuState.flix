/// TradeMenuState — 物交換ウィンドウのセッション状態を保持する effect
///
/// `TradeMenuUi`（味方同士のアイテム交換画面）の持つセッション状態
/// （各ペインの player id・フォーカス・先に選んだスロット・出口・まとめ渡しの印）を持つ。
/// 各ペインの行カーソルは World-entity UI の selection（名前パスキー）が持つのでここには持たない。
/// 見た目（各ペインのインベントリ列・ハイライト）は `TradeMenuUi` の view が描き、
/// この resource は選択セッション状態だけを持つ。
///
/// TurnPhase / SelectedPlayer / ItemMenuState と同じ Ref-based handler 注入パターンに揃える。
mod TradeMenuState {

    /// 状態の実体型は `TradeMenuUi.PanelData`（members/focus/pick/origin/marks/markPane）。
    pub eff State {
        def get(): TradeMenuUi.PanelData
        def put(target: TradeMenuUi.PanelData): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    /// 初期値はゼロ状態（members=Nil）。トレード突入時に `PhaseTransitions` が本物の members で put し直す。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref = Ref.fresh(rc, TradeMenuUi.defaultPanelData());
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
