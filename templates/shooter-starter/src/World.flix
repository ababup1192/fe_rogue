// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 下の自機を ←→ で寄せ、Space で弾を撃つ。弾は上へ飛ぶ。敵は「波」で上から降りてくる。
// 弾が敵に当たると撃破して点が入る。敵が自機まで降りてくると被弾（GAME OVER）。
// 波を全部そろえて全滅させたら CLEAR。
// 手触りと収支の数値（移動速度・弾速・連射・敵速・得点）は RulesDoc、色は ThemeDoc、
// 敵の並び（波）は WavesDoc — World は「規則」だけに集中する。
//
// ── 毎フレームの流れ ──
//   入力（Controls.step）→ 状態更新（World.step: 自機移動・発射・弾/敵の移動・当たり判定・波の進行）
//   → 描画（View.frame）。Main の App.game の update 行がこの順（Controls.step |> ActiveDocs.step）。
//
// ── 場面の移り変わり（Phase）──
//
//   Title ──Space/Enter──▶ Playing ──全波を全滅──▶ Clear ──Space/Enter──▶ Title
//                                   └──敵が自機へ到達──▶ GameOver ──Space/Enter──▶ Title
//
// 遷移を起こす関数の doc には [遷移: X→Y] を付けてある（探すときの目印）。
//
// Doc が壊れていても止まらない（fail-open）: 読めない → 既定値で起動、一部が欠け → その欄だけ既定。
mod World {

    /// いま画面が何をしているか。
    ///   Title    … 開始待ち（遊び方を出している）。
    ///   Playing  … 撃って避けている（ふつうの状態）。
    ///   Clear    … 全波を全滅させて勝った（Space/Enter で最初へ）。
    ///   GameOver … 敵に自機まで降りられて負けた（Space/Enter で最初へ）。
    pub enum Phase with Eq, ToString {
        case Title
        case Playing
        case Clear
        case GameOver
    }

    /// 空を飛ぶ点（弾・敵が共有する形）。(x, y) は画面座標（px。y は下ほど大きい）。
    pub type alias Point = { x = Float64, y = Float64 }

    /// 敵 1 体。pos = 位置、alive = まだ生きているか（撃破で false）。
    /// 撃破しても即消さず alive=false にしておき、View が一瞬だけ爆発を描いてから消える。
    pub type alias Enemy = { pos = Point, alive = Bool, boomTimer = Float64 }

    /// ゲームの状態。自機の位置と、飛んでいる弾と、いまの波の敵たちと、収支を持つ。
    ///   playerX      … 自機の左右位置（px。y は固定で View と対）。
    ///   bullets      … 飛んでいる弾（上へ動く）。
    ///   enemies      … いまの波の敵たち（撃破済みも爆発が消えるまで残る）。
    ///   fireCooldown … 次に撃てるまでの残り秒（連射レートの心臓）。
    ///   waveIndex    … いま何番目の波か（0 始まり）。全滅で次へ。
    pub type alias World = {
        rules = RulesDoc.Doc,
        theme = ThemeDoc.Doc,
        waves = WavesDoc.Doc,
        phase = Phase,
        playerX = Float64,
        bullets = List[Point],
        enemies = List[Enemy],
        fireCooldown = Float64,
        waveIndex = Int32,
        score = Int32,
        stars = List[Point],
        starTime = Float64,
        activeDocsWritten = String
    }

    // ── 画面の寸法とレイアウト（project.json の design 240×360 と対。View も同じ値を使う） ──

    pub def designW(): Float64 = 240.0
    pub def designH(): Float64 = 360.0

    /// 自機の中心の y（下部に固定）。敵がこの高さまで降りてきたら被弾。
    pub def playerY(): Float64 = 330.0

    /// 自機・敵の当たり判定の半径（見た目の 1 辺の半分。enemyStep から導く）。
    pub def hitRadius(w: World): Float64 = w#rules#enemyStep / 2.0

    /// 自機が左右に出られる範囲（画面の縁に少し余白を残す）。
    def marginX(): Float64 = 14.0

    /// 起動時と bake が同じ形で読む Doc の束。
    pub type alias Docs = { rules = RulesDoc.Doc, theme = ThemeDoc.Doc, waves = WavesDoc.Doc }

