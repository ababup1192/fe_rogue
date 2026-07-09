/// MinimapState — ミニマップの表示トグルを保持する effect
///
/// ミニマップ（探索済みマップ）は M キーで表示/非表示を切り替える。その表示状態と、押しっぱなしの
/// 連続発火を防ぐための前フレームキー状態だけをこの resource が持つ。探索の記憶（訪問済み module）は
/// World 権威（`World.visitedModulesOf`）が持ち、ここには含めない。見た目（部屋矩形・マーカー円）は
/// `RenderWorld.renderMinimap` が World / Map から直接描く。
///
/// `MinimapDriver.step` が M のエッジ検出で `visible` を反転して書き、`RenderWorld.renderMinimap` が
/// `visible` を読んで描画するかを決める。TurnPhase / SelectedPlayer と同じ Ref-based handler 注入に揃える。
mod MinimapState {

    /// ミニマップの表示トグル状態。
    /// `visible`: M で切り替える表示 ON/OFF（フロアをまたいでも維持される）。
    /// `mPrev`  : 前フレームの M 押下状態。押しっぱなしの連続反転を防ぐエッジ検出に使う。
    pub type alias Data = {
        visible = Bool,
        mPrev   = Bool
    }

    /// 初期状態（起動時から左下に表示・エッジ履歴なし）。
    pub def initial(): Data =
        {visible = true, mPrev = false}

    /// `withState` が提供する handler 1 つで読み書きする。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `minimapRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let minimapRef: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(minimapRef))
                def put(target, k) = {
                    Ref.put(target, minimapRef);
                    k()
                }
            }
        }
}
