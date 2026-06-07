/// EnemyAI — 敵 1 体の sense（検知）と「どの相手を・どう攻めるか」を決める純粋ロジック
///
/// 1 体ごとに `decideAction(board, enemy, targets) -> (EnemyAction, Data)` を呼んで
/// 「次のターンに取る行動」と「Data の更新（alerted フラグ等）」を返す。
/// scene の更新（Marker2D 移動・Tween 開始・ログ出力）は呼び出し側が責務を持つ。
///
/// **ターゲット選択 = 優先度つき評価軸の辞書式比較**:
///   「性質」を `Criterion`（enum）でデータ化し、`priorities()` に優先度順で並べる。
///   候補（`targets`）をその並びで辞書式比較（先頭の基準で差がつけば決定、同点なら次の基準…）
///   して、engage する 1 体を選ぶ。性質を足したいときは `priorities()` に 1 行足すだけ。
///   現状の優先順位: 仕留め(Killable) > 反撃不能(NoCounter, 遠隔のみ) > 低HP(LowHp) > 近さ(Near)。
///
/// **2 段階で行動を決める**（攻撃できるなら必ず攻撃する）:
///   - フェーズ1: 今ターン攻撃できる相手（武器射程内）が居れば、その中の最良を `Attack`。
///     → 射程内に相手が居るのに遠くの弱い相手を追って攻撃を見送る／待機するのを防ぐ。
///   - フェーズ2: 射程内に誰も居なければ、全候補から最良を選び `chase`/`retreat` で寄る:
///       最小射程より近い（弓に踏み込まれた）→ `retreat`（カイティング）/ 遠い → `chaseTo`。
///
/// **1 step / 1 frame 実装**: `decideAction` は「次の 1 マス」だけを返す。複数マス分の
/// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ取り出して処理する。
/// 各 step で再評価されるため「接近 → 射程に入った step で Attack」が自然に成立する。
///
/// **BFS の障害物**: 壁 + 他敵駒。プレイヤー駒は障害にしない（追跡先なので）。
mod EnemyAI {

    use Weapon.manhattan

    /// 敵 1 体の 1 ターンぶんの行動。
    /// `Move` の {x, y} は 1 マス分の移動先（隣接セル）。
    /// `Attack` は (enemyId, targetPlayerId)。
    pub enum EnemyAction {
        case Move(Int32, {x = Int32, y = Int32})
        case Attack(Int32, Int32)
        case Wait(Int32)
        case Skip(Int32)
    }

    /// ターゲット 1 名ぶんの評価材料（呼び出し元が scene から組む純粋値）。
    /// `estDamage` = この敵 → 相手の推定与ダメ（命中前提・RNG なし）。
    /// `counterRange` = 相手の装備武器射程。`None` は武器なし＝反撃不能。
    pub type alias TargetInfo = {
        id           = Int32,
        pos          = {x = Int32, y = Int32},
        hp           = Int32,
        estDamage    = Int32,
        counterRange = Option[{min = Int32, max = Int32}]
    }

    /// ターゲット評価軸（性質）。`priorities()` に優先度順で並べる。
    ///   - `Killable`  : 今ターン仕留められるか（`estDamage >= hp`）
    ///   - `NoCounter` : 自分の攻撃距離で反撃されない相手か（全敵共通。近接は距離1で弓兵を優先）
    ///   - `LowHp`     : HP が低いほど良い
    ///   - `Near`      : 近いほど良い
    pub enum Criterion with Eq, ToString {
        case Killable
        case NoCounter
        case LowHp
        case Near
    }

    /// 評価に使う敵側の文脈（位置と武器の最大射程）。
    type alias Ctx = {pos = {x = Int32, y = Int32}, weaponMax = Int32}

    // ════════════════════════════════════════════════════════
    // 公開: 1 体ぶんの decision
    // ════════════════════════════════════════════════════════

