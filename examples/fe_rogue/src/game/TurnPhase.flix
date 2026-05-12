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
        /// 味方ターン・攻撃で敵を倒した直後の演出ホールド。
        /// `attack_lunge` が完了し倒した敵が `death_blink` 中の間、カメラを瀕死の敵
        /// （= カーソル位置）に留めるための過渡状態。入力は受け付けない。
        /// `Pacing.State.hold` が抜けた瞬間に GameManager が `commitWaitedAndAdvance`
        /// を呼び、PlayerCursor または EnemyTurn に遷移する。
        case PlayerAttackHold
        /// 味方ターン・自動移動フェーズ。空マスに旗を立てた直後、全アクティブ味方が
        /// その旗に向かって 1 マスずつ自動で歩く。旗の周囲 2 マス以内に到達するか
        /// 敵に発見されると止まり、PlayerCursor に戻る（旗は自動で消える）。
        /// 入力は受け付けない。
        case PlayerAutoMove
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

/// TurnRules — 「フェーズ × 入力 × 盤面 → 次にどう遷移するか」の純粋ルール
///
/// 入力ハンドラから `decide(context)` を呼ぶと、その状況で起きる遷移を `Transition`
/// として返す。Game.flix 側はこれを match して、対応する Scene 操作 / effect handler
/// を起動する（実体の副作用は呼び出し側に閉じ込めて、ここは純粋に保つ）。
///
/// `Phase` enum と同居させているのは、両者が同じ「ターン進行」というデータ構造を
/// 中心にした処理だから（Phase 単独で別ファイルにすると分割しすぎる）。
mod TurnRules {

    /// プレイヤーが押した決定 / キャンセルのどちらか。
    /// 実際のキー（Z / X / Space / Enter）からの変換は呼び出し側が行う。
    pub enum Input with Eq, ToString {
        case Confirm
        case Cancel
    }

    /// 1 回の入力に対して起きる遷移。`Stay` は何もしないことを表す（無効入力など）。
    /// 各バリアントは Scene 操作 / effect handler 起動に必要な情報を全部抱える
    /// （apply 側で再ルックアップしないで済むように）。
    ///
    /// 位置は `{x = Int32, y = Int32}` ではなく `(x, y)` の Int32 ペアで持つ。
    /// （Vec2i は record alias で auto-derive Eq に対応していないため。）
    pub enum Transition with Eq, ToString {
        /// 何も起きない（入力無効・条件未成立）
        case Stay
        /// PlayerCursor 中、カーソル位置にアクティブ味方が居て選択した
        case CursorSelectPlayer(Int32)
        /// PlayerCursor 中、カーソルが空き床マスで旗を立てる（PlayerAutoMove へ向かう）
        /// 引数: (旗を立てるマスの x, y)
        case CursorPlantFlag(Int32, Int32)
        /// PlayerMoving 中の Confirm: 攻撃フェーズに移る
        case MovingEnterAttack
        /// PlayerMoving 中の Cancel: 選択駒を origin に戻して PlayerCursor へ
        case MovingCancel
        /// PlayerAttack 中の Confirm: 生きている敵に攻撃成立
        /// 引数: (attackerId, defenderId, defender の x, defender の y)
        case AttackHit(Int32, Int32, Int32, Int32)
        /// PlayerAttack 中の Cancel: 攻撃せず waited にして次のセレクトへ
        case AttackSkip
    }

    /// `decide` に渡すコンテキスト一式。Scene[NodeTag] / Tween / 各 effect から
    /// 「いま判断に必要な値」だけを抜き出した record。テストでは直接合成できる。
    ///
    /// フィールドの意味:
    ///   - `phase`: 現在のフェーズ（TurnPhase.State.get の値）
    ///   - `input`: 押されたキーの分類（Confirm / Cancel）
    ///   - `board`: 盤面スナップショット（BoardQuery.board の値）
    ///   - `cursor`: カーソルのグリッド位置（CursorScene.getGridPos の値）
    ///   - `selected`: 選択中味方 id（SelectedPlayer.State.get の値）
    ///   - `waitedPlayerIds`: 既に行動済みの味方 id（findActiveIdAt で除外する用）
    ///   - `dyingEnemyIds`: 死亡演出中の敵 id（findIdAt で除外する用）
    ///   - `playerBusy`: 選択中味方が Tween 中なら true（Confirm/Cancel のガードに使う）
    pub type alias Context = {
        phase           = TurnPhase.Phase,
        input           = Input,
        board           = Board,
        cursor          = {x = Int32, y = Int32},
        selected        = Option[Int32],
        waitedPlayerIds = List[Int32],
        dyingEnemyIds   = List[Int32],
        playerBusy      = Bool
    }

    /// フェーズ × 入力 × 盤面 → 遷移を決める。Scene/effect を一切触らない純粋関数。
    pub def decide(context: Context): Transition =
        match (context#phase, context#input) {
            case (TurnPhase.Phase.PlayerCursor, Input.Confirm) =>
                match activePlayerAt(context) {
                    case Some(playerId) => Transition.CursorSelectPlayer(playerId)
                    case None           =>
                        // アクティブ味方が居ない: 床マスで誰も占有していなければ旗を立てる。
                        // それ以外（壁・敵上・waited 味方上）は何もしない。
                        if (context#board#map#isFloor(context#cursor)
                            and not Board.isOccupied(context#cursor, context#board))
                            Transition.CursorPlantFlag(context#cursor#x, context#cursor#y)
                        else Transition.Stay
                }
            case (TurnPhase.Phase.PlayerMoving, Input.Confirm) =>
                if (context#playerBusy) Transition.Stay
                else Transition.MovingEnterAttack
            case (TurnPhase.Phase.PlayerMoving, Input.Cancel) =>
                if (context#playerBusy) Transition.Stay
                else Transition.MovingCancel
            case (TurnPhase.Phase.PlayerAttack, Input.Confirm) =>
                // 生きている敵が cursor に居て、かつ選択中駒があれば攻撃成立
                match (aliveEnemyAt(context), context#selected) {
                    case (Some(defenderId), Some(attackerId)) =>
                        Transition.AttackHit(attackerId, defenderId,
                            context#cursor#x, context#cursor#y)
                    case _ => Transition.Stay
                }
            case (TurnPhase.Phase.PlayerAttack, Input.Cancel) =>
                Transition.AttackSkip
            // EnemyTurn / PlayerAutoMove は入力無視（自動進行で抜ける）
            case _ => Transition.Stay
        }

    /// cursor 位置にアクティブ（waited でない）な味方の id を返す。居なければ None。
    /// PlayerScene.findActiveIdAt の純粋版（Board と waitedPlayerIds から復元）。
    def activePlayerAt(context: Context): Option[Int32] =
        Board.playerPositions(context#board)
            |> List.findMap(entry -> {
                let (playerId, position) = entry;
                if (samePosition(position, context#cursor)
                    and not isInList(playerId, context#waitedPlayerIds))
                    Some(playerId)
                else None
            })

    /// cursor 位置に「生きている」敵の id を返す。居なければ None。
    /// EnemyScene.findIdAt の純粋版（Board と dyingEnemyIds から復元）。
    def aliveEnemyAt(context: Context): Option[Int32] =
        Board.enemyPositions(context#board)
            |> List.findMap(entry -> {
                let (enemyId, position) = entry;
                if (samePosition(position, context#cursor)
                    and not isInList(enemyId, context#dyingEnemyIds))
                    Some(enemyId)
                else None
            })

    def samePosition(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        a#x == b#x and a#y == b#y

    def isInList(target: Int32, list: List[Int32]): Bool =
        List.exists(value -> value == target, list)
}
