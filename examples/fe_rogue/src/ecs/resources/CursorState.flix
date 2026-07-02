/// CursorState — 選択カーソルの論理状態を保持する effect
///
/// 味方ターンの選択カーソル（`CursorScene` の Marker2D + 四隅 L字）が指す論理マスと、
/// 移動加速・敵ホバー検出のための入力状態をまとめて持つ。見た目（Marker2D の位置・L字）は
/// `CursorScene` の view が描き、この resource は「どのセルを指しているか」等の状態だけを持つ。
///
/// `CursorScene.physicsProcess` の各フェーズ stepper が読み書きし、`getGridPos` を通じて
/// UnitCard / EnemyCard / BattlePanel / WeaponSelect / ItemMenu などが現在の指しセルを読む。
/// TurnPhase / SelectedPlayer と同じ Ref-based handler 注入パターンに揃える。
mod CursorState {

    /// カーソル固有の状態。
    /// `gridPos`: カーソルが指している論理マス。moveStep で即更新される。
    /// `lastHoveredEnemyId`: 直前フレームでカーソルが乗っていた敵 id。
    ///   None ↔ Some(id) や Some(a) ↔ Some(b) の遷移をログ・赤レンジ再構築のトリガーに使う。
    /// `holdDir`: 直前フレームに方向キーが押されていた向き。同方向継続の判定と加速リセットに使う。
    /// `holdSteps`: 同方向に連続で進んだマス数。`computeSlideDuration` で 1 マス分のスライド時間を
    ///   初速 → 最高速に補間するのに使う。
    pub type alias Data = {
        gridPos            = {x = Int32, y = Int32},
        lastHoveredEnemyId = Option[Int32],
        holdDir            = Option[{x = Int32, y = Int32}],
        holdSteps          = Int32
    }

    /// 初期状態（原点・ホバーなし・hold なし）。`add` の初期セルは `CursorScene` が put で上書きする。
    pub def initial(): Data =
        {gridPos = {x = 0, y = 0}, lastHoveredEnemyId = None, holdDir = None, holdSteps = 0}

    /// `withState` が提供する handler 1 つで処理する。
    pub eff State {
        def get(): Data
        def put(target: Data): Unit
    }

    /// 内部 `cursorRef` は closure に閉じ込め、読み書きを `State.get` / `State.put` 経由に強制する。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let cursorRef: Ref[Data, r] = Ref.fresh(rc, initial());
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(cursorRef))
                def put(target, k) = {
                    Ref.put(target, cursorRef);
                    k()
                }
            }
        }
}
