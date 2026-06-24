///
/// Game の純粋関数のテスト。
///
/// ポイント：ここには `GameEngine.Game` も `Math.Random` も `Scene` も登場しない。
/// テスト対象は game/ の純粋層（Model / Update）だけ。副作用が無いので、
/// ウィンドウもエンジンも起動せず「値を入れて値を確かめる」だけでテストできる。
/// これが「ロジックを純粋に保つ」ことの見返り。
///

// ========================================================================
// 自機の移動：入力方向へ一定速度で動く
// ========================================================================

/// 速度 110 で 0.5 秒、右(+x)へ動かすと x が 55 だけ増える（110 × 0.5 = 55）。
/// 中央付近スタートなので画面端のはみ出し補正は効かない。
@Test
def testMovePlayerMovesRightByVelocity(): Unit \ Assert =
    let after = Update.movePlayer(0.5, {x = 1.0, y = 0.0}, 110.0, {x = 100.0, y = 100.0});
    Assert.assertEq(expected = (155.0, 100.0), (after#x, after#y))

/// 入力が無ければ自機は動かない（方向ベクトルが 0 なら速度も 0）。
@Test
def testMovePlayerStaysWhenNoInput(): Unit \ Assert =
    let after = Update.movePlayer(0.5, {x = 0.0, y = 0.0}, 110.0, {x = 100.0, y = 100.0});
    Assert.assertEq(expected = (100.0, 100.0), (after#x, after#y))

// ========================================================================
// 強化：レベルアップで選んだ強化が World に効く（純粋・値だけで確認）
// ========================================================================

/// MaxHp 強化は最大 HP を +1 し、同時に現在 HP も +1 回復する。初期(hp5/maxHp5)→(6,6)。
@Test
def testApplyMaxHpRaisesCapAndHeals(): Unit \ Assert =
    let after = Upgrade.apply(Upgrade.Kind.MaxHp, Model.initialWorld());
    Assert.assertEq(expected = (6, 6), (after#hp, after#maxHp))

/// MultiShot 強化は 1 回の発射数を +1 する（初期 1 → 2）。
@Test
def testApplyMultiShotIncrementsShots(): Unit \ Assert =
    let after = Upgrade.apply(Upgrade.Kind.MultiShot, Model.initialWorld());
    Assert.assertEq(expected = 2, after#multiShot)

/// FireRate 強化は発射間隔を短くする（初期 0.35 → 0.35×0.85 ＝ 0.2975）。
@Test
def testApplyFireRateShortensInterval(): Unit \ Assert =
    let after = Upgrade.apply(Upgrade.Kind.FireRate, Model.initialWorld());
    Assert.assertTrue(Float64.abs(after#fireInterval - 0.2975) < 0.0001)

// ========================================================================
// 激化：スポーン間隔は時間とともに短くなり、下限で頭打ちになる
// ========================================================================

/// 開始時（0秒）はベース間隔 0.8。
@Test
def testSpawnIntervalStartsAtBase(): Unit \ Assert =
    Assert.assertEq(expected = 0.8, Model.spawnIntervalAt(0.0))

/// 時間が経つほど間隔は短くなる（10秒後 < 0秒）。
@Test
def testSpawnIntervalShrinksOverTime(): Unit \ Assert =
    Assert.assertTrue(Model.spawnIntervalAt(10.0) < Model.spawnIntervalAt(0.0))

/// 十分時間が経つと下限 0.15 で頭打ちになる（これ以上は速くならない）。
@Test
def testSpawnIntervalClampsAtMinimum(): Unit \ Assert =
    Assert.assertEq(expected = 0.15, Model.spawnIntervalAt(200.0))

// ========================================================================
// 経験値ジェム：吸い寄せと回収
// ========================================================================

/// 自機(0,0) のすぐ上(0,10)のジェムは吸引半径(45)内なので、自機側へ寄る（y が減る）。
@Test
def testMagnetGemMovesTowardPlayer(): Unit \ Assert =
    let after = Update.magnetGem(0.1, {x = 0.0, y = 0.0}, {pos = {x = 0.0, y = 10.0}});
    Assert.assertTrue(after#pos#y < 10.0)

/// 遠く(0,200)のジェムは吸引半径外なので動かない。
@Test
def testMagnetGemIgnoresFarGem(): Unit \ Assert =
    let after = Update.magnetGem(0.1, {x = 0.0, y = 0.0}, {pos = {x = 0.0, y = 200.0}});
    Assert.assertEq(expected = (0.0, 200.0), (after#pos#x, after#pos#y))

/// 自機に重なったジェムは回収できる（pickup 半径 14 内）。離れたジェムはできない。
@Test
def testGemPickedOnlyWhenClose(): Unit \ Assert =
    let near = Update.gemPicked({x = 0.0, y = 0.0}, {pos = {x = 0.0, y = 5.0}});
    let far  = Update.gemPicked({x = 0.0, y = 0.0}, {pos = {x = 0.0, y = 50.0}});
    Assert.assertEq(expected = (true, false), (near, far))

// ========================================================================
// 向き：移動方向が撃つ方向になる。止まっている間は前の向きを保つ
// ========================================================================

// ========================================================================
// 向き：水平入力が左右の向きを決める。止まっている間は前の向きを保つ
// ========================================================================

/// 右(+x)に動いていれば右向き、左(-x)なら左向き。
@Test
def testFaceFromHorizontalInput(): Unit \ Assert =
    let right = Update.faceFrom({x = 1.0,  y = 0.3}, false);
    let left  = Update.faceFrom({x = -1.0, y = 0.3}, true);
    Assert.assertEq(expected = (true, false), (right, left))

/// 水平入力が無ければ（上下のみ・無入力）向きは前のまま。
@Test
def testFaceFromKeepsWhenNoHorizontal(): Unit \ Assert =
    let keptUp   = Update.faceFrom({x = 0.0, y = -1.0}, true);
    let keptIdle = Update.faceFrom({x = 0.0, y = 0.0},  false);
    Assert.assertEq(expected = (true, false), (keptUp, keptIdle))

// ========================================================================
// 薙ぎ（Whip）：向いた側の矩形内の敵だけが当たる
// ========================================================================

/// 自機(0,0) で右向きのとき、右の矩形内(40,0)の敵は当たり、左(-40,0)の敵は外れる。
@Test
def testEnemyInWhipHitsFacingSideOnly(): Unit \ Assert =
    let player = {x = 0.0, y = 0.0};
    let rightEnemy = {pos = {x = 40.0,  y = 0.0}, kind = Model.EnemyKind.Grunt, hp = 1};
    let leftEnemy  = {pos = {x = -40.0, y = 0.0}, kind = Model.EnemyKind.Grunt, hp = 1};
    Assert.assertEq(expected = (true, false),
        (Update.enemyInWhip(player, true, rightEnemy), Update.enemyInWhip(player, true, leftEnemy)))

/// 縦に外れた敵（半幅 24 を超える y=40）は、横が範囲内でも当たらない。
@Test
def testEnemyInWhipMissesVerticallyFar(): Unit \ Assert =
    let player = {x = 0.0, y = 0.0};
    let highEnemy = {pos = {x = 40.0, y = 40.0}, kind = Model.EnemyKind.Grunt, hp = 1};
    Assert.assertEq(expected = false, Update.enemyInWhip(player, true, highEnemy))

/// 右向きで矩形内に居る敵は、薙ぎ 1 回（クールダウン満了）で削られて倒れる（kills=1）。
/// dt 0・sinceFire を間隔ちょうどにして「この瞬間に薙ぐ」状況を作る。
@Test
def testWhipKillsEnemyInFront(): Unit \ Assert =
    let base = Model.initialWorld();
    let enemy = {pos = {x = base#player#x + 30.0, y = base#player#y},
                 kind = Model.EnemyKind.Grunt, hp = 1};
    let world = { sinceFire = base#fireInterval, facingRight = true, enemies = enemy :: Nil | base };
    let after = Update.step(0.0, {x = 0.0, y = 0.0}, {x = 0.0, y = 0.0}, Model.EnemyKind.Grunt, world);
    Assert.assertEq(expected = 1, after#kills)

// ========================================================================
// 死亡判定：HP が尽きたフレームでゲームオーバーへ遷移する
// ========================================================================

/// HP 1・無敵なしで、自機と同じ位置にいる敵に接触すると HP が 0 になる
/// （接触ダメージの段が効くことを 1 本で固定。局面 GameOver への遷移は presentation 側が hp を見て行う）。
/// 入力なし・dt 0.1 秒・敵は initialWorld の自機位置(240,135)＝確実に接触。
@Test
def testStepReducesHpToZeroOnContact(): Unit \ Assert =
    let enemy = {pos = {x = 240.0, y = 135.0}, kind = Model.EnemyKind.Grunt, hp = 1};
    let world = { hp = 1, invulnLeft = 0.0, enemies = enemy :: Nil | Model.initialWorld() };
    let after = Update.step(0.1, {x = 0.0, y = 0.0}, {x = 0.0, y = 0.0}, Model.EnemyKind.Grunt, world);
    Assert.assertEq(expected = 0, after#hp)

// ========================================================================
// 敵の種類：Tank は HP が高い／Damage 強化で威力が上がる
// ========================================================================

/// 種類ごとの初期 HP（Grunt 1、Tank 4）。
@Test
def testEnemyHpByKind(): Unit \ Assert =
    Assert.assertEq(expected = (1, 4),
        (Model.enemyHpFor(Model.EnemyKind.Grunt), Model.enemyHpFor(Model.EnemyKind.Tank)))

/// Damage 強化は弾の威力を +1 する（初期 1 → 2）。
@Test
def testApplyDamageIncreasesDamage(): Unit \ Assert =
    let after = Upgrade.apply(Upgrade.Kind.Damage, Model.initialWorld());
    Assert.assertEq(expected = 2, after#damage)
