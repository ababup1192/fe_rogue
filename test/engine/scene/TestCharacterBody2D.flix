// Tests for CharacterBody2D

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
// moveAndSlide — velocity に基づく移動
// ========================================================================

/// velocity (100, 0) で 0.5 秒 → 位置が (50, 0) 移動する
@Test
def testCharacterBody2DMoveAndSlideBasic(): Unit \ Assert =
    let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 200.0)
        |> CharacterBody2D.setVelocity({x = 100.0, y = 0.0})
        |> CharacterBody2D.moveAndSlide(0.5);
    let pos = Node2D.getPosition(body);
    Assert.assertEq(expected = (50.0, 0.0), (pos#x, pos#y))

/// velocity (0, -200) で 1 秒 → 上方向に 200 ピクセル移動
@Test
def testCharacterBody2DMoveAndSlideUpward(): Unit \ Assert =
    let body = CharacterBody2D.make({x = 100.0, y = 300.0}, moveSpeed = 200.0)
        |> CharacterBody2D.setVelocity({x = 0.0, y = -200.0})
        |> CharacterBody2D.moveAndSlide(1.0);
    let pos = Node2D.getPosition(body);
    Assert.assertEq(expected = (100.0, 100.0), (pos#x, pos#y))

/// velocity ゼロでは位置が変わらない
@Test
def testCharacterBody2DMoveAndSlideZeroVelocity(): Unit \ Assert =
    let body = CharacterBody2D.make({x = 42.0, y = 99.0}, moveSpeed = 100.0)
        |> CharacterBody2D.moveAndSlide(1.0);
    let pos = Node2D.getPosition(body);
    Assert.assertEq(expected = (42.0, 99.0), (pos#x, pos#y))

/// delta=0 では位置が変わらない
@Test
def testCharacterBody2DMoveAndSlideZeroDelta(): Unit \ Assert =
    let body = CharacterBody2D.make({x = 10.0, y = 20.0}, moveSpeed = 100.0)
        |> CharacterBody2D.setVelocity({x = 500.0, y = 500.0})
        |> CharacterBody2D.moveAndSlide(0.0);
    let pos = Node2D.getPosition(body);
    Assert.assertEq(expected = (10.0, 20.0), (pos#x, pos#y))

/// moveAndSlide は velocity を変更しない（衝突応答なしの現状）
@Test
def testCharacterBody2DMoveAndSlidePreservesVelocity(): Unit \ Assert =
    let body = CharacterBody2D.make({x = 0.0, y = 0.0}, moveSpeed = 100.0)
        |> CharacterBody2D.setVelocity({x = 30.0, y = 40.0})
        |> CharacterBody2D.moveAndSlide(1.0);
    let vel = CharacterBody2D.getVelocity(body);
    Assert.assertEq(expected = (30.0, 40.0), (vel#x, vel#y))

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
