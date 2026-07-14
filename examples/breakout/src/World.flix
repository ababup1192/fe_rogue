// World — breakout 1 プレイぶんの全状態を、1 つの「値」として定義するファイル。
// ここにあるのは型・定数・出発点の組み立てだけ: 1 フレームのルールは Step、描画は View、
// 外の世界に触れる処理（ループ・キー読み・描画命令）は App、キー割り当ては Controls、
// 面の文字データは Levels が持つ。
// 値の型は Field.World（モジュール名は Field。sokoban の Board.World と同じ流儀で、
// `World.World` という重複した名前を避ける）。
//
// 状態の持ち方の教え その一 **フェーズごとに、そのフェーズで意味のあるデータだけを持つ。**
// World は調整値 params とフェーズ phase の二つきり。ゲームのデータは phase の case が所有する:
// タイトルは盤を持たず（Title）、飛行中だけボールの速度と残像を持ち（Playing 内の Moving）、
// クリア・ゲームオーバーは凍結した盤を持つ。「サーブ待ちなのに速度がある」「タイトルなのに
// 残機に触れる」は、その case にそのデータが無いので型から消える。
//
// 状態の持ち方の教え その二 **Store は「同じ種類がたくさんあるもの」のための道具。1 個しか
// 無いものは普通のフィールドで持つ。** Store は ECS の言葉で「能力ごとの表」のこと（ここでは
// Map で実装）。盤（GameCore）の中で、ボールの位置とパドルは 1 個しか無いのでフィールド
// （`core#ballPos` / `core#paddle#x` と直に読める）、壁とブロックはたくさんあるので能力ごとの
// Store へ分ける:
//   positions    …… 動かないもの（壁・ブロック）の中心座標
//   shapes       …… 動かないものの当たり判定の形
//   blocks       …… ブロックである印と、色分け用の行番号
//   durabilities …… 壊せるブロックだけが持つ耐久。**ここに載っていないブロックは壊れない**
// Store は分類タグではなく、載っているかどうかで役割が決まる: 「壊れない」= durabilities に
// 不在、「ハード」= 耐久 2、「通常」= 耐久 1 という値そのもの。ボールとパドルは物理を呼ぶ
// 瞬間だけ Store に合流する（Step.stepPhysics 参照）。
// 設計解像度は 320x240、原点は左上、y は下向き。

mod Field {

    /// パドル: 中心 x だけが動く。y と形は定数（paddlePos / paddleShape）が持つ。
    pub type alias Paddle = { x = Float64 }

    /// 壊せるブロックの耐久。hp が残り、maxHp が生まれたときの値（見た目・得点・シェイクの
    /// 強さはこの 2 つから導く）。durabilities に居ないブロックはそもそも壊れない。
    pub type alias Durability = { hp = Int32, maxHp = Int32 }

    /// 破壊の破片ひと吹き。状態は持たず、この 3 つ（種＋原点＋経過秒）から粒を導出する。
    pub type alias Burst = { seed = Int32, pos = Vec2.Vec2, elapsed = Float64 }

    /// このフレームにボールが立てた音の種類。Step の政策が盤に記録し、Sfx が音名へ写す。
    /// 連続物理では「何に当たったか」を前後の World の差分から言い当てられない
    /// （速さが上限に達するとパドルヒットでも何も変わらない）ので、知っている者が書き残す。
    pub enum Sfx with Eq, Order, ToString {
        case PaddleHit    // パドルに当たった（反射角の上書きと同時）
        case WallHit      // 壁に当たった（物理の跳ね返りのみ）
        case BlockChip    // ハードブロックが耐えた
        case BlockBreak   // ブロックを壊した
    }

    // ── このフレームの入力（素のデータ）──
    // moveX はパドル移動の軸値。左右キーの押し下げを -1.0（左） 〜 0.0 〜 +1.0（右）に畳んだもの。
    // launch/enter は 1 回きり効けばよい判定（エッジ）で、押された瞬間だけ true になって届く。
    pub type alias Input = { moveX = Float64, launch = Bool, enter = Bool }

    /// 何も押されていない入力。
    pub def noInput(): Input = { moveX = 0.0, launch = false, enter = false }

    // ── フェーズ（Phase）: ゲームのデータはフェーズの case が所有する ──
    // タグを作るなら、そのタグが真にするデータを case が所有し、他のフェーズで無意味なデータは
    // 持たない。比較は match で行う（payload に匿名レコード・Map を含むので Eq は自動導出できない）。

    /// ゲームの大きなフェーズ。case ごとに、そのフェーズで意味のあるデータだけを持つ。
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

    /// 1 面の盤: 1 個だけのもの（ballPos・paddle）と、たくさんあるものの Store、そして盤の意味（残機・スコア・演出）。
    /// ボールの位置 ballPos は待機・飛行・凍結のすべてで描画に要るのでここに常在し、速度は
    /// BallState.Moving だけが持つ（位置は描画・速度は物理、と生存範囲で割る）。
    pub type alias GameCore = {
        paddle = Paddle,                            // 1 個だけ: パドル（中心 x）
        positions = Map[EntityId, Vec2.Vec2],       // 静止群（壁・ブロック）の中心座標
        shapes = Map[EntityId, CollisionShape2D],   // 静止群の当たり判定の形
        blocks = Map[EntityId, Int32],              // ブロックの印＋行番号（色分け用）
        durabilities = Map[EntityId, Durability],   // 壊せるブロックだけの耐久（不在=壊れない）
        ballPos = Vec2.Vec2,                        // 1 個だけ: ボールの中心（待機・飛行・凍結すべてで描画に要る）
        level = Int32,                              // いま遊んでいる面（1 始まり）
        lives = Int32,                              // 残機
        score = Int32,                              // スコア
        trauma = Float64,                           // 揺れの蓄積量 [0,1]。ヒットで積み、時間で減る（連打は重なる）
        fxClock = Float64,                          // 演出の通し時計（シェイクノイズの位相。常に進む）
        bursts = List[Burst],                       // 破壊の破片（状態を持たず、種と経過秒から毎フレーム計算で描くための記録）
        sfx = List[Sfx]                             // このフレームの衝突音の記録（毎フレーム頭で空へ。凍結盤では読まれない）
    }

