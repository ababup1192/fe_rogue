// slice `simevent-algebra` のテスト。
//
// SimEvent の CLOSED / EXPLICITLY-PARTITIONED な event set に対する
//   (1) per-variant reducer（applyEventToWorld）
//   (2) adapter（eventToCmds）の順序 + Cmd 等価（cmdKey 経由）
//   (3) 既出荷 move seam（EnemyScene.stepEnemyMove / Moved 返却）上での emit→replay TIMING 等価
//   (4) TOTAL な cmdKey（全 19 Cmd variant）
//   (5) eventEntity の exhaustiveness（コンパイル）
//   (6) ViewFx の World-identity（全 ViewFxKind・Died 含む）
// を固定する。production emitter は無い DESIGN SPIKE。combat sim-subset の LEGACY Cmd-stream
// との cross-check は golden-trace スライスが担う（ここではない）。
//
// fixture は TestWorld の最小 scene パターン（World ノード＋直接 addChildAt＋壁なし floor map）を踏襲。

mod TestSimEvent {

    // ── fixtures ────────────────────────────────────────────────────────────

    def playerData(id: Int32): PlayerScene.Data = {
        id                = id,
        statuses          = Nil,
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

    def floorMapLayer(): TileMapLayer =
        let atlas: TileSetAtlasSource = {
            textureName = "test", texWidth = 0.0, texHeight = 0.0,
            tileSize = 16.0, marginX = 0.0, marginY = 0.0, spacingX = 0.0, spacingY = 0.0
        };
        TileMapLayer.make({
            tileSet        = TileSet.make(atlas),
            tiles          = Nil,
            collisionCells = Nil,
            gridSize       = ({x = 13, y = 13}: {x = Int32, y = Int32})
        })

    def floorMapData(): MapScene.Data = {
        anchorOffset = {x = 0, y = 0},
        spawnGrid    = {x = 5, y = 5},
        placements   = RoomLayout.singleRoom(13, 13),
        roomCount    = 1,
        plan         = ({modulePaths = Nil, sideConnections = Nil, roomCount = 1}: DungeonGenerator.Plan)
    }

    /// World ノード下に player 0（{2,2}・hp10）と enemy 5（{3,2}・hp10）＋ floor map を挿した最小 scene。
    def baseScene(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))
            |> Scene.addNode("DungeonLevel0",
                EngineNode.TileMapLayerWithState(floorMapLayer(), NodeTag.Map(floorMapData())))

    def baseWorld(): World = World.syncFromScene(baseScene(), World.empty())

    def dummyResult(): LevelSystem.Result =
        ({unitName = "x", fromLevel = 1, toLevel = 3, changes = Nil}: LevelSystem.Result)

    // ── (1) per-variant reducer ───────────────────────────────────────────────

    /// Damaged は被ダメージ後の絶対 hp を set する。
    @Test
    def testReducerDamaged(): Unit \ Assert =
        let w = World.applyEventToWorld(
            World.SimEvent.Damaged(World.EntityRef.Player(0), {newHp = 5, dmg = 3}), World.empty());
        Assert.assertEq(expected = Some(5), World.hpOf(World.EntityRef.Player(0), w))

    /// Healed / Lifesteal はどちらも絶対 hp を set する。
    @Test
    def testReducerHealedLifesteal(): Unit \ Assert =
        let wh = World.applyEventToWorld(
            World.SimEvent.Healed(World.EntityRef.Player(0), {newHp = 8, amt = 4}), World.empty());
        let wl = World.applyEventToWorld(
            World.SimEvent.Lifesteal(World.EntityRef.Player(0), {newHp = 9, amt = 2}), World.empty());
        Assert.assertEq(
            expected = (Some(8), Some(9)),
            (World.hpOf(World.EntityRef.Player(0), wh), World.hpOf(World.EntityRef.Player(0), wl)))

