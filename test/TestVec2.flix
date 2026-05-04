// Tests for Vec2 module

// --- Arithmetic ---

@Test
def testVec2Add(): Unit \ Assert =
    let r = Vec2.add({x = 1.0, y = 2.0}, {x = 3.0, y = 4.0});
    Assert.assertEq(expected = 4.0, r#x);
    Assert.assertEq(expected = 6.0, r#y)

@Test
def testVec2Sub(): Unit \ Assert =
    let r = Vec2.sub({x = 5.0, y = 7.0}, {x = 2.0, y = 3.0});
    Assert.assertEq(expected = 3.0, r#x);
    Assert.assertEq(expected = 4.0, r#y)

@Test
def testVec2Mul(): Unit \ Assert =
    let r = Vec2.mul({x = 3.0, y = 4.0}, 2.0);
    Assert.assertEq(expected = 6.0, r#x);
    Assert.assertEq(expected = 8.0, r#y)

@Test
def testVec2Div(): Unit \ Assert =
    let r = Vec2.div({x = 6.0, y = 8.0}, 2.0);
    Assert.assertEq(expected = 3.0, r#x);
    Assert.assertEq(expected = 4.0, r#y)

@Test
def testVec2Neg(): Unit \ Assert =
    let r = Vec2.neg({x = 3.0, y = -4.0});
    Assert.assertEq(expected = -3.0, r#x);
    Assert.assertEq(expected = 4.0, r#y)

// --- Length ---

@Test
def testVec2LengthSquared(): Unit \ Assert =
    Assert.assertEq(expected = 25.0, Vec2.lengthSquared({x = 3.0, y = 4.0}))

@Test
def testVec2Length345(): Unit \ Assert =
    let len = Vec2.length({x = 3.0, y = 4.0});
    Assert.assertEq(expected = 5.0, len)

@Test
def testVec2LengthZero(): Unit \ Assert =
    Assert.assertEq(expected = 0.0, Vec2.length(Vec2.zero()))

// --- Normalized ---

@Test
def testVec2Normalized(): Unit \ Assert =
    let r = Vec2.normalized({x = 3.0, y = 4.0});
    let len = Vec2.length(r);
    Assert.assertTrue(Float64.abs(len - 1.0) < 0.001)

@Test
def testVec2NormalizedDirection(): Unit \ Assert =
    let r = Vec2.normalized({x = 0.0, y = 5.0});
    Assert.assertTrue(Float64.abs(r#x) < 0.001);
    Assert.assertTrue(Float64.abs(r#y - 1.0) < 0.001)

@Test
def testVec2NormalizedZero(): Unit \ Assert =
    let r = Vec2.normalized(Vec2.zero());
    Assert.assertEq(expected = 0.0, r#x);
    Assert.assertEq(expected = 0.0, r#y)

// --- Dot ---

@Test
def testVec2DotPerpendicular(): Unit \ Assert =
    Assert.assertEq(expected = 0.0, Vec2.dot({x = 1.0, y = 0.0}, {x = 0.0, y = 1.0}))

@Test
def testVec2DotParallel(): Unit \ Assert =
    Assert.assertEq(expected = 6.0, Vec2.dot({x = 2.0, y = 0.0}, {x = 3.0, y = 0.0}))

@Test
def testVec2DotGeneral(): Unit \ Assert =
    Assert.assertEq(expected = 11.0, Vec2.dot({x = 1.0, y = 2.0}, {x = 3.0, y = 4.0}))

// --- Reflect & Bounce ---

// Reflect downward vector off horizontal surface (normal = up)
@Test
def testVec2Reflect(): Unit \ Assert =
    let v = {x = 1.0, y = 1.0};
    let n = {x = 0.0, y = -1.0};
    let r = Vec2.reflect(v, n);
    Assert.assertTrue(Float64.abs(r#x - 1.0) < 0.001);
    Assert.assertTrue(Float64.abs(r#y - (-1.0)) < 0.001)

@Test
def testVec2Bounce(): Unit \ Assert =
    let v = {x = 1.0, y = 1.0};
    let n = {x = 0.0, y = -1.0};
    let r = Vec2.bounce(v, n);
    Assert.assertTrue(Float64.abs(r#x - (-1.0)) < 0.001);
    Assert.assertTrue(Float64.abs(r#y - 1.0) < 0.001)

// --- Clamp ---

@Test
def testVec2Clamp(): Unit \ Assert =
    let v = {x = 5.0, y = -3.0};
    let r = Vec2.clamp(v, {x = -2.0, y = -2.0}, {x = 2.0, y = 2.0});
    Assert.assertEq(expected = 2.0, r#x);
    Assert.assertEq(expected = -2.0, r#y)

@Test
def testVec2ClampSymmetric(): Unit \ Assert =
    let v = {x = 10.0, y = -5.0};
    let r = Vec2.clampSymmetric(v, {x = 3.0, y = 3.0});
    Assert.assertEq(expected = 3.0, r#x);
    Assert.assertEq(expected = -3.0, r#y)

// --- Lerp ---

@Test
def testVec2LerpZero(): Unit \ Assert =
    let a = {x = 0.0, y = 0.0};
    let b = {x = 10.0, y = 20.0};
    let r = Vec2.lerp(a, b, 0.0);
    Assert.assertEq(expected = 0.0, r#x);
    Assert.assertEq(expected = 0.0, r#y)

@Test
def testVec2LerpOne(): Unit \ Assert =
    let a = {x = 0.0, y = 0.0};
    let b = {x = 10.0, y = 20.0};
    let r = Vec2.lerp(a, b, 1.0);
    Assert.assertEq(expected = 10.0, r#x);
    Assert.assertEq(expected = 20.0, r#y)

@Test
def testVec2LerpHalf(): Unit \ Assert =
    let a = {x = 0.0, y = 0.0};
    let b = {x = 10.0, y = 20.0};
    let r = Vec2.lerp(a, b, 0.5);
    Assert.assertEq(expected = 5.0, r#x);
    Assert.assertEq(expected = 10.0, r#y)

// --- Rotated ---

// Rotate (1, 0) by 90 degrees → (0, 1) approximately
@Test
def testVec2Rotated90(): Unit \ Assert =
    let pi = 3.14159265;
    let r = Vec2.rotated({x = 1.0, y = 0.0}, pi / 2.0);
    Assert.assertTrue(Float64.abs(r#x) < 0.001);
    Assert.assertTrue(Float64.abs(r#y - 1.0) < 0.001)

// Rotate (1, 0) by 180 degrees → (-1, 0) approximately
@Test
def testVec2Rotated180(): Unit \ Assert =
    let pi = 3.14159265;
    let r = Vec2.rotated({x = 1.0, y = 0.0}, pi);
    Assert.assertTrue(Float64.abs(r#x - (-1.0)) < 0.001);
    Assert.assertTrue(Float64.abs(r#y) < 0.001)

// --- Utility ---

@Test
def testVec2IsNormalized(): Unit \ Assert =
    Assert.assertTrue(Vec2.isNormalized({x = 1.0, y = 0.0}));
    Assert.assertFalse(Vec2.isNormalized({x = 2.0, y = 0.0}))

@Test
def testVec2IsZeroApprox(): Unit \ Assert =
    Assert.assertTrue(Vec2.isZeroApprox(Vec2.zero()));
    Assert.assertFalse(Vec2.isZeroApprox({x = 1.0, y = 0.0}))

@Test
def testVec2LimitLength(): Unit \ Assert =
    let v = {x = 6.0, y = 8.0};
    let r = Vec2.limitLength(v, 5.0);
    let len = Vec2.length(r);
    Assert.assertTrue(Float64.abs(len - 5.0) < 0.01)

@Test
def testVec2LimitLengthNoOp(): Unit \ Assert =
    let v = {x = 1.0, y = 0.0};
    let r = Vec2.limitLength(v, 5.0);
    Assert.assertEq(expected = 1.0, r#x);
    Assert.assertEq(expected = 0.0, r#y)

