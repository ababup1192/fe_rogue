/// ActionMenuUi（行動選択ウィンドウ・World-entity UI 版）の純粋 / ゲームロジック部分を pin する。
///
/// 検証する観点:
///   - buildItems: 文脈（味方選択 / 空マス / 集合隣接）ごとの項目の text/disabled/meta と並び順
///   - onActionConfirmed: たいき / ターンエンド / ひろう / 集合ガードのゲーム帰結（waited / phase / 在庫）
///   - onActionCancelled: X で戻る先フェーズと cursor 再表示の確立
///
/// 可視同期（frameStep）とスロット流し込みは UiWorldState を要する結線なので、ここでは項目構築の
/// 純粋部分（buildItems）を直接観測する（旧 refreshItems + ItemList 経由の置換）。
/// 選択カーソルの disabled スキップは `TestUiWidget.selectionMoveSkipping` が別に pin する。
mod TestActionMenuUi {

    use World.Cmd
    use World.EntityRef

    // ════════════════════════════════════════════════════════
    // フィクスチャ（World.Cmd 直組み）
    // ════════════════════════════════════════════════════════

    /// id=0 を (1,1)、id=1 を (3,3) に置いた 2 人分の spawn Cmd 列。どちらもアクティブ。
    def twoPlayerCmds(): List[Cmd] =
        List.flatten(
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 1, y = 1})) ::
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, {x = 3, y = 3})) ::
            Nil)

    /// World + 2 人の Player。id=0 を (1,1)、id=1 を (3,3) に置き、どちらもアクティブ。
    def loadTwoPlayerWorld(): World = TestWorldFixtures.worldOf(twoPlayerCmds())

    /// 「こうかん」項目の出現確認用フィクスチャ。id=0 を (1,1)、id=1 を (2,1)（隣接）に置く。
    def loadAdjacentPartyWorld(): World =
        TestWorldFixtures.worldOf(List.flatten(
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 1, y = 1})) ::
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, {x = 2, y = 1})) ::
            Nil))

    /// 指定 id のプレイヤーの waited フラグを **World store** から取り出す。
    def waitedOf(id: Int32, world: World): Bool =
        World.waitedOf(EntityRef.Player(id), world) |> Option.getWithDefault(false)

    /// 指定 id のプレイヤーの所持武器本数を返す（在庫は World 権威）。未登録は 0。
    def weaponCountOf(id: Int32, world: World): Int32 =
        World.weaponsOf(EntityRef.Player(id), world)
            |> Option.map(List.length)
            |> Option.getWithDefault(0)

    /// 指定 id のプレイヤー Data を World から取り出す（居なければテストを潰す）。
    def playerDataOf(id: Int32, world: World): PlayerScene.Data =
        match World.dataFromWorld(id, world) {
            case Some(d) => d
            case None    => bug!("player ${id} not found")
        }

    /// テスト用 floor item を 1 個だけ World に置く（`SpawnItem` seed 用の値組み seam）。
    def attachGroundItemAt(cell: {x = Int32, y = Int32},
                            kind: ItemData.GroundItemKind,
                            world: World): World =
        World.applyCmd(Cmd.SpawnItem({
            gridPos = cell,
            itemKey = "test-ground-item",
            item    = kind,
            elapsed = Duration.seconds(0.0)
        }), world)

    /// `loadTwoPlayerWorld()` に「id=0 の足下 (1,1) に床武器 1 本」を足した World。
    def loadWorldWithFloorWeapon(): World =
        attachGroundItemAt({x = 1, y = 1},
            ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
            loadTwoPlayerWorld())

    /// `loadWorldWithFloorWeapon()` の id=0 の武器一覧を丸ごと差し替えた版
    /// （積載過多を作るための武器複数持ちフィクスチャ）。
    def loadWorldWithFloorWeaponAndWeapons(weapons: List[UnitCatalog.WeaponResource]): World =
        World.applyCmd(Cmd.SetWeapons(EntityRef.Player(0), weapons), loadWorldWithFloorWeapon())

    // ════════════════════════════════════════════════════════
    // buildItems — 文脈ごとの項目構築（旧 refreshItems の項目テストの置換）
    // ════════════════════════════════════════════════════════

    /// 味方選択中（selectedId）で buildItems を read mock 込みで実行し項目列を返す。
    def buildItemsWith(selectedId: Int32, world: World): List[ItemEntry] =
        TestUnitFixtures.withMenuReadMocks(TurnPhase.Phase.ActionSelect, selectedId, world, () ->
            ActionMenuUi.buildItems())

    /// 空マスメニュー（未選択）で buildItems を実行し項目列を返す。
    def buildItemsNoSel(world: World): List[ItemEntry] =
        TestUnitFixtures.withMenuReadMocksNoSel(TurnPhase.Phase.ActionSelect, world, () ->
            ActionMenuUi.buildItems())

    /// `buildItemsNoSel` の盤面込み版。フォグの明るい穴からの敵可視導出（集合 disabled 判定）を
    /// 成立させたい呼び出し側が、あらかじめ盤面 Cmd を含む World を渡す。
    def buildItemsNoSelOnBoard(world: World): List[ItemEntry] =
        TestUnitFixtures.withMenuReadMocksNoSel(TurnPhase.Phase.ActionSelect, world, () ->
            ActionMenuUi.buildItems())

    /// 集合（行軍）隣接メニュー（gatherActive=true・主人公選択中）で buildItems を実行し項目列を返す。
    def buildItemsGather(world: World): List[ItemEntry] =
        TestUnitFixtures.withMenuReadMocksGather(world, () -> ActionMenuUi.buildItems())

    /// 指定 metadata の項目の disabled フラグを返す（見つからなければ None）。
    def disabledOf(meta: String, items: List[ItemEntry]): Option[Bool] =
        items
            |> List.findLeft(e -> e#metadata == Some(meta))
            |> Option.map(e -> e#disabled)

    /// 項目列の metadata を並び順に取り出す。
    def metadataList(items: List[ItemEntry]): List[Option[String]] =
        List.map(e -> e#metadata, items)

    /// id=0 (1,1)・id=1 (2,1) の隣接配置で「こうかん」は**選択可能**で出る（Some(false)）。
    @Test
    def testExchangeItemEnabledWhenAdjacentAllyExists(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(false),
            disabledOf("exchange", buildItemsWith(0, loadAdjacentPartyWorld())))

    /// 非隣接配置でも「こうかん」は**常に出る**が、隣接味方が居ないので disabled=true。
    @Test
    def testExchangeItemDisabledWhenNoAdjacentAlly(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(true),
            disabledOf("exchange", buildItemsWith(0, loadTwoPlayerWorld())))

    /// 「攻撃」は敵が射程外でも常に出る。敵が居ないので disabled=true。
    @Test
    def testAttackAlwaysShownDisabledWhenNoTarget(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(true),
            disabledOf("attack", buildItemsWith(0, loadTwoPlayerWorld())))

    /// 空マスメニュー: 主人公が未行動 + 別の生存味方が居れば「集合」は選択可能。
    @Test
    def testGatherEnabledWhenLordActiveWithAlly(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(false),
            disabledOf("gather", buildItemsNoSel(loadTwoPlayerWorld())))

    /// 空マスメニュー: 主人公が行動済み(waited)なら「集合」は出るが disabled。
    @Test
    def testGatherDisabledWhenLordWaited(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(true),
            disabledOf("gather", buildItemsNoSel(loadWaitedLordWorld())))

    /// 空マスメニュー: フォグで見えている敵が居る間は「集合」は出るが disabled。
    /// 敵可視は World 導出（明るい穴×敵位置）なので、盤面（1 部屋）を seed し
    /// 部屋の中（プレイヤーと同室＝点灯）に敵を置いて「見えている」を作る。
    @Test
    def testGatherDisabledWhenEnemyVisible(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(true),
            disabledOf("gather", buildItemsNoSelOnBoard(
                addEnemyNodeAt({x = 5, y = 5}, worldOnBoard()))))

    /// 空マスメニュー: 敵が居てもフォグで見えていなければ「集合」は選択可能。
    /// 部屋の外（明るい穴の外）に敵を置いて「フォグで隠れている」を作る。
    @Test
    def testGatherEnabledWhenEnemyHiddenByFog(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(false),
            disabledOf("gather", buildItemsNoSelOnBoard(
                addEnemyNodeAt({x = 30, y = 30}, worldOnBoard()))))

    /// loadTwoPlayerWorld と同じだが主人公(id=0)を行動済み(waited=true)にした World。
    def loadWaitedLordWorld(): World =
        World.applyCmd(Cmd.SetWaited(EntityRef.Player(0), true), loadTwoPlayerWorld())

    /// 13×13 の壁なし盤面 + loadTwoPlayerWorld の駒配置。フォグ由来の敵可視判定を成立させる用途。
    def worldOnBoard(): World =
        TestWorldFixtures.worldOf(List.flatten(
            TestWorldFixtures.boardCmds({w = 13, h = 13}, None) :: twoPlayerCmds() :: Nil))

    /// World 配下に生存敵(id=9)を 1 体挿す。可視性はフォグ（明るい穴×`cell`）から導出される。
    def addEnemyNodeAt(cell: {x = Int32, y = Int32}, world: World): World =
        List.foldLeft((w, c) -> World.applyCmd(c, w), world,
            TestWorldFixtures.enemyCmds({moveTiles = 3 | TestWorldFixtures.unitSpec(9, cell)}))

    // ════════════════════════════════════════════════════════
    // 集合（行軍）の隣接メニュー（gatherActive=true × 主人公選択中）
    // ════════════════════════════════════════════════════════

    /// World + 主人公(id0, (1,1)) + 味方(id1, allyPos)。
    def loadGatherMenuWorld(allyPos: {x = Int32, y = Int32}): World =
        TestWorldFixtures.worldOf(List.flatten(
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, {x = 1, y = 1})) ::
            TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(1, allyPos)) ::
            Nil))

    /// 主人公に隣接する味方((2,1)) が居れば、隣接メニューは「交換 → 全員待機」。
    @Test
    def testGatherAdjacentMenuShowsTradeWithAdjacentAlly(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("gatherTrade") :: Some("waitAll") :: Nil,
            metadataList(buildItemsGather(loadGatherMenuWorld({x = 2, y = 1}))))

    /// 隣接する味方が居なければ((5,5))、「交換」は出さず「全員待機」だけ。
    @Test
    def testGatherAdjacentMenuHidesTradeWithoutAdjacentAlly(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("waitAll") :: Nil,
            metadataList(buildItemsGather(loadGatherMenuWorld({x = 5, y = 5}))))

    /// 配置済み(placed)の階段を `cell` に置いた World。
    def withStairsAt(cell: {x = Int32, y = Int32}, world: World): World =
        World.applyCmd(Cmd.SetStairs(Some(cell)), world)

    /// 主人公(1,1)の足元に床アイテムがあると、集合メニューの先頭に「拾う」が出る。
    @Test
    def testGatherMenuShowsPickupWhenItemUnderLord(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("pickup") :: Some("waitAll") :: Nil,
            metadataList(buildItemsGather(
                attachGroundItemAt({x = 1, y = 1},
                    ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()),
                    loadGatherMenuWorld({x = 5, y = 5})))))

    /// 主人公(1,1)が階段マスに立っているときだけ集合メニューに「階段」が出る。
    @Test
    def testGatherMenuShowsStairsWhenLordOnStairs(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("gatherStairs") :: Some("waitAll") :: Nil,
            metadataList(buildItemsGather(
                withStairsAt({x = 1, y = 1}, loadGatherMenuWorld({x = 5, y = 5})))))

    /// 階段が別マス(5,5)にあっても主人公(1,1)が乗っていなければ「階段」は出さない。
    @Test
    def testGatherMenuHidesStairsWhenLordOffStairs(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("waitAll") :: Nil,
            metadataList(buildItemsGather(
                withStairsAt({x = 5, y = 5}, loadGatherMenuWorld({x = 5, y = 5})))))

    /// 足元アイテム + 階段上 + 隣接味方が揃うと固定順「拾う → 階段 → 交換 → 全員待機」。
    @Test
    def testGatherMenuFullOrder(): Unit \ Assert =
        Assert.assertEq(
            expected = Some("pickup") :: Some("gatherStairs") :: Some("gatherTrade")
                        :: Some("waitAll") :: Nil,
            metadataList(buildItemsGather(
                loadGatherMenuWorld({x = 2, y = 1})
                    |> attachGroundItemAt({x = 1, y = 1},
                        ItemData.GroundItemKind.WeaponItem(TestUnitFixtures.testWeapon()))
                    |> withStairsAt({x = 1, y = 1}))))

    // ════════════════════════════════════════════════════════
    // onActionConfirmed 回帰テスト（ゲーム帰結: waited / phase / 在庫）
    // ════════════════════════════════════════════════════════

    /// `runOnActionConfirm` に渡す入力一式。
    type alias ActionConfirmArgs = {
        initialPhase   = TurnPhase.Phase,
        selectedId     = Int32,
        selectedOrigin = {x = Int32, y = Int32},
        world          = World,
        entry          = ItemEntry
    }

    /// `onActionConfirmed` の effect を一括でスタブして実行し、最終 phase / World を返す。
    /// PartyQuery / RosterQuery / 盤面は `args#world` の**開始時点の静的スナップショット**を渡す
    /// （実行中の World.Command emit で変化する在庫は World.WorldQuery 側（wref）から読む）。
    def runOnActionConfirm(rc: Region[r], args: ActionConfirmArgs): (TurnPhase.Phase, World) \ r =
        let wref = Ref.fresh(rc, args#world);
        let board = BoardSnapshot.fromParts(TestWorldFixtures.floorSnapshot({w = 13, h = 13}),
            TestUnitFixtures.worldPlayers(args#world), TestUnitFixtures.worldEnemies(args#world));
        let (_, phase) = run {
        ItemPickupPopupState.withState(rc, () ->
        TestUnitFixtures.withMockBoard(board, () ->
        TestUnitFixtures.withPhaseRef(rc, args#initialPhase, () ->
            TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockEnemyTurnQueue(() ->
                            TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(args#world), () ->
                                TestUnitFixtures.withMockRosterQuery(TestUnitFixtures.worldEnemies(args#world), () ->
                                  TestUnitFixtures.withMockAudio(() ->
                                    TestUnitFixtures.withNoopFloorAdvance(() ->
                                      TestUnitFixtures.withMockGatherResume(() ->
                                        TestUnitFixtures.withSelectedPlayer(args#selectedId, () ->
                                         TestUnitFixtures.withCursor(() ->
                                          TestUnitFixtures.withRangeOverlay(rc, () ->
                                          TestUnitFixtures.withItemMenu(() ->
                                          TestUnitFixtures.withTradeMenu(rc, () ->
                                          ActionMenuUi.onActionConfirmed(args#entry))))))))))))))))))
        } with handler World.WorldQuery {
            def get(k) = k(Ref.get(wref))
        }
          with handler World.Command {
            def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(wref)), wref); k() }
        }
          with StairsExitDriver.withState(rc);
        (phase, Ref.get(wref))

    /// たいき (`wait`) を確定すると選択者(id=0)が waited、もう 1 人は据え置き、PlayerCursor へ戻る。
    @Test
    def testWaitMarksSelectedAndAdvancesToPlayerCursor(): Unit \ Assert =
        region rc {
            let world = loadTwoPlayerWorld();
            let waitEntry: ItemEntry =
                { text = "たいき", disabled = false, metadata = Some("wait") };
            let (finalPhase, wFin) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                world          = world,
                entry          = waitEntry
            });
            Assert.assertEq(
                expected = (TurnPhase.Phase.PlayerCursor, true, false),
                (finalPhase, waitedOf(0, wFin), waitedOf(1, wFin)))
        }

    /// ターンエンド (`turnEnd`) を確定すると全味方が waited、フェーズは EnemyTurn へ進む。
    @Test
    def testTurnEndMarksAllAndAdvancesToEnemyTurn(): Unit \ Assert =
        region rc {
            let world = loadTwoPlayerWorld();
            let turnEndEntry: ItemEntry =
                { text = "ターンエンド", disabled = false, metadata = Some("turnEnd") };
            let (finalPhase, wFin) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = -1,
                selectedOrigin = {x = 0, y = 0},
                world          = world,
                entry          = turnEndEntry
            });
            Assert.assertEq(
                expected = (TurnPhase.Phase.EnemyTurn, true, true),
                (finalPhase, waitedOf(0, wFin), waitedOf(1, wFin)))
        }

    /// ひろう (`pickup`) を確定すると ActionSelect 維持・waited 立たず・床から消え・武器 1→2 本。
    @Test
    def testPickupKeepsActionSelectAndAddsItemToInventory(): Unit \ Assert =
        region rc {
            let world = loadWorldWithFloorWeapon();
            let pickupEntry: ItemEntry =
                { text = "ひろう", disabled = false, metadata = Some("pickup") };
            let (finalPhase, wFin) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                world          = world,
                entry          = pickupEntry
            });
            let groundItemStillThere =
                Option.nonEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(
                expected = (TurnPhase.Phase.ActionSelect, false, false, 2),
                ( finalPhase
                , waitedOf(0, wFin)
                , groundItemStillThere
                , weaponCountOf(0, wFin) ))
        }

    /// World + 主人公(id0,(1,1)) + 味方(id1,(3,3))。lordWaited で主人公の waited を切り替える。
    def loadGatherStartWorld(lordWaited: Bool): World =
        let base = loadTwoPlayerWorld();
        if (lordWaited) World.applyCmd(Cmd.SetWaited(EntityRef.Player(0), true), base) else base

    /// 「集合」確定: 主人公が行動済みなら開始せず ActionSelect に留まる（リーダー行動済みガード）。
    @Test
    def testGatherBlockedWhenLeaderWaited(): Unit \ Assert =
        region rc {
            let gatherEntry: ItemEntry =
                { text = "集合", disabled = false, metadata = Some("gather") };
            let (finalPhase, _wFin) = runOnActionConfirm(rc, {
                initialPhase   = TurnPhase.Phase.ActionSelect,
                selectedId     = 0,
                selectedOrigin = {x = 1, y = 1},
                world          = loadGatherStartWorld(true),
                entry          = gatherEntry
            });
            Assert.assertEq(expected = TurnPhase.Phase.ActionSelect, finalPhase)
        }

    /// 「ひろう」で拾った後に選択解除キャンセル (cancelSelection) すると拾得が巻き戻る:
    ///   床アイテムが (1,1) に戻り、仮取得した武器が 2 → 1 本に戻る。
    @Test
    def testPickupThenCancelSelectionRevertsPickup(): Unit \ Assert =
        region rc {
            let world0 = loadWorldWithFloorWeapon();
            let pickupEntry: ItemEntry =
                { text = "ひろう", disabled = false, metadata = Some("pickup") };
            let board = BoardSnapshot.fromParts(TestWorldFixtures.floorSnapshot({w = 13, h = 13}),
                TestUnitFixtures.worldPlayers(world0), TestUnitFixtures.worldEnemies(world0));
            let (_after, wFin) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () ->
                TestUnitFixtures.withNoopPickupPopup(() ->
                TestUnitFixtures.withMockBoard(board, () ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withNoopAnim(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withMockEnemyTurnQueue(() ->
                            TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world0), () ->
                                TestUnitFixtures.withMockRosterQuery(TestUnitFixtures.worldEnemies(world0), () ->
                                  TestUnitFixtures.withMockAudio(() ->
                                    TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ActionSelect, () ->
                                      TestUnitFixtures.withNoopFloorAdvance(() ->
                                        TestUnitFixtures.withMockGatherResume(() ->
                                          TestUnitFixtures.withSelectionRef(rc,
                                            {id = Some(0), drafts = Nil, gatherActive = false}, () ->
                                            TestUnitFixtures.withCursor(() ->
                                            TestUnitFixtures.withRangeOverlay(rc, () ->
                                            TestUnitFixtures.withItemMenu(() ->
                                            TestUnitFixtures.withTradeMenu(rc, () ->
                                            run {
                                                ActionMenuUi.onActionConfirmed(pickupEntry);
                                                PlayerScene.cancelSelection()
                                            } with StairsExitDriver.withState(rc)))))))))))))))))));
            let groundItemBack =
                Option.nonEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(
                expected = (true, 1),
                (groundItemBack, weaponCountOf(0, wFin)))
        }

    // ════════════════════════════════════════════════════════
    // 移動着地の自動取得（PlayerMovementDriver.autoPickupOrLog）
    //   フィクスチャ（loadWorldWithFloorWeapon 他）を再利用する回帰テスト。
    // ════════════════════════════════════════════════════════

    /// 着地マス (1,1) の床武器を、重量が許すので **自動で拾う**（床から消え・武器 1→2 本）。
    @Test
    def testAutoPickupPicksUpWhenWeightAllows(): Unit \ Assert =
        region rc {
            let world0 = loadWorldWithFloorWeapon();
            let data   = playerDataOf(0, world0);
            let (_after, wFin) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () ->
                TestUnitFixtures.withNoopPickupPopup(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withSelectedPlayer(0, () ->
                         TestUnitFixtures.withCursor(() ->
                            PlayerMovementDriver.autoPickupOrLog(data, {x = 1, y = 1}))))));
            let floorEmpty = Option.isEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(
                expected = (true, 2),
                (floorEmpty, weaponCountOf(0, wFin)))
        }

    /// 拾うと積載過多になるなら着地しても **拾わず床に残す**（床に残り・武器 4 本のまま）。
    @Test
    def testAutoPickupSkipsWhenWouldOverload(): Unit \ Assert =
        region rc {
            let w = TestUnitFixtures.testWeapon();
            // 在庫は World 権威＝重い在庫(4本)を初期 World に Cmd で seed してから拾う。
            let world0 = loadWorldWithFloorWeaponAndWeapons(w :: w :: w :: w :: Nil);
            let data   = playerDataOf(0, world0);
            let (_after, wFin) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () ->
                TestUnitFixtures.withNoopPickupPopup(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        TestUnitFixtures.withSelectedPlayer(0, () ->
                         TestUnitFixtures.withCursor(() ->
                            PlayerMovementDriver.autoPickupOrLog(data, {x = 1, y = 1}))))));
            let floorStillThere = Option.nonEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(
                expected = (true, 4),
                (floorStillThere, weaponCountOf(0, wFin)))
        }

    /// 着地の自動取得は移動キャンセルで巻き戻せる（床に戻り・武器 2→1 本）。
    @Test
    def testAutoPickupThenCancelSelectionRevertsPickup(): Unit \ Assert =
        region rc {
            let world0 = loadWorldWithFloorWeapon();
            let data   = playerDataOf(0, world0);
            let (_after, wFin) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () ->
                TestUnitFixtures.withNoopPickupPopup(() ->
                    TestUnitFixtures.withNoopTween(() ->
                        TestUnitFixtures.withNoopAnim(() ->
                            TestUnitFixtures.withMockGameLogger(() ->
                                TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world0), () ->
                                    TestUnitFixtures.withFixedPhase(TurnPhase.Phase.PlayerMoving, () ->
                                        TestUnitFixtures.withSelectionRef(rc,
                                            {id = Some(0), drafts = Nil, gatherActive = false}, () ->
                                            TestUnitFixtures.withCursor(() ->
                                            TestUnitFixtures.withRangeOverlay(rc, () -> {
                                                PlayerMovementDriver.autoPickupOrLog(data, {x = 1, y = 1});
                                                PlayerScene.cancelSelection()
                                            }))))))))));
            let groundItemBack = Option.nonEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(
                expected = (true, 1),
                (groundItemBack, weaponCountOf(0, wFin)))
        }

    // ════════════════════════════════════════════════════════
    // 装備 / 捨てる の巻き戻し（移動中の仮アクションを逆順 revert）
    // ════════════════════════════════════════════════════════

    /// World + 単一プレイヤー(id0) で weapons を指定した最小 World（巻き戻し検証用）。
    def loadPlayerWithWeaponsWorld(pos: {x = Int32, y = Int32},
                                    weapons: List[UnitCatalog.WeaponResource]): World =
        World.applyCmd(Cmd.SetWeapons(EntityRef.Player(0), weapons),
            TestWorldFixtures.worldOf(TestWorldFixtures.playerCmds(TestWorldFixtures.unitSpec(0, pos))))

    /// 与えた drafts を SelectedPlayer に載せて `cancelSelection` を実行するランナー。
    def runCancelWithDrafts(rc: Region[r], world0: World,
                              drafts: List[MoveDraft.DraftAction]): World \ r =
        let (_out, world) = TestUnitFixtures.withWorldAppliedSeeded(rc, world0, () ->
            TestUnitFixtures.withSelectionRef(rc,
                {id = Some(0), drafts = drafts, gatherActive = false}, () ->
                    TestUnitFixtures.withNoopTween(() ->
                        TestUnitFixtures.withNoopAnim(() ->
                            TestUnitFixtures.withMockPartyQuery(TestUnitFixtures.worldPlayers(world0), () ->
                                TestUnitFixtures.withFixedPhase(TurnPhase.Phase.ActionSelect, () ->
                                 TestUnitFixtures.withCursor(() ->
                                  TestUnitFixtures.withRangeOverlay(rc, () ->
                                    PlayerScene.cancelSelection()))))))));
        world

    /// 拾得 → 装備 → 選択解除キャンセルで、装備の並び替えも拾得も正しく巻き戻る。
    @Test
    def testEquipAfterPickupThenCancelRevertsBoth(): Unit \ Assert =
        region rc {
            let wA = TestUnitFixtures.testWeaponFull(5, 10);
            let wB = TestUnitFixtures.testWeaponFull(99, 10);
            let world0 = loadPlayerWithWeaponsWorld({x = 1, y = 1}, wB :: wA :: Nil);
            let drafts =
                MoveDraft.DraftAction.Equipped(0, 1) ::
                MoveDraft.DraftAction.PickedUp(0, {x = 1, y = 1}, "wB",
                    ItemData.GroundItemKind.WeaponItem(wB)) ::
                MoveDraft.DraftAction.MovedFrom(0, {x = 1, y = 1}) :: Nil;
            let wFin = runCancelWithDrafts(rc, world0, drafts);
            let attacks = TestUnitFixtures.withWorldQuery(wFin, () ->
                List.map(w -> w#attack, PlayerScene.getWeapons(0)));
            let floorB  = Option.nonEmpty(World.groundItemAtOf({x = 1, y = 1}, wFin));
            Assert.assertEq(expected = (5 :: Nil, true), (attacks, floorB))
        }

    /// 中央の武器を捨ててからキャンセルすると、元の idx に正確に戻る（順序保持）。
    @Test
    def testDropThenCancelRestoresItemAtIndex(): Unit \ Assert =
        region rc {
            let wA = TestUnitFixtures.testWeaponFull(1, 10);
            let wB = TestUnitFixtures.testWeaponFull(2, 10);
            let wC = TestUnitFixtures.testWeaponFull(3, 10);
            let world0 = loadPlayerWithWeaponsWorld({x = 2, y = 2}, wA :: wC :: Nil);
            let drafts =
                MoveDraft.DraftAction.Dropped(0, PlayerData.ItemKind.Weapon(1),
                    ItemData.GroundItemKind.WeaponItem(wB)) ::
                MoveDraft.DraftAction.MovedFrom(0, {x = 2, y = 2}) :: Nil;
            let wFin = runCancelWithDrafts(rc, world0, drafts);
            let attacks = TestUnitFixtures.withWorldQuery(wFin, () ->
                List.map(w -> w#attack, PlayerScene.getWeapons(0)));
            Assert.assertEq(expected = 1 :: 2 :: 3 :: Nil, attacks)
        }

    // ════════════════════════════════════════════════════════
    // onActionCancelled — X が戻り先フェーズの cursor を必ず確立する
    // ════════════════════════════════════════════════════════

    /// 空マスメニュー由来（SelectedPlayer = None）で X を押すと PlayerCursor + カーソル再表示。
    /// 初期カーソル可視は false（非表示から復帰することを確認）。
    @Test
    def testActionCancelFromEmptyCellRestoresCursor(): Unit \ Assert =
        let (_, finalPhase, visible) =
            TestUnitFixtures.withCancelTransitionMocks(SelectedPlayer.cleared(), false, () ->
                ActionMenuUi.onActionCancelled());
        Assert.assertEq(
            expected = (TurnPhase.Phase.PlayerCursor, true),
            (finalPhase, visible))

    /// 駒選択中（SelectedPlayer = Some(0)）で X を押すと PlayerMoving へ戻る（カーソルは設計上非表示）。
    @Test
    def testActionCancelWithSelectionReturnsToMovingHidden(): Unit \ Assert =
        let (_, finalPhase, visible) =
            TestUnitFixtures.withCancelTransitionMocks(
                {id = Some(0), drafts = Nil, gatherActive = false}, true, () ->
                ActionMenuUi.onActionCancelled());
        Assert.assertEq(
            expected = (TurnPhase.Phase.PlayerMoving, false),
            (finalPhase, visible))

    /// 集合（行軍）の隣接メニュー（gatherActive=true）で X を押すと GatherMove へ戻る（カーソル非表示）。
    @Test
    def testActionCancelGatherReturnsToGatherMoveHidden(): Unit \ Assert =
        let (_, finalPhase, visible) =
            TestUnitFixtures.withCancelTransitionMocks(
                {id = Some(0), drafts = Nil, gatherActive = true}, true, () ->
                ActionMenuUi.onActionCancelled());
        Assert.assertEq(
            expected = (TurnPhase.Phase.GatherMove, false),
            (finalPhase, visible))

    // ════════════════════════════════════════════════════════
    // 実 asset のスロット宣言数 ⇔ maxSlots() の一致（スロット超過防御の前提を pin）
    //   ui.json は slot0..slot{maxSlots-1} を宣言し、slot{maxSlots} は宣言しない。
    // ════════════════════════════════════════════════════════

    /// 実 asset（ActionMenu.ui.json）を parse し、menu 直下の "slot" 名の子の数を数える。
    /// UiWorld は組まず Spec ツリーだけを歩く（読み込み失敗はテストを潰す）。
    def actionMenuSlotCount(): Int32 \ Fs.FileRead =
        match UiSpec.load(ActionMenuUi.specPath()) {
            case Ok(root) => UiSpec.countPrefixedChildren("panel" :: "menu" :: Nil, "slot", root)
            case Err(_)   => bug!("ActionMenu.ui.json load failed")
        }

    /// 実 asset の slot 宣言数が `ActionMenuUi.maxSlots()` と一致する（宣言過不足を弾く）。
    @Test
    def testSlotDeclarationCountMatchesMaxSlots(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = ActionMenuUi.maxSlots(), actionMenuSlotCount())

    // ════════════════════════════════════════════════════════
    // 幅フィットの純粋コア（ラベル実測幅リスト + 見出し幅 → innerW / panelW）
    //   contentW = 最長ラベル + 2×4.0、headerW = 見出し + 2.0、
    //   innerW = max(contentW, headerW)、panelW = innerW + 2×2.0。
    // ════════════════════════════════════════════════════════

    /// ラベルが見出しより広い: 最長ラベル 20 → contentW=20+8=28、headerW=12+2=14、
    /// innerW=28、panelW=28+4=32。
    @Test
    def testFitWidthsLabelDominant(): Unit \ Assert =
        let fit = ActionMenuUi.fitWidths(10.0 :: 20.0 :: 15.0 :: Nil, 12.0);
        Assert.assertEq(expected = (28.0, 32.0), (fit#innerW, fit#panelW))

    /// 見出しがラベルより広い: ラベル 5 → contentW=5+8=13、見出し 40 → headerW=40+2=42、
    /// innerW=42、panelW=42+4=46。見出し幅が下限になることを pin する。
    @Test
    def testFitWidthsHeaderDominant(): Unit \ Assert =
        let fit = ActionMenuUi.fitWidths(5.0 :: Nil, 40.0);
        Assert.assertEq(expected = (42.0, 46.0), (fit#innerW, fit#panelW))

    /// ラベル無し（項目 0）: maxLabelW=0 → contentW=8、見出し 10 → headerW=12、
    /// innerW=12、panelW=16。空メニューでも見出しぶんの幅は残す。
    @Test
    def testFitWidthsNoLabels(): Unit \ Assert =
        let fit = ActionMenuUi.fitWidths(Nil, 10.0);
        Assert.assertEq(expected = (12.0, 16.0), (fit#innerW, fit#panelW))
}
