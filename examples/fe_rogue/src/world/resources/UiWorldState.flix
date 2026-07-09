// UiWorldState — UI 状態（UiStore.UiWorld）を保持する effect resource
//
// CursorState / SelectedPlayer と同じ Ref-based handler 注入パターン。
// gameLoop から 1 つの handler で get/put し、bindingSystem や UiExtract のパイプラインへ渡す。
// World enum には入れない（テイスティング判断。採用後に World 統合を再検討）。

mod UiWorldState {

    /// `withState` が提供する handler 1 つで UI 状態を読み書きする。
    pub eff State {
        def get(): UiStore.UiWorld
        def put(ui: UiStore.UiWorld): Unit
    }

    /// 内部 `uiRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    /// 初期値は空の UiWorld。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let uiRef: Ref[UiStore.UiWorld, r] = Ref.fresh(rc, UiStore.empty());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(uiRef))
                def put(ui, k) = {
                    Ref.put(ui, uiRef);
                    k()
                }
            }
        }

    /// World の `uiWorld` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として
    /// 受け取り、get/put とも World 経由で読み書きする（本番 `Game.start` 用。test は `withState`）。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k)     = k(World.uiWorldOf(Ref.get(worldRef)))
                def put(ui, k) = { Ref.put(World.applyCmd(World.Cmd.SetUiWorld(ui), Ref.get(worldRef)), worldRef); k() }
            }
        }
}
