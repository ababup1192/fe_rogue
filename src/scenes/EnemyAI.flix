/// EnemyAI — 敵の sense（検知）と chase（追跡）の純粋ロジック
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
///       ├ プレイヤーと隣接          → `Attack(id)`
///       ├ BFS で最短経路あり        → `Move(id, firstStep)`（隣接セルへの 1 マス）
///       └ 経路なし（壁・他駒で詰み）→ `Wait(id)`
///
/// **1 step / 1 frame 実装**: `decideAction` は「次の 1 マス」だけを返す。複数マス分の
/// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ取り出して処理する
/// 形で実現する。これにより 1 体ずつ・縦横 1 マスずつ動く UX が成立する。
///
/// **BFS の障害物（Q7-A）**: 壁 + 他敵駒。プレイヤー駒は障害にしない（追跡先なので）。
/// **行動順（Q6-A）**: 呼び出し側が id 昇順で並べてから 1 体ずつ呼ぶ。
mod EnemyAI {

    /// 敵 1 体の 1 ターンぶんの行動。
    /// `Move` の Vec2.Vec2i は 1 マス分の移動先（隣接セル）。
    /// `Attack` は (enemyId, targetPlayerId) — 隣接する 1 名を狙う（複数人パーティ対応）。
    pub enum EnemyAction {
        case Move(Int32, Vec2.Vec2i)
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
        // 1) 検知判定: dormant なら同モジュールチェックで alerted を更新
        //    どのプレイヤーでもいいので「同モジュールに 1 人でも居るか」で起動する
        let alertedNow = if (enemy#alerted) true
                         else sameModuleAsAnyPlayer(board, enemy#gridPos);
        let updated = {alerted = alertedNow | enemy};
        if (not alertedNow) (EnemyAction.Skip(enemy#id), updated)
        else
            // 2) Attack 優先: 隣接プレイヤーが居れば誰でも 1 名殴る（最寄り問わず）
            match Board.adjacentPlayer(enemy#gridPos, board) {
                case Some(adj) =>
                    let (targetId, _) = adj;
                    (EnemyAction.Attack(enemy#id, targetId), updated)
                case None =>
                    // 3) chase: 最寄りのプレイヤーを target にして 1 歩目を返す
                    match Board.nearestPlayer(enemy#gridPos, board) {
                        case None              => (EnemyAction.Skip(enemy#id), updated)
                        case Some(targetEntry) =>
                            let (_, target) = targetEntry;
                            match bfsPath(board, enemy#gridPos, target) {
                                case None       => (EnemyAction.Wait(enemy#id), updated)
                                case Some(path) =>
                                    match List.head(dropLast(path)) {
                                        case Some(step) =>
                                            (EnemyAction.Move(enemy#id, step), updated)
                                        case None       =>
                                            (EnemyAction.Wait(enemy#id), updated)
                                    }
                            }
                    }
            }

    // ════════════════════════════════════════════════════════
    // 検知ロジック
    // ════════════════════════════════════════════════════════

    /// 敵セルが「いずれかのプレイヤー」と同じモジュール idx に属するか。
    /// パーティ全員のうち 1 人でも同モジュールに居れば true を返す。
    /// 両方が None（モジュール外＝void）の場合は同一とみなさない。
    def sameModuleAsAnyPlayer(board: Board, enemyPos: Vec2.Vec2i): Bool =
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
    // 4 方向 BFS — 最短経路（リスト）を返す
    // ════════════════════════════════════════════════════════

    /// `source` から `goal` への最短経路を返す。経路無しなら None。
    /// 戻り値は **source を含まない** 順序付きリスト（先頭 = 1 歩目、末尾 = goal）。
    /// 障害物 = 壁 + 他駒（自分・goal のセルは通行可）。
    /// 隣接判定は呼び出し側が済ませている前提（source == goal は使用想定外）。
    def bfsPath(board: Board, source: Vec2.Vec2i,
                 goal: Vec2.Vec2i): Option[List[Vec2.Vec2i]] =
        let isOpen = c -> bfsIsOpen(board, c, source, goal);
        let initVisited = source :: Nil;
        // queue: (current, pathReversedFromSource) — pathReversedFromSource は source から
        //   current までの経路を末尾 cons で積んだもの（reverse すれば 1 歩目 → goal）。
        let initQueue: List[(Vec2.Vec2i, List[Vec2.Vec2i])] = (source, Nil) :: Nil;
        bfsLoop(isOpen, goal, initVisited, initQueue)

    def bfsLoop(isOpen: Vec2.Vec2i -> Bool,
                 goal: Vec2.Vec2i,
                 visited: List[Vec2.Vec2i],
                 queue: List[(Vec2.Vec2i, List[Vec2.Vec2i])]):
                Option[List[Vec2.Vec2i]] =
        match queue {
            case Nil => None
            case (cur, pathRev) :: rest =>
                if (vecEqI(cur, goal)) Some(List.reverse(pathRev))
                else
                    let dirs = Vec2.upI() :: Vec2.downI()
                                :: Vec2.leftI() :: Vec2.rightI() :: Nil;
                    let neighbors = List.map(d -> Vec2.addI(cur, d), dirs);
                    let fresh = List.filter(c ->
                        isOpen(c) and not isInList(c, visited),
                        neighbors);
                    let withPath = List.map(c -> (c, c :: pathRev), fresh);
                    let newVisited = List.append(visited, fresh);
                    let newQueue   = List.append(rest, withPath);
                    bfsLoop(isOpen, goal, newVisited, newQueue)
        }

    /// リストの末尾 1 要素を除いた残りを返す。長さ 0/1 なら Nil。
    /// BFS 経路から goal（= プレイヤーセル）を取り除き「踏める範囲」だけ取り出すのに使う。
    def dropLast(list: List[a]): List[a] =
        match list {
            case Nil      => Nil
            case _ :: Nil => Nil
            case x :: rest => x :: dropLast(rest)
        }

    /// BFS で「踏める」と判定するセルの述語。
    /// - 床でなければ NG
    /// - source（自分） / goal（プレイヤー）は通行可
    /// - 他駒（他の敵 or 別の駒）が居れば NG
    def bfsIsOpen(board: Board, c: Vec2.Vec2i,
                   source: Vec2.Vec2i, goal: Vec2.Vec2i): Bool =
        if (not BoardLogic.isWalkable(board, c)) false
        else if (vecEqI(c, source) or vecEqI(c, goal)) true
        else not Board.isOccupied(c, board)

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    pub def isAdjacent(a: Vec2.Vec2i, b: Vec2.Vec2i): Bool =
        let dx = Int32.abs(a#x - b#x);
        let dy = Int32.abs(a#y - b#y);
        (dx == 1 and dy == 0) or (dx == 0 and dy == 1)

    def vecEqI(a: Vec2.Vec2i, b: Vec2.Vec2i): Bool =
        a#x == b#x and a#y == b#y

    def isInList(c: Vec2.Vec2i, list: List[Vec2.Vec2i]): Bool =
        List.exists(v -> vecEqI(v, c), list)
}
