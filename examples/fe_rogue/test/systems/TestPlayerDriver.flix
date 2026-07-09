// PlayerDriver のテスト（multi-player 版）
//
// 駒の状態は World（examples/fe_rogue/src/world/World.flix）の store 群が唯一の権威。
// 位置（gridPos）は `World.Cmd.Move` で即更新され、見た目の描画位置（renderPos）は
// World の tween（`World.moveUnit` / `World.Cmd.StartTween`）が別途 stepWorld で進める。
// 壁判定は Board の責務なので PlayerDriver 自身は考えない。
//
// 検証する観点:
//   - moveToById が gridPos を即更新する（renderPos は tween 登録のみで即座には動かない）
//   - swapItem / useStairs / reconcileWithCarry / removeDeadAndCheckGameOver の World 反映
//   - adjacentAllies / gatherNotMovedYet 等の純粋寄りロジック
//
// テスト用 tileSize は 16。`PlayerDriver.add` を介さず `PlayerDriver.addOnePlayer` を直接呼ぶ。

mod TestPlayerDriver {

    /// テスト用 tileSize
    def testTileSize(): Float64 = 16.0

    /// テスト用ワールド座標換算
    def testGridToWorld(coords: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(coords);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// テスト用 MapSnapshot — 床のみ・13×13・grid↔world は testGridToWorld
    def testSnapshot(): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = {x = 0, y = 0}, size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            wallCells    = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
        }

    /// テスト用初期グリッド
    def initialGrid(): {x = Int32, y = Int32} = {x = 5, y = 5}

    /// GameOverRequest を「フラグ Ref に true を書く」モックにする。
    /// 「ゲームオーバーを要求したか」を、呼び出し側が渡す region の Ref で観測できる。
    def withGameOverFlag(flagRef: Ref[Bool, r], thunk: Unit -> a \ ef):
            a \ (ef - CustomEffects.GameOverRequest) + r =
        run { thunk() } with handler CustomEffects.GameOverRequest {
            def markDeaths(_positions, k) = k()
            def request(k)          = { Ref.put(true, flagRef); k() }
            def restartBeginning(k) = k()
            def restartFloor(k)     = k()
            def reviveInPlace(k)    = k()
        }

    // ========================================================================
    // moveToById — gridPos を即更新する。描画位置（renderPos）は tween 登録のみで
    //   この場では動かない（滑走→スナップの World 側性質は TestWorld / TestEcsTween が担保）。
    // ========================================================================

