// World — Worldline を流れる「値」の番地: breakout 1 プレイぶんの全状態と、レベル配置の宣言データ。
// 値だけがここに住む —— 1 フレームのルールは Step、描画は View、副作用の縁は Game。
// 値の型は Field.World（モジュール名は領域名 Field のまま。sokoban の Board.World と同じ流儀で、
// `World.World` の重複を避ける）。
//
// 状態の持ち方の教え その一 **局面ごとに、その局面で意味のあるデータだけを持つ。** World は
// 調整値 params と局面 phase の二つきり。ゲームのデータは phase の case が所有する: タイトルは
// 盤を持たず（Title）、飛行中だけボールの速度と残像を持ち（Playing 内の Moving）、クリア・
// ゲームオーバーは凍結した盤を持つ。「サーブ待ちなのに速度がある」「タイトルなのに残機に
// 触れる」は、その case にそのデータが無いので型から消える。
//
// 状態の持ち方の教え その二 **ストアは群れのための道具。1 個しか居ないものは普通の値として持つ。**
// 盤（GameCore）の中で、ボールの位置とパドルは名前のある単独者なので型つきフィールド
// （`core#ballPos` / `core#paddle#x` と直に読める）、壁とブロックは群れなので能力ごとの店（Map）へ分ける:
//   positions    …… 静止群（壁・ブロック）の中心座標
//   shapes       …… 静止群の当たり判定の形
//   blocks       …… ブロックである印と、色分け用の行番号
//   durabilities …… 壊せるブロックだけが持つ耐久。**この店に居ないブロックは壊れない**
// 店は分類タグではなく、載っているかどうかで役割が創発する: 「壊れない」は durabilities からの
// 不在、「ハード」は耐久 2、「通常」は耐久 1 という値そのもの。単独者は物理を呼ぶ瞬間だけ
// 店へ射影される（Step.stepPhysics 参照）。
// ここにあるのは純粋なデータと出発点の組み立てだけで、1 フレームのルールは Step に、
// 描画は View に住む。設計解像度は 320x240、原点は左上、y は下向き。

mod Field {

    /// パドル（単独者）: 中心 x だけが動く。y と形は定数（paddlePos / paddleShape）が持つ。
    pub type alias Paddle = { x = Float64 }

    /// 壊せるブロックの耐久。hp が残り、maxHp が生まれたときの値（見た目・得点・シェイクの
    /// 強さはこの 2 つから導く）。durabilities に居ないブロックはそもそも壊れない。
    pub type alias Durability = { hp = Int32, maxHp = Int32 }

    /// 破壊の破片ひと吹き。状態は持たず、この 3 つ（種＋原点＋経過秒）から粒を導出する。
    pub type alias Burst = { seed = Int32, pos = Vec2.Vec2, elapsed = Float64 }

    // ── このフレームの入力（素のデータ）──
    // left/right はパドル移動なので押しっぱなしを見る。launch/enter は 1 回きり効けばよい
    // 判定（エッジ）で、押された瞬間だけ true になって届く。
    pub type alias Input = { left = Bool, right = Bool, launch = Bool, enter = Bool }

    /// 何も押されていない入力。
    pub def noInput(): Input = { left = false, right = false, launch = false, enter = false }

    // ── 局面（Phase）: ゲームのデータは局面の case が所有する ──
    // タグを作るなら、そのタグが真にするデータを case が所有し、他の局面で無意味なデータは
    // 持たない。比較は match で行う（payload に匿名レコード・Map を含むので Eq は自動導出できない）。

    /// ゲームの大きな局面。case ごとに、その局面で意味のあるデータだけを持つ。
    pub enum Phase {
        case Title                          // タイトル: 文字を見せるだけ。盤（GameCore）を持たない
        case Playing(GameCore, BallState)   // 進行中: 盤 GameCore と、ボールの状態 BallState
        case Cleared(GameCore)              // クリア: 凍結した盤（最終スコアと配置）を見せる
        case GameOver(GameCore)             // 残機ゼロ: 死んだ盤を見せる
    }

    /// 進行中のボールの状態。速度と残像は「飛んでいる間だけ」在るので Moving の中にだけ持つ。
    /// サーブ待ち（Waiting）には速度も残像も無い —— 型がそれを保証する。
    pub enum BallState {
        case Waiting                                              // サーブ待ち: パドルの上で静止（速度も残像も無い）
        case Moving({ vel = Vec2.Vec2, trail = List[Vec2.Vec2] }) // 飛行中: 速度と、直近位置の残像リング（新しい順・有界）
    }