    /// breakout 1 プレイの全状態: 調整値 params と、いまのフェーズ phase。ゲームのデータは phase の中。
    pub type alias World = {
        params = GameParameters.Params,   // 調整パラメータ（F1 で parameters.json から差し替わる・全フェーズ共通）
        phase = Phase                     // いまのフェーズ（ゲームのデータはこの case の中）
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

    /// ボールの半径（px）。ボールの形は Store ではなくこの定数が持つ。
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

    // シェイク（trauma 方式）: ヒットで trauma を積み、揺れ幅は trauma の二乗で効く。
    // 単発は控えめに、連打は蓄積して画面が暴れる —— 重なりこそが手応えになる。
    // 式と進め方（積む・減衰・オフセット導出）は CameraRig が持ち、ここは調整値だけを決める。

    /// シェイクの調整値: 満タン時の揺れ幅（px）・揺れの速さ（格子点/秒）・1 秒あたりの減衰量。
    pub def shakeSpec(): CameraRig.ShakeSpec = { maxOffset = 8.0, freq = 25.0, decayPerSecond = 1.5 }

    /// ハードブロックが耐えたときに積む trauma（単発では目立たず、連打で効いてくる小ささ）。
    pub def chipTrauma(): Float64 = 0.3

    // スコア。
    def normalScore(): Int32 = 10
    def hardScore(): Int32 = 30

    /// 壊したブロックの得点。2 発以上耐えたブロック（ハード）ほど高い。
    pub def blockScore(maxHp: Int32): Int32 = if (maxHp >= 2) hardScore() else normalScore()

    /// 壊したブロックが積む trauma。ハード（maxHp 2 以上）の破壊は重く揺れる。
    pub def destroyTrauma(maxHp: Int32): Float64 = if (maxHp >= 2) 0.7 else 0.45

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

    // ── ボールとパドルの形と位置（Store に載せず、定数と x から導く）──

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

    // ── レベルとの橋: セルへの id 採番と、文字の意味づけ ──
    // 盤面そのもの（文字の宣言データ）は Levels が持つ。ここはセルへ id を振り、文字を耐久へ写す。

    /// セル (col, row) のブロック id。文字の並びから決まる安定した番号。
    def cellId(col: Int32, row: Int32): EntityId = firstBlockId() + row * blockCols() + col

    /// レベル n の盤面を (id, col, row, 文字) のセル列で受け取る（文字データは Levels から）。
    def levelCells(n: Int32): List[(EntityId, Int32, Int32, Char)] =
        Levels.cells(n) |> List.map(cell ->
            (cellId(cell#col, cell#row), cell#col, cell#row, cell#glyph))

    /// 文字ごとの耐久。'#'（壊れない）は None = durabilities に載らない。
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
    /// ボールとパドルは普通のフィールドとして持ち、Store（positions / shapes）には動かないもの
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
          trauma = 0.0, fxClock = 0.0, bursts = Nil, sfx = Nil }

    /// レベル n のプレイ開始時の World: 盤は freshCore(n)、ボールはサーブ待ち、パラメータは既定値。
    pub def playingWorld(n: Int32): World =
        { params = GameParameters.defaults(), phase = Phase.Playing(freshCore(n), BallState.Waiting) }

    /// タイトル画面の World: 文字を見せるだけのフェーズ（盤は持たない）。
    pub def titleWorld(): World = { params = GameParameters.defaults(), phase = Phase.Title }

    pub def initialWorld(): World = titleWorld()

    // ── 導出クエリ ──

    /// 壊せるブロックが 0 になったらクリア（壊れないブロックは残ってよい）。盤 GameCore から判定する。
    pub def won(core: GameCore): Bool = Map.isEmpty(core#durabilities)

    /// リモートデバッグ（view=status）用の 1 行サマリ。フェーズと、調査に効く値だけを短く並べる。
    pub def statusLine(world: World): String =
        match world#phase {
            case Phase.Title => "phase=Title"
            case Phase.Playing(core, BallState.Waiting) =>
                "phase=Playing state=Waiting ${coreStatus(core)}"
            case Phase.Playing(core, BallState.Moving(moving)) =>
                "phase=Playing state=Moving vel=(${RemoteDebug.fmt1(moving#vel#x)},${RemoteDebug.fmt1(moving#vel#y)}) ${coreStatus(core)}"
            case Phase.Cleared(core)  => "phase=Cleared ${coreStatus(core)}"
            case Phase.GameOver(core) => "phase=GameOver ${coreStatus(core)}"
        }

    /// 盤のサマリ（ボール・パドル・残機・スコア・残りブロック数）。座標は 1 桁小数へ丸める。
    def coreStatus(core: GameCore): String =
        "ball=(${RemoteDebug.fmt1(core#ballPos#x)},${RemoteDebug.fmt1(core#ballPos#y)})"
        + " paddle=${RemoteDebug.fmt1(core#paddle#x)} lives=${core#lives} score=${core#score}"
        + " level=${core#level} blocks=${Map.size(core#blocks)}"
}
