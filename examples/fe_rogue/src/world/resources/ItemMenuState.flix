/// ItemMenuState — アイテム選択ウィンドウの選択状態を保持する effect
///
/// `ItemMenuUi`（`ItemSelect` / `ItemActionSelect` フェーズのインベントリ窓）が持つ
/// 「いま見ているカテゴリ index」と「一括操作の複数選択マーク」をまとめて持つ。
/// 行カーソル（selectedIndex）はリスト UI 側が持つのでここには持たない。
/// 見た目（行・アイコン・バッジ・ヒント）は `ItemMenuUi` の view が毎フレーム World の在庫から
/// 組み直して描き、この resource は選択状態だけを持つ。
///
/// TurnPhase / SelectedPlayer / CursorState と同じ Ref-based handler 注入パターンに揃える。
mod ItemMenuState {

    /// 選択状態の実体。`category` はカテゴリ index（0=武器…）、`marks` は一括捨て等の複数選択印。
    pub type alias Data = {category = Int32, marks = Set[PlayerData.ItemKind]}

    /// 初期値（武器カテゴリ・印なし）。窓を開くたび `ItemMenuUi` が明示的に put し直す。
    pub def initial(): Data = {category = 0, marks = Set#{}}

    /// `withState` が提供する handler 1 つで読み書きする。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `ref` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref = Ref.fresh(rc, initial());
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

    /// World の `itemMenu` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口として
    /// 受け取り、get/put とも World 経由で読み書きする（本番 `Game.start` 用。test は `withState`）。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            run {
                thunk()
            } with handler State {
                def get(k)         = k(World.itemMenuOf(Ref.get(worldRef)))
                def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetItemMenu(target), Ref.get(worldRef)), worldRef); k() }
            }
        }
}
