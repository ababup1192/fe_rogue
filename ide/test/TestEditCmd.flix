// EditCmd（統一 Edit Command 層）の純粋部分テスト。Fs を伴わない live-only 適用と
// inverseOf（適用前状態の捕捉）を検証する。
mod TestEditCmd {

    enum Tag { case NoTag }

    def sceneWithSprite(name: String, pos: Vec2.Vec2): Scene[Tag] =
        let sprite = Sprite2D.make("tex", pos, {x = 1.0, y = 1.0});
        Scene.empty() |> Scene.addNode(name, EngineNode.Sprite2DWithState(sprite, Tag.NoTag))

    /// 親（子を持つ）ノードを足したシーン。親 global を fractional にできる。
    def sceneWithChild(parent: String, child: String,
                       parentPos: Vec2.Vec2, childLocal: Vec2.Vec2): Scene[Tag] =
        let p = Sprite2D.make("tex", parentPos, {x = 1.0, y = 1.0});
        let c = Sprite2D.make("tex", childLocal, {x = 1.0, y = 1.0});
        Scene.empty()
            |> Scene.addNode(parent, EngineNode.Sprite2DWithState(p, Tag.NoTag))
            |> Scene.addChild(parent, child, EngineNode.Sprite2DWithState(c, Tag.NoTag))

    /// applyLive はノードのグローバル位置を pos に設定する
    @Test
    def testApplyLiveSetsPosition(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 10.0, y = 20.0});
        let cmd = EditCmd.Command.SetGlobalPos({
            jsonPath = "s.json", nodePath = "hero" :: Nil,
            jsonNodePath = "hero" :: Nil, pos = {x = 64.0, y = 32.0}});
        let moved = EditCmd.applyLive(cmd, scene);
        let p = Scene.globalPositionAt("hero" :: Nil, moved);
        Assert.assertEq(expected = (64.0, 32.0), (p#x, p#y))

    /// inverseOf は現在位置を捕捉する → 逆命令を適用すると元に戻る
    @Test
    def testInverseRestoresOriginalPosition(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 10.0, y = 20.0});
        let fwd = EditCmd.Command.SetGlobalPos({
            jsonPath = "s.json", nodePath = "hero" :: Nil,
            jsonNodePath = "hero" :: Nil, pos = {x = 100.0, y = 100.0}});
        let inv = EditCmd.inverseOf(fwd, scene);          // 現在(10,20)を捕捉
        let moved = EditCmd.applyLive(fwd, scene);         // (100,100) へ
        let back = EditCmd.applyLive(inv, moved);          // (10,20) へ戻る
        let p = Scene.globalPositionAt("hero" :: Nil, back);
        Assert.assertEq(expected = (10.0, 20.0), (p#x, p#y))

    /// SetRotation: applyLive が回転を設定する
    @Test
    def testApplyLiveSetsRotation(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 0.0, y = 0.0});
        let cmd = EditCmd.Command.SetRotation({
            jsonPath = "s.json", nodePath = "hero" :: Nil,
            jsonNodePath = "hero" :: Nil, rotation = 1.5});
        let moved = EditCmd.applyLive(cmd, scene);
        let rot = match Scene.getEngineNode("hero" :: Nil, moved) {
            case Some(en) => Node2D.getRotation(en)
            case None     => -1.0
        };
        Assert.assertEq(expected = 1.5, rot)

    /// SetRotation: inverseOf が現在回転を捕捉 → 逆適用で元に戻る
    @Test
    def testInverseRestoresRotation(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 0.0, y = 0.0});
        let fwd = EditCmd.Command.SetRotation({
            jsonPath = "s.json", nodePath = "hero" :: Nil,
            jsonNodePath = "hero" :: Nil, rotation = 2.0});
        let inv = EditCmd.inverseOf(fwd, scene);       // 現在(0.0)を捕捉
        let moved = EditCmd.applyLive(fwd, scene);      // 2.0 へ
        let back = EditCmd.applyLive(inv, moved);       // 0.0 へ戻る
        let rot = match Scene.getEngineNode("hero" :: Nil, back) {
            case Some(en) => Node2D.getRotation(en)
            case None     => -1.0
        };
        Assert.assertEq(expected = 0.0, rot)

    /// Resize: snapshot 状態へ戻す（位置）。snapshotForResize で捕捉 → 移動 → 復元。
    @Test
    def testResizeRestoresSnapshotPosition(): Unit \ Assert =
        let scene = sceneWithSprite("hero", {x = 10.0, y = 20.0});
        let snap = match Scene.getEngineNode("hero" :: Nil, scene) {
            case Some(en) => EditableNode.snapshotForResize("hero" :: Nil, en)
            case None     => bug!("node missing")
        };
        let movedAway = EditCmd.applyLive(EditCmd.Command.SetGlobalPos({
            jsonPath = "s.json", nodePath = "hero" :: Nil,
            jsonNodePath = "hero" :: Nil, pos = {x = 99.0, y = 99.0}}), scene);
        let restored = EditCmd.applyLive(EditCmd.Command.Resize({
            jsonPath = "s.json", snapshots = snap :: Nil}), movedAway);
        let p = Scene.globalPositionAt("hero" :: Nil, restored);
        Assert.assertEq(expected = (10.0, 20.0), (p#x, p#y))

    /// 入れ子ノード：inverseOf が子の global を捕捉し、逆適用で global が元に戻る
    /// （setGlobalPositionAt の親 global 減算経路を実際に通す）。
    @Test
    def testInverseRestoresNestedChildGlobal(): Unit \ Assert =
        let scene = sceneWithChild("parent", "kid",
                                   {x = 30.0, y = 30.0}, {x = 5.0, y = 5.0});
        let np = "parent" :: "kid" :: Nil;
        let before = Scene.globalPositionAt(np, scene);    // (35, 35)
        let fwd = EditCmd.Command.SetGlobalPos({
            jsonPath = "s.json", nodePath = np, jsonNodePath = np,
            pos = {x = 80.0, y = 80.0}});
        let inv = EditCmd.inverseOf(fwd, scene);
        let moved = EditCmd.applyLive(fwd, scene);
        let back = EditCmd.applyLive(inv, moved);
        let after = Scene.globalPositionAt(np, back);
        Assert.assertEq(expected = (before#x, before#y), (after#x, after#y))
}