    /// 1 面の盤: 単独者（ballPos・paddle）と群れの店、そして盤の意味（残機・スコア・演出）。
    /// ボールの位置 ballPos は待機・飛行・凍結のすべてで描画に要るのでここに常在し、速度は
    /// BallState.Moving だけが持つ（位置は描画・速度は物理、と生存範囲で割る）。
    pub type alias GameCore = {
        paddle = Paddle,                            // 単独者: パドル（中心 x）
        positions = Map[EntityId, Vec2.Vec2],       // 静止群（壁・ブロック）の中心座標
        shapes = Map[EntityId, CollisionShape2D],   // 静止群の当たり判定の形
        blocks = Map[EntityId, Int32],              // ブロックの印＋行番号（色分け用）
        durabilities = Map[EntityId, Durability],   // 壊せるブロックだけの耐久（不在=壊れない）
        ballPos = Vec2.Vec2,                        // 単独者: ボールの中心（待機・飛行・凍結すべてで描画に要る）
        level = Int32,                              // いま遊んでいる面（1 始まり）
        lives = Int32,                              // 残機
        score = Int32,                              // スコア
        shakeElapsed = Float64,                     // カメラシェイク時計（発火で 0 に戻り、以後増える）
        shakeMagnitude = Float64,                   // 直近シェイクの振幅（耐える=小 / ハード破壊=大）
        bursts = List[Burst]                        // 破壊の破片（closed-form で描くための種の列）
    }

    /// breakout 1 プレイの全状態: 調整値 params と、いまの局面 phase。ゲームのデータは phase の中。
    pub type alias World = {
        params = GameParameters.Params,   // 調整パラメータ（F1 で parameters.json から差し替わる・全局面共通）
        phase = Phase                     // いまの局面（ゲームのデータはこの case の中）
    }

    // ── レイアウト定数（design px）──

    pub def designW(): Float64 = 320.0
    pub def designH(): Float64 = 240.0

    def wallThickness(): Float64 = 6.0
    def innerLeft(): Float64 = wallThickness()               // 6
    def innerRight(): Float64 = designW() - wallThickness()  // 314

    def paddleWidth(): Float64 = 44.0
    def paddleHeight(): Float64 = 6.0
    def paddleY(): Float64 = 220.0
    /// パドルが横に動く速さ（px/秒）。
    pub def paddleSpeed(): Float64 = 200.0
    /// パドルの半幅。反射角の政策（Bounce）が当たり位置の正規化に使う。
    pub def paddleHalfWidth(): Float64 = paddleWidth() / 2.0
    /// パドルの半分の厚み（View が面シェーディングの帯を組むのに使う）。
    pub def paddleHalfHeight(): Float64 = paddleHeight() / 2.0
    /// パドル中心 x の可動範囲（枠の内側でパドルが全部見える範囲）。
    pub def paddleMinX(): Float64 = innerLeft() + paddleHalfWidth()
    pub def paddleMaxX(): Float64 = innerRight() - paddleHalfWidth()

    /// ボールの半径（px）。単独者の形は店ではなくこの定数が持つ。
    pub def ballRadius(): Float64 = 3.0
    /// ボールの基準の速さ（px/秒）。サーブとミス後のリセットはこの値に戻る。
    /// プレイ中はパドルヒットのたびに Bounce の加速規則で少しずつ速くなる。
    pub def ballSpeed(): Float64 = 130.0
    /// この距離だけ画面下端を割ったらミス（枠の無い底からボールが落ちた）。
    pub def ballFallMargin(): Float64 = 8.0

    // ブロック格子。
    def blockCols(): Int32 = 9
    def blockGap(): Float64 = 2.0
    def blockAreaTop(): Float64 = 34.0
    def blockH(): Float64 = 12.0
    def blockCellW(): Float64 = (innerRight() - innerLeft()) / Int32.toFloat64(blockCols())
    def blockW(): Float64 = blockCellW() - blockGap()

    // 演出の寿命。
    /// 破片ひと吹きが消えるまでの秒数（View と経年処理が共有）。
    pub def burstLifetime(): Float64 = 0.5

