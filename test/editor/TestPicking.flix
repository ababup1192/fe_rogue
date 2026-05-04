// Tests for Picking — マウス位置 → 編集対象ノード 1 件選択（純粋関数）
//
// pickTopAt は `GameEngine.Game` 等のエフェクトを必要としないので、
// 候補リスト + シーンを手で組んで直接呼べる

// ========================================================================
// テスト用ヘルパー
// ========================================================================

/// 中央基準の Sprite2D を指定 zIndex で root に置いたシーンを作る
def sceneWithSprite(name: NodeName, pos: Vec2.Vec2, zIndex: Int32): Scene[NodeTag] =
    let sprite = Sprite2D.make("dummy.png", pos, {x = 1.0, y = 1.0})
        |> CanvasItem.setZIndex(zIndex);
    let s: Scene[NodeTag] = Scene.empty();
    s |> Scene.addNode(name, EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

/// 2 つの Sprite2D を root に並べたシーン（重なる位置に配置可）
def sceneWith2Sprites(nameA: NodeName, posA: Vec2.Vec2, zA: Int32,
                      nameB: NodeName, posB: Vec2.Vec2, zB: Int32): Scene[NodeTag] =
    let spriteA = Sprite2D.make("dummy.png", posA, {x = 1.0, y = 1.0})
        |> CanvasItem.setZIndex(zA);
    let spriteB = Sprite2D.make("dummy.png", posB, {x = 1.0, y = 1.0})
        |> CanvasItem.setZIndex(zB);
    let s: Scene[NodeTag] = Scene.empty();
    s |> Scene.addNode(nameA, EngineNode.Sprite2DWithState(spriteA, NodeTag.NoTag))
      |> Scene.addNode(nameB, EngineNode.Sprite2DWithState(spriteB, NodeTag.NoTag))

/// 32x32 で中央基準の EditableEntry を 1 件作る（テスト共通ヘルパー）
def entry32Centered(name: NodeName): EditableNode.EditableEntry = {
    jsonPath = "test.scene.json",
    nodePath = name :: Nil,
    width = 32.0,
    height = 32.0,
    topLeftOffset = {x = -16.0, y = -16.0}
}

// ========================================================================
// pickTopAt — 単独 hit / 非 hit
// ========================================================================

/// 単独のスプライトの中心をクリックすれば、そのスプライトが返る
@Test
def testPickTopAtSingleHit(): Unit \ Assert =
    let scene = sceneWithSprite("a", {x = 100.0, y = 100.0}, 0i32);
    let entries = entry32Centered("a") :: Nil;
    let result = Picking.pickTopAt({x = 100.0, y = 100.0}, entries, {x = 0.0, y = 0.0}, scene);
    match result {
        case Some((entry, globalPos)) =>
            Assert.assertEq(
                expected = ("a" :: Nil, 100.0, 100.0),
                (entry#nodePath, globalPos#x, globalPos#y))
        case None => bug!("expected hit, got None")
    }

/// 矩形外なら None
@Test
def testPickTopAtMissReturnsNone(): Unit \ Assert =
    let scene = sceneWithSprite("a", {x = 100.0, y = 100.0}, 0i32);
    let entries = entry32Centered("a") :: Nil;
    let result = Picking.pickTopAt({x = 500.0, y = 500.0}, entries, {x = 0.0, y = 0.0}, scene);
    Assert.assertEq(expected = true, Option.isEmpty(result))

/// entries が空なら None
@Test
def testPickTopAtEmptyEntriesReturnsNone(): Unit \ Assert =
    let scene: Scene[NodeTag] = Scene.empty();
    let result = Picking.pickTopAt({x = 0.0, y = 0.0}, Nil, {x = 0.0, y = 0.0}, scene);
    Assert.assertEq(expected = true, Option.isEmpty(result))

// ========================================================================
// pickTopAt — z-index 優先（直近修正の回帰防止）
// ========================================================================

/// 重なっている 2 つのスプライトのうち、zIndex が大きい方が選ばれる。
/// entries の並び順に関係なく z で勝負する
@Test
def testPickTopAtPicksHigherZIndex(): Unit \ Assert =
    // a: z=0, b: z=10。同じ位置に置いて重ねる
    let scene = sceneWith2Sprites(
        "a", {x = 100.0, y = 100.0}, 0i32,
        "b", {x = 100.0, y = 100.0}, 10i32);
    // entries の順序は a, b（a が先頭でも結果は b）
    let entries = entry32Centered("a") :: entry32Centered("b") :: Nil;
    let result = Picking.pickTopAt({x = 100.0, y = 100.0}, entries, {x = 0.0, y = 0.0}, scene);
    match result {
        case Some((entry, _)) =>
            Assert.assertEq(expected = "b" :: Nil, entry#nodePath)
        case None => bug!("expected hit, got None")
    }

/// entries の順序が逆（b, a）でも、z が大きい方（b）が勝つ
@Test
def testPickTopAtPicksHigherZRegardlessOfOrder(): Unit \ Assert =
    let scene = sceneWith2Sprites(
        "a", {x = 100.0, y = 100.0}, 0i32,
        "b", {x = 100.0, y = 100.0}, 10i32);
    let entries = entry32Centered("b") :: entry32Centered("a") :: Nil;
    let result = Picking.pickTopAt({x = 100.0, y = 100.0}, entries, {x = 0.0, y = 0.0}, scene);
    match result {
        case Some((entry, _)) =>
            Assert.assertEq(expected = "b" :: Nil, entry#nodePath)
        case None => bug!("expected hit, got None")
    }

/// z が同値なら entries の後ろ（preorder で後 = より深い／後発）が選ばれる
@Test
def testPickTopAtTieBreaksToLaterEntry(): Unit \ Assert =
    let scene = sceneWith2Sprites(
        "a", {x = 100.0, y = 100.0}, 5i32,
        "b", {x = 100.0, y = 100.0}, 5i32);
    let entries = entry32Centered("a") :: entry32Centered("b") :: Nil;
    let result = Picking.pickTopAt({x = 100.0, y = 100.0}, entries, {x = 0.0, y = 0.0}, scene);
    match result {
        case Some((entry, _)) =>
            Assert.assertEq(expected = "b" :: Nil, entry#nodePath)
        case None => bug!("expected hit, got None")
    }

/// 重なっていない 2 つのうち、マウスが乗っている方が選ばれる
@Test
def testPickTopAtNonOverlappingHitsCorrectOne(): Unit \ Assert =
    // a は (50, 50) 中心、b は (200, 200) 中心。マウスは (200, 200)
    let scene = sceneWith2Sprites(
        "a", {x = 50.0, y = 50.0}, 0i32,
        "b", {x = 200.0, y = 200.0}, 0i32);
    let entries = entry32Centered("a") :: entry32Centered("b") :: Nil;
    let result = Picking.pickTopAt({x = 200.0, y = 200.0}, entries, {x = 0.0, y = 0.0}, scene);
    match result {
        case Some((entry, _)) =>
            Assert.assertEq(expected = "b" :: Nil, entry#nodePath)
        case None => bug!("expected hit, got None")
    }

// ========================================================================
// makeBBox — 純粋ジオメトリ
// ========================================================================

/// 中央基準（topLeftOffset = (-w/2, -h/2)）の場合、refPos からの bbox は左上が
/// refPos - (w/2, h/2) になる
@Test
def testMakeBBoxCentered(): Unit \ Assert =
    let entry = entry32Centered("x");
    let bbox = Picking.makeBBox({x = 100.0, y = 100.0}, entry);
    Assert.assertEq(
        expected = (84.0, 84.0, 32.0, 32.0),
        (bbox#position#x, bbox#position#y, bbox#size#x, bbox#size#y))

/// topLeftOffset = (0, 0) なら refPos がそのまま bbox の左上
@Test
def testMakeBBoxTopLeftAnchored(): Unit \ Assert =
    let entry: EditableNode.EditableEntry = {
        jsonPath = "test.scene.json",
        nodePath = "x" :: Nil,
        width = 50.0,
        height = 20.0,
        topLeftOffset = {x = 0.0, y = 0.0}
    };
    let bbox = Picking.makeBBox({x = 10.0, y = 20.0}, entry);
    Assert.assertEq(
        expected = (10.0, 20.0, 50.0, 20.0),
        (bbox#position#x, bbox#position#y, bbox#size#x, bbox#size#y))