    /// LeveledUp は progress（level, exp）AND hp の BOTH を absolute で set する。
    @Test
    def testReducerLeveledUp(): Unit \ Assert =
        let w = World.applyEventToWorld(
            World.SimEvent.LeveledUp({entity = World.EntityRef.Player(0),
                newLevel = 3, newExp = 20, newHp = 15, grownStats = LevelSystem.zeroStats(), result = dummyResult()}), World.empty());
        Assert.assertEq(
            expected = (Some((3, 20)), Some(15)),
            (World.progressOf(World.EntityRef.Player(0), w), World.hpOf(World.EntityRef.Player(0), w)))

    /// ExpGained は progress のみ set し、hp は触らない（kill-without-levelup の bare emission）。
    @Test
    def testReducerExpGained(): Unit \ Assert =
        let w = World.applyEventToWorld(
            World.SimEvent.ExpGained({entity = World.EntityRef.Player(0), newLevel = 2, newExp = 30}),
            World.empty());
        Assert.assertEq(
            expected = (Some((2, 30)), (None: Option[Int32])),
            (World.progressOf(World.EntityRef.Player(0), w), World.hpOf(World.EntityRef.Player(0), w)))

    /// Afflicted は statusEffects に StatusSystem.add 意味論で状態異常を積む（Cmd.Add と同一）。
    @Test
    def testReducerAfflicted(): Unit \ Assert =
        let st = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 2, remaining = 3}: StatusSystem.Status);
        let w  = World.applyEventToWorld(
            World.SimEvent.Afflicted(World.EntityRef.Player(0), st), World.empty());
        let effs = World.statusEffectsOf(World.EntityRef.Player(0), w) |> List.map(s -> s#effect);
        Assert.assertEq(expected = StatusSystem.StatusEffect.SpdDown :: Nil, effs)

    /// Dying は対象敵を死亡演出中(enemyDying)へ＝**world 状態変化**（ViewFx.Died の identity と対照）。
    /// 撃破された敵を sim 状態として dying に遷移させる side ＝event set の閉包に必要な variant。
    @Test
    def testReducerDying(): Unit \ Assert =
        let before = World.isDyingOf(World.EntityRef.Enemy(5), World.empty());
        let w = World.applyEventToWorld(
            World.SimEvent.Dying(World.EntityRef.Enemy(5)), World.empty());
        Assert.assertEq(
            expected = (false, true),
            (before, World.isDyingOf(World.EntityRef.Enemy(5), w)))

    /// Released は statusEffects から Immobilized(かなしばり)を除去する（Cmd.ClearImmobilized 意味論）。
    /// Immobilized を積んだ world に Released を当てると当該効果が消えることを射影で固定する。
    @Test
    def testReducerReleased(): Unit \ Assert =
        let immob = ({effect = StatusSystem.StatusEffect.Immobilized, magnitude = 0, remaining = 3}: StatusSystem.Status);
        let bound = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), immob), World.empty());
        let freed = World.applyEventToWorld(World.SimEvent.Released(World.EntityRef.Player(0)), bound);
        let effsOf = w -> World.statusEffectsOf(World.EntityRef.Player(0), w) |> List.map(s -> s#effect);
        Assert.assertEq(
            expected = (StatusSystem.StatusEffect.Immobilized :: Nil, (Nil: List[StatusSystem.StatusEffect])),
            (effsOf(bound), effsOf(freed)))

    // ── (2) adapter 順序 + Cmd 等価（cmdKey 経由）─────────────────────────────

    /// Moved: eventToCmds(Moved).map(cmdKey) == [cmdKey(Cmd.Move)]、かつ
    /// applyEventToWorld(Moved) と applyCmd(Cmd.Move) が同一 World（boardKey）。
    @Test
    def testAdapterMovedEquivalence(): Unit \ Assert =
        let scene = baseScene();
        let w     = World.syncFromScene(scene, World.empty());
        let ev    = World.SimEvent.Moved(World.EntityRef.Enemy(5), {x = 9, y = 9});
        let viaEvent = World.applyEventToWorld(ev, w);
        let viaCmd   = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 9, y = 9}), w);
        let keysEq = (World.eventToCmds(ev) |> List.map(World.cmdKey))
            == (World.cmdKey(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 9, y = 9})) :: Nil);
        let worldEq = World.boardKey(World.toBoard(viaEvent, scene))
            == World.boardKey(World.toBoard(viaCmd, scene));
        Assert.assertEq(expected = (true, true), (keysEq, worldEq))

    /// LeveledUp: eventToCmds は [SetHp, SetProgress] の順（legacy applyLevelUp の emit 順に一致）。
    @Test
    def testAdapterLeveledUpOrder(): Unit \ Assert =
        let ev = World.SimEvent.LeveledUp({entity = World.EntityRef.Player(0),
            newLevel = 3, newExp = 20, newHp = 15, grownStats = LevelSystem.zeroStats(), result = dummyResult()});
        let expectedKeys =
            World.cmdKey(World.Cmd.SetHp(World.EntityRef.Player(0), 15)) ::
            World.cmdKey(World.Cmd.SetProgress(World.EntityRef.Player(0), 3, 20)) :: Nil;
        Assert.assertEq(
            expected = expectedKeys,
            World.eventToCmds(ev) |> List.map(World.cmdKey))

    /// Afflicted: eventToCmds(Afflicted).map(cmdKey) == [cmdKey(Cmd.Add)]、かつ
    /// applyEventToWorld(Afflicted) と applyCmd(Cmd.Add) が同一 statusEffects（effect 列で射影）。
    @Test
    def testAdapterAfflictedEquivalence(): Unit \ Assert =
        let ref = World.EntityRef.Enemy(5);
        let st  = ({effect = StatusSystem.StatusEffect.HitDown, magnitude = 1, remaining = 4}: StatusSystem.Status);
        let ev  = World.SimEvent.Afflicted(ref, st);
        let viaEvent = World.applyEventToWorld(ev, World.empty());
        let viaCmd   = World.applyCmd(World.Cmd.Add(ref, st), World.empty());
        let keysEq = (World.eventToCmds(ev) |> List.map(World.cmdKey))
            == (World.cmdKey(World.Cmd.Add(ref, st)) :: Nil);
        // FULL (effect, magnitude, remaining) 射影で等価を取る（effect 列だけだと量/残ターン違いを見逃す）。
        let projOf = w -> World.statusEffectsOf(ref, w) |> List.map(s -> (s#effect, s#magnitude, s#remaining));
        let statusEq = projOf(viaEvent) == projOf(viaCmd);
        // 付与結果が入力 status を verbatim 反映していることも凍結する（HitDown, mag=1, rem=4）。
        let projFrozen = projOf(viaEvent) == (StatusSystem.StatusEffect.HitDown, 1, 4) :: Nil;
        Assert.assertEq(expected = (true, true, true), (keysEq, statusEq, projFrozen))

    /// Dying / Released: eventToCmds が単一の SetDying / ClrImmob を返し（cmdKey 一致）、かつ
    /// applyEventToWorld == applyCmd（同一 World）。新 sim-affecting variant の adapter↔reducer 整合を固定。
    @Test
    def testAdapterDyingReleasedEquivalence(): Unit \ Assert =
        let en  = World.EntityRef.Enemy(5);
        let pl  = World.EntityRef.Player(0);
        let immob = ({effect = StatusSystem.StatusEffect.Immobilized, magnitude = 0, remaining = 3}: StatusSystem.Status);
        let bound = World.applyCmd(World.Cmd.Add(pl, immob), World.empty());
        // Dying: adapter key 一致 + reducer/applyCmd の isDying 一致。
        let dyingKeysEq = (World.eventToCmds(World.SimEvent.Dying(en)) |> List.map(World.cmdKey))
            == (World.cmdKey(World.Cmd.SetDying(en)) :: Nil);
        let dyingWorldEq = World.isDyingOf(en, World.applyEventToWorld(World.SimEvent.Dying(en), World.empty()))
            == World.isDyingOf(en, World.applyCmd(World.Cmd.SetDying(en), World.empty()));
        // Released: adapter key 一致 + statusEffects(effect 列)一致。
        let relKeysEq = (World.eventToCmds(World.SimEvent.Released(pl)) |> List.map(World.cmdKey))
            == (World.cmdKey(World.Cmd.ClearImmobilized(pl)) :: Nil);
        let effsOf = w -> World.statusEffectsOf(pl, w) |> List.map(s -> s#effect);
        let relWorldEq = effsOf(World.applyEventToWorld(World.SimEvent.Released(pl), bound))
            == effsOf(World.applyCmd(World.Cmd.ClearImmobilized(pl), bound));
        Assert.assertEq(
            expected = (true, true, true, true),
            (dyingKeysEq, dyingWorldEq, relKeysEq, relWorldEq))

    // ── (3) MOVE-SEAM TIMING ──────────────────────────────────────────────────

    /// PUBLIC EnemyScene.stepEnemyMove を、emit された Cmd を記録＆worldRef へ適用する handler で駆動。
    /// recorded Cmd の cmdKey == eventToCmds(返却 Moved).map(cmdKey)（emit と返却 event の adapter が一致）、
    /// かつ boardKey(applyEventToWorld(返却 Moved, pre)) == boardKey(post-step worldRef)
    /// （新 algebra を抽象でなく EXISTING emit→replay seam に tie する）。
    @Test
    def testMoveSeamTiming(): Unit \ Assert =
        let scene = baseScene();
        let pre   = World.syncFromScene(scene, World.empty());
        region rc {
            let recRef = Ref.fresh(rc, (Nil: List[World.Cmd]));
            let wRef   = Ref.fresh(rc, pre);
            let event  = run {
                EnemyScene.stepEnemyMove(5, {x = 9, y = 9})
            } with handler World.Command {
                def emit(c, k) = {
                    Ref.put(c :: Ref.get(recRef), recRef);
                    Ref.put(World.applyCmd(c, Ref.get(wRef)), wRef);
                    k()
                }
            };
            let recordedKeys = List.reverse(Ref.get(recRef)) |> List.map(World.cmdKey);
            let post         = Ref.get(wRef);
            let eventKeys    = World.eventToCmds(event) |> List.map(World.cmdKey);
            let appliedFromEvent = World.applyEventToWorld(event, pre);
            let boardEq = World.boardKey(World.toBoard(appliedFromEvent, scene))
                == World.boardKey(World.toBoard(post, scene));
            Assert.assertEq(expected = (true, true), (recordedKeys == eventKeys, boardEq))
        }

    // ── (4) cmdKey TOTALITY（全 19 variant）─────────────────────────────────

    /// 各 variant の Cmd を 1 つずつ構築し、cmdKey のタグ文字列が期待どおり distinct であることを確認する
    /// （exhaustiveness は flix check が cmdKey の total match で強制）。
    @Test
    def testCmdKeyTags(): Unit \ Assert =
        let pl = World.EntityRef.Player(0);
        let en = World.EntityRef.Enemy(5);
        let st = ({effect = StatusSystem.StatusEffect.AtkUp, magnitude = 1, remaining = 2}: StatusSystem.Status);
        let cmds =
            World.Cmd.SetHp(pl, 5) ::
            World.Cmd.Move(pl, {x = 1, y = 2}) ::
            World.Cmd.SetProgress(pl, 2, 3) ::
            World.Cmd.SetAttackTarget(pl, 7) ::
            World.Cmd.ClearAttackTarget(pl) ::
            World.Cmd.SetFollowUpUsed(pl, true) ::
            World.Cmd.SetAlerted(en, true) ::
            World.Cmd.SetDying(en) ::
            World.Cmd.SetBottleUsed(en, true) ::
            World.Cmd.SetWaited(pl, true) ::
            World.Cmd.SetPrevPos(en, {x = 1, y = 1}) ::
            World.Cmd.ClearImmobilized(pl) ::
            World.Cmd.Add(pl, st) ::
            World.Cmd.Seed(pl, Nil) ::
            World.Cmd.SetPhase(SimPhase.PlayerTurn) ::
            World.Cmd.TickPlayers(Nil) ::
            World.Cmd.TickEnemies ::
            World.Cmd.SetEnemyTurnBusy(true) ::
            World.Cmd.SetPhaseObservedEnemy(true) :: Nil;
        let tags = cmds |> List.map(c -> let (t, _, _, _) = World.cmdKey(c); t);
        let expected =
            "SetHp" :: "Move" :: "Progress" :: "AtkTgt" :: "ClrTgt" :: "FollowUp" ::
            "Alerted" :: "Dying" :: "Bottle" :: "Waited" :: "PrevPos" :: "ClrImmob" ::
            "Add" :: "Seed" :: "Phase" :: "TickP" :: "TickE" :: "ETBusy" :: "PhObs" :: Nil;
        Assert.assertEq(expected = expected, tags)

    /// Add は status の kind ordinal（3rd slot）＋ magnitude（4th slot）で key される。
    /// magnitude が違えば key も違う（量違いを oracle に見せるための widening）。remaining は key 非依存。
    @Test
    def testCmdKeyAddStatusOrdinal(): Unit \ Assert =
        let mk = (se, mag) ->
            World.cmdKey(World.Cmd.Add(World.EntityRef.Player(0),
                ({effect = se, magnitude = mag, remaining = 9}: StatusSystem.Status)));
        Assert.assertEq(
            expected = (("Add", 0, 2, 1), ("Add", 0, 4, 99), false, true),
            (mk(StatusSystem.StatusEffect.AtkUp, 1),       // ordinal 2、magnitude 1
             mk(StatusSystem.StatusEffect.DefDown, 99),    // ordinal 4、magnitude 99
             mk(StatusSystem.StatusEffect.AtkUp, 1) == mk(StatusSystem.StatusEffect.AtkUp, 7),  // magnitude 依存＝distinct
             mk(StatusSystem.StatusEffect.AtkUp, 5) == mk(StatusSystem.StatusEffect.AtkUp, 5))) // remaining 非依存＝同一

    // ── (5) eventEntity exhaustiveness ───────────────────────────────────────

    /// eventEntity の total match がコンパイルし、各 event の主体 entity を返す（ViewFx は持つものだけ Some）。
    /// EntityRef に Eq は無いので uid（Int32）へ射影して比較する。
    @Test
    def testEventEntity(): Unit \ Assert =
        let uidOf = ev -> Option.map(World.toUid, World.eventEntity(ev));
        let af = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 1, remaining = 2}: StatusSystem.Status);
        Assert.assertEq(
            expected = (Some(0), (None: Option[Int32]), Some(World.enemyUid(5)), Some(0),
                        Some(World.enemyUid(5)), Some(0)),
            (uidOf(World.SimEvent.Moved(World.EntityRef.Player(0), {x = 1, y = 1})),
             uidOf(World.SimEvent.ViewFx(World.ViewFxKind.Popup({x = 1, y = 1, text = "t"}))),
             uidOf(World.SimEvent.ViewFx(World.ViewFxKind.Died(World.EntityRef.Enemy(5)))),
             uidOf(World.SimEvent.Afflicted(World.EntityRef.Player(0), af)),
             uidOf(World.SimEvent.Dying(World.EntityRef.Enemy(5))),
             uidOf(World.SimEvent.Released(World.EntityRef.Player(0)))))

    // ── (6) ViewFx World-identity（全 ViewFxKind）─────────────────────────────

    /// 全 ViewFxKind（Died 含む）は World 不変＝reducer が identity。boardKey と hp が変わらないことを確認。
    @Test
    def testViewFxIdentity(): Unit \ Assert =
        let scene = baseScene();
        let w     = baseWorld();
        let key0  = World.boardKey(World.toBoard(w, scene));
        let hp0   = World.hpOf(World.EntityRef.Player(0), w);
        let unchanged = vk -> {
            let after = World.applyEventToWorld(World.SimEvent.ViewFx(vk), w);
            World.boardKey(World.toBoard(after, scene)) == key0
                and World.hpOf(World.EntityRef.Player(0), after) == hp0
        };
        let all =
            unchanged(World.ViewFxKind.Popup({x = 1, y = 1, text = "hi"}))
            and unchanged(World.ViewFxKind.Sound("s"))
            and unchanged(World.ViewFxKind.Explosion({x = 2, y = 2}))
            and unchanged(World.ViewFxKind.Knockback(World.EntityRef.Enemy(5), {x = 3, y = 3}))
            and unchanged(World.ViewFxKind.Thief({x = 4, y = 4}))
            and unchanged(World.ViewFxKind.Died(World.EntityRef.Enemy(5)));
        Assert.assertEq(expected = true, all)
}
