// ルールと進行・収支だけをテストする（方針どおり）。演出（爆発・星）や座標の写経はしない。
// 期待値はリテラルでなく Doc（RulesDoc.defaults / WavesDoc.defaults）から導く — バランス調整で壊れないように。
//
// World を直接組んで規則関数を当てる。座標は px（y は下ほど大きい）。
mod TestRules {

    /// 既定の Doc から Title の World を作る土台。
    def base(): World.World =
        World.initial({ rules = RulesDoc.defaults(), theme = ThemeDoc.defaults(), waves = WavesDoc.defaults() })

    /// Playing にして敵・弾を差し替えた World（当たり判定・進行のテスト用）。
    def playing(enemies: List[World.Enemy], bullets: List[World.Point], w: World.World): World.World =
        { phase = World.Phase.Playing, enemies = enemies, bullets = bullets | w }

    /// 生きた敵 1 体（位置指定）。
    def enemyAt(x: Float64, y: Float64): World.Enemy =
        { pos = { x = x, y = y }, alive = true, boomTimer = 0.0 }

    // ══════════════════════════════════════════════════════
    // 発射（連射レート = ルール）
    // ══════════════════════════════════════════════════════

    /// 波の全滅による進行を抑えるための「遠くの生存敵」（当たり・被弾には絡まない位置）。
    /// これがいないと敵ゼロで即・波が進み、bullets が消えて発射テストが濁る。
    def decoy(): World.Enemy = enemyAt(20.0, 40.0)

