/// EnemyAI — 敵 1 体の sense（検知）と「どの相手を・どう攻めるか」を決める純粋ロジック
///
/// 1 体ごとに `decideAction(enc, self, alerted) -> (EnemyAction, {alerted})` を呼んで
/// 「次のターンに取る行動」と「alerted フラグの更新差分」を返す。
/// scene の更新（Marker2D 移動・Tween 開始・ログ出力）は呼び出し側が責務を持つ。
///
/// **入力は faction 非依存のビュー**: 盤面 + 盤上ユニットは `Encounter`(board + units)、
/// 自分自身は `UnitView`(位置・射程・戦闘ステータスを結合済み)。targets は `Encounter` から
/// 内部導出するので、呼び出し側で TargetInfo を手組みする必要はない（buildTargets 廃止）。
/// 推定ダメージは `UnitView.estDamage`(= `Combat.estimate`)、攻撃可否の射程は `Weapon.inRange`。
///
/// **ターゲット選択 = 優先度つき評価軸の辞書式比較**:
///   「性質」を `Criterion`（enum）でデータ化し、`priorities()` に優先度順で並べる。
///   候補（対立 faction の `UnitView`）をその並びで辞書式比較（先頭の基準で差がつけば決定、
///   同点なら次の基準…）して、engage する 1 体を選ぶ。性質を足したいときは `priorities()` に
///   1 行 + `rank` に 1 分岐 + 必要なら `UnitView` に 1 フィールド足すだけ。
///   現状の優先順位: 仕留め(Killable) > 反撃不能(NoCounter, 遠隔のみ) > 低HP(LowHp) > 近さ(Near)。
///
/// **2 段階で行動を決める**（攻撃できるなら必ず攻撃する）:
///   - フェーズ1: 今ターン攻撃できる相手（武器射程内）が居れば、その中の最良を `Attack`。
///   - フェーズ2: 射程内に誰も居なければ、全候補から最良を選び `chase`/`retreat` で寄る。
///
/// **1 step / 1 frame 実装**: `decideAction` は「次の 1 マス」だけを返す。複数マス分の
/// 移動は `EnemyTurn.Queue` に step を積み、1 フレームに 1 step ずつ取り出して処理する。
///
/// **BFS の障害物**: 壁 + 他敵駒。プレイヤー駒は障害にしない（追跡先なので）。
mod EnemyAI {

    use Weapon.manhattan

    /// 敵 1 体の 1 ターンぶんの行動。
    /// `Move` の {x, y} は 1 マス分の移動先（隣接セル）。
    /// `Attack` は (enemyId, targetPlayerId)。
    /// `Wander` は未起動の徘徊型が「あてもなく 1 歩動きたい」という意図。実際の行先は
    /// 乱数を要するため driver (EnemyTurnDriverScene.applyStep) が選ぶ — decideAction を pure に保つ。
    pub enum EnemyAction {
        case Move(Int32, {x = Int32, y = Int32})
        case Attack(Int32, Int32)
        case Wait(Int32)
        case Skip(Int32)
        case Wander(Int32)
    }

    /// 敵の索敵/挙動タイプ。`enemies.json` の `aiType` フィールド 1 つで IDE から選ぶ。
    /// **新タイプ追加はここに 1 case + `policy()` に 1 行 + `parseAiType` に 1 行 +
    /// `enemies.schema.json` の values に 1 文字列**。decideAction/driver 側は一切触らない。
    pub enum AiType with Eq, ToString {
        case Aggressive          // 既定: 同室 or 移動到達範囲で起動し追跡（従来挙動）
        case GuardUntilInRange   // 同室でも待機。武器の攻撃射程に入る or 攻撃を受けると起動
        case Wanderer            // 未発見のうちは徘徊（湧きは driver / spawn 側）
    }

    /// dormant → alerted に遷移する条件の種別（データ化）。
    pub enum AlertRule with Eq, ToString {
        case OnSightOrReach   // 同室 OR 移動到達範囲（従来 Aggressive）
        case OnWeaponRange    // 武器の攻撃射程に相手が入ったときのみ
    }

