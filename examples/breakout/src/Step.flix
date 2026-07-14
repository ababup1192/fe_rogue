// Step — World→World の純関数＝ルール: 盤（World）を dt だけ進める update と、その政策関数。
// ここに副作用は無い（`\ GameEngine.Game` を持たない純粋層）。境界越え —— キー読み・描画・
// parameters.json 読み直し —— は App と Controls に住む。値の定義は World、描画は View。
//
// update は `(input, dt, world) -> world` の純関数で、いまのフェーズ（world#phase）で場合分けする:
// タイトルは Enter を待ち、サーブ待ちはパドルを動かして launch を待ち、飛行中は物理を回し、
// クリア・ゲームオーバーはモーダル（Enter だけを読み、演出の余韻だけが進む）。フェーズの case が
// 網羅されているので「読み落とした状況」はコンパイラが弾く。
//
// 飛行中の 1 フレームは Physics2D の 4 つの純関数をパイプで合成して進める（能力を並べる ECS の書き味）:
//
//   ボールとパドルを Store へ合流 → 位置を積分 → 衝突を検出 → 速度を反射 & めり込み解消 → 読み戻し → 政策
//
// Store は「たくさんあるもの」のための道具。ボールとパドルは普通の値として盤（GameCore）に住み、
// stepPhysics の間だけ Store に合流する（射影と読み戻しは 1 関数に閉じ、
// 権威は常に core#ballPos / core#paddle）。飛行 1 フレームのあいだは盤・速度・残像・調整値を
// Frame に束ねてパイプへ流し、フレーム末にその結末（クリア / ミス / 続行）から次のフェーズを決める。
// 「政策」= 当たったあとゲームがどう反応するか: パドルに当たれば反射角と加速を Bounce 規則で
// 上書きし、ブロックに当たれば耐久を減らし（0 で破壊・破片・スコア・シェイク）、底へ落ちれば
// ミス。機構（Physics2D）は「跳ね返す」までを保証し、政策はそれを読んで意味を足す。

mod Step {

    /// 飛行 1 フレームの作業束: 盤・ボールの速度・残像・調整値をひとつにまとめてパイプへ流す。
    /// 位置は core#ballPos（常在）、速度と残像は飛行中だけ在るので Frame に載せて運ぶ。
    type alias Frame = { core = Field.GameCore, vel = Vec2.Vec2, trail = List[Vec2.Vec2],
                         params = GameParameters.Params }

    // ── update: フェーズごとに 1 フレーム進める ──

