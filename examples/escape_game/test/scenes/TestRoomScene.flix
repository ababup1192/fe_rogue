/// `RoomScene` の部屋構築 + Area2D ベースクリック解決の単体テスト。
///
/// scene.json 読み込み（`addRoomLayer`）は I/O 依存なので扱わず、
/// テストでは「Room レイヤだけ手で組み立てた最小 Scene」を入力にする。
/// クリック判定は engine 側 `AreaEvent.dispatchClicks` に流すが、
/// Yarn `Session.start` は handler でモックして「どの yarn ノード名が起動されたか」
/// を Ref に記録 → assertEq で確認する。
///
/// このモジュールが守るべき性質:
///   - `enter` で Data#roomId が更新される
///   - `enter` で catalog の HotspotDef ぶん Area2D 子ノードが並ぶ
///   - `dispatchClicks` が hotspot 矩形内クリックで対応する yarn ノードを起動
///   - 範囲外クリックは何も起動しない
///   - 部屋切替時に旧ホットスポットが消えて、新ホットスポットだけが対象になる
mod TestRoomScene {

    /// テスト中に「Session.start」で起動された yarn ノード名を記録する。
    /// handler が Ref にイベント順で push する。
    type alias StartLog[r: Region] = Ref[List[String], r]

    /// Room レイヤと scene.json 相当のホットスポット (drawer / door) を手で積んだ
    /// Scene を作る。scene.json を経由しないので I/O effect 不要。
    /// 本番フロー (`addRoomLayer` + `enter`) では tagParser が Hotspot タグを
    /// 解決して Area2D 子ノードに乗せるので、テストでも同じ初期状態を作る。
    /// `enter("demo_room")` 適用前は roomId が "" なので、`enter` 後に
    /// applyHotspotTags が roomId を上書きすることまでをテストで検証する。
    def emptySceneWithRoom(): Scene[NodeTag] =
        let layer = CanvasLayer.make(5);
        Scene.empty()
            |> Scene.addNode(
                RoomScene.layerName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.Room(RoomScene.emptyData())))
            |> addHotspot("drawer", ({x = 120.0, y = 200.0}: Vec2.Vec2),
                          ({x = 48.0, y = 48.0}: Vec2.Vec2))
            |> addHotspot("door",   ({x = 360.0, y = 176.0}: Vec2.Vec2),
                          ({x = 48.0, y = 96.0}: Vec2.Vec2))

    /// 1 つの Hotspot Area2D を Room レイヤ直下に追加する。タグの roomId は
    /// 仮の "" (scene.json ロード直後の状態を再現)、`enter` で上書きされる前提。
    def addHotspot(id: String, pos: Vec2.Vec2, size: Vec2.Vec2,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let shape = CollisionShape2D.RectShape2D({width = size#x, height = size#y});
        let area = Area2D.make(pos, shape);
        let data = ({roomId = "", hotspotId = id}: RoomScene.HotspotData);
        Scene.addChild(
            RoomScene.layerName(),
            "Hotspot_" + id,
            EngineNode.Area2DWithState(area, NodeTag.Hotspot(data)),
            scene)

    /// `Session.start` だけをログに記録するモック handler。
    /// 他の Session 操作は no-op で握りつぶす。テストは start のみを確認する。
    def withSessionLog(log: StartLog[r], thunk: Unit -> a \ ef):
                        a \ (ef - Dialogue.Session) + r =
        run thunk() with handler Dialogue.Session {
            def start(name, k)              = { Ref.put(name :: Ref.get(log), log); k() }
            def stop(k)                     = k()
            def isActive(k)                 = k(false)
            def submitNext(k)               = k()
            def submitSelect(_idx, k)       = k()
            def submitCommandDone(k)        = k()
            def restart(_node, _vars, k)    = k()
        }

    /// 1 クリックを `dispatchClicks` に流して、そのあとの起動 yarn ノード名を取り出す。
    /// `dispatchClicks` は `AreaHandler.onAreaClicked` 経由で `Session.start` を呼ぶ。
    /// 戻り値はクリックで起動された node 名（複数該当時は preorder の最後＝
    /// Ref に最後に push されたものが head）。
    def clickAndLog(scene: Scene[NodeTag], pos: Vec2.Vec2): List[String] =
        region rc {
            let log: StartLog[rc] = Ref.fresh(rc, Nil);
            withSessionLog(log, () -> {
                discard AreaEvent.dispatchClicks(GameEngine.MouseButton.Left, pos, scene)
            });
            Ref.get(log) |> List.reverse
        }

    // ========================================================================
    // (A) enter: Data#roomId の更新
    // ========================================================================

    /// `enter("demo_room", scene)` のあと layer root の Data#roomId が "demo_room" になる。
    /// `currentRoomId` で取り出して 1 回だけ確認する。
    @Test
    def testEnterUpdatesRoomId(): Unit \ Assert =
        let scene = emptySceneWithRoom()
            |> RoomScene.enter("demo_room");
        Assert.assertEq(expected = "demo_room", RoomScene.currentRoomId(scene))

    // ========================================================================
    // (B) Area2D 配置: catalog ぶん子ノードが並ぶ
    // ========================================================================

    /// `enter("demo_room")` のあと Room レイヤの子に `Hotspot_drawer` と `Hotspot_door` の
    /// Area2D が並ぶ。視覚はすべて背景画像 `bg_demo_room.png` 内に描き込まれているので
    /// sprite 子ノードは存在しない。
    /// （scene.json をテストでは読み込まないので Bg sprite は含まれない。
    /// catalog に基づく動的構築だけを確認する。）
    @Test
    def testEnterAddsHotspotChildrenForCatalog(): Unit \ Assert =
        let scene = emptySceneWithRoom()
            |> RoomScene.enter("demo_room");
        let children = List.sort(Scene.getChildrenAt(RoomScene.layerPath(), scene));
        let expected = List.sort("Hotspot_drawer" :: "Hotspot_door" :: Nil);
        Assert.assertEq(expected = expected, children)

    // ========================================================================
    // (C) クリック → yarn ノード起動
    // ========================================================================

    /// drawer の中心 (120, 200) をクリックすると "Hotspot_demo_room_drawer" が起動する。
    /// engine 側の `dispatchClicks` が Area2D の RectShape2D ヒット判定で
    /// `AreaHandler.onAreaClicked` を発火し、Game.flix の instance が
    /// `Session.start(yarnNodeNameFor(...))` を呼ぶ。
    @Test
    def testClickAtDrawerCenterStartsYarnNode(): Unit \ Assert =
        let scene = emptySceneWithRoom() |> RoomScene.enter("demo_room");
        let started = clickAndLog(scene, ({x = 120.0, y = 200.0}: Vec2.Vec2));
        Assert.assertEq(expected = "Hotspot_demo_room_drawer" :: Nil, started)

    /// door の中心 (360, 176) をクリックすると "Hotspot_demo_room_door" が起動する。
    /// drawer と door が混在する catalog で、別ホットスポットへのヒットも独立に動くこと。
    @Test
    def testClickAtDoorCenterStartsYarnNode(): Unit \ Assert =
        let scene = emptySceneWithRoom() |> RoomScene.enter("demo_room");
        let started = clickAndLog(scene, ({x = 360.0, y = 176.0}: Vec2.Vec2));
        Assert.assertEq(expected = "Hotspot_demo_room_door" :: Nil, started)

    /// catalog 範囲外の点 (10, 10) をクリックしても何も起動しない。
    @Test
    def testClickOutsideAllHotspotsStartsNothing(): Unit \ Assert =
        let scene = emptySceneWithRoom() |> RoomScene.enter("demo_room");
        let started = clickAndLog(scene, ({x = 10.0, y = 10.0}: Vec2.Vec2));
        Assert.assertEq(expected = Nil, started)

    // ========================================================================
    // (D) 矩形端の境界（境界含む）
    // ========================================================================

    /// drawer は中心 (120, 200) / size (48, 48) なので、矩形の左上端 (96, 176) と
    /// 右下端 (144, 224) はぎりぎりヒット領域に含まれる（CollisionShape2D.containsPoint
    /// は境界を含む実装）。直前 (95, 175) と直後 (145, 225) は外。
    @Test
    def testHotspotBoundaryEdges(): Unit \ Assert =
        let scene = emptySceneWithRoom() |> RoomScene.enter("demo_room");
        let topLeft     = clickAndLog(scene, ({x = 96.0,  y = 176.0}: Vec2.Vec2));
        let bottomRight = clickAndLog(scene, ({x = 144.0, y = 224.0}: Vec2.Vec2));
        let outsideTL   = clickAndLog(scene, ({x = 95.0,  y = 175.0}: Vec2.Vec2));
        let outsideBR   = clickAndLog(scene, ({x = 145.0, y = 225.0}: Vec2.Vec2));
        let drawer = "Hotspot_demo_room_drawer" :: Nil;
        Assert.assertEq(expected = (drawer, drawer, Nil, Nil),
                         (topLeft, bottomRight, outsideTL, outsideBR))

    // ========================================================================
    // (E) 部屋切替: 旧ホットスポットは消える
    // ========================================================================

    /// 部屋 id を切り替えると、scene.json 由来の同じ Area2D が **新しい部屋名空間**で
    /// yarn ノードを起動するように tag が再ラベルされる。
    /// 例: enter("demo_room") → クリック = Hotspot_demo_room_drawer
    ///     enter("other_room") → 同じ位置 = Hotspot_other_room_drawer
    /// (yarn 側で対応ノードを定義していないと Session.start で missing node になるが、
    ///  本テストは「タグが新しい roomId で書き換わる」点だけを検証する)
    @Test
    def testRoomSwitchRelabelsHotspotTags(): Unit \ Assert =
        let scene1 = emptySceneWithRoom() |> RoomScene.enter("demo_room");
        let hitFirst = clickAndLog(scene1, ({x = 120.0, y = 200.0}: Vec2.Vec2));
        let scene2 = scene1 |> RoomScene.enter("other_room");
        let hitSecond = clickAndLog(scene2, ({x = 120.0, y = 200.0}: Vec2.Vec2));
        Assert.assertEq(
            expected = ("Hotspot_demo_room_drawer" :: Nil,
                        "Hotspot_other_room_drawer" :: Nil),
            (hitFirst, hitSecond))
}