    /// 敵 1 体の sense + ターゲット選択 + 行動を決定する。返り値の Data は alerted 更新済み。
    /// `targets` は盤面に居る（hidden でない）プレイヤーの評価材料。
    pub def decideAction(board: Board, enemy: EnemyScene.Data,
                          targets: List[TargetInfo]): (EnemyAction, EnemyScene.Data) =
        // 検知: dormant なら「同じ部屋」または「索敵範囲（移動到達範囲）にプレイヤー」で起動。
        let alertedNow = enemy#alerted
                         or sameModuleAsAnyPlayer(board, enemy#gridPos)
                         or anyPlayerWithinReach(board, enemy#gridPos, enemy#moveTiles);
        let updated = {alerted = alertedNow | enemy};
        if (not alertedNow) (EnemyAction.Skip(enemy#id), updated)
        else
            let ctx = ({pos = enemy#gridPos, weaponMax = weaponMaxOf(enemy)}: Ctx);
            // フェーズ1: 今ターン攻撃できる相手（武器射程内）の最良。攻撃を優先することで
            //   「射程内に相手が居るのに遠くの弱い相手を追って攻撃を見送る」のを防ぐ。
            // フェーズ2: 射程内に居なければ全候補の最良へ接近 or カイティング。
            // 2 つの選択結果をタプルで一度に見て分岐する（ネストを浅く保つ）。
            let attackTarget = pickTarget(ctx, attackableTargets(enemy, targets));
            let engageTarget = pickTarget(ctx, targets);
            match (attackTarget, engageTarget) {
                case (Some(t), _)    => (EnemyAction.Attack(enemy#id, t#id), updated)
                case (None, Some(t)) => moveTowardOrKite(board, enemy, updated, t)
                case (None, None)    => chase(board, enemy, updated)   // 候補なし → 最寄り追跡
            }

    /// 今ターン攻撃できる（武器射程 min..max 内の）相手だけを残す。武器なしは空。
    def attackableTargets(enemy: EnemyScene.Data,
                           targets: List[TargetInfo]): List[TargetInfo] =
        enemy#weapon
            |> Option.map(w -> List.filter(t ->
                let d = manhattan(enemy#gridPos, t#pos);
                d >= w#range#min and d <= w#range#max, targets))
            |> Option.getWithDefault(Nil)

    /// 射程内に相手が居ないときの移動。選んだ相手が（弓の最小射程より）近すぎれば後退
    /// （カイティング）、それ以外はその相手へ最短経路で 1 歩接近する。
    def moveTowardOrKite(board: Board, enemy: EnemyScene.Data, updated: EnemyScene.Data,
                          t: TargetInfo): (EnemyAction, EnemyScene.Data) =
        let tooClose = enemy#weapon
            |> Option.map(w -> manhattan(enemy#gridPos, t#pos) < w#range#min)
            |> Option.getWithDefault(false);
        if (tooClose) retreat(board, enemy, updated)
        else approachOrFallback(board, enemy, updated, t#pos)

    /// 選んだ相手 `targetCell` へ接近する。発見したら止まらず近づくため、3 段階で粘る:
    ///   1) 選んだ相手へ到達経路があれば、その相手へ 1 歩。
    ///   2) 無ければ最寄りプレイヤーへ。到達経路があればそこへ 1 歩。
    ///   3) それも無い（通路を別ユニットが塞ぐ等で誰にも届かない）→ 行ける範囲で最寄り
    ///      プレイヤーに一番近づけるマスへ 1 歩（通路口の手前まで詰める）。
    def approachOrFallback(board: Board, enemy: EnemyScene.Data, updated: EnemyScene.Data,
                            targetCell: {x = Int32, y = Int32}): (EnemyAction, EnemyScene.Data) =
        // 「Move が出たらそれを採用、ダメなら次の手段」を orElseMove で段階的に試す（ネストを浅く）。
        orElseMove(chaseTo(board, enemy, targetCell, updated), () ->
            approachNearest(board, enemy, updated))

    /// 最寄りプレイヤーへ接近。到達経路があればそこへ、無ければ「行ける範囲で一番近づけるマス」へ。
    def approachNearest(board: Board, enemy: EnemyScene.Data,
                         updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        match Board.nearestPlayer(enemy#gridPos, board) {
            case None          => (EnemyAction.Wait(enemy#id), updated)
            case Some(nearest) =>
                let (_, np) = nearest;
                orElseMove(chaseTo(board, enemy, np, updated), () ->
                    stepClosestTo(board, enemy, updated, np))
        }

    /// `primary` が Move ならそれを、そうでなければ代替 `alt` を評価して返す。
    /// 接近フォールバックの「ダメなら次」を入れ子 match なしで連結するための高階ヘルパー。
    def orElseMove(primary: (EnemyAction, EnemyScene.Data),
                    alt: Unit -> (EnemyAction, EnemyScene.Data)):
            (EnemyAction, EnemyScene.Data) =
        match primary {
            case (EnemyAction.Move(id, step), u) => (EnemyAction.Move(id, step), u)
            case _                               => alt()
        }

    /// `target` への到達経路が無いとき、到達可能なマスのうち `target` に最も近いマスへ向けて
    /// 1 歩進む。現在地より近づけるマスが無ければ Wait。通路が塞がれていても「行けるところまで
    /// 寄る」ことで、発見した敵が遠くで止まらないようにする。
    def stepClosestTo(board: Board, enemy: EnemyScene.Data, updated: EnemyScene.Data,
                       target: {x = Int32, y = Int32}): (EnemyAction, EnemyScene.Data) =
        let pos     = enemy#gridPos;
        let curDist = manhattan(pos, target);
        let passable = c ->
            Board.isWalkable(board, c)
                and ((c#x == pos#x and c#y == pos#y) or not Board.isOccupied(c, board));
        Board.reachableCells(passable, pos, approachReach())
            |> List.filter(c -> manhattan(c, target) < curDist)
            |> List.minimumBy((a, b) ->
                Order.compare(manhattan(a, target), manhattan(b, target)))
            |> Option.map(c -> stepTo(board, enemy, c, updated))
            |> Option.getWithDefault((EnemyAction.Wait(enemy#id), updated))

    /// 空きマス `cell` へ最短経路で 1 歩進む（`cell` 自体に乗る）。`chaseTo` と違い末尾を
    /// 落とさないので、プレイヤーではなく「行きたい空きマス」へ向かうのに使う。
    def stepTo(board: Board, enemy: EnemyScene.Data, cell: {x = Int32, y = Int32},
                updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        Board.bfsPath(board, enemy#gridPos, cell)
            |> Option.flatMap(List.head)
            |> moveOrWait(enemy, updated)

    /// `stepClosestTo` の到達範囲上限（マップ全域を見渡せるよう十分大きく取る）。
    def approachReach(): Int32 = 64

    /// 進む先 `stepOpt` があれば Move、無ければ Wait（経路探索系の共通の締め）。
    def moveOrWait(enemy: EnemyScene.Data, updated: EnemyScene.Data,
                    stepOpt: Option[{x = Int32, y = Int32}]): (EnemyAction, EnemyScene.Data) =
        match stepOpt {
            case Some(step) => (EnemyAction.Move(enemy#id, step), updated)
            case None       => (EnemyAction.Wait(enemy#id), updated)
        }

    // ════════════════════════════════════════════════════════
    // ターゲット選択（優先度つき評価軸の辞書式比較）
    // ════════════════════════════════════════════════════════

    /// 賢さの定義＝この並び（先頭が最優先）。性質追加はここに 1 行足すだけ。
    pub def priorities(): List[Criterion] =
        Criterion.Killable :: Criterion.NoCounter :: Criterion.LowHp :: Criterion.Near :: Nil

    /// 1 軸の「良さ」を素の整数で返す（大きいほど良い）。
    /// 重み調整は不要（辞書式なので `priorities()` の順序だけで優先が決まる）。
    pub def rank(c: Criterion, ctx: Ctx, t: TargetInfo): Int32 = match c {
        case Criterion.Killable  => if (t#estDamage >= t#hp) 1 else 0
        case Criterion.NoCounter =>
            // 自分の攻撃距離（武器の最大射程）で相手が反撃できないなら優先（全敵共通）。
            // 近接(距離1)なら弓兵(射程2)は反撃できないので、近接敵も弓兵を優先して狙う。
            if (not canCounterAt(t#counterRange, ctx#weaponMax)) 1 else 0
        case Criterion.LowHp     => 0 - t#hp                       // HP が低いほど大
        case Criterion.Near      => 0 - manhattan(ctx#pos, t#pos)  // 近いほど大
    }

    /// `priorities()` の順に各軸を点数化したキー（辞書式比較に使う）。
    pub def keyOf(ctx: Ctx, t: TargetInfo): List[Int32] =
        List.map(c -> rank(c, ctx, t), priorities())

    /// 同じ長さの点数キーを辞書式（先頭が最優先）に比較し、`xs` が `ys` より良ければ true。
    /// 先頭の軸で差がつけばそれで決定、同点なら次の軸へ。
    pub def lexGreater(xs: List[Int32], ys: List[Int32]): Bool = match (xs, ys) {
        case (x :: xt, y :: yt) => if (x != y) x > y else lexGreater(xt, yt)
        case _                  => false
    }

    /// `targets` から辞書式で最良の 1 体を選ぶ（argmax）。候補が空なら None。
    pub def pickTarget(ctx: Ctx, targets: List[TargetInfo]): Option[TargetInfo] =
        List.foldLeft((best, t) -> match best {
            case None    => Some(t)
            case Some(b) => if (lexGreater(keyOf(ctx, t), keyOf(ctx, b))) Some(t) else best
        }, None, targets)

    /// 相手が距離 `d` で反撃できるか。`None`（武器なし）は反撃不能。
    pub def canCounterAt(range: Option[{min = Int32, max = Int32}], d: Int32): Bool =
        Option.exists(r -> d >= r#min and d <= r#max, range)

    /// 敵の装備武器の最大射程（武器なしは 0）。
    def weaponMaxOf(enemy: EnemyScene.Data): Int32 =
        enemy#weapon |> Option.map(w -> w#range#max) |> Option.getWithDefault(0)

    // ════════════════════════════════════════════════════════
    // 移動（接近・後退）
    // ════════════════════════════════════════════════════════

    /// 最寄りプレイヤーへ接近する（ターゲット未選択時のフォールバック）。プレイヤー不在なら Skip。
    def chase(board: Board, enemy: EnemyScene.Data,
              updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        match Board.nearestPlayer(enemy#gridPos, board) {
            case None              => (EnemyAction.Skip(enemy#id), updated)
            case Some(targetEntry) =>
                let (_, target) = targetEntry;
                chaseTo(board, enemy, target, updated)
        }

    /// 指定セル `targetCell`（プレイヤー想定）への最短経路の 1 歩目を返す。末尾（相手セル）は
    /// 落として隣で止まる。経路無し（壁・他駒で詰み）なら Wait。
    def chaseTo(board: Board, enemy: EnemyScene.Data,
                 targetCell: {x = Int32, y = Int32},
                 updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        Board.bfsPath(board, enemy#gridPos, targetCell)
            |> Option.flatMap(path -> List.init(path) |> Option.flatMap(List.head))
            |> moveOrWait(enemy, updated)

    /// 最小射程より近づかれた弓系の敵が、隣接 1 マスへ後退して間合いを取り直す（カイティング）。
    /// 4 近傍のうち「床 + 駒に占有されていない」マスから、最寄りプレイヤーとの距離を最も
    /// 広げられるマスを選ぶ。距離を広げられるマスが無い（壁際・包囲）なら chase に委譲（= Wait）。
    def retreat(board: Board, enemy: EnemyScene.Data,
                updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        let pos     = enemy#gridPos;
        let curDist = distToNearestPlayer(pos, board);
        let dirs    = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
        let best    = dirs
            |> List.map(d -> Board.stepTarget(pos, d))
            |> List.filter(c -> Board.isWalkable(board, c) and not Board.isOccupied(c, board))
            |> List.maximumBy((a, b) ->
                Order.compare(distToNearestPlayer(a, board), distToNearestPlayer(b, board)));
        match best {
            case Some(c) =>
                if (distToNearestPlayer(c, board) > curDist)
                    (EnemyAction.Move(enemy#id, c), updated)
                else chase(board, enemy, updated)
            case None    => chase(board, enemy, updated)
        }

    /// `cell` から最も近いプレイヤーまでのマンハッタン距離。プレイヤー不在なら 0。
    def distToNearestPlayer(cell: {x = Int32, y = Int32}, board: Board): Int32 =
        match Board.nearestPlayer(cell, board) {
            case None    => 0
            case Some(p) =>
                let (_, pp) = p;
                manhattan(cell, pp)
        }

    // ════════════════════════════════════════════════════════
    // 検知ロジック
    // ════════════════════════════════════════════════════════

    /// 敵が索敵範囲（自分の移動到達範囲 = 赤マス）内にプレイヤーを捉えているか。
    def anyPlayerWithinReach(board: Board, enemyPos: {x = Int32, y = Int32},
                              moveTiles: Int32): Bool =
        let reach = Board.reachableCells(board#map#isFloor, enemyPos, moveTiles);
        Board.playerPositions(board)
            |> List.exists(entry -> {
                let (_, pos) = entry;
                Board.containsCell(pos, reach)
            })

    /// 敵セルが「いずれかのプレイヤー」と同じモジュール idx に属するか。
    def sameModuleAsAnyPlayer(board: Board, enemyPos: {x = Int32, y = Int32}): Bool =
        match board#map#moduleOfCell(enemyPos) {
            case None    => false
            case Some(a) =>
                Board.playerPositions(board)
                    |> List.exists(p -> {
                        let (_, pos) = p;
                        match board#map#moduleOfCell(pos) {
                            case Some(b) => a == b
                            case None    => false
                        }
                    })
        }

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    pub def isAdjacent(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        let dx = Int32.abs(a#x - b#x);
        let dy = Int32.abs(a#y - b#y);
        (dx == 1 and dy == 0) or (dx == 0 and dy == 1)

}
