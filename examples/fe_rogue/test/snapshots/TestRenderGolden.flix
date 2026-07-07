// TestRenderGolden — 本番 renderFrame（render-from-World パイプライン）の描画リスト golden。
//
// World fixture（TestWorldFixtures.duelWorld）と最小 scene（marker 2 体）を、production の
// `renderFrameForCapture`（＝renderFrame そのもの）に通し、renderCommands の描画リストを
// RenderDescribe で 1 行 = 1 描画物のテキストに変換して golden で凍結する。
// 駒 sprite / HP バー / 武器アイコン / 階段 / カーソルなど render-from-World の合成が
// 1 枚に載るので、描画パイプラインの黙った変化（描き漏れ / 二重描画 / z 崩れ）を検出できる。
//
// もう 1 本は「盤面レス World（空 World + 空 scene）」で renderFrame が安全に完走することの pin。
// ノード / 盤面が無い画面（Title 等）で World render System が走っても落ちない保証の土台になる。
mod TestRenderGolden {

    // ════════════════════════════════════════════════════════
    // フィクスチャ（duelWorld の view 側 twin: marker 2 体入りの最小 scene）
    // ════════════════════════════════════════════════════════

    /// duelWorld の味方 id0（(2,2)・HP10）と同じ内容の scene 側 Data。
    /// renderUnits は scene の Data（resource の見た目）と World store（位置ゲート）の両方を読む。
    def playerData(): PlayerScene.Data = {
        id                = 0,
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
        statuses          = Nil,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    /// duelWorld の敵 id1（(3,2)・HP10）と同じ内容の scene 側 Data。
    def enemyData(): EnemyScene.Data = {
        id             = 1,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 4,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(4, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// World ルート + 味方/敵 marker（セル中心に配置）の最小 scene。
    /// 駒の視覚位置は marker が権威なので、duelWorld の renderPos と同じセル中心に置く。
    def duelScene(): Scene[NodeTag] =
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(MapSnapshot.cellCenter({x = 2, y = 2})),
                                             NodeTag.Player(playerData())))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(1),
                EngineNode.Marker2DWithState(Marker2D.make(MapSnapshot.cellCenter({x = 3, y = 2})),
                                             NodeTag.Enemy(enemyData())))

    /// renderFrame が要求するカタログ束（描画で実際に読むのは chests のみだが、record は全部埋める）。
    def loadCatalogs(): GameLifecycle.Catalogs \ Fs.FileRead =
        let weapons = WeaponCatalog.load();
        {weapons     = weapons,
         players     = UnitCatalog.load(AssetPath.resolve("resources/units.json"), weapons),
         enemies     = EnemyCatalog.load(),
         floors      = FloorCatalog.load(),
         staves      = Staff.load(),
         consumables = Consumable.load(),
         chests      = ChestCatalog.load(),
         rings       = Ring.load()}

    // ════════════════════════════════════════════════════════
    // 駆動（本番 renderFrame を記録 handler の中で 1 回呼ぶ）
    // ════════════════════════════════════════════════════════

    /// production の renderFrame を read 系 resource の初期値で 1 フレーム分駆動し、
    /// renderCommands に渡った描画リスト（Frame 列。renderFrame は 1 回だけ呼ぶので長さ 1）を返す。
    /// テクスチャ実寸表は実 PNG から読む（sprite 描画がテクスチャ登録を要求するため）。
    def captureFrames(world: World, scene: Scene[NodeTag]): List[RenderDescribe.Frame] \ {Fs.FileRead, IO} =
        region rc {
            let catalogs = loadCatalogs();
            let texInfo = SnapshotSupport.buildTextureInfo(
                SnapshotSupport.buildTexturePaths(), RenderDescribe.atlasDim());
            let (_, frames) = RenderDescribe.withRecordingGame(rc, texInfo, () ->
                run {
                    TestUnitFixtures.withWorldQuery(world, () ->
                        renderFrameForCapture(catalogs, world, scene))
                } with TurnPhase.withState(rc)
                  with SelectedPlayer.withState(rc)
                  with CursorState.withState(rc)
                  with CameraState.withState(rc)
                  with ArrowCursorState.withState(rc)
                  with MinimapState.withState(rc)
                  with RangeOverlayState.withState(rc)
                  with UiWorldState.withState(rc)
                  with UnitHPBarRender.withForecast(rc));
            frames
        }

    // ════════════════════════════════════════════════════════
    // golden テスト
    // ════════════════════════════════════════════════════════

    /// 代表 World（duelWorld: 駒 2 体 + 盤面 + 階段）の renderFrame 描画リストを golden で凍結する。
    @Test
    def testRenderFrameDuelMatchesGolden(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} =
        let frames = captureFrames(TestWorldFixtures.duelWorld(), duelScene());
        Assert.assertEq(expected = Some(None),
            frames |> List.head |> Option.map(f ->
                RenderDescribe.matchGolden("render_frame_duel", RenderDescribe.describe(f))))

    /// 盤面レス World（空 World + 空 scene = Title 相当）でも renderFrame が完走し、
    /// その（ほぼ空の）描画リストを golden で凍結する。盤面が無い画面で render System が
    /// 走っても落ちないことの恒久 pin。
    @Test
    def testRenderFrameBoardlessMatchesGolden(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} =
        let frames = captureFrames(World.empty(), Scene.empty());
        Assert.assertEq(expected = Some(None),
            frames |> List.head |> Option.map(f ->
                RenderDescribe.matchGolden("render_frame_boardless", RenderDescribe.describe(f))))
}
