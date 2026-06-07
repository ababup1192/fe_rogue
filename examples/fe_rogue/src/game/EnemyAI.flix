/// EnemyAI — 敵 1 体の sense（検知）と chase（追跡）を決定する純粋ロジック
///
/// 1 体ごとに `decideAction(board, enemy) -> (EnemyAction, Data)` を呼んで
/// 「次のターンに取る行動」と「Data の更新（alerted フラグ等）」を返す。
/// scene の更新（Marker2D 移動・Tween 開始・ログ出力）は呼び出し側が責務を持つ。
///
/// 状態遷移（Q3-B: 検知した瞬間に動く）:
///   - dormant (`alerted = false`)
///       └ 同モジュールにプレイヤー → `alerted := true`、その場で chase 計算に進む
///       └ 別モジュール             → `Skip(id)`（ターン消費せず何もしない）
///   - alerted (`alerted = true`、永続)
///       ├ 武器射程内にプレイヤー        → `Attack(id)`（剣=距離1 / 弓=距離2 など min..max）
///       ├ 最小射程より近づかれた(弓系)  → `Move(id, retreatStep)`（後退して間合い再確保 = カイティング）
///       ├ BFS で最短経路あり            → `Move(id, firstStep)`（隣接セルへの 1 マス）
///       └ 経路なし（壁・他駒で詰み）    → `Wait(id)`
///
/// **1 step / 1 frame 実装**: `decideAction` は「次の 1 マス」だけを返す。複数マス分の
/// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ取り出して処理する
/// 形で実現する。これにより 1 体ずつ・縦横 1 マスずつ動く UX が成立する。
///
/// **BFS の障害物（Q7-A）**: 壁 + 他敵駒。プレイヤー駒は障害にしない（追跡先なので）。
/// 経路探索の本体は `Board.bfsPath` に集約してあり、ここからは呼び出すだけ。
/// **行動順（Q6-A）**: 呼び出し側が id 昇順で並べてから 1 体ずつ呼ぶ。
mod EnemyAI {

    /// 敵 1 体の 1 ターンぶんの行動。
    /// `Move` の {x = Int32, y = Int32} は 1 マス分の移動先（隣接セル）。
    /// `Attack` は (enemyId, targetPlayerId) — 隣接する 1 名を狙う（複数人パーティ対応）。
    pub enum EnemyAction {
        case Move(Int32, {x = Int32, y = Int32})
        case Attack(Int32, Int32)
        case Wait(Int32)
        case Skip(Int32)
    }

    // ════════════════════════════════════════════════════════
    // 公開: 1 体ぶんの decision
    // ════════════════════════════════════════════════════════

