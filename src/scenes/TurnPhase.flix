/// TurnPhase — 味方ターン内の細分化フェーズと敵ターンを 1 つの enum で扱う effect
///
/// ターン制 SRPG の入力契約は単純な「敵ターン中か否か」だけでは表現できない。
/// 味方ターンには「カーソルでマスを選ぶ」「味方を動かす」「攻撃対象を選ぶ」の 3 段が
/// あり、Z / X / WASD のそれぞれが意味を変える。`EnemyTurn.Queue.isEmpty()` だけでは
/// 「味方ターン中のどのサブフェーズか」を区別できないため、専用のフェーズ effect を持つ。
///
/// 設計意図:
///   - 入力ハンドラ・各 Scene の `physicsProcess` がフェーズで分岐するための単一情報源
///   - フェーズ切替は **どの handler から put してもよい**（決定キー押下の InputHandler、
///     敵ターン終了処理など）。実体の更新は次フレーム冒頭で全 Scene が `get` で観測する
///   - `EnemyTurn.Queue` と二重管理になるが、Queue は「敵 step の駆動キュー」、Phase は
///     「入力 / 描画 / カメラの分岐用シグナル」と責務を分離する。Phase が EnemyTurn の
///     間は Queue 非空が成立する不変条件は、Game.flix が両方を同時に書き換えて維持する
///
/// 使い方:
///   - `Game.start` で `with TurnPhase.withState(rc)` を 1 行注入する
///   - 起動時の初期値は `PlayerCursor`（味方のターン・カーソル選択フェーズ）
///   - 決定キー：味方マスで Z → `PlayerMoving` / 移動中に Z → `PlayerAttack` /
///              攻撃中に Z（赤マス上の敵）→ ダメージ適用 + `EnemyTurn`
///   - キャンセルキー：移動中に X → `PlayerCursor` に戻す /
///                    攻撃中に X → 攻撃せず即 `EnemyTurn`（敵フェーズへスキップ）
///   - 敵ターン終了（`finishEnemyTurn`）→ `PlayerCursor` に戻す
mod TurnPhase {

    /// ゲーム全体の進行フェーズ。
    /// `PlayerCursor` がデフォルト = 味方ターン開始時の状態。
    pub enum Phase with Eq, ToString {
        /// 味方ターン・カーソル選択フェーズ。WASD/方向キーでカーソルを動かす。
        case PlayerCursor
        /// 味方ターン・選択した味方を動かしているフェーズ。WASD/方向キーで味方を動かす。
        case PlayerMoving
        /// 味方ターン・攻撃対象選択フェーズ。
        /// 味方の周囲（射程内）に赤マスが出て、カーソルは赤マス内のみ移動可。
        /// 赤マス上の敵に Z でダメージ → 敵ターンへ自動遷移、X で攻撃せず敵ターンへ。
        case PlayerAttack
        /// 敵ターン。入力は無効、カーソル非表示、カメラはプレイヤーに固定。
        case EnemyTurn
    }

    /// フェーズの読み書きを表す effect。
    /// 内部 `Ref` の存在は handler に隠蔽し、`Game.flix` 側からは effect op だけ見える。
    pub eff State {
        /// 現在のフェーズを返す。
        def get(): Phase
        /// 新しいフェーズを設定する。次フレーム以降で全 Scene が観測する。
        def put(target: Phase): Unit
    }

    /// `Tween.withScheduler` と同じ流儀の handler 注入。
    /// 内部 `phaseRef` は closure に閉じ込められ、外からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let phaseRef: Ref[Phase, r] = Ref.fresh(rc, Phase.PlayerCursor);
            run {
                thunk()
            } with handler State {
                def get(k) = k(Ref.get(phaseRef))
                def put(target, k) = {
                    Ref.put(target, phaseRef);
                    k()
                }
            }
        }
}