    /// 未起動（dormant）時の振る舞いの種別（データ化）。
    pub enum IdleBehavior with Eq, ToString {
        case StayDormant   // Skip（その場で待機）
        case Roam          // Wander（あてもなく 1 歩徘徊）
    }

    /// 1 タイプぶんのポリシー。起動条件と未起動時の振る舞いを 1 レコードで宣言する。
    /// 起動後の振る舞いは現状全タイプ「追跡 + 攻撃」共通なのでフィールド化しない
    /// （必要になったらここに 1 フィールド足す）。
    pub type alias AiPolicy = { alert = AlertRule, idle = IdleBehavior }

    /// **唯一のディスパッチ点**。タイプ → ポリシー。match 網羅性検査が
    /// 「新タイプの policy 追加し忘れ」をコンパイル時に検出する。
    pub def policy(t: AiType): AiPolicy = match t {
        case AiType.Aggressive        => { alert = AlertRule.OnSightOrReach, idle = IdleBehavior.StayDormant }
        case AiType.GuardUntilInRange => { alert = AlertRule.OnWeaponRange,  idle = IdleBehavior.StayDormant }
        case AiType.Wanderer          => { alert = AlertRule.OnSightOrReach, idle = IdleBehavior.Roam }
    }

    /// JSON 文字列 → AiType。未知 / 欠落は Aggressive にフォールバック（後方互換）。
    pub def parseAiType(s: String): AiType = match s {
        case "GuardUntilInRange" => AiType.GuardUntilInRange
        case "Wanderer"          => AiType.Wanderer
        case _                   => AiType.Aggressive
    }

    /// AiType → JSON 文字列（encode 用）。`parseAiType` と往復一致する。
    pub def aiTypeToString(t: AiType): String = "${t}"

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