    /// ゲーム開始時の状態。Title 画面から始まる（まだ波は出ていない）。
    /// 星（背景の飾り）だけ決定的に撒いておく。
    pub def initial(docs: Docs): World =
        { rules = docs#rules, theme = docs#theme, waves = docs#waves,
          phase = Phase.Title, playerX = designW() / 2.0, bullets = Nil,
          enemies = Nil, fireCooldown = 0.0, waveIndex = 0, score = 0,
          stars = initialStars(), starTime = 0.0, activeDocsWritten = "" }

    /// 背景の星を決定的に撒く（16 個。LCG で散らすだけの飾り。ルールには絡まない）。
    def initialStars(): List[Point] =
        List.range(0, 16) |> List.map(i -> {
            let sx = pseudo(i * 2) * designW();
            let sy = pseudo(i * 2 + 1) * designH();
            { x = sx, y = sy }
        })

    /// 0.0..1.0 の決定的な擬似乱数（星の配置だけに使う小物。ルールの乱数ではない）。
    def pseudo(i: Int32): Float64 =
        let s = Int32.toInt64(i + 1) * 2654435761i64;
        let hi = Int64.abs(Int64.rightShift(s, 20));
        Int64.toFloat64(Int64.modulo(hi, 1000i64)) / 1000.0

    // ══════════════════════════════════════════════════════
    // 波の生成（WavesDoc の文字格子 → 敵たちの初期位置）
    // ══════════════════════════════════════════════════════

    /// n 番目の波の敵たちを配置する。格子の (col,row) を画面上部の隊列座標へ写す。
    /// 横は中央そろえ（一番長い行の幅を画面中央に収める）、縦は上から enemyStep 間隔。
    pub def spawnWave(n: Int32, w: World): List[Enemy] =
        let grid = WavesDoc.waveAt(n, w#waves);
        let step = w#rules#enemyStep;
        let cols = grid |> List.map(String.length) |> List.foldLeft(Int32.max, 0);
        let formationW = Int32.toFloat64(cols) * step;
        let left = (designW() - formationW) / 2.0 + step / 2.0;   // 中央そろえの左端（中心基準）
        let topY = step;                                         // 一番上の行の中心 y
        grid |> List.zipWithIndex |> List.flatMap(rowEntry -> {
            let (r, row) = rowEntry;
            String.toList(row) |> List.zipWithIndex |> List.filterMap(cellEntry -> {
                let (c, ch) = cellEntry;
                if (WavesDoc.isEnemy(ch))
                    Some({ pos = { x = left + Int32.toFloat64(c) * step,
                                   y = topY + Int32.toFloat64(r) * step },
                           alive = true, boomTimer = 0.0 })
                else
                    None
            })
        })

    /// 遊び始め（Title → Playing）。最初の波を涌かせ、収支を初期化する。[遷移: Title→Playing]
    pub def startGame(w: World): World =
        { phase = Phase.Playing, waveIndex = 0, score = 0, bullets = Nil,
          fireCooldown = 0.0, playerX = designW() / 2.0,
          enemies = spawnWave(0, w) | w }

    // ══════════════════════════════════════════════════════
    // 毎フレームの更新（自機移動・発射・弾/敵の移動・当たり判定・波の進行）
    // ══════════════════════════════════════════════════════

    /// 毎フレームの拍。phase ごとに分岐する。
    ///   Playing 以外（Title/Clear/GameOver）… 星だけ流して待つ（入力は Controls が拾う）。
    ///   Playing … 自機を動かし・弾と敵を進め・当たりを取り・波の進行を判定する。
    /// dir = 左右入力（-1/0/+1）、firing = 発射ボタンが押されているか（Controls が渡す）。
    pub def step(dir: Float64, firing: Bool, dt: Float64, w: World): World =
        let w1 = driftStars(dt, w);
        match w1#phase {
            case Phase.Playing => tickPlaying(dir, firing, dt, w1)
            case _             => w1
        }

