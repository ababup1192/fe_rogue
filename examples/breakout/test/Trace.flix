// Trace — ギャラリーとテストが共有する、breakout 固有のシナリオ。
//
// breakout の物理は update が駆動するので、シナリオは「入力の列」より「初期 World」で表す:
// ボールをどこに置き、どの向きへ撃つか。あとは idle 入力で Replay.play / Replay.timeline に
// 流せば、純粋な update が結果を言い当てる —— 反射角の確認にも、GIF の駒にも、テストの pin にも
// 同じ 1 つのシナリオが使える。時計は 1/64 秒（2進小数）なので固定した結末は誤差なく正確。

mod Trace {

    // ── 時計と入力 ──
    pub def dt(): Float64 = 1.0 / 64.0
    pub def idle(): Field.Input = Field.noInput()

    pub def hold(input: Field.Input, frames: Int32): Replay.Cue[Field.Input] =
        { input = input, frames = frames }

    /// idle のまま n フレーム流す（物理だけを走らせる）。
    pub def flight(frames: Int32): List[Replay.Cue[Field.Input]] = hold(idle(), frames) :: Nil

    // ── 局面の読み取り（テストが World から値を取り出す）──
    // 盤やボール速度は局面の case の中にあるので、テストは match でなくこの薄いアクセサ越しに読む。
    // 「その局面に無い値」は Option の None / 空リストで返る（サーブ待ちに速度は無い、等）。

