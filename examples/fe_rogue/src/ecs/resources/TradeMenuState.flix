/// TradeMenuState — 物交換ウィンドウのセッション状態を保持する effect
///
/// `TradeMenuScene`（味方同士のアイテム交換画面）の Panel が持つセッション状態
/// （各ペインの player id・フォーカス・先に選んだスロット・出口・まとめ渡しの印）を持つ。
/// 各ペインの行カーソル（selectedIndex）は Godot 標準の `ItemList` ノード
/// （`NodeTag.TradeMenu(i)`）が自前で所有するのでここには持たない。
/// 見た目（左右のインベントリ列・ハイライト）は `TradeMenuScene` の view が描き、
/// この resource は選択セッション状態だけを持つ。
///
/// TurnPhase / SelectedPlayer / ItemMenuState と同じ Ref-based handler 注入パターンに揃える。
mod TradeMenuState {

    /// 状態の実体型は `TradeMenuScene.PanelData`（members/focus/pick/origin/marks/markPane）。
    pub eff State {
        def get(): TradeMenuScene.PanelData
        def put(target: TradeMenuScene.PanelData): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    /// 初期値はゼロ状態（members=Nil）。トレード突入時に `PhaseTransitions` が本物の members で put し直す。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref = Ref.fresh(rc, TradeMenuScene.defaultPanelData());
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