    pub def update(input: Field.Input, dt: Float64, world: Field.World): Field.World =
        { phase = nextPhase(input, dt, world#params, world#phase) | world }

    /// いまのフェーズから次のフェーズを決める。case は網羅（ワイルドカードを使わず、読み落としを型で防ぐ）。
    def nextPhase(input: Field.Input, dt: Float64, params: GameParameters.Params,
                  phase: Field.Phase): Field.Phase =
        match phase {
            case Field.Phase.Title =>
                if (input#enter) Field.Phase.Playing(Field.freshCore(1), Field.BallState.Waiting)
                else Field.Phase.Title
            case Field.Phase.Playing(core, Field.BallState.Waiting)   => updateWaiting(input, dt, params, core)
            case Field.Phase.Playing(core, Field.BallState.Moving(mv)) => updateMoving(input, dt, params, core, mv)
            case Field.Phase.Cleared(core)  => updateCleared(input, dt, core)
            case Field.Phase.GameOver(core) => updateGameOver(input, dt, core)
        }

    /// サーブ待ち: パドルを動かし、ボールをその上に貼り付ける。launch でその速度を与えて飛ばす。
    /// 待っている間も演出（シェイク・破片）の時計は進む。速度も残像も持たない = Waiting の型のまま。
    /// 音の記録（sfx）はフレーム頭で空へ（待機中は何にも当たらない）。
    def updateWaiting(input: Field.Input, dt: Float64, params: GameParameters.Params,
                      core: Field.GameCore): Field.Phase =
        let movedCore = movePaddle(input, dt, params, { sfx = Nil | core });
        let glued = updateEffects(dt, { ballPos = Field.servePos(movedCore#paddle#x) | movedCore });
        if (input#launch)
            Field.Phase.Playing(glued, Field.BallState.Moving({ vel = Field.serveVelocity(), trail = Nil }))
        else
            Field.Phase.Playing(glued, Field.BallState.Waiting)

    /// 飛行本体: パドルを動かしてから物理を 1 ステップ回し、その衝突(collisions)を政策で読む。
    /// フレーム末に結末で分岐する —— 同フレームで「勝ち」と「落下」が両立しうるが勝ちが優先:
    ///   壊せるブロックが尽きた   → Cleared（速度は Moving ごと消え、ballPos は凍結）
    ///   落下して残機が尽きた     → GameOver
    ///   落下したが残機が残る     → サーブ待ちへ戻す（残機を 1 減らし、ボールをパドル上へ）
    ///   まだ飛んでいる           → Moving のまま次フレームへ
    /// どの結末でも updateEffects(dt) を必ず通してから移る（破片の経過・シェイクを 1dt 進める）。
    def updateMoving(input: Field.Input, dt: Float64, params: GameParameters.Params,
                     core: Field.GameCore, moving: { vel = Vec2.Vec2, trail = List[Vec2.Vec2] }): Field.Phase =
        let movedCore = movePaddle(input, dt, params, { sfx = Nil | core });   // 音の記録はフレーム頭で空へ
        let (stepped, collisions) =
            stepPhysics(dt, { core = movedCore, vel = moving#vel, trail = moving#trail, params = params });
        let frame = stepped
            |> onPaddleHit(collisions)
            |> onBlockHit(collisions)
            |> onWallHit(collisions)
            |> updateTrail;
        let played = frame#core;
        match (Field.won(played), fellBelow(played#ballPos)) {
            case (true, _)     => Field.Phase.Cleared(updateEffects(dt, played))
            case (false, true) =>
                if (played#lives <= 1)
                    Field.Phase.GameOver(updateEffects(dt, { lives = 0 | played }))
                else
                    Field.Phase.Playing(
                        updateEffects(dt, { lives = played#lives - 1,
                                            ballPos = Field.servePos(played#paddle#x) | played }),
                        Field.BallState.Waiting)
            case (false, false) =>
                Field.Phase.Playing(updateEffects(dt, played),
                                    Field.BallState.Moving({ vel = frame#vel, trail = frame#trail }))
        }

    /// クリア後: Enter で次の面へスコア・残機を持ち越す（最終面を終えたらタイトルへ）。Enter 無しは
    /// 余韻（updateEffects）だけ進む。凍結した盤とボール位置はそのまま見せ続ける。
    def updateCleared(input: Field.Input, dt: Float64, core: Field.GameCore): Field.Phase =
        if (input#enter)
            (if (core#level < Levels.count())
                Field.Phase.Playing({ lives = core#lives, score = core#score | Field.freshCore(core#level + 1) },
                                    Field.BallState.Waiting)
             else
                Field.Phase.Title)
        else
            Field.Phase.Cleared(updateEffects(dt, core))

    /// ゲームオーバー後: Enter で同じ面を最初からやり直す（残機もスコアも初期値へ）。Enter 無しは
    /// 余韻だけ進む。
    def updateGameOver(input: Field.Input, dt: Float64, core: Field.GameCore): Field.Phase =
        if (input#enter)
            Field.Phase.Playing(Field.freshCore(core#level), Field.BallState.Waiting)
        else
            Field.Phase.GameOver(updateEffects(dt, core))

    /// 物理の 1 ステップ。ボールとパドルをこの間だけ Store へ合流させ、
    /// Physics2D の純関数列（積分 → 検出 → 分離・反射）を通し、ボールの位置と速度を読み戻す。
    /// ボールとパドルはここで一瞬だけ Store に混ざり、すぐ値へ帰る。
    def stepPhysics(dt: Float64, frame: Frame): (Frame, List[Physics2D.Contact]) =
        let core = frame#core;
        let positions = core#positions
            |> Map.insert(Field.ballId(), core#ballPos)
            |> Map.insert(Field.paddleId(), Field.paddlePos(core#paddle#x));
        let shapes = core#shapes
            |> Map.insert(Field.ballId(), Field.ballShape())
            |> Map.insert(Field.paddleId(), Field.paddleShape());
        let velocities = Map.singleton(Field.ballId(), frame#vel);
        let restitutions = Map.singleton(Field.ballId(), 1.0);   // ボールは完全弾性
        let integrated = Physics2D.integrate(dt, velocities, positions);
        let collisions = Physics2D.detect(integrated, shapes);
        let separated = Physics2D.separate(collisions, velocities, integrated);
        let bounced = Physics2D.bounce(collisions, restitutions, velocities);
        // 読み戻し: ボールは射影に必ず居るので、既定値は「動かなかった」に倒すだけの保険。
        let newPos = Map.get(Field.ballId(), separated) |> Option.getWithDefault(core#ballPos);
        let newVel = Map.get(Field.ballId(), bounced) |> Option.getWithDefault(frame#vel);
        ({ core = { ballPos = newPos | core }, vel = newVel | frame }, collisions)

    // ── パドル移動（位置を入力で直接書く。速さはパラメータ）──

    def movePaddle(input: Field.Input, dt: Float64, params: GameParameters.Params,
                   core: Field.GameCore): Field.GameCore =
        let dir = input#moveX;
        let newX = Float64.max(Field.paddleMinX(),
                               Float64.min(Field.paddleMaxX(),
                                           core#paddle#x + dir * params#paddleSpeed * dt));
        { paddle = { x = newX } | core }

    // ── 政策: パドル反射（角度と速さの上書き — 本作の要）──
    // 物理は素の反射（上向き）まで済ませてある。パドル衝突があれば、当たった位置で決まる
    // 角度規則（Bounce）でボール速度を丸ごと上書きする。中央=真上、端=鋭角。
    // 速さも同時に上がる: ヒット毎の倍率・端当てボーナス・上限はすべてパラメータから
    // （既定 +2.5% / 最大 +5% / 基準の 1.6 倍。落下ミス後のサーブで基準へ戻る）。
    def onPaddleHit(collisions: List[Physics2D.Contact], frame: Frame): Frame =
        if (Physics2D.touches(Field.paddleId(), collisions)) {
            let core = frame#core;
            let offset = Bounce.offsetFraction({ ballX = core#ballPos#x, paddleX = core#paddle#x,
                                                 halfWidth = Field.paddleHalfWidth() });
            let tuning = { gain = frame#params#speedGainPerHit,
                           edgeBonus = frame#params#edgeSpeedBonus,
                           maxFactor = frame#params#maxSpeedFactor };
            let speed = Bounce.speedAfterHitWith(tuning,
                { current = Vec2.length(frame#vel), offsetFrac = offset, base = Field.ballSpeed() });
            { vel = Bounce.paddleReflectWith({ maxAngle = frame#params#maxBounceAngle,
                                               offsetFrac = offset, speed = speed }),
              core = { sfx = Field.Sfx.PaddleHit :: core#sfx | core } | frame }
        }
        else frame

    // ── 政策: ブロックの耐久・破壊・破片・スコア・シェイク ──
    // ボールが絡む衝突の相手のうちブロックだけを（角で 2 衝突に割れても）id 集合で 1 発ずつ処理する。
    // 壊れないブロック（durabilities に居ない）はここで何も起きない — 物理の跳ね返りだけが残る。
    def onBlockHit(collisions: List[Physics2D.Contact], frame: Frame): Frame =
        let hitIds = Physics2D.contactsOf(Field.ballId(), collisions)
            |> List.filterMap(contact -> Physics2D.other(Field.ballId(), contact))
            |> List.filter(id -> Map.memberOf(id, frame#core#blocks))
            |> List.toSet;
        { core = Set.foldLeft((accCore, id) -> hitBlock(id, accCore), frame#core, hitIds) | frame }

    /// 政策: 壁に当たった事実の記録。物理は既に跳ね返し済みで、ここは音のために盤へ書くだけ
    /// （角で 2 枚の壁に触れても音は 1 つ）。
    def onWallHit(collisions: List[Physics2D.Contact], frame: Frame): Frame =
        let hitWall = Physics2D.contactsOf(Field.ballId(), collisions)
            |> List.filterMap(contact -> Physics2D.other(Field.ballId(), contact))
            |> List.exists(id -> List.memberOf(id, Field.wallIds()));
        if (hitWall) { core = { sfx = Field.Sfx.WallHit :: frame#core#sfx | frame#core } | frame }
        else frame

    /// ブロック 1 個に 1 発。耐久を持たなければ壊れない（素通し）。耐久が残ればちいさく揺れ、
    /// 尽きれば破壊する。
    def hitBlock(id: EntityId, core: Field.GameCore): Field.GameCore =
        match Map.get(id, core#durabilities) {
            case None => core   // 壊れないブロック: 跳ね返すだけで音も揺れも得点も無い
            case Some(durability) =>
                if (durability#hp - 1 <= 0)
                    destroyBlock(id, durability#maxHp, core)
                else
                    { durabilities = Map.insert(id, { hp = durability#hp - 1 | durability },
                                                core#durabilities),
                      sfx = Field.Sfx.BlockChip :: core#sfx | core }
                        |> CameraRig.addTrauma(Field.chipTrauma())
        }

    /// 破壊: 物理とブロックの Store から消し、スコアを足し、破片を撒き、シェイクを起こす。
    /// 得点と揺れの大きさは生まれたときの耐久（maxHp）から導く: 2 発耐えたブロックほど重い。
    def destroyBlock(id: EntityId, maxHp: Int32, core: Field.GameCore): Field.GameCore =
        let center = posOf(id, core) |> Option.getWithDefault(Vec2.zero());
        let burst: Field.Burst = { seed = id, pos = center, elapsed = 0.0 };
        { positions = Map.remove(id, core#positions),
          shapes = Map.remove(id, core#shapes),
          blocks = Map.remove(id, core#blocks),
          durabilities = Map.remove(id, core#durabilities),
          score = core#score + Field.blockScore(maxHp),
          bursts = burst :: core#bursts,
          sfx = Field.Sfx.BlockBreak :: core#sfx
          | core }
            |> CameraRig.addTrauma(Field.destroyTrauma(maxHp))

    /// ボールの今の位置を残像リングの先頭に積む（古い端は落として有界を保つ。長さはパラメータ）。
    def updateTrail(frame: Frame): Frame =
        { trail = List.take(frame#params#trailLength, frame#core#ballPos :: frame#trail) | frame }

    /// Store からの位置読み。
    def posOf(id: EntityId, core: Field.GameCore): Option[Vec2.Vec2] = Map.get(id, core#positions)

    /// この距離だけ画面下端を割ったらミス（枠の無い底からボールが落ちた）。
    def fellBelow(pos: Vec2.Vec2): Bool = pos#y > Field.designH() + Field.ballFallMargin()

    // ── 演出の経年: 揺れを減衰させ（CameraRig.tick）、寿命の切れた破片を落とす ──
    def updateEffects(dt: Float64, core: Field.GameCore): Field.GameCore =
        let ticked = CameraRig.tick(dt, Field.shakeSpec(), core);
        { bursts = ticked#bursts
              |> List.map(burst -> { elapsed = burst#elapsed + dt | burst })
              |> List.filter(burst -> burst#elapsed < Field.burstLifetime())
          | ticked }
}
