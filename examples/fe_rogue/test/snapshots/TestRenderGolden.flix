// TestRenderGolden — 本番 renderFrame（render-from-World パイプライン）の描画リスト golden。
//
// World fixture（TestWorldFixtures.duelWorld）を production の
// `renderFrameForCapture`（＝renderFrame そのもの）に通し、renderCommands の描画リストを
// RenderDescribe で 1 行 = 1 描画物のテキストに変換して golden で凍結する。
// 駒 sprite / HP バー / 武器アイコン / 階段 / カーソルなど render-from-World の合成が
// 1 枚に載るので、描画パイプラインの黙った変化（描き漏れ / 二重描画 / z 崩れ）を検出できる。
//
// もう 1 本は「盤面レス World（空 World）」で renderFrame が安全に完走することの pin。
// 駒 / 盤面が無い画面（Title 等）で World render System が走っても落ちない保証の土台になる。
mod TestRenderGolden {

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
    /// 駒の位置 / HP / 資源はすべて `world` の store 由来（renderPos は fixture がセル中心で seed 済み）。
    /// テクスチャ実寸表は実 PNG から読む（sprite 描画がテクスチャ登録を要求するため）。
    def captureFrames(world: World): List[RenderDescribe.Frame] \ {Fs.FileRead, IO} =
        region rc {
            let catalogs = loadCatalogs();
            let texInfo = SnapshotSupport.buildTextureInfo(
                SnapshotSupport.buildTexturePaths(), RenderDescribe.atlasDim());
            let (_, frames) = RenderDescribe.withRecordingGame(rc, texInfo, () ->
                run {
                    TestUnitFixtures.withWorldQuery(world, () ->
                        renderFrameForCapture(catalogs, world))
                } with TurnPhase.withState(rc)
                  with SelectedPlayer.withState(rc)
                  with CursorState.withState(rc)
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
        let frames = captureFrames(TestWorldFixtures.duelWorld());
        Assert.assertEq(expected = Some(None),
            frames |> List.head |> Option.map(f ->
                RenderDescribe.matchGolden("render_frame_duel", RenderDescribe.describe(f))))

    /// 盤面レス World（空 World = Title 相当）でも renderFrame が完走し、
    /// その（ほぼ空の）描画リストを golden で凍結する。盤面が無い画面で render System が
    /// 走っても落ちないことの恒久 pin。
    @Test
    def testRenderFrameBoardlessMatchesGolden(): Unit \ {Assert, Fs.FileRead, Fs.FileWrite, IO} =
        let frames = captureFrames(World.empty());
        Assert.assertEq(expected = Some(None),
            frames |> List.head |> Option.map(f ->
                RenderDescribe.matchGolden("render_frame_boardless", RenderDescribe.describe(f))))
}