    /// moveToById 直後: gridPos は target に即更新される。renderPos は `World.moveUnit` が
    /// tween を登録するだけなので、stepWorld を進めない限りこの場では動かない。
    @Test
    def testMoveToUpdatesGridPosImmediately(): Unit \ Assert =
        let target: {x = Int32, y = Int32} = {x = 6, y = 5};
        let initial = initialGrid();
        let initialWorld = testGridToWorld(initial);
        let ref = World.EntityRef.Player(0);
        region rc {
            let (_, w) = TestUnitFixtures.withWorldApplied(rc, () -> {
                World.Command.emit(World.Cmd.Move(ref, initial));
                World.Command.emit(World.Cmd.SetRenderPos(ref, initialWorld));
                PlayerDriver.moveToById(0, target, testSnapshot(), Duration.frames(count = 16, fps = 120))
            });
            let gridPos   = World.posOf(ref, w) |> Option.map(p -> (p#x, p#y));
            let renderPos = World.renderPosOf(ref, w) |> Option.map(p -> (p#x, p#y));
            let moving    = World.isAnimating(ref, w);
            Assert.assertEq(
                expected = (Some((6, 5)), Some((initialWorld#x, initialWorld#y)), true),
                (gridPos, renderPos, moving))
        }

    // ========================================================================
    // adjacentAllies — 上下左右 1 マスの他味方だけを返す
    // ========================================================================

    /// 配置 (self = id 0 at (5,5)):
    ///
    ///         (5,4) id=1
    ///   (4,5)        (6,5)
    ///    id=2 (5,5)   id=3
    ///                (self)
    ///         (5,6) id=4
    ///
    ///   (4,4) id=5            (6,6) id=6   ← 斜めなので非隣接
    ///
    /// 期待: 上下左右の id (1,2,3,4) だけが返り、斜め (5,6) と self (0) は除外される。
    /// getAll は id 昇順なので結果も id 昇順で並ぶ前提でリスト比較する。
    @Test
    def testAdjacentAlliesReturnsOnlyOrthogonalNeighbors(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        let (selfOpt, players) = TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer(mkSpawn(0, {x = 5, y = 5}));
            PlayerDriver.addOnePlayer(mkSpawn(1, {x = 5, y = 4}));
            PlayerDriver.addOnePlayer(mkSpawn(2, {x = 4, y = 5}));
            PlayerDriver.addOnePlayer(mkSpawn(3, {x = 6, y = 5}));
            PlayerDriver.addOnePlayer(mkSpawn(4, {x = 5, y = 6}));
            PlayerDriver.addOnePlayer(mkSpawn(5, {x = 4, y = 4}));
            PlayerDriver.addOnePlayer(mkSpawn(6, {x = 6, y = 6}));
            (PlayerDriver.get(0), PlayerDriver.getAll())
        });
        let neighborIds = selfOpt |> Option.map(self ->
            TestUnitFixtures.withMockPartyQuery(players, () -> PlayerDriver.adjacentAllies(self))
                |> List.map(d -> d#id));
        Assert.assertEq(expected = Some(1 :: 2 :: 3 :: 4 :: Nil), neighborIds)

    /// 隣接味方が居ない場合は空リストを返す。
    /// 斜めに居る駒は隣接ではない (上のテストと同じ判定だが、空の経路を独立 pin)。
    @Test
    def testAdjacentAlliesReturnsEmptyWhenNoOrthogonalNeighbor(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        let (selfOpt, players) = TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer(mkSpawn(0, {x = 5, y = 5}));
            PlayerDriver.addOnePlayer(mkSpawn(1, {x = 4, y = 4}));
            PlayerDriver.addOnePlayer(mkSpawn(2, {x = 6, y = 6}));
            (PlayerDriver.get(0), PlayerDriver.getAll())
        });
        let neighborIds = selfOpt |> Option.map(self ->
            TestUnitFixtures.withMockPartyQuery(players, () -> PlayerDriver.adjacentAllies(self))
                |> List.map(d -> d#id));
        Assert.assertEq(expected = Some(Nil), neighborIds)

    /// spawn-seed gap 回帰（2026-06-30）: command-derive store は refreshMirror が preserve する（毎フレ
    /// scene から再構築しない）ため、floor 跨ぎで scene が reset されても World は前 floor の stale 値を保持する。
    /// よって spawn funnel(addOnePlayer)が各 command-derive store を Cmd で seed しないと stale drift が起きる
    /// （usedStairs で実発生＝[USEDSTAIRS DIFF]・unit test では出ず run 検証でのみ発覚）。addOnePlayer 後の World に
    /// usedStairs が Some(false) で seed されていること（None=未 seed でない）を pin して再発を防ぐ。
    /// 敵 acted（addOneEnemy の SetActed seed）も同型ゆえこのパターンで守られる。
    @Test
    def testAddOnePlayerSeedsUsedStairs(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let sp = ({id = 0, classId = "test_player", gridPos = {x = 5, y = 5}, resource = fx#unitSample,
                   weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        region rc {
            let (_, w) = TestUnitFixtures.withWorldApplied(rc, () -> PlayerDriver.addOnePlayer(sp));
            Assert.assertEq(expected = Some(false), World.usedStairsOf(World.EntityRef.Player(0), w))
        }

    // ========================================================================
    // gatherNotMovedYet — 集合直後（誰も origin から動いていない）か
    //   true のときだけ C で集合 → 個別行動モードへ戻せる。
    // ========================================================================

    /// 主人公(id 0, lordPos) + 味方(id 1, 常に (5,4)) の 2 人を World へ spawn し、
    /// `sel` を SelectedPlayer に固定して `gatherNotMovedYet` を評価する。region は内部で閉じる。
    def gatherNotMovedFor(lordPos: {x = Int32, y = Int32},
                           sel: SelectedPlayer.Selection): Bool \ Fs.FileRead =
        region rc {
            let fx = loadTestCatalogs();
            let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos,
                                          resource = fx#unitSample, weapons = Nil, staves = Nil,
                                          consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
            TestUnitFixtures.withWorldCommand(rc, () -> {
                PlayerDriver.addOnePlayer(mkSpawn(0, lordPos));
                PlayerDriver.addOnePlayer(mkSpawn(1, {x = 5, y = 4}));
                TestUnitFixtures.withSelectionRef(rc, sel, () -> PlayerDriver.gatherNotMovedYet())
            })
        }

    /// 集合中で全員が draft の origin に居る（一歩も動いていない）→ true（C で切替可能）。
    @Test
    def testGatherNotMovedYetTrueWhenNobodyMoved(): Unit \ {Assert, Fs.FileRead} =
        let sel: SelectedPlayer.Selection =
            {id = Some(0),
             drafts = MoveDraft.DraftAction.MovedFrom(0, {x = 5, y = 5})
                   :: MoveDraft.DraftAction.MovedFrom(1, {x = 5, y = 4}) :: Nil,
             gatherActive = true};
        Assert.assertEq(expected = true, gatherNotMovedFor({x = 5, y = 5}, sel))

    /// 主人公が origin (5,5) から (6,5) へ動いている → false（移動開始後は切替不可）。
    @Test
    def testGatherNotMovedYetFalseWhenLordMoved(): Unit \ {Assert, Fs.FileRead} =
        let sel: SelectedPlayer.Selection =
            {id = Some(0),
             drafts = MoveDraft.DraftAction.MovedFrom(0, {x = 5, y = 5})
                   :: MoveDraft.DraftAction.MovedFrom(1, {x = 5, y = 4}) :: Nil,
             gatherActive = true};
        Assert.assertEq(expected = false, gatherNotMovedFor({x = 6, y = 5}, sel))

    /// そもそも集合中でない（gatherActive=false）→ false。
    @Test
    def testGatherNotMovedYetFalseWhenNotGather(): Unit \ {Assert, Fs.FileRead} =
        let sel: SelectedPlayer.Selection =
            {id = Some(0), drafts = Nil, gatherActive = false};
        Assert.assertEq(expected = false, gatherNotMovedFor({x = 5, y = 5}, sel))

    // ========================================================================
    // tradeComponent — 隣接連結成分（集合の N 人交換メンバー抽出）
    //
    // 集合の交換は「主人公を含む、隣接（マンハッタン 1）で連結した塊」全員が対象。
    // 直接隣接だけでなくチェーン（0-1-2）でつながった味方も含める。
    // ========================================================================

    /// 交換メンバー抽出用の最小レコード（id + gridPos のみ）。
    def mkMember(id: Int32, x: Int32, y: Int32): {id = Int32, gridPos = {x = Int32, y = Int32}} =
        {id = id, gridPos = {x = x, y = y}}

    /// チェーン: 0=(5,5) 1=(6,5) 2=(7,5)。2 は 0 に非隣接だが 1 経由で連結 → 全員。
    @Test
    def testTradeComponentIncludesChainedAllies(): Unit \ Assert =
        let members = mkMember(0, 5, 5) :: mkMember(1, 6, 5) :: mkMember(2, 7, 5) :: Nil;
        Assert.assertEq(expected = 0 :: 1 :: 2 :: Nil,
            PlayerDriver.tradeComponent(0, members))

    /// 分断: 0=(5,5) と 1=(6,5) は隣接、2=(10,10) は遠い → 0,1 のみ（2 は除外）。
    @Test
    def testTradeComponentExcludesDisconnected(): Unit \ Assert =
        let members = mkMember(0, 5, 5) :: mkMember(1, 6, 5) :: mkMember(2, 10, 10) :: Nil;
        Assert.assertEq(expected = 0 :: 1 :: Nil,
            PlayerDriver.tradeComponent(0, members))

    /// 主人公が誰とも隣接していない（斜めは隣接でない）→ 主人公だけ（< 2 で交換は開かれない）。
    @Test
    def testTradeComponentLordAloneWhenNoNeighbor(): Unit \ Assert =
        let members = mkMember(0, 5, 5) :: mkMember(1, 6, 6) :: mkMember(2, 10, 10) :: Nil;
        Assert.assertEq(expected = 0 :: Nil,
            PlayerDriver.tradeComponent(0, members))

    /// start（主人公）が members に居なければ空（リーダー死亡など）。
    @Test
    def testTradeComponentEmptyWhenStartMissing(): Unit \ Assert =
        let members = mkMember(1, 6, 5) :: mkMember(2, 7, 5) :: Nil;
        Assert.assertEq(expected = (Nil: List[Int32]),
            PlayerDriver.tradeComponent(0, members))

    // ========================================================================
    // swapItem — 2 プレイヤー間でアイテムを交換する
    //
    // 本体経路を使う:
    //   - `UnitCatalog.load` で本番 resources の catalog を読む
    //   - `UnitCatalog.lookupWeapon(id, catalog)` / `Staff.lookup(id, staffCatalog)`
    //     で本物の resource を取得
    //   - `PlayerDriver.addOnePlayer(spawn)` で World へ spawn する
    //   - `PlayerDriver.swapItem(args)` を record-style 引数で呼ぶ（scene なし）
    //   - インベントリ確認は `PlayerDriver.getWeapons` / `getStaves` の戻り値を直接 map
    //
    // 武器: iron_lance (てつのやり) / iron_bow (てつの弓) / tome_grimoire (魔導書)
    // 杖:   live_staff (かいふくのつえ) / swap_staff (いれかえのつえ)
    // ========================================================================

    /// 共通: 本番の catalog をロードして「最初の player unit」を返す。
    /// 本体 `UnitCatalog.load` + `UnitCatalog.pool("players", _)` の薄い呼び出しなので
    /// テスト固有ロジックは含まない (= helper として最小)。
    def loadTestCatalogs(): {catalog = UnitCatalog.UnitCatalog,
                              staffCatalog = Staff.StaffCatalog,
                              unitSample = UnitCatalog.UnitResource} \ Fs.FileRead =
        let weaponCatalog = WeaponCatalog.load();
        let catalog = UnitCatalog.load("resources/units.json", weaponCatalog);
        let staffCatalog = Staff.load();
        let unitSample = match List.head(UnitCatalog.pool("players", catalog)) {
            case Some(pair) => snd(pair)
            case None       => bug!("no players in catalog")
        };
        {catalog = catalog, staffCatalog = staffCatalog, unitSample = unitSample}

    /// P0 weapons=[槍, 魔導書] / P1 weapons=[弓]
    /// P0 の Weapon(0)=槍 と P1 の Weapon(0)=弓 を交換。
    /// 期待:
    ///   P0: weapons=[魔導書, 弓]   (槍が抜けて末尾に 弓 追加)
    ///   P1: weapons=[槍]              (弓が抜けて末尾に 槍 追加)
    @Test
    def testSwapItemWeaponToWeaponExchangesBothInventories(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("iron_lance", fx#catalog);
        let bow   = UnitCatalog.lookupWeapon("iron_bow",      fx#catalog);
        let fire  = UnitCatalog.lookupWeapon("tome_grimoire", fx#catalog);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer({id = 0, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = spear :: fire :: Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.addOnePlayer({id = 1, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = bow :: Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Weapon(0),
                partnerId   = 1,
                partnerKind = Some(PlayerData.ItemKind.Weapon(0))
            });
            Assert.assertEq(
                expected = ("魔導書" :: "てつの弓" :: Nil, "てつのやり" :: Nil),
                (PlayerDriver.getWeapons(0) |> List.map(w -> w#name),
                 PlayerDriver.getWeapons(1) |> List.map(w -> w#name)))
        })

    /// P0 staves=[回復] / P1 staves=[入替]
    /// P0 の Staff(0)=回復 と P1 の Staff(0)=入替 を交換 (杖同士)。
    /// 期待: P0 staves=[入替] / P1 staves=[回復]
    @Test
    def testSwapItemStaffToStaffExchangesBothInventories(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let live = Staff.lookup("live_staff", fx#staffCatalog);
        let swap = Staff.lookup("swap_staff", fx#staffCatalog);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer({id = 0, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = Nil, staves = live :: Nil, consumables = Nil, rings = Nil});
            PlayerDriver.addOnePlayer({id = 1, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = Nil, staves = swap :: Nil, consumables = Nil, rings = Nil});
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Staff(0),
                partnerId   = 1,
                partnerKind = Some(PlayerData.ItemKind.Staff(0))
            });
            Assert.assertEq(
                expected = ("いれかえのつえ" :: Nil, "かいふくのつえ" :: Nil),
                (PlayerDriver.getStaves(0) |> List.map(s -> s#name),
                 PlayerDriver.getStaves(1) |> List.map(s -> s#name)))
        })

    /// P0 weapons=[槍], staves=[] / P1 weapons=[], staves=[回復]
    /// P0 の Weapon(0)=槍 と P1 の Staff(0)=回復 を交換 (種別跨ぎ)。
    /// 期待:
    ///   P0: weapons=[], staves=[回復]   (受け取った杖は staves 側に入る)
    ///   P1: weapons=[槍], staves=[]     (受け取った武器は weapons 側に入る)
    @Test
    def testSwapItemWeaponToStaffCrossesInventoryLists(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("iron_lance", fx#catalog);
        let live  = Staff.lookup("live_staff", fx#staffCatalog);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer({id = 0, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = spear :: Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.addOnePlayer({id = 1, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = Nil, staves = live :: Nil, consumables = Nil, rings = Nil});
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Weapon(0),
                partnerId   = 1,
                partnerKind = Some(PlayerData.ItemKind.Staff(0))
            });
            Assert.assertEq(
                expected = ((Nil, "かいふくのつえ" :: Nil), ("てつのやり" :: Nil, Nil)),
                ((PlayerDriver.getWeapons(0) |> List.map(w -> w#name),
                  PlayerDriver.getStaves(0)  |> List.map(s -> s#name)),
                 (PlayerDriver.getWeapons(1) |> List.map(w -> w#name),
                  PlayerDriver.getStaves(1)  |> List.map(s -> s#name))))
        })

    /// P0 weapons=[槍] / P1 weapons=[]
    /// P0 の Weapon(0)=槍 を P1 の空スロット (partnerKind = None) に渡す。
    /// 期待:
    ///   P0: weapons=[]      (槍 が消える、自分のスロットは空になる)
    ///   P1: weapons=[槍]    (槍 を受け取る)
    @Test
    def testSwapItemTransfersToEmptySlot(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("iron_lance", fx#catalog);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer({id = 0, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = spear :: Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.addOnePlayer({id = 1, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Weapon(0),
                partnerId   = 1,
                partnerKind = None
            });
            Assert.assertEq(
                expected = (Nil, "てつのやり" :: Nil),
                (PlayerDriver.getWeapons(0) |> List.map(w -> w#name),
                 PlayerDriver.getWeapons(1) |> List.map(w -> w#name)))
        })

    /// TradeMenu 「空スロット picker」シナリオ相当: 自分が空スロット pick、相手の実体を選択
    /// → TradeMenuUi.applyTradeSwap が引数を反転して `swapItem({selfId=partner, ...})`
    /// を呼ぶ経路の確認 (P1 が giver、P0 が receiver)。
    /// 配置: P0 weapons=[] / P1 weapons=[槍]
    /// 期待:
    ///   P0: weapons=[槍]    (相手から槍を受け取る)
    ///   P1: weapons=[]      (槍を渡して空になる)
    @Test
    def testSwapItemPartnerAsGiverTransfersToSelf(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("iron_lance", fx#catalog);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer({id = 0, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.addOnePlayer({id = 1, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample,
                                       weapons = spear :: Nil, staves = Nil, consumables = Nil, rings = Nil});
            PlayerDriver.swapItem({
                selfId      = 1,
                selfKind    = PlayerData.ItemKind.Weapon(0),
                partnerId   = 0,
                partnerKind = None
            });
            Assert.assertEq(
                expected = ("てつのやり" :: Nil, Nil),
                (PlayerDriver.getWeapons(0) |> List.map(w -> w#name),
                 PlayerDriver.getWeapons(1) |> List.map(w -> w#name)))
        })

    /// こうかんで消費アイテム（きずぐすり）も移動できる。
    /// 配置: P0 consumables=[きずぐすり] / P1 consumables=[]。
    /// P0 の Consumable(0) を P1 の空スロット(partnerKind=None)へ渡す。
    /// 期待: P0 は空、P1 が きずぐすり を受け取る。
    @Test
    def testSwapItemConsumableTransfersToEmptySlot(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let potion = ({name = "きずぐすり",
                        effect = Consumable.ConsumableEffect.Heal, magnitude = 10, duration = 0,
                        healAmount = 10, durability = 3, weight = 0.5,
                        sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                                    offset = {x = 0.0, y = 0.0},
                                    scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
                        description = "", effectRule = None}:
                        Consumable.ConsumableResource);
        let mkSpawn = (id, cons) -> ({id = id, classId = "test_player", gridPos = {x = 0, y = 0},
                                       resource = fx#unitSample, weapons = Nil, staves = Nil,
                                       consumables = cons, rings = Nil}: PlayerDriver.Spawn);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer(mkSpawn(0, potion :: Nil));
            PlayerDriver.addOnePlayer(mkSpawn(1, Nil));
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Consumable(0),
                partnerId   = 1,
                partnerKind = None
            });
            Assert.assertEq(
                expected = (Nil, "きずぐすり" :: Nil),
                (PlayerDriver.getConsumables(0) |> List.map(c -> c#name),
                 PlayerDriver.getConsumables(1) |> List.map(c -> c#name)))
        })

    /// こうかんで指輪も移動できる（指輪を交換対象にした回帰確認）。
    /// 配置: P0 rings=[ちからのゆびわ] / P1 rings=[]。
    /// P0 の Ring(0) を P1 の空スロット(partnerKind=None)へ渡す。
    /// 期待: P0 は空、P1 が指輪を受け取る。
    @Test
    def testSwapItemRingTransfersToEmptySlot(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let ring = Ring.lookup("power_ring", Ring.load());
        let mkSpawn = (id, rings) -> ({id = id, classId = "test_player", gridPos = {x = 0, y = 0},
                                        resource = fx#unitSample, weapons = Nil, staves = Nil,
                                        consumables = Nil, rings = rings}: PlayerDriver.Spawn);
        // 在庫は World 権威＝spawn と swap と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer(mkSpawn(0, ring :: Nil));
            PlayerDriver.addOnePlayer(mkSpawn(1, Nil));
            PlayerDriver.swapItem({
                selfId      = 0,
                selfKind    = PlayerData.ItemKind.Ring(0),
                partnerId   = 1,
                partnerKind = None
            });
            Assert.assertEq(
                expected = (Nil, ring#name :: Nil),
                (PlayerDriver.getRings(0) |> List.map(r -> r#name),
                 PlayerDriver.getRings(1) |> List.map(r -> r#name)))
        })

    // ========================================================================
    // フロア進行 — 階段退場 (useStairs) / フロア終了判定 / 持ち越し (reconcileWithCarry)
    // ========================================================================

    /// 階段を使った味方は「退場」する: usedStairs / hidden / waited が同時に立つ。
    /// hidden で盤面・カーソルから外れ、waited で行動済み扱いになって動けなくなる。
    /// usedStairs / waited / hidden はすべて World 権威（`World.Cmd` が唯一の writer）。
    @Test
    def testUseStairsExitsUnitFromFloor(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let sp = ({id = 0, classId = "test_player", gridPos = {x = 3, y = 3}, resource = fx#unitSample,
                   weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        region rc {
            let (_, w) = TestUnitFixtures.withWorldApplied(rc, () -> {
                PlayerDriver.addOnePlayer(sp);
                PlayerDriver.useStairs(0)
            });
            let ref = World.EntityRef.Player(0);
            Assert.assertEq(
                expected = (true, true, true),
                (World.usedStairsOf(ref, w) |> Option.getWithDefault(false),
                 World.waitedOf(ref, w) |> Option.getWithDefault(false),
                 World.playerHiddenOf(ref, w)))
        }

    /// フロア終了は「生存味方が全員」階段を使ったときだけ true。
    /// 味方 2 人のうち 1 人だけ使った段階では false、2 人とも使うと true。
    /// usedStairs/hp は World 権威＝spawn と useStairs と読みを同一 World（withWorldCommand）に積む。
    @Test
    def testAllLivingUsedStairsRequiresEveryone(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        region rc {
            let (afterOne, afterTwo) = TestUnitFixtures.withWorldCommand(rc, () -> {
                PlayerDriver.addOnePlayer(mkSpawn(0, {x = 3, y = 3}));
                PlayerDriver.addOnePlayer(mkSpawn(1, {x = 4, y = 3}));
                PlayerDriver.useStairs(0);
                let one = PlayerDriver.allLivingUsedStairs();
                PlayerDriver.useStairs(1);
                let two = PlayerDriver.allLivingUsedStairs();
                (one, two)
            });
            Assert.assertEq(expected = (false, true), (afterOne, afterTwo))
        }

    /// 次フロアの持ち越し: carry に居る味方は HP / 武器を引き継ぎ、carry に居ない id
    /// （前フロアで戦死）はノードごと除去される。
    /// 配置: 味方 0/1/2 をフル HP で生成 → carry = {0: HP3 + 槍, 1: HP7} のみ。
    /// 期待: 残るのは 0,1 のみ。HP は 3 / 7。0 の武器は てつのやり。
    @Test
    def testReconcileWithCarryPersistsHpAndDropsDead(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("iron_lance", fx#catalog);
        let mkSpawn = id -> ({id = id, classId = "test_player", gridPos = {x = 0, y = 0}, resource = fx#unitSample,
                               weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        let baseStats = LevelSystem.statsOf(fx#unitSample);
        let carry =
            ({id = 0, hp = 3, weapons = spear :: Nil, staves = Nil, consumables = Nil,
              rings = Nil, ringEquipped = false, level = 1, exp = 0, stats = baseStats}: PlayerDriver.CarryData) ::
            ({id = 1, hp = 7, weapons = Nil,          staves = Nil, consumables = Nil,
              rings = Nil, ringEquipped = false, level = 1, exp = 0, stats = baseStats}: PlayerDriver.CarryData) :: Nil;
        // 在庫は World 権威＝spawn と carry 反映と読みを同一 World（1 回の discharge）に載せる。
        TestUnitFixtures.dischargeWorldCommand(() -> {
            PlayerDriver.addOnePlayer(mkSpawn(0));
            PlayerDriver.addOnePlayer(mkSpawn(1));
            PlayerDriver.addOnePlayer(mkSpawn(2));
            PlayerDriver.reconcileWithCarry(carry);
            Assert.assertEq(
                expected = (0 :: 1 :: Nil, 3, 7, "てつのやり" :: Nil),
                (PlayerDriver.getAll() |> List.map(d -> d#id),
                 PlayerDriver.getHp(0),
                 PlayerDriver.getHp(1),
                 PlayerDriver.getWeapons(0) |> List.map(weapon -> weapon#name)))
        })

    // ========================================================================
    // ゲームオーバー条件 — ロード（id 0）が倒れたら 1F やり直し
    // ========================================================================

    /// ロード(id 0)が倒れると、ほかの味方が生き残っていてもゲームオーバー（1F やり直し）。
    /// 配置: ロード id0 + 味方 id1。killed=[0]（ロード死亡）。
    /// 期待: GameOverRequest が飛ぶ（flag=true）。死亡した id0 は World から除去され、
    ///       生存者 id1 はゲームオーバー画面中は盤面に残る（パーティ全消しは restart 時の
    ///       resetForGameOver の責務であり、removeDeadAndCheckGameOver は死亡駒のみ除去する）。
    @Test
    def testLordDeathTriggersGameOverEvenWithSurvivors(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        region rc {
            let flagRef = Ref.fresh(rc, false);
            let remaining = TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withNoSelection(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        withGameOverFlag(flagRef, () -> {
                            PlayerDriver.addOnePlayer(mkSpawn(0, {x = 3, y = 3}));
                            PlayerDriver.addOnePlayer(mkSpawn(1, {x = 4, y = 3}));
                            PlayerDriver.removeDeadAndCheckGameOver(0 :: Nil);
                            PlayerDriver.getAll() |> List.map(d -> d#id)
                        }))));
            Assert.assertEq(expected = (true, 1 :: Nil), (Ref.get(flagRef), remaining))
        }

    /// ロード以外の味方が倒れても、ロードが健在ならゲームオーバーにはならない。
    /// 配置: ロード id0 + 味方 id1。killed=[1]（味方死亡）。
    /// 期待: GameOverRequest は飛ばず（flag=false）、id1 だけ取り除かれて id0 が残る。
    @Test
    def testNonLordDeathRemovesUnitWithoutGameOver(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, classId = "test_player", gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerDriver.Spawn);
        region rc {
            let flagRef = Ref.fresh(rc, false);
            let remaining = TestUnitFixtures.withWorldCommand(rc, () ->
                TestUnitFixtures.withNoSelection(() ->
                    TestUnitFixtures.withMockGameLogger(() ->
                        withGameOverFlag(flagRef, () -> {
                            PlayerDriver.addOnePlayer(mkSpawn(0, {x = 3, y = 3}));
                            PlayerDriver.addOnePlayer(mkSpawn(1, {x = 4, y = 3}));
                            PlayerDriver.removeDeadAndCheckGameOver(1 :: Nil);
                            PlayerDriver.getAll() |> List.map(d -> d#id)
                        }))));
            Assert.assertEq(expected = (false, 0 :: Nil), (Ref.get(flagRef), remaining))
        }

    // ========================================================================
    // 出撃メンバー選抜 — selectParty（ロード固定 + 残りからランダム 2 体）
    // 乱数に依存しないプロパティのみを検証する。
    // ========================================================================

    /// プールが 3 体以上なら、先頭（ロード）固定 + 残りから 2 体で計 3 体。
    /// 乱数に関わらず: head = ロード / 件数 3 / 重複なし / すべて元プールの要素。
    @Test
    def testSelectPartyKeepsLordFixedAndPicksThree(): Unit \ {Assert, Math.Random} =
        let party  = "lord" :: "a" :: "b" :: "c" :: "d" :: Nil;
        let result = PlayerDriver.selectParty(party);
        let distinct = Set.size(List.toSet(result)) == List.length(result);
        let subset   = List.forAll(x -> List.memberOf(x, party), result);
        Assert.assertEq(
            expected = (Some("lord"), 3, true, true),
            (List.head(result), List.length(result), distinct, subset))

    /// ちょうど 3 体（ロード + 2）なら全員が選ばれる（残り 2 体は両方出る）。
    @Test
    def testSelectPartyWithExactlyThreeReturnsAll(): Unit \ {Assert, Math.Random} =
        let party  = "lord" :: "a" :: "b" :: Nil;
        let result = PlayerDriver.selectParty(party);
        Assert.assertEq(
            expected = (Some("lord"), 3, true),
            (List.head(result), List.length(result),
             List.memberOf("a", result) and List.memberOf("b", result)))

    /// 候補がロードのみなら、ロード 1 体だけを返す。
    @Test
    def testSelectPartyLordOnlyReturnsLord(): Unit \ {Assert, Math.Random} =
        Assert.assertEq(expected = "lord" :: Nil, PlayerDriver.selectParty("lord" :: Nil))

    /// 候補が 3 未満（ロード + 1）なら、いる分だけ（ロード先頭 + その 1 体）を返す。
    @Test
    def testSelectPartyFewerThanThreeReturnsAvailable(): Unit \ {Assert, Math.Random} =
        let result = PlayerDriver.selectParty("lord" :: "a" :: Nil);
        Assert.assertEq(
            expected = (Some("lord"), 2, true),
            (List.head(result), List.length(result), List.memberOf("a", result)))

    /// 空プールは空を返す（防御的フォールバック、panic しない）。
    @Test
    def testSelectPartyEmptyReturnsEmpty(): Unit \ {Assert, Math.Random} =
        let empty: List[String] = Nil;
        Assert.assertEq(expected = empty, PlayerDriver.selectParty(empty))

    // ════════════════════════════════════════════════════════
    // firstWeaponIdxReaching — 攻撃中の武器選択ロジック（純粋）
    // ════════════════════════════════════════════════════════

    /// 射程 1-1 の剣。
    def swordWeapon(): UnitCatalog.WeaponResource =
        {range = ({min = 1, max = 1}: UnitCatalog.WeaponRange) | TestUnitFixtures.testWeapon()}

    /// 射程 2-2 の弓。
    def bowWeapon(): UnitCatalog.WeaponResource =
        {range = ({min = 2, max = 2}: UnitCatalog.WeaponRange) | TestUnitFixtures.testWeapon()}

    /// 指定の武器リストを持つ Data（位置・ステータスはダミー）。
    def playerWithWeapons(weapons: List[UnitCatalog.WeaponResource]): PlayerDriver.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 5, y = 5},
        moveTiles         = 5,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = TestUnitFixtures.testResource(5, 10),
        weapons           = weapons,
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
        statuses          = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
    }

    /// 距離 1 では剣 (index 0) が届く。
    @Test
    def testFirstWeaponIdxReachingPicksSwordAtDistance1(): Unit \ Assert =
        let data = playerWithWeapons(swordWeapon() :: bowWeapon() :: Nil);
        Assert.assertEq(expected = Some(0), PlayerDriver.firstWeaponIdxReaching(data, 1))

    /// 距離 2 では剣は届かず弓 (index 1) が届く。
    @Test
    def testFirstWeaponIdxReachingPicksBowAtDistance2(): Unit \ Assert =
        let data = playerWithWeapons(swordWeapon() :: bowWeapon() :: Nil);
        Assert.assertEq(expected = Some(1), PlayerDriver.firstWeaponIdxReaching(data, 2))

    /// どの武器も届かない距離 3 では None。
    @Test
    def testFirstWeaponIdxReachingNoneWhenOutOfRange(): Unit \ Assert =
        let data = playerWithWeapons(swordWeapon() :: bowWeapon() :: Nil);
        Assert.assertEq(expected = None, PlayerDriver.firstWeaponIdxReaching(data, 3))

    /// 同距離に届く武器が複数あるときは先頭の index を返す。
    @Test
    def testFirstWeaponIdxReachingReturnsFirstMatch(): Unit \ Assert =
        let data = playerWithWeapons(swordWeapon() :: swordWeapon() :: Nil);
        Assert.assertEq(expected = Some(0), PlayerDriver.firstWeaponIdxReaching(data, 1))

    // ========================================================================
    // transformableOf — ringman の特殊行動で「指輪に変えられる」装備外アイテムの列挙
    // ========================================================================

    /// transformableOf テスト用の最小指輪（効果なし）。
    def transformTestRing(name: String): Ring.RingResource = {
        name        = name,
        effect      = Ring.RingEffect.Trivial,
        power       = 0,
        weight      = 0.4,
        sprite      = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                        offset = {x = 0.0, y = 0.0},
                        scale = {x = 1.0, y = 1.0}, flipForFacing = false}: SpriteRes.SpriteResource),
        description = "",
        effectRule = None
    }

    /// 位置・装備以外はダミーで埋めた最小 Data 雛形（`{ ... | pdata(...)}` で部分上書きして使う）。
    def pdata(id: Int32, gridPos: {x = Int32, y = Int32}): PlayerDriver.Data = {
        id              = id,
        classId         = "test_player",
        gridPos         = gridPos,
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
        weapons         = Nil,
        staves          = Nil,
        consumables     = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Dir4.Down,
        hidden          = false,
        usedStairs      = false,
        level           = 1,
        exp             = 0,
        pendingLevelUp  = None,
        statuses        = Nil,
        rings           = Nil,
        ringEquipped    = false,
        followUpUsed    = false
    }

    /// 装備中の武器（先頭）と装備中の指輪（ringEquipped 時の先頭）は対象外。
    /// 武器2本（先頭=装備）+ 指輪2個（ringEquipped で先頭=装備）→ 対象は weapons[1] と rings[1]。
    @Test
    def testTransformableExcludesEquipped(): Unit \ Assert =
        let player = {
            weapons      = TestUnitFixtures.testWeapon() :: TestUnitFixtures.testWeapon() :: Nil,
            rings        = transformTestRing("a") :: transformTestRing("b") :: Nil,
            ringEquipped = true
            | pdata(0, {x = 0, y = 0})};
        Assert.assertEq(
            expected = PlayerData.ItemKind.Weapon(1) :: PlayerData.ItemKind.Ring(1) :: Nil,
            List.map(fst, PlayerDriver.transformableOf(player)))

    /// 指輪を 1 つも装備していない（ringEquipped=false）なら、先頭の指輪も対象に含まれる。
    @Test
    def testTransformableIncludesUnequippedRings(): Unit \ Assert =
        let player = {
            rings        = transformTestRing("a") :: transformTestRing("b") :: Nil,
            ringEquipped = false
            | pdata(0, {x = 0, y = 0})};
        Assert.assertEq(
            expected = PlayerData.ItemKind.Ring(0) :: PlayerData.ItemKind.Ring(1) :: Nil,
            List.map(fst, PlayerDriver.transformableOf(player)))
}