    /// ボールの残像リングの長さ（保持する直近フレーム数）。長いほど尾が伸びる調整パラメータ。
    pub def trailLength(): Int32 = 12

    // シェイク振幅（px）。
    pub def smallShake(): Float64 = 1.5
    pub def largeShake(): Float64 = 4.0

    // スコア。
    def normalScore(): Int32 = 10
    def hardScore(): Int32 = 30

    /// 壊したブロックの得点。2 発以上耐えたブロック（ハード）ほど高い。
    pub def blockScore(maxHp: Int32): Int32 = if (maxHp >= 2) hardScore() else normalScore()

    /// 壊したブロックのシェイク振幅。ハード（maxHp 2 以上）の破壊は大きく揺れる。
    pub def destroyShake(maxHp: Int32): Float64 = if (maxHp >= 2) largeShake() else smallShake()

    // ── 物体の id ──
    pub def paddleId(): EntityId = 1
    pub def ballId(): EntityId = 2
    pub def leftWallId(): EntityId = 3
    pub def rightWallId(): EntityId = 4
    pub def topWallId(): EntityId = 5
    def firstBlockId(): EntityId = 100

    /// 壁の id 一覧（View がまとめて描くのに使う）。
    pub def wallIds(): List[EntityId] = leftWallId() :: rightWallId() :: topWallId() :: Nil