    /// 敵 1 体の sense + ターゲット選択 + 行動を決定する。
    /// `self` は自分の盤上ビュー、`alerted` は現在の起動フラグ、`enc` は盤面 + 盤上ユニット。
    /// 返り値の `{alerted}` は更新後の起動フラグ（呼び出し側が Data に反映する）。
    /// targets（= 対立 faction の hidden でないユニット）は `enc` から内部導出する。
    pub def decideAction(enc: Encounter, self: UnitView, alerted: Bool):
                          (EnemyAction, {alerted = Bool}) =
        // 検知 / 未起動時の振る舞いは AiType のポリシーに従う。ここに `match AiType` は無く、
        // policy() を 1 回引いて起動条件種別 / 未起動時種別を読むだけ（タイプを増やしても分岐は増えない）。
        let board = enc#board;
        let pol = policy(self#aiType);
        let alertedNow = alerted or shouldAlert(pol#alert, enc, self);
        if (not alertedNow)
            // 未起動: StayDormant は Skip（静止）、Roam は Wander（行先は driver が乱数選択）。
            let idleAction = match pol#idle {
                case IdleBehavior.StayDormant => EnemyAction.Skip(self#id)
                case IdleBehavior.Roam        => EnemyAction.Wander(self#id)
            };
            (idleAction, {alerted = alertedNow})
        else
            // フェーズ1: 今ターン攻撃できる相手（武器射程内）の最良。攻撃を優先することで
            //   「射程内に相手が居るのに遠くの弱い相手を追って攻撃を見送る」のを防ぐ。
            // フェーズ2: 射程内に居なければ全候補の最良へ接近 or カイティング。
            let targets = Encounter.enemiesOf(self#faction, enc);
            let attackTarget = pickTarget(self, attackableTargets(self, targets));
            // 射程内に居れば評価軸で選んだ最良を攻撃。居なければ距離フィールドの勾配を降りて
            // 「経路最寄りのプレイヤー」へ 1 歩寄る（迷路でも詰まらない・遠回りしない）。
            let action = match attackTarget {
                case Some(t) => EnemyAction.Attack(self#id, t#id)
                case None    => approachField(board, self)
            };
            (action, {alerted = alertedNow})

    /// 起動条件を AlertRule でディスパッチする。本体は既存の検知ヘルパーを再利用する。
    ///   - OnSightOrReach: 同室 OR 移動到達範囲（従来の Aggressive 起動）。
    ///   - OnWeaponRange : 武器の攻撃射程内に攻撃可能な相手が現れたときのみ（GuardUntilInRange）。
    ///     `attackableTargets` をそのまま使うので射程ロジックの重複なし。
    def shouldAlert(rule: AlertRule, enc: Encounter, self: UnitView): Bool =
        let board = enc#board;
        match rule {
            case AlertRule.OnSightOrReach =>
                sameModuleAsAnyPlayer(board, self#pos)
                    or anyPlayerWithinReach(board, self#pos, self#moveTiles)
            case AlertRule.OnWeaponRange  =>
                not List.isEmpty(attackableTargets(self, Encounter.enemiesOf(self#faction, enc)))
        }

    /// 今ターン攻撃できる（武器射程 min..max 内の）相手だけを残す。武器なしは空。
    /// 射程判定と生存判定を分離することで、フィルタ条件を独立してテスト・再利用できる。
    def attackableTargets(self: UnitView, targets: List[UnitView]): List[UnitView] =
        match self#weaponRange {
            case None    => Nil
            case Some(r) =>
                List.filter(t -> Weapon.inRange(manhattan(self#pos, t#pos), r), targets)
        }

    /// 射程内に相手が居ないときの移動。プレイヤー始点の距離フィールドを降りて 1 歩近づく。
    /// 弓系は最小射程より近すぎれば後退（カイティング）。経路最寄りへ向かうので迷路でも詰まらない。
    def approachField(board: Board, self: UnitView): EnemyAction =
        let players = Board.allPlayerCells(board);
        if (List.isEmpty(players)) EnemyAction.Wait(self#id)
        else {
            // プレイヤーはターン中不動なので 1 回計算を共有できる。カイティング判定と
            // 「経路が塞がれたときの寄せ」の両方に使う。
            let openField = Board.distanceField(c -> Board.isWalkable(board, c),
                                                 players, floodSteps());
            match self#weaponRange {
                case Some(r) =>
                    if (Board.fieldDist(openField, self#pos) < r#min)
                        retreat(board, self, openField)
                    else descendTwoTier(board, self, players, openField)
                case None => descendTwoTier(board, self, players, openField)
            }
        }

    /// 距離フィールドの勾配を 1 歩降りる。2 段で粘る:
    ///   1) **他敵を障害物**にしたフィールド（= 実際に通れる経路）の勾配を降りる
    ///      → 別の敵を迂回しつつ最短で寄る（局所最小なし）。
    ///   2) それで降りられない（前を敵が塞いで経路が断たれている）→ **壁のみ**フィールド
    ///      （ユニット透過）の勾配で「行けるところまで」寄せる（通路口の手前まで詰める）。
    /// どちらも降りられなければ Wait（列で待つ / 壁で隔絶）。実際の 1 歩は空きマスのみに踏む。
    def descendTwoTier(board: Board, self: UnitView,
                        players: List[{x = Int32, y = Int32}],
                        openField: Map[(Int32, Int32), Int32]): EnemyAction =
        let pos = self#pos;
        let blockedField = Board.distanceField(
            c -> Board.isWalkable(board, c)
                  and ((c#x == pos#x and c#y == pos#y) or not Board.isEnemyAt(c, board)),
            players, floodSteps());
        // okStep は「空きマスか」だけ見る。blockedField は他敵を障害物として計算した経路なので、
        // ここでは二重にユニット位置を見る必要がなく空き判定だけで足りる。
        let okStep = c -> not Board.isOccupied(c, board);
        let onBlocked = Board.stepDownhill(blockedField, pos, okStep);
        let step = if (Option.isEmpty(onBlocked))
                       Board.stepDownhill(openField, pos, okStep)
                   else onBlocked;
        step
            |> Option.map(s -> EnemyAction.Move(self#id, s))
            |> Option.getWithDefault(EnemyAction.Wait(self#id))

    /// 距離フィールドのフラッド上限（マップ全域を覆えるよう十分大きく取る）。
    def floodSteps(): Int32 = 4096

    // ターゲット選択: Criterion を enum でデータ化することで、優先順位変更が priorities() 1 箇所で完結する。

    /// 賢さの定義＝この並び（先頭が最優先）。性質追加はここに 1 行足すだけ。
    pub def priorities(): List[Criterion] =
        Criterion.Killable :: Criterion.NoCounter :: Criterion.LowHp :: Criterion.Near :: Nil

    /// 1 軸の「良さ」を素の整数で返す（大きいほど良い）。`self` は攻撃側、`t` は候補。
    /// 重み調整は不要（辞書式なので `priorities()` の順序だけで優先が決まる）。
    pub def rank(c: Criterion, self: UnitView, t: UnitView): Int32 = match c {
        case Criterion.Killable  => if (UnitView.estDamage(self, t) >= t#hp) 1 else 0
        case Criterion.NoCounter =>
            // 自分の攻撃距離（武器の最大射程）で相手が反撃できないなら優先（全敵共通）。
            // 近接(距離1)なら弓兵(射程2)は反撃できないので、近接敵も弓兵を優先して狙う。
            if (not canCounterAt(t#weaponRange, weaponMaxOf(self))) 1 else 0
        case Criterion.LowHp     => 0 - t#hp                        // HP が低いほど大
        case Criterion.Near      => 0 - manhattan(self#pos, t#pos)  // 近いほど大
    }

    /// `priorities()` の順に各軸を点数化したキー（辞書式比較に使う）。
    pub def keyOf(self: UnitView, t: UnitView): List[Int32] =
        List.map(c -> rank(c, self, t), priorities())

    /// 同じ長さの点数キーを辞書式（先頭が最優先）に比較し、`xs` が `ys` より良ければ true。
    /// 先頭の軸で差がつけばそれで決定、同点なら次の軸へ。
    pub def lexGreater(xs: List[Int32], ys: List[Int32]): Bool = match (xs, ys) {
        case (x :: xt, y :: yt) => if (x != y) x > y else lexGreater(xt, yt)
        case _                  => false
    }

    /// `targets` から辞書式で最良の 1 体を選ぶ（argmax）。候補が空なら None。
    pub def pickTarget(self: UnitView, targets: List[UnitView]): Option[UnitView] =
        List.foldLeft((best, t) -> match best {
            case None    => Some(t)
            case Some(b) => if (lexGreater(keyOf(self, t), keyOf(self, b))) Some(t) else best
        }, None, targets)

    /// 相手が距離 `d` で反撃できるか。`None`（武器なし）は反撃不能。
    pub def canCounterAt(range: Option[{min = Int32, max = Int32}], d: Int32): Bool =
        match range {
            case None    => false
            case Some(r) => d >= r#min and d <= r#max
        }

    /// 攻撃側の装備武器の最大射程（武器なしは 0）。
    def weaponMaxOf(self: UnitView): Int32 = match self#weaponRange {
        case None    => 0
        case Some(r) => r#max
    }

    /// 最小射程より近づかれた弓系の敵が、隣接 1 マスへ後退して間合いを取り直す（カイティング）。
    /// 4 近傍の「床 + 空きマス」から、距離フィールド値が最も大きい（プレイヤーから経路上で
    /// 最も遠い）マスへ退く。間合いを広げられるマスが無い（壁際・包囲）なら Wait。
    /// `field` は壁のみフィールド（経路距離が一意に決まる）を渡す。
    def retreat(board: Board, self: UnitView,
                 field: Map[(Int32, Int32), Int32]): EnemyAction =
        let pos  = self#pos;
        let here = Board.fieldDist(field, pos);
        let dirs = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
        let best = dirs
            |> List.map(d -> Board.stepTarget(pos, d))
            |> List.filter(c -> Board.isWalkable(board, c) and not Board.isOccupied(c, board))
            |> List.maximumBy((a, b) ->
                Order.compare(Board.fieldDist(field, a), Board.fieldDist(field, b)));
        match best {
            case Some(c) =>
                if (Board.fieldDist(field, c) > here) EnemyAction.Move(self#id, c)
                else EnemyAction.Wait(self#id)
            case None    => EnemyAction.Wait(self#id)
        }

    // 検知: 「同じ部屋」と「移動到達範囲内」の2条件で dormant → alerted に遷移する。

    /// 敵が索敵範囲（自分の移動到達範囲 = 赤マス）内にプレイヤーを捉えているか。
    def anyPlayerWithinReach(board: Board, enemyPos: {x = Int32, y = Int32},
                              moveTiles: Int32): Bool =
        let reach = Board.reachableCells(c -> MapSnapshot.isFloor(c, board#map), enemyPos, moveTiles);
        Board.playerPositions(board)
            |> List.exists(entry -> {
                let (_, pos) = entry;
                Board.containsCell(pos, reach)
            })

    /// 敵セルが「いずれかのプレイヤー」と同じモジュール idx に属するか。
    def sameModuleAsAnyPlayer(board: Board, enemyPos: {x = Int32, y = Int32}): Bool =
        // 敵セルの所属モジュールを取り、いずれかの味方が同じモジュールに居るか。
        // 内側の match は「moduleOfCell(pos) == Some(a)」(Option 同値) に、外側は Option.map で畳む。
        MapSnapshot.moduleOfCell(enemyPos, board#map)
            |> Option.map(a ->
                Board.playerPositions(board)
                    |> List.exists(p -> { let (_, pos) = p;
                        MapSnapshot.moduleOfCell(pos, board#map) == Some(a) }))
            |> Option.getWithDefault(false)

    /// 徘徊（Wander）で踏める 1 マス先の候補セル一覧（純粋）。シレン流の回遊にするため
    /// モジュール（部屋/通路）の境界を越えてよい＝部屋から通路、通路から別部屋へ抜けられる。
    /// 「歩行可能 + 空きマス」の 4 近傍を残し、さらに **直前にいたマス `prevPos` は除外**して
    /// 「来た道へ戻らない」ようにする（1 幅通路で前後に揺れず直進し、実際に回遊する）。
    /// ただし除外すると行き場が無くなる（袋小路）場合だけは prevPos を許して引き返せるようにする。
    /// 実際の 1 つの選択は乱数を要するため driver 側が `RandomUtil.pick` で選ぶ（ここは pure）。
    pub def wanderCandidates(board: Board, pos: {x = Int32, y = Int32},
                              prevPos: Option[{x = Int32, y = Int32}]):
            List[{x = Int32, y = Int32}] =
        let dirs = Vec2i.up() :: Vec2i.down() :: Vec2i.left() :: Vec2i.right() :: Nil;
        let open = dirs
            |> List.map(d -> Board.stepTarget(pos, d))
            |> List.filter(c -> Board.isWalkable(board, c) and not Board.isOccupied(c, board));
        let isPrev = c -> prevPos
            |> Option.map(p -> p#x == c#x and p#y == c#y)
            |> Option.getWithDefault(false);
        let forward = List.filter(c -> not isPrev(c), open);
        if (List.isEmpty(forward)) open else forward

    /// 斜め隣接を含まない 4 近傍判定（上下左右のみ）。
    pub def isAdjacent(a: {x = Int32, y = Int32}, b: {x = Int32, y = Int32}): Bool =
        let dx = Int32.abs(a#x - b#x);
        let dy = Int32.abs(a#y - b#y);
        (dx == 1 and dy == 0) or (dx == 0 and dy == 1)

}
