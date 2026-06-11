/// EnemyAI.decideAction の振る舞いを純粋関数として検証する。
///
/// 検証する状態遷移:
///   - dormant かつ別モジュール → Skip、alerted は false のまま
///   - dormant かつ同モジュール → alerted=true に更新、その場で chase（Q3-B）
///   - alerted かつ別モジュール → 引き続き chase（一度起きたら永続）
///   - 隣接 → Attack
///   - 経路無し（壁・他駒で詰まり）→ Wait
///   - BFS が壁を回避して 1 歩目を選ぶ
///   - BFS が他敵駒を障害物として回避（Q7-A）
mod TestEnemyAI {

    use EnemyAI.EnemyAction

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    def testTileSize(): Float64 = 16.0

    def testGridToWorld(c: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(c);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// MapSnapshot の定型を 1 か所に集約する核。床判定 isFloorAt とモジュール判定 moduleOf を渡す。
    /// isWall / mapToLocal / gridToWorld の決まり文句をここに閉じ込め、各テストは「床の形」だけ書く。
    def roomSnapshotWith(w: Int32, h: Int32,
                         isFloorAt: {x = Int32, y = Int32} -> Bool,
                         moduleOf: {x = Int32, y = Int32} -> Option[Int32]): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = w, y = h}: {x = Int32, y = Int32})},
            isWall       = c -> not isFloorAt(c),
            isFloor      = isFloorAt,
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = moduleOf
        }

    /// 単一モジュール(=0)版の別名。床なら Some(0)、壁なら None。大半のテストはこれを使う。
    def roomSnapshotWhere(w: Int32, h: Int32,
                          isFloorAt: {x = Int32, y = Int32} -> Bool): MapSnapshot =
        roomSnapshotWith(w, h, isFloorAt, c -> if (isFloorAt(c)) Some(0) else None)

    /// 全床 w×h で 2 つの仮想モジュール領域に区切った MapSnapshot を作る。
    /// (0..w/2, 0..h)  → moduleIdx = Some(0)（プレイヤーの部屋）
    /// (w/2..w, 0..h)  → moduleIdx = Some(1)（敵の部屋）
    def twoRoomSnapshot(w: Int32, h: Int32): MapSnapshot =
        let inB  = c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h;
        let half = w / 2;
        roomSnapshotWith(w, h, inB,
            c -> if (not inB(c)) None else if (c#x < half) Some(0) else Some(1))

    /// 1 部屋だけの snapshot（全マス moduleIdx = 0）。
    def singleRoomSnapshot(w: Int32, h: Int32): MapSnapshot =
        roomSnapshotWhere(w, h, c -> c#x >= 0 and c#x < w and c#y >= 0 and c#y < h)

    /// 壁マス wall を持つ単一部屋 snapshot（moduleIdx = 0）。
    def singleRoomWithWall(w: Int32, h: Int32, wall: {x = Int32, y = Int32}): MapSnapshot =
        roomSnapshotWhere(w, h, c ->
            c#x >= 0 and c#x < w and c#y >= 0 and c#y < h
                and not (c#x == wall#x and c#y == wall#y))

    /// プレイヤー（id=0 単独） + 敵 1 体の Board を組む。
    def boardOf(map: MapSnapshot, player: {x = Int32, y = Int32},
                 enemyId: Int32, enemyPos: {x = Int32, y = Int32}): Board =
        {
            map    = map,
            pieces = (Piece.Player(0), player)
                  :: (Piece.Enemy(enemyId), enemyPos) :: Nil
        }

    /// 敵 Data を作る。`moveTiles` は引数で指定（テストで挙動を変えるため）。
    /// `weapon = Some(...)` 固定（武器ありで動かす標準ケース）。
    /// 武器なしの挙動を検証したいテストは別フィクスチャ `enemyAtUnarmed` を使う。
    def enemyAt(id: Int32, pos: {x = Int32, y = Int32}, alerted: Bool,
                 home: Int32, moveTiles: Int32): EnemyScene.Data =
        { id = id, gridPos = pos, alerted = alerted,
          homeModuleIdx = home, moveTiles = moveTiles,
          hp = 3, isDying = false, attackTargetId = None,
          resource = TestUnitFixtures.testEnemyResource(moveTiles, 3),
          weapon = Some(TestUnitFixtures.testWeapon()), acted = false }

    /// 武器が壊れた状態（`weapon = None`）の敵 Data。武器なしで隣接プレイヤーに
    /// 攻撃しないことを確認するテストで使う。
    def enemyAtUnarmed(id: Int32, pos: {x = Int32, y = Int32}, alerted: Bool,
                       home: Int32, moveTiles: Int32): EnemyScene.Data =
        { id = id, gridPos = pos, alerted = alerted,
          homeModuleIdx = home, moveTiles = moveTiles,
          hp = 3, isDying = false, attackTargetId = None,
          resource = TestUnitFixtures.testEnemyResource(moveTiles, 3),
          weapon = None, acted = false }

    /// 射程 2-2 の弓を装備した敵 Data。アーチャーが距離 2 でのみ攻撃し、
    /// 隣接（距離 1）では体当たりしないことを検証するテストで使う。
    def enemyAtBow(id: Int32, pos: {x = Int32, y = Int32}, alerted: Bool,
                   home: Int32, moveTiles: Int32): EnemyScene.Data =
        let bow = { range = { min = 2, max = 2 } | TestUnitFixtures.testWeapon() };
        { id = id, gridPos = pos, alerted = alerted,
          homeModuleIdx = home, moveTiles = moveTiles,
          hp = 3, isDying = false, attackTargetId = None,
          resource = TestUnitFixtures.testEnemyResource(moveTiles, 3),
          weapon = Some(bow), acted = false }

    /// EnemyAction を tag だけのタプルに圧縮（id 付き）。Eq が無いので比較しやすくする。
    def tagOf(a: EnemyAction): String =
        match a {
            case EnemyAction.Move(_, _)   => "Move"
            case EnemyAction.Attack(_, _) => "Attack"
            case EnemyAction.Wait(_)      => "Wait"
            case EnemyAction.Skip(_)      => "Skip"
        }

    def moveTarget(a: EnemyAction): Option[{x = Int32, y = Int32}] =
        match a {
            case EnemyAction.Move(_, t) => Some(t)
            case _                      => None
        }

    /// Move の (tag, x, y) を取り出す。Move しか来ない前提の取り出しなので、他は bug!。
    /// （他アクションも正常に来うる比較系の `attackId` / `moveDistTo` が番兵 -1 を返すのとは別物。）
    /// 移動先セルを 1 点に pin するテストで、Option.map |> getWithDefault(-1) の 3 行を 1 か所に集約する。
    def moveTo(a: EnemyAction): (String, Int32, Int32) =
        match a {
            case EnemyAction.Move(_, t) => ("Move", t#x, t#y)
            case _                      => bug!("expected Move action")
        }

    /// Option[{x = Int32, y = Int32}] が Some か（isSome の代わり）。
    def isSome(o: Option[{x = Int32, y = Int32}]): Bool =
        match o {
            case Some(_) => true
            case None    => false
        }

    /// board + units から Encounter を組む（join helper のテストは TestEncounter 側）。
    def encOf(board: Board, units: List[UnitView]): Encounter =
        {board = board, units = units}

    /// 旧 `decideAction(board, enemy, targets)` 形のアダプタ。
    /// 敵 Data を `EnemyScene.unitView` で self ビューに、alerted を分離して渡す。
    def decide(board: Board, units: List[UnitView], enemy: EnemyScene.Data):
            (EnemyAI.EnemyAction, {alerted = Bool}) =
        EnemyAI.decideAction(encOf(board, units), EnemyScene.unitView(enemy), enemy#alerted)

    /// board の Player 駒から既定値の味方 UnitView を組む
    /// （hp 高め=仕留め不可・estDamage 0・反撃不能）。既存テストはこの既定値で挙動が変わらない
    /// （候補が 1 体なら選択は自明）。
    def targetsOf(board: Board): List[UnitView] =
        Board.playerPositions(board)
            |> List.map(entry -> {
                let (id, pos) = entry;
                mkTarget(id, pos, 99, 0, None)
            })

    /// 複数プレイヤー + 複数の敵駒を置いた Board。players / enemies はともに (id, pos) のリスト。
    def boardOfMany(map: MapSnapshot, players: List[(Int32, {x = Int32, y = Int32})],
                     enemies: List[(Int32, {x = Int32, y = Int32})]): Board =
        let playerPieces = List.map(p -> let (id, pos) = p; (Piece.Player(id), pos), players);
        let enemyPieces  = List.map(e -> let (id, pos) = e; (Piece.Enemy(id), pos), enemies);
        {map = map, pieces = List.append(playerPieces, enemyPieces)}

    /// 敵 self の実効攻撃力（素攻撃 + 装備武器攻撃）。フィクスチャから計算してハードコードを避ける。
    /// 三竦み中立前提: 本テスト群の敵（enemyAt / enemyAtBow）と target は全て Sword 型なので
    /// 相性補正 0。攻撃力フィクスチャ（attack 3 / 武器 2）を変えてもこの値が追従する。
    def selfAttack(): Int32 =
        TestUnitFixtures.testEnemyResource(0, 0)#attack + TestUnitFixtures.testWeapon()#attack

    /// 反撃射程 counterRange → その射程を持つ実武器（None は武器なし）。
    /// 武器タイプは testWeapon と同じ Sword（三竦み中立を保つ）。
    def counterWeapon(range: Option[{min = Int32, max = Int32}]):
            Option[UnitCatalog.WeaponResource] =
        Option.map(r -> {range = r | TestUnitFixtures.testWeapon()}, range)

    /// 評価軸テスト用の味方 Data。`defense` と装備武器を指定して `testResourceFull` で組む。
    def playerData(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, defense: Int32,
                   weapons: List[UnitCatalog.WeaponResource]): PlayerScene.Data =
        {id = id, gridPos = pos, moveTiles = 4, hp = hp, waited = false,
         attackTargetId = None,
         resource = TestUnitFixtures.testResourceFull(4, hp, 3, defense, 3),
         weapons = weapons, staves = Nil, consumables = Nil, selectedItem = None,
         moveStepsTaken = 0, facing = Staff.Direction.Down, hidden = false,
         usedStairs = false, level = 1, exp = 0, pendingLevelUp = None}

    /// 評価軸テスト用の味方 UnitView を実 projection（`PlayerScene.unitView`）で組む。
    /// 実武器由来なので `weaponRange`(反撃) と `combat`(ダメージ) は同じ武器から一貫して埋まる。
    /// estDamage の再現: 防御 = max(0, selfAttack() − estDamage) にすると `Combat.estimate` が
    /// estDamage を返す（estDamage は 0..selfAttack の範囲。本テスト群が使う 0/5 は範囲内）。
    /// counterRange はその射程の実武器として装備させ、反撃判定（NoCounter）に使う。
    def mkTarget(id: Int32, pos: {x = Int32, y = Int32}, hp: Int32, estDamage: Int32,
                  counterRange: Option[{min = Int32, max = Int32}]): UnitView =
        let defense = Int32.max(0, selfAttack() - estDamage);
        let weapons = match counterWeapon(counterRange) {
            case Some(w) => w :: Nil
            case None    => Nil
        };
        PlayerScene.unitView(playerData(id, pos, hp, defense, weapons))

    /// 剣（射程1-1）/ 弓（射程2-2）の反撃射程。
    def swordRange(): Option[{min = Int32, max = Int32}] = Some({min = 1, max = 1})
    def bowRange():   Option[{min = Int32, max = Int32}] = Some({min = 2, max = 2})

    /// Attack の対象 id（Attack でなければ -1）。
    def attackId(a: EnemyAction): Int32 = match a {
        case EnemyAction.Attack(_, tid) => tid
        case _                          => -1
    }

    /// Move 先からセル s までのマンハッタン距離（Move でなければ -1）。
    /// 「どの相手に向かって動いたか」を BFS のタイブレークに依らず確認するのに使う。
    def moveDistTo(a: EnemyAction, s: {x = Int32, y = Int32}): Int32 =
        match a {
            case EnemyAction.Move(_, t) => Int32.abs(t#x - s#x) + Int32.abs(t#y - s#y)
            case _                      => -1
        }

    // ════════════════════════════════════════════════════════
    // dormant ↔ alerted の遷移
    // ════════════════════════════════════════════════════════

    /// dormant + 別モジュール → Skip、alerted は false のまま。
    @Test
    def testDecideDormantDifferentModuleSkips(): Unit \ Assert =
        let map     = twoRoomSnapshot(10, 5);
        let player  = ({x = 1, y = 2}: {x = Int32, y = Int32});   // module 0
        let enemyP  = ({x = 7, y = 2}: {x = Int32, y = Int32});   // module 1
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 1, 3);
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Skip", false), (tagOf(a), d#alerted))

    /// dormant + 別モジュールでも、索敵範囲(移動到達範囲)内に居れば起動して chase する。
    /// 通路などモジュール外で接敵しても敵が反応するための検知。
    /// プレイヤー (4,2)=module0、敵 (7,2)=module1、距離 3 ≤ moveTiles 3 → 到達範囲内 → Move。
    @Test
    def testDecideDormantWithinReachAlerts(): Unit \ Assert =
        let map     = twoRoomSnapshot(10, 5);
        let player  = ({x = 4, y = 2}: {x = Int32, y = Int32});   // module 0
        let enemyP  = ({x = 7, y = 2}: {x = Int32, y = Int32});   // module 1
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 1, 3);
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    // ════════════════════════════════════════════════════════
    // 「敵が隣室からワープしてくる」原因確定の回帰テスト
    //   検知が `moveTiles` の床フラッド (reachableCells) と直結しているため、
    //   moveTiles が大きいと通路/床続きで隣室のプレイヤーを拾って即起動する。
    //   バランス調整 (a37e25e) で moveTiles を 3→5 に上げたことが引き金。
    //   幾何 (床距離 5・モジュール境界越し) を固定し moveTiles だけ変えて回帰を示す。
    //   ※現状仕様 (= バグ) を pin する形。修正時は期待値を反転する想定。
    // ════════════════════════════════════════════════════════

    /// moveTiles=3 のときは床距離 5 の隣室プレイヤーを検知できず dormant のまま (Skip)。
    @Test
    def testCrossRoomMoveTiles3StaysDormant(): Unit \ Assert =
        let map     = twoRoomSnapshot(14, 5);                       // half = 7
        let player  = ({x = 4, y = 2}: {x = Int32, y = Int32});    // module 0
        let enemyP  = ({x = 9, y = 2}: {x = Int32, y = Int32});    // module 1, 床距離 5
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 1, 3);
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Skip", false), (tagOf(a), d#alerted))

    /// 同一幾何でも moveTiles=5 にすると床距離 5 が索敵範囲に入り、隣室を越えて即起動 (Move)。
    /// これが「通路を挟んだ隣室の敵がいきなり追ってくる」回帰の核心。
    @Test
    def testCrossRoomMoveTiles5AlertsAcrossRoom(): Unit \ Assert =
        let map     = twoRoomSnapshot(14, 5);                       // half = 7
        let player  = ({x = 4, y = 2}: {x = Int32, y = Int32});    // module 0
        let enemyP  = ({x = 9, y = 2}: {x = Int32, y = Int32});    // module 1, 床距離 5
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 1, 5);
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    /// dormant + 同モジュール → alerted=true、Move（Q3-B: 検出フレームに動く）。
    @Test
    def testDecideDormantSameModuleAlertsAndMoves(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 1}: {x = Int32, y = Int32});
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, false, 0, 3);
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    /// 一度 alerted なら別モジュールでも chase 継続。
    @Test
    def testDecideAlertedDifferentModuleStillChases(): Unit \ Assert =
        let map     = twoRoomSnapshot(10, 5);
        let player  = ({x = 1, y = 2}: {x = Int32, y = Int32});
        let enemyP  = ({x = 7, y = 2}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 1, 3);    // 既に alerted
        let (a, d)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", true), (tagOf(a), d#alerted))

    // ════════════════════════════════════════════════════════
    // 隣接 → Attack
    // ════════════════════════════════════════════════════════

    @Test
    def testDecideAdjacentAttacks(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 6, y = 5}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Attack", tagOf(a))

    /// 武器が壊れている（weapon = None）敵は隣接プレイヤーがあっても攻撃しない。
    /// `Attack` を返さず `Wait` に切り替えること。
    @Test
    def testDecideAdjacentWithoutWeaponWaits(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 6, y = 5}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAtUnarmed(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Wait", tagOf(a))

    // ════════════════════════════════════════════════════════
    // 武器射程に基づく Attack 判定
    // ════════════════════════════════════════════════════════

    /// 弓 (range 2-2) の敵が隣接 (距離 1) では Attack を返さない。
    /// このバグ（アーチャーが隣接で体当たりしてくる）の回帰防止。
    /// 射程外（距離 1 < min 2）なので体当たりせず、後退 Move に切り替わる。
    @Test
    def testBowAdjacentDoesNotAttack(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 6, y = 5}: {x = Int32, y = Int32});   // 距離 1
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAtBow(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = false, tagOf(a) == "Attack")

    /// 弓の敵が隣接 (距離 1) されたら後退して間合いを取り直す（カイティング）。
    /// 開けた部屋なら Move を返し、移動先はプレイヤーから距離 2（= 弓射程）に広がる。
    /// 「間接攻撃後に隣接したら動かなくなる」硬直の回帰防止。
    @Test
    def testBowAdjacentRetreats(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 6, y = 5}: {x = Int32, y = Int32});   // 距離 1
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAtBow(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        // 移動先がプレイヤー(5,5)から距離 2（弓射程）に広がる。退き方向は pin せず距離だけ見る
        Assert.assertEq(expected = ("Move", 2), (tagOf(a), moveDistTo(a, player)))

    /// 後退できない（壁際・包囲で間合いを広げられない）弓の敵は Wait に落ちる。
    /// 2×1 の通路でプレイヤー (0,0) に隣接した敵 (1,0) は逃げ場が無く、後退不可 → Wait。
    @Test
    def testBowCorneredWaits(): Unit \ Assert =
        let map     = singleRoomSnapshot(2, 1);
        let player  = ({x = 0, y = 0}: {x = Int32, y = Int32});
        let enemyP  = ({x = 1, y = 0}: {x = Int32, y = Int32});   // 距離 1、逃げ場なし
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAtBow(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Wait", tagOf(a))

    /// 弓 (range 2-2) の敵が距離 2 の味方を Attack する。
    @Test
    def testBowAtRangeTwoAttacks(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 7, y = 5}: {x = Int32, y = Int32});   // 距離 2
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAtBow(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Attack", tagOf(a))

    /// 剣 (range 1-1) の敵は距離 2 では Attack せず前進 (Move) する。
    /// 近接武器が射程外で chase に落ちることの確認（弓と対になるケース）。
    @Test
    def testSwordAtRangeTwoChases(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 7, y = 5}: {x = Int32, y = Int32});   // 距離 2
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);            // testWeapon = 剣 1-1
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Move", tagOf(a))

    @Test
    def testIsAdjacentManhattanOne(): Unit \ Assert =
        let a = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let b = ({x = 5, y = 6}: {x = Int32, y = Int32});   // 真下
        let c = ({x = 6, y = 6}: {x = Int32, y = Int32});   // 斜め
        let d = ({x = 5, y = 5}: {x = Int32, y = Int32});   // 同位置
        Assert.assertEq(
            expected = (true, false, false),
            (EnemyAI.isAdjacent(a, b),
             EnemyAI.isAdjacent(a, c),
             EnemyAI.isAdjacent(a, d)))

    // ════════════════════════════════════════════════════════
    // BFS の経路選択
    // ════════════════════════════════════════════════════════

    /// 何も無い部屋で敵 (5,5) → プレイヤー (1,5)、moveTiles=1 なら 1 歩目は (4,5)。
    @Test
    def testBfsStraightLineOneStep(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 1);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", 4, 5), moveTo(a))

    /// `decideAction` は常に「最短経路の 1 歩目」だけを返す（複数マス分は呼び出し側
    /// の EnemyTurn.Queue が step を積んで処理する）。距離 2 のケースで 1 歩目 (2,5) を
    /// 返し、プレイヤーセル (1,5) を踏み越えないことを確認。
    @Test
    def testBfsStopsBeforePlayer(): Unit \ Assert =
        let map     = singleRoomSnapshot(10, 10);
        let player  = ({x = 1, y = 5}: {x = Int32, y = Int32});
        let enemyP  = ({x = 3, y = 5}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", 2, 5), moveTo(a))

    /// 壁を迂回するケース。
    /// 配置:
    ///   . . . . .
    ///   P # . . E
    ///   . . . . .
    /// 敵 (4,1) → プレイヤー (0,1)。直線は (1,1) が壁で塞がれているので、
    /// 上下どちらかから迂回する。1 歩目は (3,1) または (4,0) または (4,2)。
    /// ここでは「最短経路の 1 歩目」が取れること（None でない）と Move であることを検証。
    @Test
    def testBfsWallDetour(): Unit \ Assert =
        let map     = singleRoomWithWall(5, 3, ({x = 1, y = 1}: {x = Int32, y = Int32}));
        let player  = ({x = 0, y = 1}: {x = Int32, y = Int32});
        let enemyP  = ({x = 4, y = 1}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", true),
                         (tagOf(a), isSome(moveTarget(a))))

    /// 壁で**完全分断**され、到達可能なプレイヤーが 1 人も居ないときは Wait する。
    /// 5×3・x=2 列を壁で分断。味方(0,1)は左、敵(4,1)は右で、壁越しに行き来できない。
    /// 距離フィールド方式では「到達不能な方向へは進まない」（旧: マンハッタンで壁際まで寄せていた）。
    /// 通常のダンジョンは連結なのでこのケースは合成的。塞いでいるのが*ユニット*の場合は
    /// `testApproachesTowardBlockedCorridorInsteadOfWaiting` の通り壁のみフィールドで詰める。
    @Test
    def testNoPathStillStepsTowardPlayer(): Unit \ Assert =
        // 5×3 の床から x=2 の列を壁で抜いて左右を分断する
        let map = roomSnapshotWhere(5, 3, c ->
            c#x >= 0 and c#x < 5 and c#y >= 0 and c#y < 3 and c#x != 2);
        let player  = ({x = 0, y = 1}: {x = Int32, y = Int32});
        let enemyP  = ({x = 4, y = 1}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = "Wait", tagOf(a))

    /// 他敵駒は障害物。Q7-A を確認する。
    /// 配置（5×3 全床、敵 0 が (4,1)、プレイヤー (0,1)、別の敵 (3,1) で直線が塞がれる）:
    ///   . . . . .
    ///   P . . X E0
    ///   . . . . .
    /// moveTiles=3 で迂回する。敵 0 は (3,1) を通れないので上に回り込み、
    /// 次の 1 歩は (4,0)（上方向優先の決定的タイブレーク。(3,1) は通らない）。
    @Test
    def testBfsAvoidsOtherEnemy(): Unit \ Assert =
        let map    = singleRoomSnapshot(5, 3);
        // 敵 0 が本体、敵 1(3,1) は直線を塞ぐ障害物として置く
        let board  = boardOfMany(map, (0, {x = 0, y = 1}) :: Nil,
                                      (0, {x = 4, y = 1}) :: (1, {x = 3, y = 1}) :: Nil);
        let enemy  = enemyAt(0, {x = 4, y = 1}, true, 0, 3);
        let (a, _) = decide(board, targetsOf(board), enemy);
        Assert.assertEq(expected = ("Move", 4, 0), moveTo(a))

    // ════════════════════════════════════════════════════════
    // 評価軸の組み合わせ（辞書式ターゲット選択）: 仕留め > 反撃不能 > 低HP > 近さ
    //   開けた 12×12 部屋・弓敵 (5,5)・moveTiles 5 で「どの相手に・どう動くか」を pin。
    // ════════════════════════════════════════════════════════

    /// 仕留め最優先: 瀕死の相手は「反撃可能でも」最優先で攻撃する。
    /// 配置: 剣ローグ p0(7,5) 距離2・反撃不能・HP満タン / 弓P p1(5,3) 距離2・反撃可・瀕死(estDmg5≥hp2)。
    /// 期待: Killable が最優先なので、反撃される弓P(id1)を距離2で Attack。
    @Test
    def testKillablePreferredEvenIfCounterable(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let p0      = ({x = 7, y = 5}: {x = Int32, y = Int32});   // 剣・距離2・反撃不能
        let p1      = ({x = 5, y = 3}: {x = Int32, y = Int32});   // 弓・距離2・瀕死
        let board   = boardOfMany(map, (0, p0) :: (1, p1) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAtBow(9, enemyP, true, 0, 5);
        let targets = mkTarget(0, p0, 99, 0, swordRange())
                   :: mkTarget(1, p1, 2, 5, bowRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 1), (tagOf(a), attackId(a)))

    /// 攻撃優先: 射程内に相手が居れば、遠くの弱い相手を追わず「今攻撃できる相手」を攻撃する。
    /// 配置: 弓敵 (5,5)・射程内 p0(7,5) 距離2・HP10 / 遠くの瀕死 p1(5,10) 距離5・HP1（射程外）。
    /// 期待: 遠くの低HP p1 を追いかけず、射程内の p0(id0) を Attack（待機・素通りしない）。
    @Test
    def testRangedAttacksInRangeRatherThanChasingFarWeaker(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let pNear   = ({x = 7, y = 5}: {x = Int32, y = Int32});   // 距離2・射程内・HP10
        let pFar    = ({x = 5, y = 10}: {x = Int32, y = Int32});  // 距離5・射程外・HP1
        let board   = boardOfMany(map, (0, pNear) :: (1, pFar) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAtBow(9, enemyP, true, 0, 5);
        let targets = mkTarget(0, pNear, 10, 0, swordRange())
                   :: mkTarget(1, pFar, 1, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 0), (tagOf(a), attackId(a)))

    /// 接近後の射撃: 反撃不能な相手が距離2（射程内）に居れば、そのまま安全に Attack。
    /// （上のテストで接近した次のターン相当。）
    @Test
    def testRangedAttacksSafeTargetWhenInRange(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 6, y = 5}: {x = Int32, y = Int32});
        let pSword  = ({x = 8, y = 5}: {x = Int32, y = Int32});   // 距離2・反撃不能
        let board   = boardOfMany(map, (0, pSword) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAtBow(9, enemyP, true, 0, 5);
        let targets = mkTarget(0, pSword, 99, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 0), (tagOf(a), attackId(a)))

    /// 移動は「経路最寄りのプレイヤー」へ向かう（距離フィールド方式）。二者が経路距離で同じ
    /// （pA(8,5)・pB(5,8) とも距離3）なら、フィールド勾配の決定的タイブレーク（down 優先）で
    /// pB 方向へ 1 歩（pB までの距離が 3→2 に縮む）。
    /// 注: 旧仕様は評価軸の低HP で移動先を選んでいたが、移動先選定は最寄り（経路距離）基準に変更。
    /// 低HP/仕留め等の評価軸は「射程内に居る相手の攻撃選定」では引き続き効く（下の Attack 系テスト）。
    @Test
    def testRangedPrefersLowerHpAmongSafeTargets(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let pA      = ({x = 8, y = 5}: {x = Int32, y = Int32});   // 距離3・HP10
        let pB      = ({x = 5, y = 8}: {x = Int32, y = Int32});   // 距離3・HP4
        let board   = boardOfMany(map, (0, pA) :: (1, pB) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAtBow(9, enemyP, true, 0, 5);
        let targets = mkTarget(0, pA, 10, 0, swordRange())
                   :: mkTarget(1, pB, 4, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Move", 2), (tagOf(a), moveDistTo(a, pB)))

    /// 近さタイブレーク: 仕留め不可・反撃不能・HP も同じなら、近い相手を選ぶ。
    /// 配置: 剣 p0(8,5) 距離3 / 剣 p1(7,5) 距離2（射程内）。どちらも HP10。
    /// 期待: 近い p1(id1, 距離2)を選び、射程内なので Attack。
    @Test
    def testRangedPrefersNearerWhenOtherwiseTied(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let pFar    = ({x = 8, y = 5}: {x = Int32, y = Int32});   // 距離3
        let pNear   = ({x = 7, y = 5}: {x = Int32, y = Int32});   // 距離2
        let board   = boardOfMany(map, (0, pFar) :: (1, pNear) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAtBow(9, enemyP, true, 0, 5);
        let targets = mkTarget(0, pFar, 10, 0, swordRange())
                   :: mkTarget(1, pNear, 10, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 1), (tagOf(a), attackId(a)))

    /// 近接の敵も NoCounter を効かせる: 距離1で反撃できない弓兵を、HP の低い剣士より優先する。
    /// 配置: 剣敵 (5,5)・剣P p0(6,5) 隣接・HP5（距離1で反撃可）/ 弓P p1(5,6) 隣接・HP10（射程2で反撃不可）。
    /// 期待: 反撃不能 > 低HP なので、満タンでも反撃されない弓P(id1)を Attack。
    @Test
    def testMeleePrefersNoCounterTarget(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let pSword  = ({x = 6, y = 5}: {x = Int32, y = Int32});   // 隣接・HP5・反撃可
        let pBow    = ({x = 5, y = 6}: {x = Int32, y = Int32});   // 隣接・HP10・反撃不可
        let board   = boardOfMany(map, (0, pSword) :: (1, pBow) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAt(9, enemyP, true, 0, 3);             // testWeapon = 剣 1-1（近接）
        let targets = mkTarget(0, pSword, 5, 0, swordRange())
                   :: mkTarget(1, pBow, 10, 0, bowRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 1), (tagOf(a), attackId(a)))

    /// 近接（射程1）の敵も「弱い相手から優先」: 隣接する同武器の 2 体なら HP の低い方を攻撃する。
    /// 配置: 剣敵 (5,5)・剣P p0(6,5) HP8・剣P p1(5,6) HP3（どちらも隣接・反撃可）。
    /// 期待: 低HP の p1(id1) を Attack。
    @Test
    def testMeleeAttacksWeakerAdjacentFirst(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let p0      = ({x = 6, y = 5}: {x = Int32, y = Int32});   // 隣接・HP8
        let p1      = ({x = 5, y = 6}: {x = Int32, y = Int32});   // 隣接・HP3
        let board   = boardOfMany(map, (0, p0) :: (1, p1) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAt(9, enemyP, true, 0, 3);             // testWeapon = 剣 1-1（近接）
        let targets = mkTarget(0, p0, 8, 0, swordRange())
                   :: mkTarget(1, p1, 3, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 1), (tagOf(a), attackId(a)))

    /// 近接（射程1）の敵は、隣に攻撃できる相手が居れば、遠くの弱い相手を追わず隣を攻撃する。
    /// 配置: 剣敵 (5,5)・隣接 p0(6,5) HP9 / 遠くの瀕死 p1(5,8) 距離3・HP2。
    /// 期待: 遠くの低HP p1 を追わず、隣接の p0(id0) を Attack（攻撃を優先）。
    @Test
    def testMeleeAttacksAdjacentRatherThanChaseFarWeaker(): Unit \ Assert =
        let map     = singleRoomSnapshot(12, 12);
        let enemyP  = ({x = 5, y = 5}: {x = Int32, y = Int32});
        let p0      = ({x = 6, y = 5}: {x = Int32, y = Int32});   // 隣接・HP9
        let p1      = ({x = 5, y = 8}: {x = Int32, y = Int32});   // 距離3・HP2（射程外）
        let board   = boardOfMany(map, (0, p0) :: (1, p1) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAt(9, enemyP, true, 0, 3);
        let targets = mkTarget(0, p0, 9, 0, swordRange())
                   :: mkTarget(1, p1, 2, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Attack", 0), (tagOf(a), attackId(a)))

    /// 回帰: 低HP の相手が到達不能（壁の向こう）でも、敵は止まらず最寄りの相手へ近づく。
    /// 配置: x=2 を壁列で左右に分断。左に瀕死 p0(0,1) HP1（到達不能）/ 右に p1(3,1) HP10。
    ///       敵 (5,1) は右側。最良ターゲットは低HP の p0 だが経路が無い。
    /// 期待: Wait せず、最寄りで到達可能な p1 へ向かって Move（発見したら近づく挙動を保つ）。
    @Test
    def testChasesNearestWhenPreferredUnreachable(): Unit \ Assert =
        // 6×3 の床から x=2 の列を壁で抜いて左右を分断する
        let map     = roomSnapshotWhere(6, 3, c ->
            c#x >= 0 and c#x < 6 and c#y >= 0 and c#y < 3 and c#x != 2);
        let enemyP  = ({x = 5, y = 1}: {x = Int32, y = Int32});
        let p0      = ({x = 0, y = 1}: {x = Int32, y = Int32});   // 壁の向こう・HP1・到達不能
        let p1      = ({x = 3, y = 1}: {x = Int32, y = Int32});   // 同じ側・HP10・距離2
        let board   = boardOfMany(map, (0, p0) :: (1, p1) :: Nil, (9, enemyP) :: Nil);
        let enemy   = enemyAt(9, enemyP, true, 0, 3);            // 剣（近接）
        let targets = mkTarget(0, p0, 1, 0, swordRange())
                   :: mkTarget(1, p1, 10, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        // p1(3,1) へ 1 歩 → (4,1)。到達不能な p0 を選んで Wait しないことを確認。
        Assert.assertEq(expected = ("Move", 4, 1), moveTo(a))

    /// 通路口を別の敵が塞いで味方に到達できないときでも、敵は止まらず味方の方へ寄る。
    /// 配置: 左の 3×3 部屋 + y=1 の 1 マス幅通路で右へ。敵9(1,1) / 通路口を塞ぐ敵8(3,1) /
    ///       味方(5,1)。敵9 から味方への経路は (3,1) で塞がれ到達不能。
    /// 期待: Wait せず、味方に一番近づける (2,1) へ 1 歩寄る（通路口の手前まで詰める）。
    @Test
    def testApproachesTowardBlockedCorridorInsteadOfWaiting(): Unit \ Assert =
        // 左に 3×3 部屋、そこから y=1 の 1 マス幅通路で右(x=5)まで伸びる床
        let map     = roomSnapshotWhere(6, 3, c ->
            (c#x >= 0 and c#x <= 2 and c#y >= 0 and c#y <= 2)
                or (c#y == 1 and c#x >= 0 and c#x <= 5));
        let enemyP  = ({x = 1, y = 1}: {x = Int32, y = Int32});
        let playerP = ({x = 5, y = 1}: {x = Int32, y = Int32});
        // 敵 8(3,1) が通路口を塞ぐ。敵 9 から味方への経路は到達不能
        let board   = boardOfMany(map, (0, playerP) :: Nil,
                                       (9, enemyP) :: (8, {x = 3, y = 1}) :: Nil);
        let enemy   = enemyAt(9, enemyP, true, 0, 3);
        let targets = mkTarget(0, playerP, 10, 0, swordRange()) :: Nil;
        let (a, _)  = decide(board, targets, enemy);
        Assert.assertEq(expected = ("Move", 2, 1), moveTo(a))

    /// 角を曲がる: 前進にいったん manhattan 距離を増やす必要があるスパイラル/U字でも止まらない。
    /// 3×3・(1,0)(1,1) が壁の U 字。味方(0,0)・敵(2,0)。敵→味方の経路は下へ回り込む
    /// （(2,0)→(2,1)→(2,2)→(1,2)→(0,2)→(0,1)→(0,0)）。1 歩目 (2,1) は味方への manhattan が
    /// 2→3 と**増える**ため、純マンハッタン貪欲なら却下して凍結するが、距離フィールドは降下できる。
    ///   P # E   row0: P=(0,0) 壁(1,0) E=(2,0)
    ///   . # .   row1: 壁(1,1)
    ///   . . .   row2: 開通（ここを回る）
    @Test
    def testSpiralCornerDoesNotFreeze(): Unit \ Assert =
        // 3×3 から (1,0) と (1,1) を壁で抜いた U 字（row2 だけで左右がつながる）
        let map     = roomSnapshotWhere(3, 3, c ->
            c#x >= 0 and c#x < 3 and c#y >= 0 and c#y < 3
                and not (c#x == 1 and (c#y == 0 or c#y == 1)));
        let player  = ({x = 0, y = 0}: {x = Int32, y = Int32});
        let enemyP  = ({x = 2, y = 0}: {x = Int32, y = Int32});
        let board   = boardOf(map, player, 0, enemyP);
        let enemy   = enemyAt(0, enemyP, true, 0, 3);
        let (a, _)  = decide(board, targetsOf(board), enemy);
        // 凍結せず、回り込みの 1 歩目 (2,1) へ降下する（manhattan は 2→3 に増える）。
        Assert.assertEq(expected = ("Move", 2, 1), moveTo(a))

    // ════════════════════════════════════════════════════════
    // 辞書式比較ヘルパー lexGreater
    // ════════════════════════════════════════════════════════

    /// 先頭の要素で差がつけばそれで決定。先頭が同点なら次の要素で比較。完全同点は false。
    @Test
    def testLexGreaterComparesHeadFirst(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, false, true, false),
            (EnemyAI.lexGreater(1 :: 0 :: Nil, 0 :: 9 :: Nil),   // 先頭 1>0（後続無視）
             EnemyAI.lexGreater(0 :: 1 :: Nil, 1 :: 9 :: Nil),   // 先頭 0<1
             EnemyAI.lexGreater(1 :: 5 :: Nil, 1 :: 3 :: Nil),   // 先頭同点・次 5>3
             EnemyAI.lexGreater(1 :: 3 :: Nil, 1 :: 3 :: Nil)))  // 完全同点
}