    /// Playing / Cleared / GameOver が持つ盤（GameCore）。Title は盤を持たないので None。
    pub def coreOf(world: Field.World): Option[Field.GameCore] = match world#phase {
        case Field.Phase.Title                => None
        case Field.Phase.Playing(core, _ball) => Some(core)
        case Field.Phase.Cleared(core)        => Some(core)
        case Field.Phase.GameOver(core)       => Some(core)
    }

    /// 飛行中のボール速度。サーブ待ち・クリア・ゲームオーバー・タイトルは「速度という状態が無い」ので None。
    pub def ballVelOf(world: Field.World): Option[Vec2.Vec2] = match world#phase {
        case Field.Phase.Title                                      => None
        case Field.Phase.Playing(_core, Field.BallState.Waiting)    => None
        case Field.Phase.Playing(_core, Field.BallState.Moving(mv)) => Some(mv#vel)
        case Field.Phase.Cleared(_core)                             => None
        case Field.Phase.GameOver(_core)                            => None
    }

    /// ボールの残像リング。飛行中だけ中身があり、他の局面は空。
    pub def trailOf(world: Field.World): List[Vec2.Vec2] = match world#phase {
        case Field.Phase.Title                                      => Nil
        case Field.Phase.Playing(_core, Field.BallState.Waiting)    => Nil
        case Field.Phase.Playing(_core, Field.BallState.Moving(mv)) => mv#trail
        case Field.Phase.Cleared(_core)                             => Nil
        case Field.Phase.GameOver(_core)                            => Nil
    }

    /// サーブ待ちか（旧 served == false に相当）。
    pub def isWaiting(world: Field.World): Bool = match world#phase {
        case Field.Phase.Title                                       => false
        case Field.Phase.Playing(_core, Field.BallState.Waiting)     => true
        case Field.Phase.Playing(_core, Field.BallState.Moving(_mv)) => false
        case Field.Phase.Cleared(_core)                              => false
        case Field.Phase.GameOver(_core)                             => false
    }

    /// タイトル画面か。
    pub def isTitle(world: Field.World): Bool = match world#phase {
        case Field.Phase.Title           => true
        case Field.Phase.Playing(_c, _b) => false
        case Field.Phase.Cleared(_c)     => false
        case Field.Phase.GameOver(_c)    => false
    }

    /// クリア局面か。
    pub def isCleared(world: Field.World): Bool = match world#phase {
        case Field.Phase.Title           => false
        case Field.Phase.Playing(_c, _b) => false
        case Field.Phase.Cleared(_c)     => true
        case Field.Phase.GameOver(_c)    => false
    }

    /// 盤のスコア（Title は None）。
    pub def scoreOf(world: Field.World): Option[Int32] = coreOf(world) |> Option.map(c -> c#score)

    /// 盤の残機（Title は None）。
    pub def livesOf(world: Field.World): Option[Int32] = coreOf(world) |> Option.map(c -> c#lives)

    // ── 形の補助 ──
    pub def vec(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }
    pub def rect(w: Float64, h: Float64): CollisionShape2D = CollisionShape2D.RectShape2D({ width = w, height = h })

    // シナリオ用のブロック寸法と id。
    def blockW(): Float64 = 30.0
    def blockH(): Float64 = 12.0
    pub def blockId(): EntityId = 50
    def floorId(): EntityId = 40
    def keepaliveId(): EntityId = 60

    /// 耐久の速記: 通常（1発）とハード（2発）。
    pub def normalHp(): Field.Durability = { hp = 1, maxHp = 1 }
    pub def hardHp(): Field.Durability = { hp = 2, maxHp = 2 }

    /// mkWorld の材料一式。物理の静止群（壁・床・ブロックの形）と、ボール、そして
    /// ブロックの印（行番号）・耐久を店ごとに渡す（durabilities に載せなければ壊れない）。
    pub type alias Setup = {
        statics = List[(EntityId, Vec2.Vec2, CollisionShape2D)],
        ball = { pos = Vec2.Vec2, vel = Vec2.Vec2 },
        blocks = List[(EntityId, Int32)],
        durabilities = List[(EntityId, Field.Durability)]
    }

    // ── World 組み立て ──

    /// シナリオ World を組む。単独者はそのまま値に（ボール位置は指定どおり、paddle は中央 x=160）、
    /// statics は静止群の店へ。ボールは飛行中（Moving）＝即プレイで、指定の速度を持って動き出す。
    /// 壊せるブロックがひとつも無い setup には、左上隅に手の届かない「置物」ブロックを 1 個
    /// 足す — クリア（won）はモーダルで物理が止まるので、物理を観察するシナリオでは
    /// 「壊せるブロックが残っている」状態を保つ必要がある。
    pub def mkWorld(setup: Setup): Field.World =
        let keepalive = List.isEmpty(setup#durabilities);
        let statics =
            if (keepalive) (keepaliveId(), vec(30.0, 12.0), rect(blockW(), blockH())) :: setup#statics
            else setup#statics;
        let blocks = if (keepalive) (keepaliveId(), 0) :: setup#blocks else setup#blocks;
        let durabilities =
            if (keepalive) (keepaliveId(), normalHp()) :: setup#durabilities else setup#durabilities;
        let core = {
            paddle = { x = 160.0 },
            positions = List.map(entry -> { let (id, pos, _shape) = entry; (id, pos) }, statics) |> List.toMap,
            shapes    = List.map(entry -> { let (id, _pos, shape) = entry; (id, shape) }, statics) |> List.toMap,
            blocks = List.toMap(blocks),
            durabilities = List.toMap(durabilities),
            ballPos = setup#ball#pos,
            level = 1, lives = 3, score = 0,
            shakeElapsed = 999.0, shakeMagnitude = 0.0, bursts = Nil
        };
        { params = GameParameters.defaults(),
          phase = Field.Phase.Playing(core, Field.BallState.Moving({ vel = setup#ball#vel, trail = Nil })) }

    def blockAt(center: Vec2.Vec2): (EntityId, Vec2.Vec2, CollisionShape2D) =
        (blockId(), center, rect(blockW(), blockH()))

    /// 横並び 3 個のブロック（中央 x=160）。中央だけがボールに当たるので、1 個壊しても他が
    /// 残り「全消し（クリア）」にはならない（破壊/シェイク演出を CLEAR 表示で邪魔しないため）。
    def blockRow3(y: Float64, durability: Field.Durability):
            (List[(EntityId, Vec2.Vec2, CollisionShape2D)], List[(EntityId, Int32)], List[(EntityId, Field.Durability)]) =
        let xs = 122.0 :: 160.0 :: 198.0 :: Nil;
        let ids = blockId() :: (blockId() + 1) :: (blockId() + 2) :: Nil;
        let statics = List.zip(ids, xs) |> List.map(pair -> {
            let (id, x) = pair;
            (id, vec(x, y), rect(blockW(), blockH()))
        });
        (statics, List.map(id -> (id, 2), ids), List.map(id -> (id, durability), ids))

    // ── ブロック衝突の挙動シナリオ ──
    // 反射だけを見せたいので、当たっても壊れないハードブロック（2発耐久）を的にする:
    // 1 発当ててもブロックは残り、ボールの反射がそのまま見える。

    /// 横から: ボールが左からブロックの左面へ当たり、x 反転で左へ返る。
    pub def blockSideWorld(): Field.World =
        mkWorld({ statics = blockAt(vec(180.0, 90.0)) :: Nil,
                  ball = { pos = vec(120.0, 90.0), vel = vec(130.0, 0.0) },
                  blocks = (blockId(), 0) :: Nil,
                  durabilities = (blockId(), hardHp()) :: Nil })

    /// 下から: ボールが真下からブロックの底面へ当たり、y 反転で下へ返る。
    pub def blockBelowWorld(): Field.World =
        mkWorld({ statics = blockAt(vec(160.0, 70.0)) :: Nil,
                  ball = { pos = vec(160.0, 120.0), vel = vec(0.0, -130.0) },
                  blocks = (blockId(), 0) :: Nil,
                  durabilities = (blockId(), hardHp()) :: Nil })

    /// 角: ボールが斜めにブロックの角へ当たる（破綻しないことの確認）。
    pub def blockCornerWorld(): Field.World =
        mkWorld({ statics = blockAt(vec(160.0, 70.0)) :: Nil,
                  ball = { pos = vec(122.0, 108.0), vel = vec(92.0, -92.0) },
                  blocks = (blockId(), 0) :: Nil,
                  durabilities = (blockId(), hardHp()) :: Nil })

    /// 破壊: 横並び 3 個の通常ブロック（1発）の中央へ下から当てて壊す（破片が飛ぶ・他は残る）。
    pub def blockBreakWorld(): Field.World =
        let (statics, blocks, durabilities) = blockRow3(70.0, normalHp());
        mkWorld({ statics = statics, ball = { pos = vec(160.0, 120.0), vel = vec(0.0, -130.0) },
                  blocks = blocks, durabilities = durabilities })

    /// ハードブロックのシェイク: 横並び 3 個のハードブロックの中央と、下の床の間でボールが往復し、
    /// 1発目=耐える+小シェイク、床で跳ね返って 2発目=破壊+大シェイク（両脇は残るので CLEAR は出ない）。
    pub def hardShakeWorld(): Field.World =
        let (statics, blocks, durabilities) = blockRow3(60.0, hardHp());
        let floor = (floorId(), vec(160.0, 150.0), rect(220.0, 6.0));   // 静止（velocities に居ない）
        mkWorld({ statics = List.append(statics, floor :: Nil),
                  ball = { pos = vec(160.0, 120.0), vel = vec(0.0, -130.0) },
                  blocks = blocks, durabilities = durabilities })

    // ── パドル反射シナリオ（当たり位置で角度が変わる）──

    /// パドルへ当てるシナリオ: 中心からのオフセット割合 offset（-1..1）の真上からボールを落とす。
    /// パドル（単独者・中央 x=160）は mkWorld が備え付けるので、当たると角度＋加速規則
    /// （Bounce）で速度が上書きされる。
    pub def paddleBounceWorld(offset: Float64): Field.World =
        let ballX = 160.0 + offset * Field.paddleHalfWidth();
        mkWorld({ statics = Nil,
                  ball = { pos = vec(ballX, 180.0), vel = vec(0.0, 130.0) },
                  blocks = Nil, durabilities = Nil })

    // ── ポケットシナリオ（レベル 3 の見せ場）──

    /// レベル 3 の実盤で、中央の縦通路へ撃ち込む。ボールは天井まで駆け上がり、天井と不壊の
    /// 帯の間のポケットで横へ流れながら、上段のブロックを上から壊し続ける。
    /// わずかに右へ傾けて入れる（角度が横流れの速さになる。垂直だと同じ列を往復するだけ）。
    /// 入射（x=156, offset=0.10）は「600 フレームで 5 個壊す」持続チューニングの実測値。
    pub def pocketWorld(): Field.World =
        let core = { ballPos = vec(156.0, 200.0) | Field.freshCore(3) };
        { params = GameParameters.defaults(),
          phase = Field.Phase.Playing(core,
              Field.BallState.Moving({ vel = Bounce.paddleReflect(0.10, Field.ballSpeed()), trail = Nil })) }

    // ── 加速ラリーシナリオ（速度変化の見せ場）──

    /// 密閉ラリー室: 左右の壁と低い天井スラブ（不壊）で囲い、中央のパドル（mkWorld 備え付け）へ
    /// 真上からボールを落とす。垂直ラリーが続き、パドルヒットのたびに +2.5% ずつ速くなる（上限まで）。
    /// スラブの上に通常ブロックを 1 個置いてあるのは「壊せるブロックが残っている＝クリアの
    /// モーダル停止に入らない」ための置物で、ボールは決して届かない。
    pub def speedRampWorld(): Field.World =
        let slabY = 110.0;
        let leftWall = (Field.leftWallId(), vec(3.0, 120.0), rect(6.0, 240.0));
        let rightWall = (Field.rightWallId(), vec(317.0, 120.0), rect(6.0, 240.0));
        let slab = (floorId(), vec(160.0, slabY), rect(308.0, 10.0));
        let decoy = (blockId(), vec(30.0, slabY - 11.0), rect(30.0, 12.0));
        mkWorld({ statics = leftWall :: rightWall :: slab :: decoy :: Nil,
                  ball = { pos = vec(160.0, 160.0), vel = vec(0.0, Field.ballSpeed()) },
                  blocks = (blockId(), 2) :: Nil,
                  durabilities = (blockId(), normalHp()) :: Nil })
}