    // ── 形の補助 ──
    def rect(w: Float64, h: Float64): CollisionShape2D = CollisionShape2D.RectShape2D({ width = w, height = h })
    def circle(r: Float64): CollisionShape2D = CollisionShape2D.CircleShape2D({ radius = r })
    def vec(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    // ── 単独者の形と位置（店に載せず、定数と x から導く）──

    /// ボールの当たり判定の形。物理へ射影する瞬間に使う。
    pub def ballShape(): CollisionShape2D = circle(ballRadius())

    /// パドルの当たり判定の形。物理へ射影する瞬間に使う。
    pub def paddleShape(): CollisionShape2D = rect(paddleWidth(), paddleHeight())

    /// パドルの中心座標。動くのは x だけで、y はレイアウト定数。
    pub def paddlePos(x: Float64): Vec2.Vec2 = vec(x, paddleY())

    // ── 位置の導出 ──

    /// サーブ待ちのボール位置: パドル上端のすぐ上、パドル中心 paddleX の真上。
    pub def servePos(paddleX: Float64): Vec2.Vec2 =
        vec(paddleX, paddleY() - paddleHeight() / 2.0 - ballRadius())

    /// サーブの初速: 少しだけ右に傾けた上向き・基準の速さ（反射規則を再利用して真上から 0.2 ぶん開く）。
    /// ミス後の再サーブもここを通るので、加速した速さは基準へリセットされる。
    pub def serveVelocity(): Vec2.Vec2 = Bounce.paddleReflect(0.2, ballSpeed())

    /// ブロック (col, row) の中心座標。
    def blockCenter(col: Int32, row: Int32): Vec2.Vec2 =
        vec(innerLeft() + (Int32.toFloat64(col) + 0.5) * blockCellW(),
            blockAreaTop() + (Int32.toFloat64(row) + 0.5) * (blockH() + blockGap()))

    // ── レベル配置（宣言データ）──
    // 1 行 = 格子の 1 行、1 文字 = 1 セル:
    //   .  空          n  通常ブロック（1発 = 耐久 {1,1}）
    //   h  ハード（2発 = 耐久 {2,2}）   #  壊れないブロック（durabilities に載せない）
    // 難度曲線: 1面=導入のピラミッド / 2面=不壊の帯に 2 本のスリット / 3面=ポケット完備。
    // 3面は中央が縦にまるごと通路: 撃ち込んだボールは天井まで駆け上がり、天井と不壊の帯の
    // 間のポケットで横に流れながら、上段のブロックを上から壊し続ける。

    pub def levelCount(): Int32 = 3

    def levelRows(n: Int32): List[String] = match n {
        case 1 =>
            "........." ::
            ".nnnnnnn." ::
            ".nnnnnnn." ::
            "..nnnnn.." ::
            "...nnn..." :: Nil
        case 2 =>
            ".nnnnnnn." ::
            ".hhhhhhh." ::
            "##.###.##" ::
            "........." ::
            ".nn.n.nn." :: Nil
        case _ =>
            "nnnn.nnnn" ::
            "nnnn.nnnn" ::
            "####.####" ::
            "........." ::
            "hhh...hhh" ::
            ".nn...nn." :: Nil
    }

    /// セル (col, row) のブロック id。文字の並びから決まる安定した番号。
    def cellId(col: Int32, row: Int32): EntityId = firstBlockId() + row * blockCols() + col

    /// レベル文字列を (id, col, row, 文字) のセル列へ開く。'.' は空なので現れない。
    def levelCells(n: Int32): List[(EntityId, Int32, Int32, Char)] =
        let rows = levelRows(n);
        List.zip(List.range(0, List.length(rows)), rows) |> List.flatMap(rowPair -> {
            let (row, text) = rowPair;
            let chars = String.toList(text);
            List.zip(List.range(0, List.length(chars)), chars) |> List.filterMap(colPair -> {
                let (col, ch) = colPair;
                if (ch == '.') None else Some((cellId(col, row), col, row, ch))
            })
        })

    /// 文字ごとの耐久。'#'（壊れない）は None = durabilities の店に載らない。
    def durabilityOf(ch: Char): Option[Durability] = match ch {
        case 'h' => Some({ hp = 2, maxHp = 2 })
        case '#' => None
        case _   => Some({ hp = 1, maxHp = 1 })
    }

    // ── 物体の組み立て ──

    /// 三方の壁（左・右・上）。底は開いていてボールが落ちる。
    def wallEntries(): List[(EntityId, Vec2.Vec2, CollisionShape2D)] =
        (leftWallId(),  vec(wallThickness() / 2.0, designH() / 2.0), rect(wallThickness(), designH())) ::
        (rightWallId(), vec(designW() - wallThickness() / 2.0, designH() / 2.0), rect(wallThickness(), designH())) ::
        (topWallId(),   vec(designW() / 2.0, wallThickness() / 2.0), rect(designW(), wallThickness())) :: Nil

    // ── 出発点の World ──

    /// レベル n の盤（GameCore）: パドル中央、ボールはパドル上のサーブ待ち位置、残機 3、演出なし。
    /// 単独者（ballPos・paddle）は普通の値として持ち、店（positions / shapes）には静止群
    /// （壁・ブロック）だけを載せる。レベル進行・やり直しはこの盤を組み直す。
    pub def freshCore(n: Int32): GameCore =
        let cells = levelCells(n);
        let blockEntries = List.map(cell -> {
            let (id, col, row, _ch) = cell;
            (id, blockCenter(col, row), rect(blockW(), blockH()))
        }, cells);
        let entries = List.append(wallEntries(), blockEntries);
        let centerX = designW() / 2.0;
        { paddle = { x = centerX },
          positions = List.map(entry -> { let (id, pos, _shape) = entry; (id, pos) }, entries) |> List.toMap,
          shapes    = List.map(entry -> { let (id, _pos, shape) = entry; (id, shape) }, entries) |> List.toMap,
          blocks = List.map(cell -> { let (id, _col, row, _ch) = cell; (id, row) }, cells) |> List.toMap,
          durabilities = List.filterMap(cell -> {
              let (id, _col, _row, ch) = cell;
              durabilityOf(ch) |> Option.map(durability -> (id, durability))
          }, cells) |> List.toMap,
          ballPos = servePos(centerX),   // パドル上のサーブ待ち位置
          level = n,
          lives = 3, score = 0,
          shakeElapsed = 999.0, shakeMagnitude = 0.0, bursts = Nil }

    /// レベル n のプレイ開始時の World: 盤は freshCore(n)、ボールはサーブ待ち、パラメータは既定値。
    pub def playingWorld(n: Int32): World =
        { params = GameParameters.defaults(), phase = Phase.Playing(freshCore(n), BallState.Waiting) }

    /// タイトル画面の World: 文字を見せるだけの局面（盤は持たない）。
    pub def titleWorld(): World = { params = GameParameters.defaults(), phase = Phase.Title }

    pub def initialWorld(): World = titleWorld()

    // ── 導出クエリ ──

    /// 壊せるブロックが 0 になったらクリア（壊れないブロックは残ってよい）。盤 GameCore から判定する。
    pub def won(core: GameCore): Bool = Map.isEmpty(core#durabilities)
}