    /// 敵 1 体の sense + chase を決定する。返り値の Data は alerted を更新済み。
    /// gridPos の更新は行わない（Move を実際に scene に反映するときに呼び出し側で行う）。
    pub def decideAction(board: Board,
                          enemy: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        // 1) 検知判定: dormant なら「同じ部屋に居る」または「索敵範囲(移動到達範囲)に居る」で起動。
        //    同モジュール判定だけだと通路(モジュール外)で接敵しても起動せず攻撃しないため、
        //    reachableCells ベースの索敵範囲判定(ローグ移動モードの検知と同モデル)を OR で足す。
        let alertedNow = enemy#alerted
                         or sameModuleAsAnyPlayer(board, enemy#gridPos)
                         or anyPlayerWithinReach(board, enemy#gridPos, enemy#moveTiles);
        let updated = {alerted = alertedNow | enemy};
        if (not alertedNow) (EnemyAction.Skip(enemy#id), updated)
        else
            // 2) Attack 優先: 装備武器の射程 (min..max) 内にプレイヤーが居れば 1 名狙う。
            //    武器が壊れている（None）敵 / 射程外（弓で距離 1 など）は攻撃できないので
            //    chase に落ちる。decideAction は移動キューの 1 step ごとに再評価されるため、
            //    「前進 → 射程に入った step で Attack」が自然に成立する（Attack が Move より優先）。
            match enemy#weapon {
                case None    => chase(board, enemy, updated)
                case Some(w) =>
                    // 「攻撃射程内か」と「最小射程より近い（弓に踏み込まれた）か」を
                    // 1 回のタプル判定でまとめて分岐する。
                    let inAttackRange = Board.playerInRange(enemy#gridPos, w#range#min, w#range#max, board);
                    let tooClose      = Board.playerInRange(enemy#gridPos, 0, w#range#min - 1, board);
                    match (inAttackRange, tooClose) {
                        // 射程内 → 1 名狙って攻撃（近すぎ判定は無視）
                        case (Some(target), _) =>
                            let (targetId, _) = target;
                            (EnemyAction.Attack(enemy#id, targetId), updated)
                        // 射程外かつ近すぎ → 後退して間合いを取り直す（カイティング）
                        case (None, Some(_))   => retreat(board, enemy, updated)
                        // 射程外で遠い → 前進して間合いを詰める
                        case (None, None)      => chase(board, enemy, updated)
                    }
            }

    /// 攻撃できないとき（射程外 / 武器なし）の追跡。最寄りプレイヤーへの最短経路の
    /// 1 歩目を返す。経路無し（壁・他駒で詰み）なら Wait、プレイヤー不在なら Skip。
    def chase(board: Board, enemy: EnemyScene.Data,
              updated: EnemyScene.Data): (EnemyAction, EnemyScene.Data) =
        match Board.nearestPlayer(enemy#gridPos, board) {
            case None              => (EnemyAction.Skip(enemy#id), updated)
            case Some(targetEntry) =>
                let (_, target) = targetEntry;
                match Board.bfsPath(board, enemy#gridPos, target) {
                    case None       => (EnemyAction.Wait(enemy#id), updated)
                    case Some(path) =>
                        match List.init(path) |> Option.flatMap(List.head) {
                            case Some(step) =>
                                (EnemyAction.Move(enemy#id, step), updated)
                            case None       =>
                                (EnemyAction.Wait(enemy#id), updated)
                        }
                }
        }

    /// 最小射程より近づかれた弓系の敵が、隣接 1 マスへ後退して間合いを取り直す（カイティング）。
    /// 4 近傍のうち「床 + 駒に占有されていない」マスから、最寄りプレイヤーとの距離を最も
    /// 広げられるマスを選ぶ。現在地より距離を広げられるマスが無い（壁際・包囲）なら chase に
    /// 委譲（= Wait に落ちる）。後退後は decideAction が step ごとに再評価され、射程に入った
    /// 時点で Attack へ切り替わる。
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
                Int32.abs(cell#x - pp#x) + Int32.abs(cell#y - pp#y)
        }

    // ════════════════════════════════════════════════════════
    // 検知ロジック
    // ════════════════════════════════════════════════════════

    /// 敵が索敵範囲(自分の移動到達範囲 = 赤マス)内にプレイヤーを捉えているか。
    /// `reachableCells`(床ベース BFS, moveTiles まで)にプレイヤー位置が含まれれば true。
    /// 通路でも「踏み込まれたら反応する」ようにするための検知。部屋判定の補完。
    def anyPlayerWithinReach(board: Board, enemyPos: {x = Int32, y = Int32},
                              moveTiles: Int32): Bool =
        let reach = Board.reachableCells(board#map#isFloor, enemyPos, moveTiles);
        Board.playerPositions(board)
            |> List.exists(entry -> {
                let (_, pos) = entry;
                Board.containsCell(pos, reach)
            })

    /// 敵セルが「いずれかのプレイヤー」と同じモジュール idx に属するか。
    /// パーティ全員のうち 1 人でも同モジュールに居れば true を返す。
    /// 両方が None（モジュール外＝void）の場合は同一とみなさない。
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