    @Test
    def testFireEmitsBulletWhenCooldownReady(): Unit \ Assert =
        // クールダウンが空いていれば、発射入力で弾が 1 発増える。
        let w = { fireCooldown = 0.0 | playing(decoy() :: Nil, Nil, base()) };
        let after = World.step(0.0, true, 0.016, w);
        Assert.assertEq(expected = 1, List.length(after#bullets))

    @Test
    def testFireBlockedWhileCoolingDown(): Unit \ Assert =
        // 撃った直後（クールダウン中）は、押しっぱなしでも次弾は出ない。間隔は Doc の fireInterval。
        let d = RulesDoc.defaults();
        let w = { fireCooldown = d#fireInterval | playing(decoy() :: Nil, Nil, base()) };
        let after = World.step(0.0, true, 0.016, w);
        Assert.assertEq(expected = 0, List.length(after#bullets))

    // ══════════════════════════════════════════════════════
    // 弾の移動と盤外での消滅
    // ══════════════════════════════════════════════════════

    @Test
    def testBulletLeavesTopIsRemoved(): Unit \ Assert =
        // 画面上端より上へ抜けた弾は消える（盤外で消滅）。敵はいないので当たりは起きない。
        let d = RulesDoc.defaults();
        // 上端付近の弾に、1 フレームで上端を越えるだけの dt を与える。
        let bulletNearTop = { x = 120.0, y = 2.0 };
        let dt = 10.0 / d#bulletSpeed + 0.01;
        let w = playing(Nil, bulletNearTop :: Nil, base());
        let after = World.step(0.0, false, dt, w);
        Assert.assertEq(expected = 0, List.length(after#bullets))

    // ══════════════════════════════════════════════════════
    // 当たり判定（弾↔敵: 撃破・加点・弾の消費）
    // ══════════════════════════════════════════════════════

    @Test
    def testBulletKillsEnemyAndScores(): Unit \ Assert =
        // 弾が敵に重なると敵は撃破（alive=false）になり、弾は消え、scorePerKill が入る。
        let d = RulesDoc.defaults();
        let e = enemyAt(120.0, 100.0);
        let b = { x = 120.0, y = 100.0 };                 // 敵とほぼ同じ位置 = 当たる
        // decoy を残して波の進行（＝加点・弾クリア）が混ざらないようにする。撃つのは e だけ。
        let w = playing(e :: decoy() :: Nil, b :: Nil, base());
        let after = World.step(0.0, false, 0.001, w);
        let alive = after#enemies |> List.count(en -> en#alive);
        Assert.assertEq(
            expected = (1, 0, d#scorePerKill),
            (alive, List.length(after#bullets), after#score))

    @Test
    def testBulletMissesFarEnemy(): Unit \ Assert =
        // 大きく離れた弾は敵に当たらない（撃破も加点もしない）。
        let e = enemyAt(40.0, 100.0);
        let b = { x = 200.0, y = 100.0 };                 // 横に大きく離れている
        let w = playing(e :: Nil, b :: Nil, base());
        let after = World.step(0.0, false, 0.001, w);
        let alive = after#enemies |> List.count(en -> en#alive);
        Assert.assertEq(expected = (1, 0), (alive, after#score))

    // ══════════════════════════════════════════════════════
    // 被弾（敵↔自機 到達 → GAME OVER）
    // ══════════════════════════════════════════════════════

    @Test
    def testEnemyReachingPlayerIsGameOver(): Unit \ Assert =
        // 生きた敵が自機の高さ（playerY）まで降りてくると GAME OVER になる。
        let e = enemyAt(120.0, World.playerY());
        let w = playing(e :: Nil, Nil, base());
        let after = World.step(0.0, false, 0.001, w);
        Assert.assertEq(expected = World.Phase.GameOver, after#phase)

    @Test
    def testDeadEnemyAtBottomDoesNotKill(): Unit \ Assert =
        // 撃破済み（alive=false）の敵が最下段にいても被弾にはならない（生存だけが脅威）。
        let dead = { alive = false, boomTimer = 0.1 | enemyAt(120.0, World.playerY()) };
        let w = playing(dead :: Nil, Nil, base());
        let after = World.step(0.0, false, 0.001, w);
        Assert.assertEq(expected = true, after#phase != World.Phase.GameOver)

    // ══════════════════════════════════════════════════════
    // 波の進行（全滅 → 次の波 / 最後なら CLEAR。ボーナスは Doc 由来）
    // ══════════════════════════════════════════════════════

    @Test
    def testClearingNonLastWaveAdvancesAndBonus(): Unit \ Assert =
        // 最後でない波を全滅させると次の波へ進み、waveClearBonus が入る（波が 2 つ以上ある前提）。
        let d = RulesDoc.defaults();
        let w = { waveIndex = 0, score = 0 | playing(Nil, Nil, base()) };   // 敵ゼロ = 全滅済み
        let after = World.step(0.0, false, 0.001, w);
        Assert.assertEq(
            expected = (1, d#waveClearBonus, true),
            (after#waveIndex, after#score, after#phase == World.Phase.Playing))

    @Test
    def testClearingLastWaveWins(): Unit \ Assert =
        // 最後の波を全滅させると CLEAR（勝ち）。最後の波の index は WavesDoc.waveCount - 1。
        let lastIndex = WavesDoc.waveCount(WavesDoc.defaults()) - 1;
        let w = { waveIndex = lastIndex | playing(Nil, Nil, base()) };
        let after = World.step(0.0, false, 0.001, w);
        Assert.assertEq(expected = World.Phase.Clear, after#phase)

    // ══════════════════════════════════════════════════════
    // 波の生成（WavesDoc の格子 → 敵の数が一致する）
    // ══════════════════════════════════════════════════════

    @Test
    def testSpawnWaveCountMatchesGrid(): Unit \ Assert =
        // 生成した敵の数は、その波の格子の「敵マス（isEnemy）」の総数と一致する。
        let doc = WavesDoc.defaults();
        let grid = WavesDoc.waveAt(0, doc);
        let expected = grid
            |> List.map(row -> String.toList(row) |> List.count(WavesDoc.isEnemy))
            |> List.foldLeft((a, b) -> a + b, 0);
        let spawned = World.spawnWave(0, base()) |> List.length;
        Assert.assertEq(expected = expected, spawned)

    // ══════════════════════════════════════════════════════
    // 場面の決定（Title→Playing・GameOver→Title）
    // ══════════════════════════════════════════════════════

    @Test
    def testConfirmFromTitleStartsGame(): Unit \ Assert =
        // Title で決定すると Playing になり、最初の波の敵が涌く。
        let after = World.confirm(base());
        Assert.assertEq(
            expected = (World.Phase.Playing, true),
            (after#phase, not List.isEmpty(after#enemies)))

    @Test
    def testConfirmFromGameOverReturnsToTitle(): Unit \ Assert =
        // GAME OVER で決定すると Title に戻る（必ず仕切り直せる）。
        let w = { phase = World.Phase.GameOver | base() };
        Assert.assertEq(expected = World.Phase.Title, World.confirm(w)#phase)
}