    /// Playing の 1 拍: 自機移動 → 発射 → 弾の前進 → 敵の降下 → 当たり判定 → 波の進行。
    /// 「進める部品」を順に pipe でつなぐ（読み下すと 1 フレームの物語になる）。
    def tickPlaying(dir: Float64, firing: Bool, dt: Float64, w: World): World =
        w
            |> movePlayer(dir, dt)
            |> tryFire(firing, dt)
            |> moveBullets(dt)
            |> moveEnemies(dt)
            |> resolveHits
            |> tickBooms(dt)
            |> checkWaveProgress

    /// 自機を左右へ。画面の縁（marginX）で止める（外に出ない）。
    def movePlayer(dir: Float64, dt: Float64, w: World): World =
        let nx = w#playerX + dir * w#rules#playerSpeed * dt;
        { playerX = clampF(marginX(), designW() - marginX(), nx) | w }

    /// 発射ボタンが押されていて、かつ連射の間隔（fireInterval）が空いていれば弾を 1 発撃つ。
    /// クールダウンは毎フレーム dt だけ減らし、0 以下で撃てる。撃ったら間隔ぶん戻す（連射レート）。
    def tryFire(firing: Bool, dt: Float64, w: World): World =
        let cd = w#fireCooldown - dt;
        if (firing and cd <= 0.0) {
            let shot = { x = w#playerX, y = playerY() - hitRadius(w) };
            { bullets = shot :: w#bullets, fireCooldown = w#rules#fireInterval | w }
        } else
            { fireCooldown = Float64.max(0.0, cd) | w }

    /// 弾を上へ進める。画面の上端より上へ抜けた弾は消す（盤外で消える）。
    def moveBullets(dt: Float64, w: World): World =
        let moved = w#bullets
            |> List.map(b -> { y = b#y - w#rules#bulletSpeed * dt | b })
            |> List.filter(b -> b#y >= 0.0);
        { bullets = moved | w }

    /// 波の敵たちを一斉に下へ進める（撃破済みも爆発が消えるまで一緒に動く）。
    def moveEnemies(dt: Float64, w: World): World =
        let moved = w#enemies |> List.map(e ->
            { pos = { y = e#pos#y + w#rules#enemyFallSpeed * dt | e#pos } | e });
        { enemies = moved | w }

    // ══════════════════════════════════════════════════════
    // 当たり判定（弾↔敵・敵↔自機/最下段）
    // ══════════════════════════════════════════════════════

    /// 当たりをまとめて解く: まず弾↔敵（撃破・加点・弾の消費）、次に敵↔自機（被弾判定）。
    def resolveHits(w: World): World =
        let w1 = bulletsHitEnemies(w);
        enemiesReachPlayer(w1)

    /// 生きている敵に当たった弾を消し、当たられた敵を撃破する（alive=false・爆発開始）。
    /// 撃破ぶんだけ scorePerKill を足す。原始的に「弾×敵の総当たり」で判定する
    /// （敵は 1 波ぶんと少ないので素直な二重ループで十分・読みやすさ優先）。
    def bulletsHitEnemies(w: World): World =
        let r = hitRadius(w);
        let hitByAnyBullet = e -> e#alive and List.exists(b -> overlaps(b, e#pos, r), w#bullets);
        let hitAnyEnemy = b -> List.exists(e -> e#alive and overlaps(b, e#pos, r), w#enemies);
        // 当たった弾は消え、当たられた敵は撃破に変わる（爆発を灯す）。
        let survivingBullets = w#bullets |> List.filter(b -> not hitAnyEnemy(b));
        let newEnemies = w#enemies |> List.map(e ->
            if (hitByAnyBullet(e)) { alive = false, boomTimer = boomDuration() | e } else e);
        let kills = w#enemies |> List.count(hitByAnyBullet);
        { bullets = survivingBullets, enemies = newEnemies,
          score = w#score + kills * w#rules#scorePerKill | w }

    /// 生きている敵が自機の高さ（playerY）まで降りてきたら被弾 = GAME OVER。
    /// x が離れていても「最下段（自機の列）に到達したら守り切れなかった」とみなす（原始的で素直）。
    /// [遷移: Playing→GameOver]
    def enemiesReachPlayer(w: World): World =
        let reached = w#enemies |> List.exists(e -> e#alive and e#pos#y >= playerY() - hitRadius(w));
        if (reached) { phase = Phase.GameOver | w } else w

    /// 2 点が半径 r どうしで重なるか（弾・自機・敵はどれも小さな四角/円なので中心距離で判定）。
    def overlaps(a: Point, b: Point, r: Float64): Bool =
        let dx = a#x - b#x;
        let dy = a#y - b#y;
        dx * dx + dy * dy <= (r * 2.0) * (r * 2.0)

    // ══════════════════════════════════════════════════════
    // 演出の時間と 波の進行
    // ══════════════════════════════════════════════════════

    /// 撃破の爆発が見えている長さ（秒）。演出の見た目は View、ここは「消えるまでの時間」だけ。
    /// View も減衰の分母にこの値を使う（マジックナンバーを 2 か所に置かない）。
    pub def boomDuration(): Float64 = 0.18

    /// 撃破済みの敵の爆発タイマーを減らし、消え切った敵をリストから外す。
    def tickBooms(dt: Float64, w: World): World =
        let ticked = w#enemies |> List.map(e ->
            if (e#alive) e else { boomTimer = e#boomTimer - dt | e });
        let kept = ticked |> List.filter(e -> e#alive or e#boomTimer > 0.0);
        { enemies = kept | w }

    /// 生きている敵が 1 体もいなくなったら波は全滅。次の波へ、無ければ CLEAR。
    /// 爆発がまだ残っていても「生存 0」で進める（撃ち切った手応えをすぐ返す）。
    /// [遷移: Playing→Clear]（最後の波のとき）
    def checkWaveProgress(w: World): World =
        if (w#enemies |> List.exists(e -> e#alive))
            w                                            // まだ敵が残っている
        else {
            let bonus = w#rules#waveClearBonus;
            let nextIndex = w#waveIndex + 1;
            if (nextIndex >= WavesDoc.waveCount(w#waves))
                { phase = Phase.Clear, score = w#score + bonus | w }   // 最後の波 → 勝ち
            else
                { waveIndex = nextIndex, enemies = spawnWave(nextIndex, w),
                  bullets = Nil, score = w#score + bonus | w }         // 次の波へ
        }

    // ══════════════════════════════════════════════════════
    // 背景の星（飾り。ルールには絡まない）
    // ══════════════════════════════════════════════════════

    /// 星を下へ流して宇宙を進んでいる感じを出す。下端を越えたら上へ巻き戻す（無限スクロール）。
    def driftStars(dt: Float64, w: World): World =
        let speed = 20.0;
        let moved = w#stars |> List.map(s -> {
            let ny = s#y + speed * dt;
            if (ny > designH()) { y = ny - designH() | s } else { y = ny | s }
        });
        { stars = moved, starTime = w#starTime + dt | w }

    // ══════════════════════════════════════════════════════
    // 場面の仕切り直し（Title へ戻る）
    // ══════════════════════════════════════════════════════

    /// CLEAR / GAME OVER から最初（Title）へ戻る。[遷移: Clear/GameOver→Title]
    pub def toTitle(w: World): World =
        initial({ rules = w#rules, theme = w#theme, waves = w#waves })

    /// Space/Enter の意味は場面で変わる: Title/Clear/GameOver では仕切り直し、遊び中は発射（Controls 側）。
    pub def confirm(w: World): World =
        match w#phase {
            case Phase.Title    => startGame(w)
            case Phase.Clear    => toTitle(w)
            case Phase.GameOver => toTitle(w)
            case Phase.Playing  => w             // 遊び中の Space は発射（Controls が firing で扱う）
        }

    pub def isPlaying(w: World): Bool = w#phase == Phase.Playing

    // ══════════════════════════════════════════════════════
    // Doc の差し替え（保存即反映）と 表示中の名乗り
    // ══════════════════════════════════════════════════════

    pub def withRules(rules: RulesDoc.Doc, w: World): World = { rules = rules | w }
    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }
    pub def withWaves(waves: WavesDoc.Doc, w: World): World = { waves = waves | w }

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。Studio の「表示中」バッジの材料。
    pub def activeDocs(_w: World): List[(String, List[String])] =
        ("rules", RulesDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("waves", WavesDoc.path() :: Nil) :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
