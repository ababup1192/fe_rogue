// World（S0 足場）のテスト — scene→World 一方向 sync が id 集合と tick を正しく写すか。
// 最小 scene は TestCombatScene.battleScene と同じ「World ノード＋直接 addChildAt」パターン。

mod TestWorld {

    def playerData(id: Int32): PlayerScene.Data = playerDataS(id, Nil)

    def playerDataS(id: Int32, statuses: List[StatusSystem.Status]): PlayerScene.Data = {
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
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = 0,
        pendingLevelUp    = None,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    def enemyData(id: Int32): EnemyScene.Data = {
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

    /// World 配下に player 2 体（id 0,1）＋ enemy 1 体（id 5）を直接挿した最小 scene。
    def sampleScene(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(1))))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))

    /// syncFromScene が player/enemy の id 集合を写し、tick を 1 進める。
    @Test
    def testSyncFromScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(
            expected = (2, 1, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    /// id の実値も検証（player/enemy の取り違えを直接捕捉）。
    @Test
    def testSyncFromSceneIds(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(expected = (Set#{0, 1}, Set#{5}), (w#playerIds, w#enemyIds))

    /// 空 scene なら id 集合は空、tick は進む。
    @Test
    def testSyncFromEmptyScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(Scene.empty(), World.empty());
        Assert.assertEq(
            expected = (0, 0, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    // ── S1a: statuses store ──

    /// player 0 に immobilize(残3) を持たせた scene を World に mirror する。
    def sceneWithStatus(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Player(playerDataS(0, StatusSystem.immobilizeFor(3) :: Nil))))

    def firstRemaining(m: Map[EntityId, List[StatusSystem.Status]], id: EntityId): Int32 =
        Map.get(id, m) |> Option.flatMap(List.head) |> Option.map(s -> s#remaining) |> Option.getWithDefault(-1)

    /// syncFromScene が statuses を player store に写す（残3 がそのまま）。
    @Test
    def testSyncMirrorsStatuses(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sceneWithStatus(), World.empty());
        Assert.assertEq(expected = 3, firstRemaining(w#statusEffects, 0))

    /// tickStatusEffects（StatusSystem.tick 再利用）で残ターンが 1 減る（残3→2）。
    @Test
    def testTickStatuses(): Unit \ Assert =
        let synced = World.syncFromScene(sceneWithStatus(), World.empty());
        let World.World(w) = World.tickStatusEffects(synced);
        Assert.assertEq(expected = 2, firstRemaining(w#statusEffects, 0))

    // ── S1b: World→scene write-back（逆向き矢印）と parallel-run 同値実証 ──

    /// scene の player 0 の Data#statuses を読む（write-back の検証用）。
    def sceneFirstRemaining(scene: Scene[NodeTag], id: Int32): Int32 =
        PlayerScene.getAll(scene)
            |> List.find(d -> d#id == id)
            |> Option.flatMap(d -> List.head(d#statuses))
            |> Option.map(s -> s#remaining)
            |> Option.getWithDefault(-1)

    /// syncStatusesToScene が World の statuses を scene の Data#statuses へ書き戻す（残3 が往復で保たれる）。
    @Test
    def testSyncStatusesToSceneRoundTrip(): Unit \ Assert =
        let scene  = sceneWithStatus();
        let synced = World.syncFromScene(scene, World.empty());
        let back   = World.syncStatusesToScene(synced, scene);
        Assert.assertEq(expected = 3, sceneFirstRemaining(back, 0))

    /// parallel-run 同値実証: 「World 経路（tickStatusEffects→write-back で scene を更新）」と
    /// 「現行 scene 経路（StatusSystem.tick を直接 Data#statuses に畳む）」が同じ残ターンを与える。
    /// これが一致する限り、turn 開始 tick を World へ flip しても挙動は不変（S1b 後段の前提）。
    @Test
    def testTickParallelRunMatchesScenePath(): Unit \ Assert =
        let scene = sceneWithStatus();
        // World 経路: sync → tickStatusEffects → scene へ write-back → scene から読む。
        let worldPath =
            World.syncStatusesToScene(World.tickStatusEffects(World.syncFromScene(scene, World.empty())), scene)
                |> (s -> sceneFirstRemaining(s, 0));
        // scene 経路: 既存と同じく Data#statuses に StatusSystem.tick を直接畳む。
        let scenePath =
            PlayerScene.mapPlayer(0, d -> {statuses = StatusSystem.tick(d#statuses) | d}, scene)
                |> (s -> sceneFirstRemaining(s, 0));
        Assert.assertEq(expected = scenePath, worldPath)

    // ── S2: hp の read-model mirror ──

    /// syncFromScene が hp を World store へ mirror する（player 0,1／enemy 5 とも scene の hp と一致）。
    /// 権威は scene のまま＝この mirror は query/セーブ用の read-model。
    @Test
    def testSyncMirrorsHp(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        // sampleScene の fixture は player/enemy とも hp=10。
        Assert.assertEq(
            expected = (Some(10), Some(10), Some(10)),
            (Map.get(0, w#hp), Map.get(1, w#hp), Map.get(5 + World.enemyUidBase(), w#hp)))

    /// A'（faction タグ）: `team` enum component が unified-id ごとに Player/Enemy を返す。
    /// faction は id 演算でなくこの enum タグで読む。sampleScene = player 0,1 / enemy 5。
    @Test
    def testTeamTagComponent(): Unit \ Assert =
        let w = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(
            expected = (Some(Faction.Player), Some(Faction.Player),
                        Some(Faction.Enemy), true, true, None),
            (World.teamOf(0, w), World.teamOf(1, w),
             World.teamOf(5 + World.enemyUidBase(), w),
             World.isPlayerUid(0, w), World.isEnemyUid(5 + World.enemyUidBase(), w),
             World.teamOf(999, w)))

    /// hp mirror が scene の各 Data#hp と完全一致する（parallel-run 同値：World hp == scene hp）。
    @Test
    def testHpMirrorEqualsScene(): Unit \ Assert =
        let scene = sampleScene();
        let World.World(w) = World.syncFromScene(scene, World.empty());
        let scenePlayerHp = PlayerScene.getAll(scene)
            |> List.foldLeft((m, d) -> Map.insert(d#id, d#hp, m), Map.empty());
        // A': hp は単一 store。player 部分（uid < base）を取り出して比較。
        Assert.assertEq(expected = scenePlayerHp,
            Map.filterWithKey((uid, _) -> uid < World.enemyUidBase(), w#hp))

    // ── S3: gridPos の read-model mirror ──

    /// syncFromScene が gridPos を World store へ mirror する（fixture: player {2,2}／enemy {3,2}）。
    /// record の == は使えないので x/y スカラに展開して比較。
    @Test
    def testSyncMirrorsPos(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        let xy = (id, m) -> Map.get(id, m) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(
            expected = (Some((2, 2)), Some((2, 2)), Some((3, 2))),
            (xy(0, w#pos), xy(1, w#pos), xy(5 + World.enemyUidBase(), w#pos)))

    /// pos mirror が scene の各 Data#gridPos と一致（parallel-run 同値：World pos == scene gridPos・Vec2i.eq）。
    @Test
    def testPosMirrorEqualsScene(): Unit \ Assert =
        let scene = sampleScene();
        let World.World(w) = World.syncFromScene(scene, World.empty());
        let allMatch = PlayerScene.getAll(scene)
            |> List.forAll(d ->
                Map.get(d#id, w#pos)
                    |> Option.map(v -> Vec2i.eq(v, d#gridPos))
                    |> Option.getWithDefault(false));
        Assert.assertEq(expected = true, allMatch)

    // ── S4: BoardSnapshot.piecesFromWorld（位置 read-model から Board.pieces を組む）──

    /// World 配下に player 0（可視・{2,2}）／player 3（hidden）／enemy 5（{3,2}）を挿した scene。
    def sceneWithHidden(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(3),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player({hidden = true | playerData(3)})))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))

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

    /// piecesFromWorld が World 位置から正しい駒を組む：hidden 味方 3 を除外、player 0／enemy 5 が残る。
    /// fromScene の hidden フィルタ・(Piece,pos) 生成と同義であることを id→pos 同値で検証（順序非依存）。
    @Test
    def testPiecesFromWorldFiltersHidden(): Unit \ Assert =
        let world  = World.syncFromScene(sceneWithHidden(), World.empty());
        let pieces = World.boardPieces(world);
        Assert.assertEq(
            expected = (Map#{0 => (2, 2)}, Map#{5 => (3, 2)}),
            (playerPosMapOf(pieces), enemyPosMapOf(pieces)))

    // ── S1: World.Cmd applier（statuses 権威化の System/command。StatusSystem 再利用）──

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

    // ── P0a: Cmd.Move の mid-frame currency（位置権威化・gather 是正の前提）──

    /// P0a tripwire: 主人公が **mid-frame に prev→now と動いた**直後、`Cmd.Move` を適用すると
    /// BoardQuery が返す盤面（= `World.toBoard` → `boardPieces`）は **now を反映**し、stale な prev を返さない。
    ///
    /// これは検証器 `[P0a BOARD DIFF]`（Game.flix）が gather で「主人公位置を prev→now に是正する」根拠そのもの。
    /// `Cmd.Move` を `applyCmd`／`playerPos` ストアに配線し損ねる（または `boardPieces` が別ストアを読む）と、
    /// `before==after==prev` になりこのテストが赤くなる＝手動 run 前に回帰を機械検出できる。
    ///
    /// 補足: gather の追従計算 `Board.followStepsToward` 自体は board の主人公セル位置に**非依存**
    /// （味方は全プレイヤーセルを通過可・goal は強制 open・lordNewPos は予約）。よって tripwire は
    /// followStepsToward でなく、P0a が実際に変える「World 盤面の currency」を対象に置く。
    @Test
    def testMoveReflectsNewPosInBoardMidFrame(): Unit \ Assert =
        let now = ({x = 5, y = 5}: {x = Int32, y = Int32});
        // frame-head: scene を mirror（sampleScene の player 0 は {2,2}）。
        let w0 = World.syncFromScene(sampleScene(), World.empty());
        // mid-frame: 主人公(player 0)が now へ移動 → Cmd.Move を World に即時適用。
        let w1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), now), w0);
        let posOf0 = w -> Map.get(0, playerPosMapOf(World.boardPieces(w)));
        // before は frame-head の prev {2,2}、after は now {5,5}（prev のままなら配線漏れ）。
        Assert.assertEq(expected = (Some((2, 2)), Some((5, 5))), (posOf0(w0), posOf0(w1)))

    // ── P0b: spawn/restore funnel が新規ユニットの位置を World へ seed ──

    /// P0b tripwire: `addOnePlayer`（spawn/restore の funnel）が新規ユニットの初期位置を
    /// World へ seed する（`Cmd.Move` を emit）。emit を applyCmd で worldRef に積み、
    /// `boardPieces` に id 7 @ (3,4) が現れることを確認する。funnel の emit 行を消す回帰で赤になる。
    @Test
    def testAddOnePlayerSeedsPositionToWorld(): Unit \ Assert =
        let sp = ({id = 7, classId = "test_player", gridPos = {x = 3, y = 4},
                    resource = TestUnitFixtures.testResource(4, 10),
                    weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerScene.Spawn);
        let world = region rc {
            let ref = Ref.fresh(rc, World.empty());
            run {
                discard PlayerScene.addOnePlayer(sp, MapScene.addWorldNode(Scene.empty())); ()
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(ref)), ref); k() }
            };
            Ref.get(ref)
        };
        Assert.assertEq(expected = Some((3, 4)), Map.get(7, playerPosMapOf(World.boardPieces(world))))

    // ── P3: refreshMirror（位置 mirror 撤去・World が位置権威）──

    /// P3 の要: `refreshMirror` は **scene gridPos を読まず** command 由来の位置を保持する。
    /// command で player 0 を {5,5} に置き、gridPos が {2,2} の scene を渡しても pos は {5,5} のまま。
    /// もし refreshMirror が gridPos を再構築（＝mirror 復活）すると {2,2} になり赤くなる回帰ガード。
    @Test
    def testRefreshMirrorKeepsCommandPosNotGridPos(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty());
        // sampleScene の player 0 の gridPos は {2,2}。refreshMirror は command の {5,5} を保持する。
        let refreshed = World.refreshMirror(sampleScene(), seeded);
        let World.World(w) = refreshed;
        Assert.assertEq(expected = Some((5, 5)), Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)))

    /// P3: scene に居なくなった id（死亡/退場で scene から除去）は pos から prune される（ghost piece 防止）。
    /// command で enemy 99 を置くが sampleScene に 99 は居ない → prune される。scene に居る player 0 は残る。
    @Test
    def testRefreshMirrorPrunesAbsentIds(): Unit \ Assert =
        let s1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(99), {x = 9, y = 9}),
                 World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let World.World(w) = World.refreshMirror(sampleScene(), s1);
        Assert.assertEq(
            expected = (Some((5, 5)), None),
            (Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)),
             Map.get(99 + World.enemyUidBase(), w#pos) |> Option.map(p -> (p#x, p#y))))

    /// F6b: hp は **command 由来で保持**（scene から re-mirror しない＝hp 権威は World）。`Cmd.SetHp` で
    /// player 0 を 3 に下げ、refreshMirror 後も scene の 10 でなく command の 3 が残ることを pin。
    /// status/ids は引き続き scene 由来。位置と同じく prune（scene に居ない id は落ちる）。
    @Test
    def testRefreshMirrorPreservesCommandHp(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());      // hp 0/1 = 10
        let damaged = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 3), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), damaged);
        // player 0 は command の 3（scene の 10 で上書きされない）、player 1 は 10 のまま、ids は scene 由来。
        Assert.assertEq(
            expected = (Some(3), Some(10), Set#{0, 1}),
            (Map.get(0, w#hp), Map.get(1, w#hp), w#playerIds))

    // ── §A payoff デモ: 位置の決定論（World は Cmd.Move ログの純粋関数）──
    // P0a→S5 で World が位置の権威・scene はその派生になった。位置の唯一の source は `Cmd.Move` のログ。
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

    // ── F0: System パイプライン段 stepWorld（OOP→ECS 移行の足場）──

    /// F0 不変条件: `stepWorld`（現状 inert な `tickStatusEffects` のみ）は **位置を変えない**。
    /// gameLoop は `syncTreeFromWorld(stepWorld(world1))` で scene gridPos を derive するので、
    /// stepWorld が pos を保つ限り render は不変＝F0 は挙動不変。System を足して pos を壊す回帰で赤になる。
    @Test
    def testStepWorldPreservesPositions(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3}),
                     World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let stepped = World.stepWorld(seeded);
        let tup = ref -> worldPosOf(ref, stepped) |> Option.map(p -> (p#x, p#y));
        Assert.assertEq(
            expected = (Some((5, 5)), Some((3, 3))),
            (tup(World.EntityRef.Player(0)), tup(World.EntityRef.Enemy(5))))

    /// F3 基盤: `syncTreeFromWorld` が World の位置を scene の `gridPos` に **derive** する。
    /// F3 の sim/view 分離（位置の権威は World・scene はその派生／`replayMoveView` は見た目のみ）の前提。
    /// `Cmd.Move` で World 位置を動かし、syncTreeFromWorld 後に scene Player gridPos が World 由来に
    /// なる（元 scene は不変）ことを pin。既存テストは World 側（`worldPosOf`）のみで、この
    /// World→scene 書き戻しは未カバーだった＝F3 の土台を直接固定する。
    @Test
    def testSyncTreeFromWorldDerivesScenePos(): Unit \ Assert =
        let scene  = sampleScene();                       // player 0 @ (2,2)
        let seeded = World.syncFromScene(scene, World.empty());
        let moved  = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 7, y = 1}), seeded);
        let before = PlayerScene.getGridPos(0, scene);    // 元 scene は派生前ゆえ不変（2,2）
        let after  = PlayerScene.getGridPos(0, World.syncTreeFromWorld(moved, scene));
        Assert.assertEq(
            expected = ((2, 2), (7, 1)),
            ((before#x, before#y), (after#x, after#y)))

    // ── F2a: turn FSM の World mirror（SimPhase）──

    /// F2a: 既定は PlayerTurn・`mirrorTurnPhase`/`turnPhaseOf` が round-trip する。
    @Test
    def testTurnPhaseMirrorRoundTrips(): Unit \ Assert =
        let after = World.mirrorTurnPhase(SimPhase.EnemyTurn, World.empty());
        Assert.assertEq(
            expected = (SimPhase.PlayerTurn, SimPhase.EnemyTurn),
            (World.turnPhaseOf(World.empty()), World.turnPhaseOf(after)))

    /// F2a 不変条件: `refreshMirror`（毎フレーム）は turnPhase を**保持**する（書き手は gameLoop の mirror だけ）。
    /// status/pos と違い turnPhase は scene 由来でないので、refreshMirror が勝手に上書きしないことを pin。
    @Test
    def testRefreshMirrorPreservesTurnPhase(): Unit \ Assert =
        let seeded = World.mirrorTurnPhase(SimPhase.EnemyTurn, World.empty());
        let refreshed = World.refreshMirror(sampleScene(), seeded);
        Assert.assertEq(expected = SimPhase.EnemyTurn, World.turnPhaseOf(refreshed))

    /// F2b: `Cmd.SetPhase` が World.turnPhase を command で更新する（TurnPhase.State handler が put 時に emit）。
    @Test
    def testSetPhaseCommandUpdatesTurnPhase(): Unit \ Assert =
        let after = World.applyCmd(World.Cmd.SetPhase(SimPhase.EnemyTurn), World.empty());
        Assert.assertEq(expected = SimPhase.EnemyTurn, World.turnPhaseOf(after))

    /// F7-spike: `Cmd.SetAlerted` が World の enemyAlerted を更新し `alertedOf` で読める（flag→World の土台）。
    @Test
    def testSetAlertedCommandUpdatesWorld(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), World.empty());
        Assert.assertEq(expected = Some(true), World.alertedOf(World.EntityRef.Enemy(5), w))

    /// F7-slice5: `Cmd.SetWaited` が World を更新し `waitedOf` で読める＋preserve（command が scene 上書きされない）。
    @Test
    def testSetWaitedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // player 0 waited=false
        let acted  = World.applyCmd(World.Cmd.SetWaited(World.EntityRef.Player(0), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), acted);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.waitedOf(World.EntityRef.Player(0), acted), Map.get(0, w#playerWaited)))

    /// F8-slice1: `Cmd.SetAttackTarget`/`ClearAttackTarget` が World を更新し `attackTargetOf` で読める＋preserve。
    /// `anyPlayerAttacking`/`anyEnemyAttacking`（driver の順序非依存判定の本体）も同時に検証。
    @Test
    def testSetAttackTargetCommandAndPreserve(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());     // 誰も攻撃中でない
        let set     = seeded
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Player(0), 5))
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Enemy(5), 0));
        let World.World(w) = World.refreshMirror(sampleScene(), set);        // scene は None だが command 由来は保持
        Assert.assertEq(
            expected = (Some(5), Some(0), true, true),
            (World.attackTargetOf(World.EntityRef.Player(0), set),
             Map.get(5 + World.enemyUidBase(), w#attackTarget),
             World.anyPlayerAttacking(set),
             World.anyEnemyAttacking(set)))

    /// F8-slice1: `ClearAttackTarget` で対象が消え、`anyXAttacking` が false に戻る。
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
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let leveled = seeded
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Player(0), 3, 40))
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Enemy(5), 9, 99));  // no-op
        let kept = World.refreshMirror(sampleScene(), leveled);
        Assert.assertEq(
            expected = (Some((3, 40)), None, Some((3, 40))),
            (World.progressOf(World.EntityRef.Player(0), leveled),
             World.progressOf(World.EntityRef.Enemy(5), leveled),
             World.progressOf(World.EntityRef.Player(0), kept)))

    /// 軸1 仕上げ: `Cmd.SetDying` が敵を World の dying set に入れ `isDyingOf` で読める＋preserve。
    /// Player は no-op（常に false）。
    @Test
    def testSetDyingCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // enemy 5 isDying=false
        let dying  = seeded
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Enemy(5)))
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Player(0)));  // no-op
        let kept = World.refreshMirror(sampleScene(), dying);
        Assert.assertEq(
            expected = (true, false, true),
            (World.isDyingOf(World.EntityRef.Enemy(5), dying),
             World.isDyingOf(World.EntityRef.Player(0), dying),
             World.isDyingOf(World.EntityRef.Enemy(5), kept)))

    /// F8-slice2: `Cmd.SetEnemyTurnBusy`/`SetPhaseObservedEnemy` が scalar bool を更新し読める＋
    /// refreshMirror で保持（scene mirror 元なし＝command 由来を持ち越す）。
    @Test
    def testSetTopBarBoolsCommandAndPreserve(): Unit \ Assert =
        let set = World.empty()
            |> World.applyCmd(World.Cmd.SetEnemyTurnBusy(true))
            |> World.applyCmd(World.Cmd.SetPhaseObservedEnemy(true));
        let kept = World.refreshMirror(sampleScene(), set);   // scene に mirror 元なし＝保持されるはず
        Assert.assertEq(
            expected = (true, true, true, true),
            (World.enemyTurnBusyOf(set), World.phaseObservedEnemyOf(set),
             World.enemyTurnBusyOf(kept), World.phaseObservedEnemyOf(kept)))

    /// F7-slice4: `Cmd.SetFollowUpUsed` が両 faction を更新し `followUpUsedOf` で読める＋preserve。
    @Test
    def testSetFollowUpUsedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let used   = seeded
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(0), true))
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(5), true));
        let World.World(w) = World.refreshMirror(sampleScene(), used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (Map.get(0, w#followUpUsed), Map.get(5 + World.enemyUidBase(), w#followUpUsed)))

    /// F7-slice3: `Cmd.SetPrevPos` が World を更新し `prevPosOf` で読める＋preserve（command が scene 上書きされない）。
    @Test
    def testSetPrevPosCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let moved  = World.applyCmd(World.Cmd.SetPrevPos(World.EntityRef.Enemy(5), {x = 7, y = 1}), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), moved);
        let toT = op -> Option.map(p -> (p#x, p#y), op);
        Assert.assertEq(
            expected = (Some((7, 1)), Some((7, 1))),
            (toT(World.prevPosOf(World.EntityRef.Enemy(5), moved)), toT(Map.get(5 + World.enemyUidBase(), w#enemyPrevPos))))

    /// F7-slice2: `Cmd.SetBottleUsed` が World を更新し `bottleUsedOf` で読める＋preserve。
    @Test
    def testSetBottleUsedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // enemy 5 bottleUsed=false
        let used   = World.applyCmd(World.Cmd.SetBottleUsed(World.EntityRef.Enemy(5), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.bottleUsedOf(World.EntityRef.Enemy(5), used), Map.get(5 + World.enemyUidBase(), w#enemyBottleUsed)))

    /// F7-spike: alerted は command 由来で **保持**（scene から re-mirror しない）。`Cmd.SetAlerted(5,true)` 後、
    /// refreshMirror しても scene fixture（enemy 5 alerted=false）でなく command の true が残る＝flag も World 権威化可。
    @Test
    def testRefreshMirrorPreservesCommandAlerted(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());
        let alerted = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), alerted);
        Assert.assertEq(expected = Some(true), Map.get(5 + World.enemyUidBase(), w#enemyAlerted))

    /// F6a: `Cmd.SetHp` が World の hp store を faction 別に更新し、`hpOf` で読める（hp→World 権威化の土台）。
    /// 後段（F6b）で reader を World へ flip・refreshMirror を preserve 化する前提のコマンドシーム。
    @Test
    def testSetHpCommandUpdatesWorldHp(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 7),
                World.applyCmd(World.Cmd.SetHp(World.EntityRef.Enemy(5), 3), World.empty()));
        Assert.assertEq(
            expected = (Some(7), Some(3)),
            (World.hpOf(World.EntityRef.Player(0), w), World.hpOf(World.EntityRef.Enemy(5), w)))
}
