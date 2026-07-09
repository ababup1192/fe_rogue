// World のテスト — store の書込/読み出しセマンティクス（applyCmd・各 read-model アクセサ・
// refreshMirror・stepWorld）を World 単独（scene 非依存）で検証する。
// 駒 fixture が要るテストは TestWorldFixtures（playerCmds/enemyCmds/worldOf）を使う。

mod TestWorld {

    def playerData(id: Int32): PlayerDriver.Data = playerDataS(id, Nil)

    def playerDataS(id: Int32, statuses: List[StatusSystem.Status]): PlayerDriver.Data = {
        id                = id,
        statuses          = statuses,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Dir4.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = 0,
        pendingLevelUp    = None,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    def enemyData(id: Int32): EnemyDriver.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    // ── statuses store（applyCmd の直接セマンティクス）──

    def spdUp(mag: Int32, rem: Int32): StatusSystem.Status =
        {effect = StatusSystem.StatusEffect.SpdUp, magnitude = mag, remaining = rem}

    /// List[Status] 先頭の残ターン（無ければ -1）。
    def firstRem(xs: List[StatusSystem.Status]): Int32 =
        List.head(xs) |> Option.map(s -> s#remaining) |> Option.getWithDefault(-1)

    /// AddPlayer は付与する。同 effect 種別の再付与は増えず、**元の値が据え置かれる**（skip であって置換でない）。
    @Test
    def testApplyAddPlayerDedup(): Unit \ Assert =
        let w1 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        let w2 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(9, 9)), w1);  // 同 effect 再付与（skip される）
        let xs = World.playerStatusEffectsOf(0, w2);
        let mag = List.head(xs) |> Option.map(s -> s#magnitude) |> Option.getWithDefault(-1);
        Assert.assertEq(expected = (1, 2), (List.length(xs), mag))  // 1 件・残ったのは元の magnitude=2

    /// TickPlayers(ids) はリスト内 id のみ remaining を減らし、リスト外 id（usedStairs 相当）は不変。
    @Test
    def testApplyTickPlayersFilters(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(1), spdUp(2, 5)),
                   World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 5)), World.empty()));
        let w1 = World.applyCmd(World.Cmd.TickPlayers(0 :: Nil), w0);
        Assert.assertEq(
            expected = (4, 5),  // id0 は tick(5→4)、id1 はリスト外で不変(5)
            (firstRem(World.playerStatusEffectsOf(0, w1)), firstRem(World.playerStatusEffectsOf(1, w1))))

    /// TickEnemies は全敵を tick する（残4→3）。
    @Test
    def testApplyTickEnemies(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Enemy(5), spdUp(2, 4)), World.empty());
        let w1 = World.applyCmd(World.Cmd.TickEnemies, w0);
        Assert.assertEq(expected = 3, firstRem(World.enemyStatusEffectsOf(5, w1)))

    /// SeedPlayer は既存を完全置換する（replace 意味論）。immobilize を捨て spdUp だけになる。
    @Test
    def testApplySeedPlayerReplaces(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), StatusSystem.immobilizeFor(3)), World.empty());
        let w1 = World.applyCmd(World.Cmd.Seed(World.EntityRef.Player(0), spdUp(2, 7) :: Nil), w0);
        Assert.assertEq(
            expected = (1, false),  // 1 件・immobilize は消えている
            (List.length(World.playerStatusEffectsOf(0, w1)),
             StatusSystem.isImmobilized(World.playerStatusEffectsOf(0, w1))))

    /// ClearEnemyImmobilized は完全停止だけ解除する（clearImmobilized 再利用）。
    @Test
    def testApplyClearEnemyImmobilized(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Enemy(5), StatusSystem.immobilizeFor(3)), World.empty());
        let w1 = World.applyCmd(World.Cmd.ClearImmobilized(World.EntityRef.Enemy(5)), w0);
        Assert.assertEq(expected = false, StatusSystem.isImmobilized(World.enemyStatusEffectsOf(5, w1)))

    /// faction 隔離: AddPlayer は enemyStatuses を変えない。
    @Test
    def testApplyFactionIsolation(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        Assert.assertEq(
            expected = (1, 0),
            (List.length(World.playerStatusEffectsOf(0, w)), List.length(World.enemyStatusEffectsOf(0, w))))

    /// アクセサ既定は Nil（未登録 id＝mid-game spawn は seed 不要の根拠）。
    @Test
    def testStatusesOfDefaultNil(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true),
            (List.isEmpty(World.playerStatusEffectsOf(99, World.empty())),
             List.isEmpty(World.enemyStatusEffectsOf(99, World.empty()))))

    /// 統一アクセサ `statusEffectsOf(EntityRef)` が faction を判別する＝**味方 id0 と敵 id0 が衝突しない**
    /// （read seam が live＝Query handler が呼ぶ実体）。
    @Test
    def testStatusEffectsOfRoutesByFaction(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        // Player(0) には付与済み、同 id でも Enemy(0) は別エンティティで空。
        Assert.assertEq(
            expected = (1, 0),
            (List.length(World.statusEffectsOf(World.EntityRef.Player(0), w)),
             List.length(World.statusEffectsOf(World.EntityRef.Enemy(0), w))))

    /// Command/Query を **effect 経由で** end-to-end 検証（Game.start と同じ handler 配線）。
    /// emit した Cmd が worldRef へ即時適用され、Query で読み戻せる＝live な seam を守るテスト。
    @Test
    def testCommandQueryHandlersRoundTrip(): Unit \ Assert =
        let len = region rc {
            let worldRef = Ref.fresh(rc, World.empty());
            run {
                World.Command.emit(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 4)));
                List.length(World.StatusQuery.statusEffects(World.EntityRef.Player(0)))
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(worldRef)), worldRef); k() }
            } with handler World.StatusQuery {
                def statusEffects(ref, k) = k(World.statusEffectsOf(ref, Ref.get(worldRef)))
            }
        };
        Assert.assertEq(expected = 1, len)

    /// tickStatusEffects（StatusSystem.tick 再利用）で残ターンが 1 減る（残3→2）。
    @Test
    def testTickStatuses(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Seed(World.EntityRef.Player(0), StatusSystem.immobilizeFor(3) :: Nil), World.empty());
        let ticked = World.tickStatusEffects(seeded);
        Assert.assertEq(expected = 2, firstRem(World.playerStatusEffectsOf(0, ticked)))

    // ── faction タグ（team component）──

    /// A'（faction タグ）: `team` enum component が unified-id ごとに Player/Enemy を返す。
    /// `Cmd.Spawn` が team を書く唯一のサイト。faction は id 演算でなくこのタグで読む。
    @Test
    def testTeamTagComponent(): Unit \ Assert =
        let w = World.empty()
            |> World.applyCmd(World.Cmd.Spawn(World.EntityRef.Player(0)))
            |> World.applyCmd(World.Cmd.Spawn(World.EntityRef.Player(1)))
            |> World.applyCmd(World.Cmd.Spawn(World.EntityRef.Enemy(5)));
        Assert.assertEq(
            expected = (Some(Faction.Player), Some(Faction.Player),
                        Some(Faction.Enemy), true, true, None),
            (World.teamOf(0, w), World.teamOf(1, w),
             World.teamOf(5 + World.enemyUidBase(), w),
             World.isPlayerUid(0, w), World.isEnemyUid(5 + World.enemyUidBase(), w),
             World.teamOf(999, w)))

    // ── BoardSnapshot.piecesFromWorld（位置 read-model から Board.pieces を組む）──

    /// pieces を faction 別に id→(x,y) の Map へ畳む（record の == 不可のため tuple 化、順序非依存比較）。
    def playerPosMapOf(pieces: List[(Piece, {x = Int32, y = Int32})]): Map[Int32, (Int32, Int32)] =
        List.foldLeft((m, pair) -> { let (pc, p) = pair; match pc {
            case Piece.Player(id) => Map.insert(id, (p#x, p#y), m)
            case _                => m
        }}, Map.empty(), pieces)

    def enemyPosMapOf(pieces: List[(Piece, {x = Int32, y = Int32})]): Map[Int32, (Int32, Int32)] =
        List.foldLeft((m, pair) -> { let (pc, p) = pair; match pc {
            case Piece.Enemy(id) => Map.insert(id, (p#x, p#y), m)
            case _               => m
        }}, Map.empty(), pieces)

    /// piecesFromWorld が World 位置から正しい駒を組む：hidden 味方（`Cmd.SetHidden`）を除外、
    /// 非 hidden 味方／敵は残る（順序非依存）。
    @Test
    def testPiecesFromWorldFiltersHidden(): Unit \ Assert =
        let world = World.empty()
            |> World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 2, y = 2}))
            |> World.applyCmd(World.Cmd.Move(World.EntityRef.Player(3), {x = 9, y = 9}))
            |> World.applyCmd(World.Cmd.SetHidden(World.EntityRef.Player(3), true))
            |> World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 2}));
        let pieces = World.boardPieces(world);
        Assert.assertEq(
            expected = (Map#{0 => (2, 2)}, Map#{5 => (3, 2)}),
            (playerPosMapOf(pieces), enemyPosMapOf(pieces)))

    // ── World.Cmd applier（statuses 権威化の System/command。StatusSystem 再利用）──

    /// tripwire: 主人公が **mid-frame に prev→now と動いた**直後、`Cmd.Move` を適用すると
    /// BoardQuery が返す盤面（= `World.boardOf` → `boardPieces`）は **now を反映**し、stale な prev を返さない。
    ///
    /// これは gather が「主人公位置を prev→now に是正する」根拠そのもの。
    /// `Cmd.Move` を `applyCmd`／`playerPos` ストアに配線し損ねる（または `boardPieces` が別ストアを読む）と、
    /// `before==after==prev` になりこのテストが赤くなる＝手動 run 前に回帰を機械検出できる。
    @Test
    def testMoveReflectsNewPosInBoardMidFrame(): Unit \ Assert =
        let now = ({x = 5, y = 5}: {x = Int32, y = Int32});
        // frame-head: 主人公(player 0)を {2,2} に置く。
        let w0 = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 2, y = 2}), World.empty());
        // mid-frame: 主人公が now へ移動 → Cmd.Move を World に即時適用。
        let w1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), now), w0);
        let posOf0 = w -> Map.get(0, playerPosMapOf(World.boardPieces(w)));
        // before は frame-head の prev {2,2}、after は now {5,5}（prev のままなら配線漏れ）。
        Assert.assertEq(expected = (Some((2, 2)), Some((5, 5))), (posOf0(w0), posOf0(w1)))

    // ── spawn/restore funnel が新規ユニットの位置を World へ seed ──

    /// tripwire: `addOnePlayer`（spawn/restore の funnel）が新規ユニットの初期位置を
    /// World へ seed する（`Cmd.Move` を emit）。emit を applyCmd で worldRef に積み、
    /// `boardPieces` に id 7 @ (3,4) が現れることを確認する。funnel の emit 行を消す回帰で赤になる。
    @Test
    def testAddOnePlayerSeedsPositionToWorld(): Unit \ Assert =
        let sp = ({id = 7, classId = "test_player", gridPos = {x = 3, y = 4},
                    resource = TestUnitFixtures.testResource(4, 10),
                    weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        let world = region rc {
            let ref = Ref.fresh(rc, World.empty());
            run {
                PlayerDriver.addOnePlayer(sp)
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(ref)), ref); k() }
            };
            Ref.get(ref)
        };
        Assert.assertEq(expected = Some((3, 4)), Map.get(7, playerPosMapOf(World.boardPieces(world))))

    // ── refreshMirror（毎フレーム段。tick を進める以外は素通し）──

    /// 要: `refreshMirror` は位置 store を素通しする（tick を進めるだけ）。`Cmd.Move` で書いた位置は
    /// refreshMirror を挟んでも変わらないことを pin する回帰ガード。
    @Test
    def testRefreshMirrorKeepsCommandPosNotGridPos(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty());
        let refreshed = World.refreshMirror(seeded);
        let World.World(w) = refreshed;
        Assert.assertEq(expected = Some((5, 5)), Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)))

    /// ghost piece 防止は refreshMirror の prune ではなく **Cmd.Despawn**（ノード除去サイトが emit）。
    /// enemy 99 を Despawn すると pos から消え、player 0 は残ることを pin。
    @Test
    def testDespawnRemovesEntityFromStores(): Unit \ Assert =
        let s1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(99), {x = 9, y = 9}),
                 World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let World.World(w) = World.applyCmd(World.Cmd.Despawn(World.EntityRef.Enemy(99)), s1);
        Assert.assertEq(
            expected = (Some((5, 5)), None),
            (Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)),
             Map.get(99 + World.enemyUidBase(), w#pos) |> Option.map(p -> (p#x, p#y))))

    /// hp は `Cmd.SetHp` の値をそのまま保持する。refreshMirror を挟んでも書いた値のまま
    /// （player 0 = 3・player 1 = 未変更の 10・playerIds は Spawn で登録した集合のまま）。
    @Test
    def testRefreshMirrorPreservesCommandHp(): Unit \ Assert =
        let seeded = World.empty()
            |> World.applyCmd(World.Cmd.Spawn(World.EntityRef.Player(0)))
            |> World.applyCmd(World.Cmd.Spawn(World.EntityRef.Player(1)))
            |> World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 10))
            |> World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(1), 10));
        let damaged = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 3), seeded);
        let World.World(w) = World.refreshMirror(damaged);
        Assert.assertEq(
            expected = (Some(3), Some(10), Set#{0, 1}),
            (Map.get(0, w#hp), Map.get(1, w#hp), w#playerIds))

    // ── dataFromWorld / dataFromWorldEnemy の field pin（各 field が対応する store をそのまま返す）──

    /// dataFromWorld(0) の core field は対応する Cmd の値をそのまま返す：hp は `SetHp` 由来の 3
    /// （spawn 直後の 10 に戻らない）、classId は spawn 時に seed した "test_player" のまま。
    @Test
    def testDataFromWorldReadsWorldAuthorityForCore(): Unit \ Assert =
        let seeded  = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2})));
        let damaged = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 3), seeded);
        let recon   = World.dataFromWorld(0, damaged);
        Assert.assertEq(
            expected = Some((3, "test_player")),
            recon |> Option.map(d -> (d#hp, d#classId)))

    /// dataFromWorldEnemy 版: hp は `SetHp` 由来の 3、resourceId は spawn 時に seed した "test_enemy" のまま。
    @Test
    def testDataFromWorldEnemyReadsWorldAuthorityForCore(): Unit \ Assert =
        let seeded  = TestWorldFixtures.worldOf(TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(5, {x = 3, y = 2})));
        let damaged = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Enemy(5), 3), seeded);
        let recon   = World.dataFromWorldEnemy(5, damaged);
        Assert.assertEq(
            expected = Some((3, "test_enemy")),
            recon |> Option.map(d -> (d#hp, d#resourceId)))

    /// field-complete（bottleUsed）: bottleUsed の権威は World 単独。spawn 直後の false から
    /// `SetBottleUsed` で true にすると `dataFromWorldEnemy` がその true をそのまま返すことを pin。
    @Test
    def testDataFromWorldEnemyBottleUsedIsWorldAuthority(): Unit \ Assert =
        let seeded  = TestWorldFixtures.worldOf(TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(5, {x = 3, y = 2})));
        let thrown  = World.applyCmd(World.Cmd.SetBottleUsed(World.EntityRef.Enemy(5), true), seeded);
        Assert.assertEq(
            expected = Some(true),
            World.dataFromWorldEnemy(5, thrown) |> Option.map(d -> d#bottleUsed))

    /// field-complete（followUpUsed）: followUpUsed は World 単独権威。spawn 直後の false から
    /// `SetFollowUpUsed` で true にすると `dataFromWorld` がその true を返すことを pin。
    @Test
    def testDataFromWorldFollowUpUsedIsWorldAuthority(): Unit \ Assert =
        let seeded = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2})));
        let used   = World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(0), true), seeded);
        Assert.assertEq(
            expected = Some(true),
            World.dataFromWorld(0, used) |> Option.map(d -> d#followUpUsed))

    /// field-complete（prevPos）: prevPos は World 単独権威。`SetPrevPos` で書いた座標が
    /// `dataFromWorldEnemy` にそのまま反映されることを pin。
    @Test
    def testDataFromWorldEnemyPrevPosIsWorldAuthority(): Unit \ Assert =
        let seeded = TestWorldFixtures.worldOf(TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(5, {x = 3, y = 2})));
        let moved  = World.applyCmd(World.Cmd.SetPrevPos(World.EntityRef.Enemy(5), {x = 7, y = 8}), seeded);
        Assert.assertEq(
            expected = Some(Some((7, 8))),
            World.dataFromWorldEnemy(5, moved) |> Option.map(d -> Option.map(p -> (p#x, p#y), d#prevPos)))

    /// `enemyIdAt`（RosterQuery.findIdAt の World 版）は pos から coord 上の非瀕死敵 id を引く。
    /// {3,3}=敵5・{4,4}=敵7・空きマス=None、敵5 を dying にすると {3,3}=None（isDying 除外）。
    @Test
    def testEnemyIdAtReadsWorldPosExcludingDying(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3}), World.empty());
        let w1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(7), {x = 4, y = 4}), w0);
        let w2 = World.applyCmd(World.Cmd.SetDying(World.EntityRef.Enemy(5)), w1);
        Assert.assertEq(
            expected = (Some(5), Some(7), (None: Option[Int32]), (None: Option[Int32])),
            (World.enemyIdAt({x = 3, y = 3}, w1), World.enemyIdAt({x = 4, y = 4}, w1),
             World.enemyIdAt({x = 9, y = 9}, w1), World.enemyIdAt({x = 3, y = 3}, w2)))

    // ── payoff デモ: 位置の決定論（World は Cmd.Move ログの純粋関数）──
    // World が位置の権威・唯一の source は `Cmd.Move` のログ。
    // ゆえに「同じログ → 同じ位置」が成り立ち、save/replay の素地（World さえ持てば位置を再構築できる）になる。

    /// 共通のサンプル command ログ（移動の履歴）。
    def sampleMoveLog(): List[World.Cmd] =
        World.Cmd.Move(World.EntityRef.Player(0), {x = 1, y = 1})
            :: World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3})
            :: World.Cmd.Move(World.EntityRef.Player(0), {x = 2, y = 2}) :: Nil

    /// ログを空 World に畳んで replay する。
    def replayLog(log: List[World.Cmd]): World =
        List.foldLeft((w, c) -> World.applyCmd(c, w), World.empty(), log)

    /// テスト用: World から EntityRef の位置を引く（単体 pos アクセサは prod では使わない＝BoardQuery 経由
    /// で読むため、ここに test-local で置く）。
    def worldPosOf(ref: World.EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; Map.get(World.toUid(ref), w#pos)

    /// determinism: World 位置は `Cmd.Move` ログの**純粋関数**。最終位置は「最後の Move 勝ち」
    /// （player 0 は {1,1}→{2,2}）。**同じログを独立に2回 replay すると同一**＝決定論リプレイの素地。
    @Test
    def testCommandLogReplayIsDeterministic(): Unit \ Assert =
        let log = sampleMoveLog();
        let tup = (ref, w) -> worldPosOf(ref, w) |> Option.map(p -> (p#x, p#y));
        let w1 = replayLog(log);
        let w2 = replayLog(log);
        Assert.assertEq(
            expected = (Some((2, 2)), Some((3, 3)), Some((2, 2)), Some((3, 3))),
            (tup(World.EntityRef.Player(0), w1), tup(World.EntityRef.Enemy(5), w1),
             tup(World.EntityRef.Player(0), w2), tup(World.EntityRef.Enemy(5), w2)))

    /// save/load の素地: ログから replay した World 位置を **`(id, x, y)` 列にシリアライズ→復元**しても
    /// 位置が round-trip する（World.pos は単純な component-map ＝そのまま保存可能）。
    /// EcsCodec の store 封筒（Map[EntityId, c]）にそのまま載る形であることをデモする。
    @Test
    def testWorldPosRoundTripsThroughSerialization(): Unit \ Assert =
        let World.World(w) = replayLog(sampleMoveLog());
        // "save": pos（単一 store）を (id, x, y) のフラット列へ。
        let saved = Map.foldRightWithKey((id, c, acc) -> (id, c#x, c#y) :: acc, Nil, w#pos);
        // "load": 列から pos を復元。
        let loaded = List.foldLeft((m, t) -> { let (id, x, y) = t;
            Map.insert(id, ({x = x, y = y}: {x = Int32, y = Int32}), m) }, Map.empty(), saved);
        let toTuples = m -> Map.foldRightWithKey((id, c, acc) -> (id, c#x, c#y) :: acc, Nil, m);
        Assert.assertEq(expected = toTuples(w#pos), toTuples(loaded))

    // ── System パイプライン段 stepWorld ──

    /// 不変条件: `stepWorld`（現状 inert な `tickStatusEffects` のみ）は **位置を変えない**。
    /// World が位置権威で scene gridPos はその派生ゆえ、stepWorld が pos を保つ限り render は不変
    /// ＝挙動不変。System を足して pos を壊す回帰で赤になる。
    @Test
    def testStepWorldPreservesPositions(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3}),
                     World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let (stepped, _moved) = World.stepWorld(seeded, 0.0);
        let tup = ref -> worldPosOf(ref, stepped) |> Option.map(p -> (p#x, p#y));
        Assert.assertEq(
            expected = (Some((5, 5)), Some((3, 3))),
            (tup(World.EntityRef.Player(0)), tup(World.EntityRef.Enemy(5))))

    /// `stepWorld` は移動（Position tween）の補間結果を `moved`（EntityRef＋pixel）で返す。
    /// **完了フレームでも moved に含まれる**（active∪done）ので、marker を target に取りこぼしなく置ける
    /// ＝敵の武器アイコン 1 フレームラグ修正の要。中点で中間 pixel（x=50）、完了で target（x=100）＋移動終了を確認する。
    @Test
    def testStepWorldReportsMovedThroughCompletion(): Unit \ Assert =
        // Player(0) を (0,0)→(100,0) へ 1 秒で滑らせる Position tween を開始する。
        let seeded = World.applyCmd(
            World.Cmd.StartTween(World.EntityRef.Player(0), Channel.Position,
                EcsTween.Track.Vec({start = {x = 0.0, y = 0.0}, target = {x = 100.0, y = 0.0}}),
                1.0, EcsTween.Easing.Linear, false),
            World.empty());
        // 0.5 秒進める（中点 x=50・移動中）→ さらに 0.5 秒で完了（x=100・移動終了）。
        let (mid, movedMid) = World.stepWorld(seeded, 0.5);
        let (fin, movedFin) = World.stepWorld(mid, 0.5);
        let xOf      = w -> World.renderPosOf(World.EntityRef.Player(0), w) |> Option.map(p -> p#x);
        let movedUid = ms -> match ms {
            case m :: Nil => World.toUid(m#ref)
            case _        => bug!("expected exactly one moved entity")
        };
        Assert.assertEq(
            expected = (Some(50.0),  true,  0,
                        Some(100.0), false, 0),
            (xOf(mid), World.isAnimating(World.EntityRef.Player(0), mid), movedUid(movedMid),
             xOf(fin), World.isAnimating(World.EntityRef.Player(0), fin), movedUid(movedFin)))

    // ── 背景タイルの World 権威化（bake ハンドル preserve と gen bump）──

    /// setTileLayers した描画ハンドルが stepWorld（identity）を経ても残る（rebuild イベント間 World 権威で保持）。
    @Test
    def testTileLayersPreservedThroughStep(): Unit \ Assert =
        let handle = ({textureName = "atlas", tileSize = 26.0, worldPos = {x = 0.0, y = 0.0},
                       color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}, zIndex = -1,
                       tileVaoId = 7, tileCount = 42}: TileLayerHandle);
        let (stepped, _moved) = World.stepWorld(World.setTileLayers(handle :: Nil, World.empty()), 0.0);
        match World.tileLayersOf(stepped) {
            case h :: Nil => Assert.assertEq(expected = (7, 42), (h#tileVaoId, h#tileCount))
            case _        => bug!("expected exactly 1 tile layer preserved")
        }

    /// `Cmd.SetTileLayers` がタイルハンドル store を差し替える（build choke の seed の根拠）。
    @Test
    def testSetTileLayersCmdReplacesStore(): Unit \ Assert =
        let handle: TileLayerHandle = {textureName = "t", tileSize = 16.0,
            worldPos = {x = 0.0, y = 0.0}, color = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            zIndex = 0, tileVaoId = 7, tileCount = 3};
        let w1 = World.applyCmd(World.Cmd.SetTileLayers(handle :: Nil), World.empty());
        let w2 = World.applyCmd(World.Cmd.SetTileLayers(Nil), w1);
        Assert.assertEq(expected = (1, 0),
            (List.length(World.tileLayersOf(w1)), List.length(World.tileLayersOf(w2))))

    // ── turn FSM の World 権威（19-case TurnPhase.Phase）──

    /// 既定は PlayerCursor・`Cmd.SetPhase`/`turnPhaseOf` が round-trip する。
    @Test
    def testTurnPhaseRoundTrips(): Unit \ Assert =
        let after = World.applyCmd(World.Cmd.SetPhase(TurnPhase.Phase.EnemyTurn), World.empty());
        Assert.assertEq(
            expected = (TurnPhase.Phase.PlayerCursor, TurnPhase.Phase.EnemyTurn),
            (World.turnPhaseOf(World.empty()), World.turnPhaseOf(after)))

    /// 不変条件: `refreshMirror`（毎フレーム）は turnPhase を**保持**する（tick を進めるだけの段だから）。
    @Test
    def testRefreshMirrorPreservesTurnPhase(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.SetPhase(TurnPhase.Phase.EnemyTurn), World.empty());
        let refreshed = World.refreshMirror(seeded);
        Assert.assertEq(expected = TurnPhase.Phase.EnemyTurn, World.turnPhaseOf(refreshed))

    /// `Cmd.SetPhase` が World.turnPhase（19-case 権威）を command で更新する（TurnPhase.State facade が put 時に書く）。
    @Test
    def testSetPhaseCommandUpdatesTurnPhase(): Unit \ Assert =
        let after = World.applyCmd(World.Cmd.SetPhase(TurnPhase.Phase.EnemyTurn), World.empty());
        Assert.assertEq(expected = TurnPhase.Phase.EnemyTurn, World.turnPhaseOf(after))

    /// `Cmd.SetAlerted` が World の enemyAlerted を更新し `alertedOf` で読める（flag は World 権威）。
    @Test
    def testSetAlertedCommandUpdatesWorld(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), World.empty());
        Assert.assertEq(expected = Some(true), World.alertedOf(World.EntityRef.Enemy(5), w))

    /// `Cmd.SetWaited` が World を更新し `waitedOf` で読める＋refreshMirror を挟んでも保持される。
    @Test
    def testSetWaitedCommandAndPreserve(): Unit \ Assert =
        let acted = World.applyCmd(World.Cmd.SetWaited(World.EntityRef.Player(0), true), World.empty());
        let World.World(w) = World.refreshMirror(acted);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.waitedOf(World.EntityRef.Player(0), acted), Map.get(0, w#playerWaited)))

    /// `Cmd.SetAttackTarget`/`ClearAttackTarget` が World を更新し `attackTargetOf` で読める＋preserve。
    /// `anyPlayerAttacking`/`anyEnemyAttacking`（driver の順序非依存判定の本体）も同時に検証。
    @Test
    def testSetAttackTargetCommandAndPreserve(): Unit \ Assert =
        let set = World.empty()
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Player(0), 5))
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Enemy(5), 0));
        let World.World(w) = World.refreshMirror(set);
        Assert.assertEq(
            expected = (Some(5), Some(0), true, true),
            (World.attackTargetOf(World.EntityRef.Player(0), set),
             Map.get(5 + World.enemyUidBase(), w#attackTarget),
             World.anyPlayerAttacking(set),
             World.anyEnemyAttacking(set)))

    /// `ClearAttackTarget` で対象が消え、`anyXAttacking` が false に戻る。
    @Test
    def testClearAttackTargetRemovesAndPredicateFalse(): Unit \ Assert =
        let cleared = World.empty()
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Player(0), 5))
            |> World.applyCmd(World.Cmd.ClearAttackTarget(World.EntityRef.Player(0)));
        Assert.assertEq(
            expected = (None, false),
            (World.attackTargetOf(World.EntityRef.Player(0), cleared),
             World.anyPlayerAttacking(cleared)))

    /// World 拡張: `Cmd.SetProgress` が味方の (level, exp) を更新し `progressOf` で読める＋preserve。
    /// Enemy は no-op（常に None）。
    @Test
    def testSetProgressCommandAndPreserve(): Unit \ Assert =
        let leveled = World.empty()
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Player(0), 3, 40))
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Enemy(5), 9, 99));  // no-op
        let kept = World.refreshMirror(leveled);
        Assert.assertEq(
            expected = (Some((3, 40)), None, Some((3, 40))),
            (World.progressOf(World.EntityRef.Player(0), leveled),
             World.progressOf(World.EntityRef.Enemy(5), leveled),
             World.progressOf(World.EntityRef.Player(0), kept)))

    /// `Cmd.SetDying` が敵を World の dying set に入れ `isDyingOf` で読める＋preserve。
    /// Player は no-op（常に false）。
    @Test
    def testSetDyingCommandAndPreserve(): Unit \ Assert =
        let dying = World.empty()
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Enemy(5)))
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Player(0)));  // no-op
        let kept = World.refreshMirror(dying);
        Assert.assertEq(
            expected = (true, false, true),
            (World.isDyingOf(World.EntityRef.Enemy(5), dying),
             World.isDyingOf(World.EntityRef.Player(0), dying),
             World.isDyingOf(World.EntityRef.Enemy(5), kept)))

    /// `Cmd.SetEnemyTurnBusy`/`SetPhaseObservedEnemy` が scalar bool を更新し読める＋refreshMirror で保持。
    @Test
    def testSetTopBarBoolsCommandAndPreserve(): Unit \ Assert =
        let set = World.empty()
            |> World.applyCmd(World.Cmd.SetEnemyTurnBusy(true))
            |> World.applyCmd(World.Cmd.SetPhaseObservedEnemy(true));
        let kept = World.refreshMirror(set);
        Assert.assertEq(
            expected = (true, true, true, true),
            (World.enemyTurnBusyOf(set), World.phaseObservedEnemyOf(set),
             World.enemyTurnBusyOf(kept), World.phaseObservedEnemyOf(kept)))

    /// `Cmd.SetFollowUpUsed` が両 faction を更新し読める＋preserve。
    @Test
    def testSetFollowUpUsedCommandAndPreserve(): Unit \ Assert =
        let used = World.empty()
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(0), true))
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(5), true));
        let World.World(w) = World.refreshMirror(used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (Map.get(0, w#followUpUsed), Map.get(5 + World.enemyUidBase(), w#followUpUsed)))

    /// `Cmd.SetPrevPos` が World を更新し `prevPosOf` で読める＋preserve。
    @Test
    def testSetPrevPosCommandAndPreserve(): Unit \ Assert =
        let moved = World.applyCmd(World.Cmd.SetPrevPos(World.EntityRef.Enemy(5), {x = 7, y = 1}), World.empty());
        let World.World(w) = World.refreshMirror(moved);
        let toT = op -> Option.map(p -> (p#x, p#y), op);
        Assert.assertEq(
            expected = (Some((7, 1)), Some((7, 1))),
            (toT(World.prevPosOf(World.EntityRef.Enemy(5), moved)), toT(Map.get(5 + World.enemyUidBase(), w#prevPos))))

    /// `Cmd.SetBottleUsed` が World を更新し `bottleUsedOf` で読める＋preserve。
    @Test
    def testSetBottleUsedCommandAndPreserve(): Unit \ Assert =
        let used = World.applyCmd(World.Cmd.SetBottleUsed(World.EntityRef.Enemy(5), true), World.empty());
        let World.World(w) = World.refreshMirror(used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.bottleUsedOf(World.EntityRef.Enemy(5), used), Map.get(5 + World.enemyUidBase(), w#enemyBottleUsed)))

    /// alerted は `Cmd.SetAlerted` の値をそのまま保持する（refreshMirror を挟んでも変わらない）。
    @Test
    def testRefreshMirrorPreservesCommandAlerted(): Unit \ Assert =
        let alerted = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), World.empty());
        let World.World(w) = World.refreshMirror(alerted);
        Assert.assertEq(expected = Some(true), Map.get(5 + World.enemyUidBase(), w#enemyAlerted))

    /// `Cmd.SetHp` が World の hp store を faction 別に更新し、`hpOf` で読める（hp は World 権威）。
    @Test
    def testSetHpCommandUpdatesWorldHp(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 7),
                World.applyCmd(World.Cmd.SetHp(World.EntityRef.Enemy(5), 3), World.empty()));
        Assert.assertEq(
            expected = (Some(7), Some(3)),
            (World.hpOf(World.EntityRef.Player(0), w), World.hpOf(World.EntityRef.Enemy(5), w)))

    // ── baseStats（stats + maxHp）store（command-derive・preserve）──

    /// applyCmd(SetBaseStats) が baseStats store を更新する（両 faction）。baseStatsOf で読み戻し、
    /// record Eq 非自動ゆえ 8-tuple に射影して比較する。
    @Test
    def testApplySetBaseStatsUpdatesStore(): Unit \ Assert =
        let bs = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4,
                   skill = 5, speed = 6, luck = 7, maxHp = 99}: Combat.BaseStats);
        let toTup = b -> (b#attack, b#magicAttack, b#defense, b#magicDefense, b#skill, b#speed, b#luck, b#maxHp);
        let wP = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Player(0), bs), World.empty());
        let wE = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Enemy(5), bs), World.empty());
        Assert.assertEq(
            expected = (Some((1, 2, 3, 4, 5, 6, 7, 99)), Some((1, 2, 3, 4, 5, 6, 7, 99))),
            (Option.map(toTup, World.baseStatsOf(World.EntityRef.Player(0), wP)),
             Option.map(toTup, World.baseStatsOf(World.EntityRef.Enemy(5), wE))))

    /// `Combat.baseStatsFrom` で組んだ baseStats（maxHp=resource#hp）を SetBaseStats で書くと
    /// refreshMirror を挟んでも保持される。
    @Test
    def testRefreshMirrorPreservesBaseStats(): Unit \ Assert =
        let res = TestUnitFixtures.testResource(4, 10);
        let seeded    = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Player(0), Combat.baseStatsFrom(res)), World.empty());
        let refreshed = World.refreshMirror(seeded);
        Assert.assertEq(
            expected = Some(10),
            Option.map(bs -> bs#maxHp, World.baseStatsOf(World.EntityRef.Player(0), refreshed)))

    // ── weapons store（command-derive・preserve+prune）──

    /// applyCmd(SetWeapons) が weapons store を更新する。weaponsOf で読み戻し、record Eq 非自動ゆえ
    /// (長さ, 先頭耐久) に射影して比較する（具体値 pin・test 本体に match を書かない）。
    @Test
    def testApplySetWeaponsUpdatesStore(): Unit \ Assert =
        let ws = TestUnitFixtures.testWeaponFull(2, 5) :: TestUnitFixtures.testWeaponFull(3, 9) :: Nil;
        let w  = World.applyCmd(World.Cmd.SetWeapons(World.EntityRef.Player(0), ws), World.empty());
        let proj = World.weaponsOf(World.EntityRef.Player(0), w)
            |> Option.map(xs -> (List.length(xs), List.head(xs) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((2, Some(5))), proj)

    // weapons は World 単独権威（scene 側の複製は持たない）。write/read は本テストと
    // dataFromWorld 系テストが担う。

    // ── weaponView / ringBonus store（command-derive・両 faction・preserve+prune）──

    /// SetWeaponView で書いた投影が refreshMirror を挟んでも保持される（具体値: testWeapon の attack=2）。
    @Test
    def testRefreshMirrorPreservesCommandWeaponView(): Unit \ Assert =
        let seeded    = World.applyCmd(World.Cmd.SetWeaponView(World.EntityRef.Player(0),
                            Combat.weaponView(Some(TestUnitFixtures.testWeapon()), true)), World.empty());
        let refreshed = World.refreshMirror(seeded);
        Assert.assertEq(
            expected = Some(2),
            Option.map(wv -> wv#attack, World.weaponViewOf(World.EntityRef.Player(0), refreshed)))

    /// SetRingBonus で書いた補正が refreshMirror を挟んでも保持される（attack=77 の具体値 pin）。
    @Test
    def testRefreshMirrorPreservesCommandRingBonus(): Unit \ Assert =
        let custom    = ({attack = 77 | Ring.zeroBonuses()}: Ring.Bonuses);
        let withCmd   = World.applyCmd(World.Cmd.SetRingBonus(World.EntityRef.Player(0), custom), World.empty());
        let refreshed = World.refreshMirror(withCmd);
        Assert.assertEq(
            expected = Some(77),
            Option.map(rb -> rb#attack, World.ringBonusOf(World.EntityRef.Player(0), refreshed)))

    // ── moveTiles store（command-derive・両 faction・preserve+prune）──

    /// applyCmd(SetMoveTiles) が moveTiles store を更新する（Int32 ゆえ直接比較）。
    @Test
    def testApplySetMoveTilesUpdatesStore(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetMoveTiles(World.EntityRef.Player(0), 7), World.empty());
        Assert.assertEq(expected = Some(7), World.moveTilesOf(World.EntityRef.Player(0), w))

    /// SetMoveTiles で書いた値が refreshMirror を挟んでも保持される。
    @Test
    def testRefreshMirrorPreservesCommandMoveTiles(): Unit \ Assert =
        let withCmd   = World.applyCmd(World.Cmd.SetMoveTiles(World.EntityRef.Player(0), 99), World.empty());
        let refreshed = World.refreshMirror(withCmd);
        Assert.assertEq(expected = Some(99), World.moveTilesOf(World.EntityRef.Player(0), refreshed))

    // ── staves/consumables/rings/ringEquipped store（command-derive・player-only・preserve+prune）──

    def d4Staff(): Staff.StaffResource = {
        name       = "テスト杖", effect = Staff.StaffEffect.Heal, durability = 3, weight = 0.75,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                        scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
        description = "", effectRule = None
    }
    def d4Consumable(): Consumable.ConsumableResource = {
        name = "きずぐすり", effect = Consumable.ConsumableEffect.Heal, magnitude = 10, duration = 0,
        healAmount = 10, durability = 5, weight = 0.5,
        sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                    scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
        description = "", effectRule = None
    }
    def d4Ring(): Ring.RingResource = {
        name = "ちからの指輪", effect = Ring.RingEffect.Power, power = 3, weight = 0.4,
        sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                    scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
        description = "", effectRule = None
    }

    /// applyCmd(SetStaves) が staves store を更新する。stavesOf で読み戻し、(長さ, 先頭耐久) に射影。
    @Test
    def testApplySetStavesUpdatesStore(): Unit \ Assert =
        let xs = d4Staff() :: d4Staff() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.stavesOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((2, Some(3))), proj)

    /// SetStaves は player-only（Enemy は no-op）＝stavesOf(Enemy) は None。
    @Test
    def testStavesEnemyIsNone(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Enemy(5), d4Staff() :: Nil), World.empty());
        Assert.assertEq(expected = None, World.stavesOf(World.EntityRef.Enemy(5), w) |> Option.map(List.length))

    // staves も World 単独権威。write/read は本テストが担う。

    /// applyCmd(SetConsumables) が consumables store を更新する。
    @Test
    def testApplySetConsumablesUpdatesStore(): Unit \ Assert =
        let xs = d4Consumable() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetConsumables(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.consumablesOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((1, Some(5))), proj)

    /// applyCmd(SetRings) が rings store を更新する。(長さ, 先頭 power) 射影で pin。
    @Test
    def testApplySetRingsUpdatesStore(): Unit \ Assert =
        let xs = d4Ring() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetRings(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.ringsOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#power)));
        Assert.assertEq(expected = Some((1, Some(3))), proj)

    /// applyCmd(SetRingEquipped) が ringEquipped store を更新する（Bool・player-only）。
    @Test
    def testApplySetRingEquippedUpdatesStore(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetRingEquipped(World.EntityRef.Player(0), true), World.empty());
        Assert.assertEq(expected = Some(true), World.ringEquippedOf(World.EntityRef.Player(0), w))

    /// `equippedRingOf` は rings/ringEquipped store から導出する。store に ring＋装備 true を積むと、
    /// refreshMirror を挟んでも store 由来の Some(ring) を返し続けることを pin する。
    @Test
    def testRefreshMirrorDerivesEquippedRingFromStore(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.SetRingEquipped(World.EntityRef.Player(0), true),
                     World.applyCmd(World.Cmd.SetRings(World.EntityRef.Player(0), d4Ring() :: Nil), World.empty()));
        let after = World.refreshMirror(seeded);
        let proj = World.equippedRingOf(World.EntityRef.Player(0), after) |> Option.map(r -> r#power);
        Assert.assertEq(expected = Some(3), proj)

    /// SetStaves で積んだ 1 本が refreshMirror を挟んでも保持される。
    @Test
    def testRefreshMirrorPreservesCommandStaves(): Unit \ Assert =
        let withStaff = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Player(0), d4Staff() :: Nil), World.empty());
        let refreshed = World.refreshMirror(withStaff);
        Assert.assertEq(
            expected = Some(1),
            World.stavesOf(World.EntityRef.Player(0), refreshed) |> Option.map(List.length))

    // ── combatViewOf（baseStats/hp/ringBonus/weaponView/statuses から CombatView を組む）──

    /// 戦闘 8 field を埋めた代表 WeaponView。record 部分上書きで 1 field だけ違える基点。
    def wvSample(): Combat.WeaponView =
        {weaponType = WeaponCatalog.WeaponType.Sword, attack = 5, hit = 80, crit = 0,
         isPhysical = true, proficient = true,
         effect = WeaponCatalog.WeaponEffect.NoEffect, effectValue = 0}

    /// combatViewOf が `Combat.assembleView` と同一の組立を通ることを、状態異常 active な駒で確認する
    /// （SpdDown を 1 件付けて `StatusSystem.combatMods` の spdDelta が乗ることを pin）。
    /// `PlayerDriver.combatView(pdata)` は Data レコード直渡しの純粋関数（scene 非依存）。
    @Test
    def testCombatViewOfParityWithStatus(): Unit \ Assert =
        let status = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 2,
                       remaining = 3}: StatusSystem.Status);
        let pdata  = playerDataS(0, status :: Nil);
        let w = TestWorldFixtures.worldOf(List.append(
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2})),
            World.Cmd.Seed(World.EntityRef.Player(0), status :: Nil) :: Nil));
        let wvProj = wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue);
        let cvProj = cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
                            cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod,
                            Option.map(wvProj, cv#weapon));
        Assert.assertEq(
            expected = Some(cvProj(PlayerDriver.combatView(pdata))),
            Option.map(cvProj, World.combatViewOf(World.EntityRef.Player(0), w)))

    // ── growth（level-up 用 base Stats + 成長率 + 名前）の read-model（player-only） ──

    /// growth は `Cmd.SetGrowth` の値をそのまま格納する read-model（player-only・enemy は常に None）。
    /// resolveCombat の level-up を resource threading 無しで World 完結に解ける根拠。
    @Test
    def testGrowthIsPlayerOnlyReadModel(): Unit \ Assert =
        let res = TestUnitFixtures.testResource(4, 10);
        let w = World.applyCmd(
            World.Cmd.SetGrowth(0, {base = LevelSystem.statsOf(res), rates = res#growthRates, name = res#description}),
            World.empty());
        Assert.assertEq(
            expected = (Some((10, 0, "")), true),
            (World.growthOf(World.EntityRef.Player(0), w) |> Option.map(g -> (g#base#hp, g#rates#hp, g#name)),
             Option.isEmpty(World.growthOf(World.EntityRef.Enemy(0), w))))

    // ── dataFromWorld（World 由来 PlayerData 再構築）の field pin ──

    /// フィールド単位 pin: dataFromWorld(0) の代表 field（gridPos/hp/moveTiles/level/classId）が
    /// playerCmds fixture 値と一致し、かつ再構築結果が Some（None の vacuous でない）ことを併せて検証する。
    @Test
    def testDataFromWorldRepresentativeFields(): Unit \ Assert =
        let world = TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 2, y = 2})));
        let field = d -> ((d#gridPos#x, d#gridPos#y), d#hp, d#moveTiles, d#level, d#classId);
        let twin  = World.dataFromWorld(0, world) |> Option.map(field);
        Assert.assertEq(
            expected = (Some(((2, 2), 10, 4, 1, "test_player")), false),
            (twin, Option.isEmpty(twin)))

    // ── 正準キー集約: near-duplicate 分離維持 & composite field-coverage pin ──
    // call-site の key selection（誤 sibling 配線）の唯一の防壁。コンパイラも捕えられない
    // 「強→弱」（field 落ち・誤 key）を、各キーが正しい field を見ていることで pin する。

    /// ★MANDATORY (§5.2): weaponViewKey(8) ≠ weaponViewCombatKey(6)。weaponType だけ違える 2 値で
    /// 8-key は検出（!=）・6-key は検出しない（==・weaponType を含めない設計の pin）。誤統合の防壁。
    @Test
    def testWeaponViewKeysSeparateOnWeaponType(): Unit \ Assert =
        let a = wvSample();
        let b = {weaponType = WeaponCatalog.WeaponType.Axe | wvSample()};
        Assert.assertEq(
            expected = (true, true),
            (World.weaponViewKey(a) != World.weaponViewKey(b),
             World.weaponViewCombatKey(a) == World.weaponViewCombatKey(b)))

    /// ★MANDATORY (§5.2): weaponViewKey は effect も見る／weaponViewCombatKey は見ない。effect だけ
    /// 違える 2 値で 8-key 検出・6-key 非検出を pin（weaponType と並ぶ single-site silent field）。
    @Test
    def testWeaponViewKeysSeparateOnEffect(): Unit \ Assert =
        let a = wvSample();
        let c = {effect = WeaponCatalog.WeaponEffect.Lifesteal | wvSample()};
        Assert.assertEq(
            expected = (true, true),
            (World.weaponViewKey(a) != World.weaponViewKey(c),
             World.weaponViewCombatKey(a) == World.weaponViewCombatKey(c)))

    /// ★MANDATORY (§5.2): equippedRingKey(name,effect,power) ≠ ringKey(name,power)。effect だけ違える
    /// 指輪で 3-key は検出・2-key は検出しない（装備=effect 必須 / 在庫=power 代表）。誤統合の防壁。
    @Test
    def testRingKeysSeparateOnEffect(): Unit \ Assert =
        let r1 = d4Ring();                                     // effect = Power
        let r2 = {effect = Ring.RingEffect.Guard | d4Ring()};  // name+power 同一・effect のみ Guard
        Assert.assertEq(
            expected = (true, true),
            (World.equippedRingKey(r1) != World.equippedRingKey(r2),
             World.ringKey(r1) == World.ringKey(r2)))

    /// ★MANDATORY (§5.3): baseStatsKey が 8 field を漏れなく見る pin（各 1 field drift で検出）。
    @Test
    def testBaseStatsKeyCoversAllFields(): Unit \ Assert =
        let b = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4,
                  skill = 5, speed = 6, luck = 7, maxHp = 8}: Combat.BaseStats);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true),
            (World.baseStatsKey({attack = 99 | b})       != World.baseStatsKey(b),
             World.baseStatsKey({magicAttack = 99 | b})  != World.baseStatsKey(b),
             World.baseStatsKey({defense = 99 | b})      != World.baseStatsKey(b),
             World.baseStatsKey({magicDefense = 99 | b}) != World.baseStatsKey(b),
             World.baseStatsKey({skill = 99 | b})        != World.baseStatsKey(b),
             World.baseStatsKey({speed = 99 | b})        != World.baseStatsKey(b),
             World.baseStatsKey({luck = 99 | b})         != World.baseStatsKey(b),
             World.baseStatsKey({maxHp = 99 | b})        != World.baseStatsKey(b)))

    /// ★MANDATORY (§5.3): resourceStatKey が 11 stat field を漏れなく見る pin。
    @Test
    def testResourceStatKeyCoversAllFields(): Unit \ Assert =
        let r = TestUnitFixtures.testResource(4, 10);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true),
            (World.resourceStatKey({moveTiles = 99 | r})    != World.resourceStatKey(r),
             World.resourceStatKey({level = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({hp = 99 | r})           != World.resourceStatKey(r),
             World.resourceStatKey({attack = 99 | r})       != World.resourceStatKey(r),
             World.resourceStatKey({defense = 99 | r})      != World.resourceStatKey(r),
             World.resourceStatKey({magicAttack = 99 | r})  != World.resourceStatKey(r),
             World.resourceStatKey({magicDefense = 99 | r}) != World.resourceStatKey(r),
             World.resourceStatKey({speed = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({skill = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({luck = 99 | r})         != World.resourceStatKey(r),
             World.resourceStatKey({constitution = 99 | r}) != World.resourceStatKey(r)))

    /// ★MANDATORY (§5.3): combatViewKey が 10 数値 field + 内蔵 weapon を見る pin。最後の項は
    /// 戦闘 field を違える weapon を載せると検出する＝weaponViewCombatKey 配線の pin（combat sub-key 落ち防止）。
    @Test
    def testCombatViewKeyCoversAllFields(): Unit \ Assert =
        let cv = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4, skill = 5,
                   speed = 6, luck = 7, hp = 8, maxHp = 9, hitMod = 10, weapon = None}: Combat.CombatView);
        let cvW1 = {weapon = Some(wvSample()) | cv};
        let cvW2 = {weapon = Some({attack = 999 | wvSample()}) | cv};
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true),
            (World.combatViewKey({attack = 99 | cv})       != World.combatViewKey(cv),
             World.combatViewKey({magicAttack = 99 | cv})  != World.combatViewKey(cv),
             World.combatViewKey({defense = 99 | cv})      != World.combatViewKey(cv),
             World.combatViewKey({magicDefense = 99 | cv}) != World.combatViewKey(cv),
             World.combatViewKey({skill = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({speed = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({luck = 99 | cv})         != World.combatViewKey(cv),
             World.combatViewKey({hp = 99 | cv})           != World.combatViewKey(cv),
             World.combatViewKey({maxHp = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({hitMod = 99 | cv})       != World.combatViewKey(cv),
             World.combatViewKey(cvW1)                      != World.combatViewKey(cvW2)))

    /// ★MANDATORY (§5.3・§1.1): unitViewKey が 10 field を見る pin。pos（posKey）・weaponRange
    /// （weaponRangeKey の (min,max) ネスト）・combat（combatViewKey 内包）の sub-key 落ちまで検出する。
    @Test
    def testUnitViewKeyCoversAllFields(): Unit \ Assert =
        let uv = PlayerDriver.unitView(playerData(0));
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true),
            (World.unitViewKey({id = 99 | uv})                             != World.unitViewKey(uv),
             World.unitViewKey({faction = Faction.Enemy | uv})             != World.unitViewKey(uv),
             World.unitViewKey({pos = {x = 99, y = 99} | uv})              != World.unitViewKey(uv),
             World.unitViewKey({hp = 99 | uv})                             != World.unitViewKey(uv),
             World.unitViewKey({moveTiles = 99 | uv})                      != World.unitViewKey(uv),
             World.unitViewKey({weaponRange = Some({min = 99, max = 99}) | uv}) != World.unitViewKey(uv),
             World.unitViewKey({combat = {attack = 999 | uv#combat} | uv}) != World.unitViewKey(uv),
             World.unitViewKey({isDying = true | uv})                      != World.unitViewKey(uv),
             World.unitViewKey({hidden = true | uv})                       != World.unitViewKey(uv),
             World.unitViewKey({aiType = EnemyAI.AiType.Wanderer | uv})    != World.unitViewKey(uv)))

    /// ★MANDATORY (§5.3・§1.3): playerDataKey 第1 group を漏れなく見る pin。resourceStatKey の
    /// sub-key 落ちまで検出する。
    /// gridPos/hp/waited と在庫4種＋ringEquipped は playerDataKey に含まれない（World 単独権威の
    /// フィールド）＝**含まれないこと**を == で pin（誤って含めない防壁）。
    @Test
    def testPlayerDataKeyCoversGroup1Fields(): Unit \ Assert =
        let d = playerData(0);
        let k = World.playerDataKey;
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true, true, true),
            (k({id = 99 | d})                              != k(d),
             k({classId = "other" | d})                    != k(d),
             k({gridPos = {x = 99, y = 99} | d})           == k(d),
             k({moveTiles = 99 | d})                       != k(d),
             k({hp = 99 | d})                              == k(d),
             k({waited = true | d})                        == k(d),
             k({attackTargetId = Some(7) | d})             != k(d),
             k({resource = TestUnitFixtures.testResource(99, 10) | d}) != k(d),
             k({weapons = Nil | d})                        == k(d),
             k({staves = d4Staff() :: Nil | d})            == k(d),
             k({consumables = d4Consumable() :: Nil | d})  == k(d),
             k({rings = d4Ring() :: Nil | d})              == k(d),
             k({ringEquipped = true | d})                  == k(d)))

    /// ★MANDATORY (§5.3・§1.3): playerDataKey 第2 group（hidden）を見る pin。
    /// followUpUsed・level/exp・selectedItem・moveStepsTaken・facing・usedStairs・pendingLevelUp・
    /// statuses は playerDataKey に含まれない（World 単独権威のフィールド）＝**含まれないこと**を == で pin。
    @Test
    def testPlayerDataKeyCoversGroup2Fields(): Unit \ Assert =
        let d = playerData(0);
        let k = World.playerDataKey;
        let plu = ({unitName = "x", fromLevel = 1, toLevel = 2, changes = Nil}: LevelSystem.Result);
        let st  = ({effect = StatusSystem.StatusEffect.AtkUp, magnitude = 1, remaining = 1}: StatusSystem.Status);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true),
            (k({selectedItem = Some(PlayerData.ItemKind.Weapon(0)) | d}) == k(d),
             k({moveStepsTaken = 99 | d})                  == k(d),
             k({facing = Dir4.Up | d})                     == k(d),
             k({hidden = true | d})                        != k(d),
             k({usedStairs = true | d})                    == k(d),
             k({level = 99 | d})                           == k(d),
             k({exp = 99 | d})                             == k(d),
             k({pendingLevelUp = Some(plu) | d})           == k(d),
             k({statuses = st :: Nil | d})                 == k(d)))

    // ── dataFromWorldEnemy（World 由来 EnemyData 再構築）の field pin / enemyDataKey ──

    /// フィールド単位 pin: dataFromWorldEnemy(5) の代表 field（gridPos/hp/moveTiles/alerted/resourceId）が
    /// enemyCmds fixture 値と一致し、かつ再構築結果が Some（None の vacuous でない）ことを併せて検証する。
    @Test
    def testDataFromWorldEnemyRepresentativeFields(): Unit \ Assert =
        let world = TestWorldFixtures.worldOf(TestWorldFixtures.enemyCmds(TestWorldFixtures.unitSpec(5, {x = 3, y = 2})));
        let field = d -> ((d#gridPos#x, d#gridPos#y), d#hp, d#moveTiles, d#alerted, d#resourceId);
        let twin  = World.dataFromWorldEnemy(5, world) |> Option.map(field);
        Assert.assertEq(
            expected = (Some(((3, 2), 10, 4, false, "test_enemy")), false),
            (twin, Option.isEmpty(twin)))

    /// ★MANDATORY (§5.3・§1.3): enemyDataKey 第1 group（9 field）を漏れなく見る pin。posKey の sub-key
    /// 落ちまで検出する。gridPos/hp は enemyDataKey に含まれない（World 単独権威のフィールド）。
    @Test
    def testEnemyDataKeyCoversGroup1Fields(): Unit \ Assert =
        let d = enemyData(5);
        let k = World.enemyDataKey;
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true),
            (k({id = 99 | d})                     != k(d),
             k({resourceId = "other" | d})        != k(d),
             k({gridPos = {x = 99, y = 99} | d})  == k(d),
             k({alerted = true | d})              != k(d),
             k({homeModuleIdx = 99 | d})          != k(d),
             k({moveTiles = 99 | d})              != k(d),
             k({hp = 99 | d})                     == k(d),
             k({isDying = true | d})              != k(d),
             k({attackTargetId = Some(7) | d})    != k(d)))

    /// ★MANDATORY (§5.3・§1.3): enemyDataKey 第2 group（5 field）を漏れなく見る pin。weaponKey/
    /// equippedRingKey/statusListKey の sub-key 落ちまで検出する。resource（resourceId 代表）は
    /// group1 の resourceId pin が兼ねる（両辺同一構築＝drift 不能）。
    /// acted / weapon / statuses / ring は enemyDataKey に含まれない（World 単独権威のフィールド）ゆえ
    /// 含まれないことを == で pin（bottleUsed / followUpUsed / prevPos の World 単独権威は
    /// testDataFromWorldEnemyBottleUsed... / dataFromWorldEnemy None-gate が保証）。
    @Test
    def testEnemyDataKeyCoversGroup2Fields(): Unit \ Assert =
        let d = enemyData(5);
        let k = World.enemyDataKey;
        let st = ({effect = StatusSystem.StatusEffect.AtkUp, magnitude = 1, remaining = 1}: StatusSystem.Status);
        Assert.assertEq(
            expected = (true, true, true, true),
            (k({weapon = None | d})                       == k(d),
             k({acted = true | d})                        == k(d),
             k({statuses = st :: Nil | d})                == k(d),
             k({ring = Some(d4Ring()) | d})               == k(d)))

    // ════════════════════════════════════════════════════════
    // fx（ダメージ数字/爆発）の World store 権威
    //   spawn=Cmd（applyCmd が nextSeq 採番）・寿命 tick と期限切れ drop=stepWorld
    // ════════════════════════════════════════════════════════

    /// SpawnPopupFx 2 連発で seq 0,1 に挿入され nextSeq が 2 になる。text/pos は spawn 値を保持
    /// （見た目も store 持ち）。
    @Test
    def testSpawnPopupFxAllocatesSequentialSeqs(): Unit \ Assert =
        let white = ({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color);
        let w1 = World.applyCmd(World.Cmd.SpawnPopupFx(
            {total = 0.7, pos = {x = 0.0, y = 5.0}, text = "5", color = white}), World.empty());
        let w2 = World.applyCmd(World.Cmd.SpawnPopupFx(
            {total = 0.7, pos = {x = 0.0, y = 9.0}, text = "miss", color = white}), w1);
        let entries = World.popupFxOf(w2)
            |> Map.toList |> List.map(p -> {let (seq, d) = p; (seq, d#pos#y, d#text)});
        Assert.assertEq(
            expected = ((0, 5.0, "5") :: (1, 9.0, "miss") :: Nil, 2),
            (entries, World.popupFxNextSeqOf(w2)))

    /// stepWorld が fx の remaining を dt 減算し 0 以下で drop する（popup/爆発同型）。
    /// 0.1s 寿命 → 0.05s 進めて両方生存・さらに 0.06s で両方消滅、を pin。
    @Test
    def testStepWorldTicksAndDropsExpiredFx(): Unit \ Assert =
        let white = ({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color);
        let w1 = World.applyCmd(World.Cmd.SpawnPopupFx(
            {total = 0.1, pos = {x = 0.0, y = 0.0}, text = "1", color = white}), World.empty());
        let w1b = World.applyCmd(World.Cmd.SpawnExplosionFx(
            {total = 0.1, pos = {x = 0.0, y = 0.0}, scale = 0.4}), w1);
        let (w2, _) = World.stepWorld(w1b, 0.05);
        let (w3, _) = World.stepWorld(w2, 0.06);
        Assert.assertEq(
            expected = (1, 1, 0, 0),
            (Map.size(World.popupFxOf(w2)), Map.size(World.explosionFxOf(w2)),
             Map.size(World.popupFxOf(w3)), Map.size(World.explosionFxOf(w3))))

    /// refreshMirror は fx store と nextSeq を保持する（tick を進めるだけの段だから）。
    @Test
    def testRefreshMirrorPreservesFxStores(): Unit \ Assert =
        let white = ({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color);
        let w1 = World.applyCmd(World.Cmd.SpawnPopupFx(
            {total = 0.7, pos = {x = 0.0, y = 3.0}, text = "3", color = white}), World.empty());
        let w2 = World.refreshMirror(w1);
        Assert.assertEq(
            expected = (1, 1),
            (Map.size(World.popupFxOf(w2)), World.popupFxNextSeqOf(w2)))
}
