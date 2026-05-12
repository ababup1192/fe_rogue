// Tests for CharacterBody2D

mod TestCharacterBody2D {

    // ========================================================================
    // ヘルパー
    // ========================================================================

    /// 衝突体なしの空シーン
    def emptyScene(): Scene[Unit] = Scene.empty()

    /// pos に幅×高さの矩形衝突を持つ静的ボディだけのシーン
    def sceneWithRectWall(pos: Vec2.Vec2, w: Float64, h: Float64): Scene[Unit] =
        let body = StaticBody2D.make(pos,
            CollisionShape2D.RectShape2D({width = w, height = h}));
        Scene.empty()
            |> Scene.addNode("Wall",
                EngineNode.StaticBody2DWithState(body, ()))

    /// 14×14 矩形の衝突形状を持つ CharacterBody2D を生成する
    def makeBody(pos: Vec2.Vec2): CharacterBody2D =
        CharacterBody2D.make(pos, moveSpeed = 200.0)
            |> CharacterBody2D.setCollisionShape(
                Some(CollisionShape2D.RectShape2D({width = 14.0, height = 14.0})))

    // ========================================================================
    // make — デフォルト値
    // ========================================================================

    /// make で生成した CharacterBody2D のデフォルト値が Godot 準拠であること
    @Test
    def testCharacterBody2DMakeDefaults(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 10.0, y = 20.0}, moveSpeed = 200.0);
        let vel = CharacterBody2D.getVelocity(body);
        let up = CharacterBody2D.getUpDirection(body);
        Assert.assertEq(
            expected = (10.0, 20.0, 200.0, 0.0, 0.0, 0.0, -1.0, 4),
            (Node2D.getPosition(body)#x, Node2D.getPosition(body)#y,
             CharacterBody2D.getMoveSpeed(body),
             vel#x, vel#y,
             up#x, up#y,
             CharacterBody2D.getMaxSlides(body)))

    /// floorMaxAngle のデフォルトは π/4（≈ 0.785 rad = 45°）
    @Test
    def testCharacterBody2DDefaultFloorMaxAngle(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0);
        let angle = CharacterBody2D.getFloorMaxAngle(body);
        // π/4 ≈ 0.7853981633974483
        Assert.assertTrue(Float64.abs(angle - 0.7853981633974483) < 0.0001)

    // ========================================================================
    // moveAndSlide — 衝突なしの移動
    // ========================================================================

    /// velocity (100, 0) で 0.5 秒 → 位置が (50, 0) 移動する
    @Test
    def testCharacterBody2DMoveAndSlideBasic(): Unit \ Assert =
        let body = makeBody({x = 0.0, y = 0.0})
            |> CharacterBody2D.setVelocity({x = 100.0, y = 0.0})
            |> CharacterBody2D.moveAndSlide(0.5 |> Duration.seconds, emptyScene());
        let pos = Node2D.getPosition(body);
        Assert.assertEq(expected = (50.0, 0.0), (pos#x, pos#y))

    /// velocity (0, -200) で 1 秒 → 上方向に 200 ピクセル移動
    @Test
    def testCharacterBody2DMoveAndSlideUpward(): Unit \ Assert =
        let body = makeBody({x = 100.0, y = 300.0})
            |> CharacterBody2D.setVelocity({x = 0.0, y = -200.0})
            |> CharacterBody2D.moveAndSlide(1.0 |> Duration.seconds, emptyScene());
        let pos = Node2D.getPosition(body);
        Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

    /// velocity ゼロでは位置が変わらない
    @Test
    def testCharacterBody2DMoveAndSlideZeroVelocity(): Unit \ Assert =
        let body = makeBody({x = 42.0, y = 99.0})
            |> CharacterBody2D.moveAndSlide(1.0 |> Duration.seconds, emptyScene());
        let pos = Node2D.getPosition(body);
        Assert.assertEq(expected = (42.0, 99.0), (pos#x, pos#y))

    /// delta=0 では位置が変わらない
    @Test
    def testCharacterBody2DMoveAndSlideZeroDelta(): Unit \ Assert =
        let body = makeBody({x = 10.0, y = 20.0})
            |> CharacterBody2D.setVelocity({x = 500.0, y = 500.0})
            |> CharacterBody2D.moveAndSlide(0.0 |> Duration.seconds, emptyScene());
        let pos = Node2D.getPosition(body);
        Assert.assertEq(expected = (10.0, 20.0), (pos#x, pos#y))

    /// 衝突しないなら moveAndSlide は velocity を変更しない
    @Test
    def testCharacterBody2DMoveAndSlidePreservesVelocityWhenFree(): Unit \ Assert =
        let body = makeBody({x = 0.0, y = 0.0})
            |> CharacterBody2D.setVelocity({x = 30.0, y = 40.0})
            |> CharacterBody2D.moveAndSlide(1.0 |> Duration.seconds, emptyScene());
        let vel = CharacterBody2D.getVelocity(body);
        Assert.assertEq(expected = (30.0, 40.0), (vel#x, vel#y))

    /// 衝突形状が None の場合は静的衝突体があっても素通り（Godot 同等）
    @Test
    def testCharacterBody2DMoveAndSlideNoShapePassesThrough(): Unit \ Assert =
        // 衝突形状を付けない CharacterBody2D を直接作る
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
            |> CharacterBody2D.setVelocity({x = 100.0, y = 0.0});
        // 進路上に壁があっても、shape=None なので衝突判定されず通過する
        let scene: Scene[Unit] = sceneWithRectWall({x = 50.0, y = 0.0}, 20.0, 20.0);
        let after = CharacterBody2D.moveAndSlide(1.0 |> Duration.seconds, scene, body);
        let pos = Node2D.getPosition(after);
        Assert.assertEq(expected = (100.0, 0.0), (pos#x, pos#y))

    // ========================================================================
    // moveAndSlide — 衝突応答とスライド
    // ========================================================================

    /// 真横に進んで矩形壁にぶつかる: 法線が水平方向なので X 速度はスライドで失われる。
    /// 位置は壁の手前で押し戻される。
    @Test
    def testMoveAndSlideStopsOnHorizontalWall(): Unit \ Assert =
        // body (14×14) at (30, 0)、壁 (20×100) at (60, 0) は x = 50..70 を占める。
        // velocity (100, 0) で delta=0.2 → motion (20, 0)、targetPos (50, 0)。
        // body は (43, 0)..(57, 0) を占め、壁 (50..70) と x で 7 ピクセル重なる。
        // MTV は (-7, 0) なので押し戻されて (43, 0)。velocity は法線 (-1,0) に沿ってスライド → (0, 0)
        let scene: Scene[Unit] = sceneWithRectWall({x = 60.0, y = 0.0}, 20.0, 100.0);
        let after = makeBody({x = 30.0, y = 0.0})
            |> CharacterBody2D.setVelocity({x = 100.0, y = 0.0})
            |> CharacterBody2D.moveAndSlide(0.2 |> Duration.seconds, scene);
        let pos = Node2D.getPosition(after);
        let vel = CharacterBody2D.getVelocity(after);
        Assert.assertEq(
            expected = (43.0, 0.0, 0.0, 0.0),
            (pos#x, pos#y, vel#x, vel#y))

    /// 斜め進入で水平壁にぶつかる: 法線が縦方向なので Y 速度がスライドで失われ、
    /// X 速度は接線方向として残る → 壁に沿って横に滑る
    @Test
    def testMoveAndSlideSlidesAlongHorizontalSurface(): Unit \ Assert =
        // body (14×14) at (0, 30)、壁 (200×20) at (0, 80) は y = 70..90 を占める。
        // velocity (50, 100) で delta=0.4 → motion (20, 40)、targetPos (20, 70)。
        // body (y = 63..77) と 壁 (y = 70..90) が y で 7 重なる。MTV (0, -7)、normal (0, -1)。
        // velocity slid: (50, 100) - (0,-1)*(-100) = (50, 0)
        let scene: Scene[Unit] = sceneWithRectWall({x = 0.0, y = 80.0}, 200.0, 20.0);
        let after = makeBody({x = 0.0, y = 30.0})
            |> CharacterBody2D.setVelocity({x = 50.0, y = 100.0})
            |> CharacterBody2D.moveAndSlide(0.4 |> Duration.seconds, scene);
        let vel = CharacterBody2D.getVelocity(after);
        Assert.assertEq(expected = (50.0, 0.0), (vel#x, vel#y))

    // ========================================================================
    // upDirection
    // ========================================================================

    /// upDirection を設定・取得できる
    @Test
    def testCharacterBody2DSetUpDirection(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
            |> CharacterBody2D.setUpDirection({x = 1.0, y = 0.0});
        let up = CharacterBody2D.getUpDirection(body);
        Assert.assertEq(expected = (1.0, 0.0), (up#x, up#y))

    /// setUpDirection は正規化して保存する
    @Test
    def testCharacterBody2DSetUpDirectionNormalizes(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
            |> CharacterBody2D.setUpDirection({x = 0.0, y = -10.0});
        let up = CharacterBody2D.getUpDirection(body);
        // (0, -10) を正規化すると (0, -1)
        Assert.assertEq(expected = (0.0, -1.0), (up#x, up#y))

    // ========================================================================
    // floorMaxAngle / maxSlides
    // ========================================================================

    /// floorMaxAngle を変更できる
    @Test
    def testCharacterBody2DSetFloorMaxAngle(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
            |> CharacterBody2D.setFloorMaxAngle(1.0);
        Assert.assertEq(expected = 1.0, CharacterBody2D.getFloorMaxAngle(body))

    /// maxSlides を変更できる
    @Test
    def testCharacterBody2DSetMaxSlides(): Unit \ Assert =
        let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
            |> CharacterBody2D.setMaxSlides(8);
        Assert.assertEq(expected = 8, CharacterBody2D.getMaxSlides(body))
}
