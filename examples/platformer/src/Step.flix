// Step — 1 フレームのルール（純粋）。タイマー → ジャンプの成立（前フレームの接地で判定・
// 離脱時に床の水平速度を継承）→ 走りと重力 → carry（乗っている床の移動ぶんを物理の前に運ぶ）→
// 積分・検出 → 一方通行フィルタ → 分離 → 速度の解決 → 接地の再導出 → 下り坂の吸着 →
// 乗り床の再導出 → 敵との接触（床の物理の後・死亡判定の前）→ 出来事の記録、の順で進む。
//
// 順序が手触りを決める:
//   ジャンプ判定は「前フレームの接地」を見る（1 フレームの遅れはコヨーテタイムが吸収する）。
//   carry は積分の前 — 下降するリフトでも足元が床と一緒に下がるので接地が切れない。
//   一方通行フィルタの足元判定（prevBottom）も carry 後の位置で取る: 床上面と足元が
//   同期して動くので、下降リフトの上でも「足元が上面より上」が成立し続ける。
//   接地の再計算は separate の後 — 押し出し済みの位置での接触が本当の接地で、
//   崖から歩き出た瞬間はここで grounded が消え、次フレームからコヨーテが減り始める。
//   重力は接地中も掛け続ける — separate が毎フレーム打ち消すので接触が切れず、接地が安定する。
//   下り坂の吸着は接地の再計算の直後 — 直前まで接地していたのに接触を失ったフレームだけ
//   足元を snapProbe px 探り、坂を降りる 1 フレームの段差を接地のまま繋ぐ（着地音スパム防止）。
//
// 坂の上だけは二本立て: 登り（入力が坂の高い側）は速度を斜面の接線に沿わせ（重力なし・
//   吸い付き速度で接触維持）、入力なしは静止摩擦でその場に停める。下り・勢いの滑走・空中は
//   従来の物理のまま — 45° 下りの overspeed（P スピード帯でゆっくりしか戻らない滑り）は手触りの山。

mod Step {

    /// ダッシュの勢い（0..1）: |vx| が maxRunSpeed（160）から最高速 280 までのどこかを示す。
    /// 土埃の頻度・粒の多さ・大きさをこの 1 本の帯で段階づける（新しい状態は持たない）。
    def dashBand(vx: Float64): Float64 =
        Float64.max(0.0, Float64.min(1.0, (Float64.abs(vx) - Jump.maxRunSpeed()) / 120.0))

    /// 演出の粒（ダスト）を出す cadence（1 秒あたりの回数）。速いほど頻繁（8〜24 回/秒）。
    /// ダッシュ中ずっと出さず、t×rate の floor が変わったフレームだけ 1 個出す = 足跡の間隔。
    def dustRate(vx: Float64): Float64 = 8.0 + 16.0 * dashBand(vx)

    /// vx の符号（0 は正扱い）。土埃・ジャンプ噴射の向き決めに使う小さな補助。
    def sign(vx: Float64): Float64 = if (vx < 0.0) -1.0 else 1.0

    /// フレーム数から決定的な Int32 の種を作る（同じ入力なら常に同じ種＝リプレイで揺れない）。
    def seedAt(t: Float64, dt: Float64): Int32 =
        RenderUtil.floatToInt32(Float64.floor(t / dt + 0.5))

    /// 1 フレーム進める。入力 → タイマー → ジャンプ → 走り → carry → 物理 → 接地 → 出来事。
    pub def update(input: Field.Input, dt: Float64, world: Field.World): Field.World =
        let p = world#params;
        let player0 = world#player;
        let t0 = world#time;
        let t1 = t0 + dt;
        // 動く床は時刻の純関数: このフレームの実位置で当たる。
        let platformsNow = Field.platformsAt(t1, world#platforms);

        // ── 演出の粒: 経年（elapsed を進め、寿命切れを落とす）。スポーンは物理解決後に行う
        //    （posFinal/velFinal/groundedFinal がここではまだ求まっていないため）。──
        let bursts1 = world#bursts
            |> List.map(b -> { elapsed = b#elapsed + dt | b })
            |> List.filter(b -> b#elapsed < GameFx.lifeOf(b#kind));

        // ── 乗っている床（前フレームの接地が導出済み）──
        let ridingPf = player0#ridingId
            |> Option.flatMap(id -> List.findLeft(pf -> pf#id == id, world#platforms));

        // ── すり抜け降下: 一方通行の上で 下+ジャンプ。押下はバッファに入れない（暴発防止）──
        let ridingOneWay = ridingPf |> Option.map(pf -> pf#oneWay) |> Option.getWithDefault(false);
        let dropping = input#down and input#jumpPressed and player0#grounded and ridingOneWay;
        let dropLeft1 = if (dropping) Field.dropTime() else Jump.tickTimer(dt, player0#dropLeft);

        // ── タイマー（バッファは押下で充填、コヨーテは接地中ずっと満タン）──
        let buffer0 = if (input#jumpPressed and not dropping) p#bufferTime
                      else Jump.tickTimer(dt, player0#bufferLeft);
        let coyote0 = if (player0#grounded) p#coyoteTime else Jump.tickTimer(dt, player0#coyoteLeft);

        // ── ジャンプの成立（前フレームの接地で判定）──
        let jumps = Jump.canJump(player0#grounded, coyote0, buffer0);
        let vyJumped = if (jumps) Jump.jumpVelocity(p) else player0#vel#y;
        let buffer1 = if (jumps) 0.0 else buffer0;
        let coyote1 = if (jumps) 0.0 else coyote0;
        let held1 = if (jumps) true else player0#jumpHeld;

        // ── 上昇カット（離した瞬間の 1 回だけ。下降中の離しは素通し）──
        let cutting = not input#jumpDown and held1;
        let vyCut = if (cutting) Jump.cutJump(p, vyJumped) else vyJumped;
        let held2 = if (cutting) false else held1;

        // ── 走り + ジャンプ離脱時だけ床の水平速度を 1 回継承（垂直は継承しない）──
        let dir = (if (input#left) -1.0 else 0.0) + (if (input#right) 1.0 else 0.0);
        let vxRun = Jump.horizontalStep(p, dt,
            { grounded = player0#grounded, dash = input#dash, dir = dir, vx = player0#vel#x });
        let vx = vxRun + (if (jumps) platformVx(dt, t0, t1, ridingPf) else 0.0);
        let vy = Jump.applyGravity(p, dt, vyCut);
        // ── 坂の二本立て: 登り（入力が坂の高い側）は速度を斜面の接線に沿わせる。
        //    下り・入力なしの滑走・空中は従来の物理のまま（下りの overspeed は手触りの山）。
        //    従来は登りも「重力 + 法線成分ゼロ化 + 分離の押し出し」で、登りの速度が
        //    ほぼ食い潰され、低速では押し出しの下り成分が勝って入力と逆に滑って見えた。──
        let vel = match climbVelocity(p, dt, { dash = input#dash, dir = dir, jumps = jumps },
                                      player0, ridingPf) {
            case Some(velClimb) => velClimb
            case None           => { x = vx, y = vy }
        };

        // ── carry: 乗っている床の移動ぶんだけ、物理の前に位置を運ぶ（下降リフトで接地が切れない鍵）──
        let carryDelta = ridingPf
            |> Option.map(pf -> Vec2.sub(Field.platformPosAt(t1, pf), Field.platformPosAt(t0, pf)))
            |> Option.getWithDefault(Vec2.zero());
        let posCarried = Vec2.add(player0#pos, carryDelta);

        // ── 物理: 積分 → 検出（separate はフィルタの後）──
        let (integrated, contactsRaw) = integrateAndDetect(dt, platformsNow, posCarried, vel);

        // ── 一方通行フィルタ: 上向きに押される接触で、かつ前フレーム（carry 後）の足元が床上面より上のときだけ残す ──
        let prevBottom = posCarried#y + Field.playerRadius();
        let kept = oneWayFilter(prevBottom, dropLeft1, platformsNow, contactsRaw);

        // ── 分離と速度解決（残した接触だけを見る）──
        // 着地は vy が消えて vx が残り（慣性）、頭ぶつけは上昇が消え、壁は vx が消える。
        let velocities = Map.singleton(Field.playerId(), vel);
        let separated = Physics2D.separate(kept, velocities, integrated);
        let posResolved = Map.get(Field.playerId(), separated) |> Option.getWithDefault(posCarried);
        let velResolved = Physics2D.slide(Field.playerId(), kept, vel);

        // ── 接地の再計算（分離後の接触が正）──
        let grounded1 = List.exists(contact -> playerNormal(contact)#y < Field.groundedNormalY(), kept);

        // ── 下り坂の吸着: 直前まで接地していて、ジャンプせず、上昇もしていないのに接触を失ったら、
        //    足元を少し下へ探る（snapProbe px）。坂を降りる 1 フレームの段差はこの範囲に収まる。──
        let wantsSnap = player0#grounded and not jumps and velResolved#y >= 0.0 and not grounded1;
        let snapped = if (wantsSnap) trySnap(prevBottom, dropLeft1, platformsNow, posResolved, velResolved)
                      else None;
        let (posMoved, velMoved, groundedFinal, supports) = match snapped {
            case Some((posSnap, velSnap, snapContacts)) => (posSnap, velSnap, true, snapContacts)
            case None                                   => (posResolved, velResolved, grounded1, kept)
        };

        // ── 坂の静止摩擦: 坂に乗っていて入力が無ければ、その場に停める。従来は重力と分離の
        //    押し出しが斜面向きの速度を毎フレーム少し残し、静止したいのにゆっくり滑り落ちた。
        //    x をフレーム開始位置へ戻し（y は分離済みの値のまま = 斜面の上で安定）、速度も止める。
        //    P スピード帯の勢いの滑走（|vx| > maxRunSpeed）と上昇中は従来の物理に譲る。──
        let onSlopeNow = ridingPf
            |> Option.map(pf -> not Option.isEmpty(pf#slope))
            |> Option.getWithDefault(false);
        let parked = onSlopeNow and dir == 0.0 and not jumps and groundedFinal
            and velMoved#y >= 0.0 and Float64.abs(velMoved#x) <= p#maxRunSpeed;
        let posFinal = if (parked) { x = posCarried#x | posMoved } else posMoved;
        let velFinal = if (parked) Vec2.zero() else velMoved;

        // ── 敵との接触（物理には干渉しない: 解決済みの位置で円同士の重なりだけを見る）──
        // 踏み = 踏める種 ∧ 前フレーム（carry 後）の足元が敵の頭より上 ∧ 下向きに落ちている。
        // 同フレームで踏みと致命の接触が同時なら死亡が勝つ（安全側）: 致命の重なりが
        // 1 つでもあれば、そのフレームの踏みは成立させない（敵も倒れない）。
        let overlaps = world#enemies
            |> List.filter(enemy -> enemy#alive and overlapsPlayer(t1, posFinal, enemy));
        let diedByEnemy = overlaps |> List.exists(enemy -> not isStomp(t1, prevBottom, velFinal#y, enemy));
        let stompedIds = if (diedByEnemy) Nil
            else overlaps
                |> List.filter(enemy -> isStomp(t1, prevBottom, velFinal#y, enemy))
                |> List.map(enemy -> enemy#id);
        let stomping = not List.isEmpty(stompedIds);
        let enemies1 = if (stomping)
                world#enemies |> List.map(enemy ->
                    if (List.memberOf(enemy#id, stompedIds)) { alive = false | enemy } else enemy)
            else world#enemies;
        // 踏んだ瞬間は半ジャンプのバウンド。jumpHeld は立てない（離しても上昇カットさせない）。
        let velStomped = if (stomping) { y = Field.stompBounceVy() | velFinal } else velFinal;
        let heldFinal = if (stomping) false else held2;

        // ── 出来事 ──
        let bumped = List.exists(contact -> playerNormal(contact)#y > 0.7, kept);
        let landed = not player0#grounded and grounded1 and vy >= Field.landEventSpeed();
        let diedPit = posFinal#y > Field.deathLineOf(world);
        let died = diedPit or diedByEnemy;
        // 中間地点: 発動線（checkpointPos の x）を初めて越えた 1 回だけ。以後の死亡はそこへ戻る。
        let checkpointing = world#respawnPos#x < world#checkpointPos#x
            and posFinal#x >= world#checkpointPos#x;
        let respawnPos1 = if (checkpointing) world#checkpointPos else world#respawnPos;
        // クリア: ゴール線を初めて越えた 1 回だけ。時刻を覚える（花火の発射台本の基点）。
        let clearing = Option.isEmpty(world#clearedAt) and posFinal#x >= world#goalX;
        let clearedAt1 = if (clearing) Some(t1) else world#clearedAt;
        // 花火: クリアの 0.6 秒後から 0.2 秒おきに 10 発。発射時刻をこのフレームが跨いだ発だけ
        // 撃つ（土埃の cadence と同じ「時刻の线を越えたら 1 回」方式・決定的）。
        let fireworkBursts = match clearedAt1 {
            case None     => Nil
            case Some(tc) => List.range(0, 10) |> List.filterMap(i -> {
                let launchAt = tc + 0.6 + Int32.toFloat64(i) * 0.2;
                if (t0 < launchAt and launchAt <= t1) Some(fireworkBurst(world#goalX, i)) else None
            })
        };
        let fireworking = not List.isEmpty(fireworkBursts);
        let events = List.filterMap(identity,
            (if (jumps) Some(Field.Event.JumpEvent) else None) ::
            (if (landed) Some(Field.Event.LandEvent) else None) ::
            (if (bumped) Some(Field.Event.BumpEvent) else None) ::
            (if (stomping) Some(Field.Event.StompEvent) else None) ::
            (if (died) Some(Field.Event.DeathEvent) else None) ::
            (if (checkpointing) Some(Field.Event.CheckpointEvent) else None) ::
            (if (clearing) Some(Field.Event.ClearEvent) else None) ::
            (if (fireworking) Some(Field.Event.FireworkEvent) else None) :: Nil);

        // ── 乗っている床の再導出: 支持接触（最も上向きに押すもの・同点は小さい id）──
        let ridingId1 = if (groundedFinal) supportingId(supports) else None;

        // ── 演出の粒: スポーン。ジャンプの瞬間はジェット、接地ダッシュ中は cadence で土埃。
        //    posFinal/velFinal/groundedFinal が揃うここで組む（jumps は上で確定済み）。──
        let seed = seedAt(t1, dt);
        let jetBurst: Field.Burst =
            { kind = Field.FxKind.JetKind, seed = seed,
              pos = { x = posFinal#x, y = posFinal#y + Field.playerRadius() },
              dir = { x = 0.0, y = 1.0 }, power = 1.0, elapsed = 0.0 };
        let bursts2 = if (jumps) jetBurst :: bursts1 else bursts1;
        // 土埃は速いほど頻繁に・強く（cadence と power を同じ dashBand で段階づける）。
        let dashing = groundedFinal and Float64.abs(velFinal#x) > Jump.maxRunSpeed();
        let dustPower = dashBand(velFinal#x);
        let cadenceTicked = Float64.floor(t1 * dustRate(velFinal#x)) != Float64.floor(t0 * dustRate(velFinal#x));
        let dustBurst: Field.Burst =
            { kind = Field.FxKind.DustKind, seed = seed,
              pos = { x = posFinal#x - sign(velFinal#x) * Field.playerRadius(),
                      y = posFinal#y + Field.playerRadius() - 2.0 },
              dir = { x = -sign(velFinal#x), y = -0.2 }, power = dustPower, elapsed = 0.0 };
        let bursts3 = if (dashing and cadenceTicked) dustBurst :: bursts2 else bursts2;
        // 着地の瞬間は足元から左右へ土煙（power は落下の速さから: 高い落下ほど大きく舞う）。
        let puffPower = Float64.max(0.0, Float64.min(1.0,
            (vy - Field.landEventSpeed()) / 400.0));
        let puffAt = (dirX: Float64) -> {
            { kind = Field.FxKind.DustKind, seed = seed,
              pos = { x = posFinal#x, y = posFinal#y + Field.playerRadius() - 2.0 },
              dir = { x = dirX, y = -0.3 }, power = puffPower, elapsed = 0.0 }
        };
        let bursts4 = if (landed) puffAt(1.0) :: puffAt(-1.0) :: bursts3 else bursts3;
        // 踏んだ敵の位置にもジェットを 1 発ずつ（倒した手応え）。
        let stompBursts = overlaps
            |> List.filter(enemy -> List.memberOf(enemy#id, stompedIds))
            |> List.map(enemy -> {
                { kind = Field.FxKind.JetKind, seed = seed,
                  pos = Field.enemyPosAt(t1, enemy), dir = { x = 0.0, y = 1.0 },
                  power = 1.0, elapsed = 0.0 }
            });
        let burstsFinal = List.append(fireworkBursts, List.append(stompBursts, bursts4));

        let time = t1;
        let player1 = {
            pos = posFinal, vel = velStomped, grounded = groundedFinal,
            coyoteLeft = coyote1, bufferLeft = buffer1, jumpHeld = heldFinal,
            squashLeft = if (landed) Field.squashTime() else Jump.tickTimer(dt, player0#squashLeft),
            ridingId = ridingId1, dropLeft = dropLeft1 };

        // ── カメラ: 不感帯つき追従（横・縦）。死亡時はリスポーン地点（出発点か中間地点）へ
        //    スナップ（レベル横断のパンをしない）──
        let camX1 =
            if (died) FollowCam.snapCam(world#levelW, respawnPos1#x)
            else FollowCam.stepCam(dt, world#levelW, posFinal#x, world#camX);
        let camY1 =
            if (died) FollowCam.snapCamY(world#levelH, respawnPos1#y)
            else FollowCam.stepCamY(dt, world#levelH, posFinal#y, world#camY);

        // 死亡（崖・敵とも同じ扱い）: リスポーン地点へ（タイマー・速度も初期化）。死んだ回数を数える。
        { player = if (died) Field.freshPlayerAt(respawnPos1) else player1,
          enemies = enemies1,
          events = events,
          eventLog = appendLog(time, events, world#eventLog),
          bursts = burstsFinal,
          deaths = world#deaths + (if (died) 1 else 0),
          camX = camX1,
          camY = camY1,
          respawnPos = respawnPos1,
          clearedAt = clearedAt1,
          time = time | world }

    /// 花火 1 発の種。ゴール上空の空（画面に入る帯 y 250..350）へ、i から決めた散らばりで置く。
    /// x/y とも i の剰余で決める（決定的・保存しない）。seed = i なので粒の散り方も発ごとに違う。
    def fireworkBurst(goalX: Float64, i: Int32): Field.Burst =
        { kind = Field.FxKind.FireworkKind, seed = i,
          pos = { x = goalX - 200.0 + Int32.toFloat64(Int32.modulo(i * 53, 240)),
                  y = 250.0 + Int32.toFloat64(Int32.modulo(i * 37, 100)) },
          dir = { x = 0.0, y = -1.0 }, power = 1.0, elapsed = 0.0 }

    // ── 敵との接触判定 ──
    // 敵は Physics2D の positions/shapes に載せない（床の物理へ一切干渉しない）。
    // 解決済みのプレイヤー位置と、時刻 t1 の敵の実位置で円同士の重なりだけを見る。

    /// 踏める種か（トゲだけは踏めない）。
    def stompable(enemy: Field.Enemy): Bool =
        enemy#kind != Field.EnemyKind.SpikyKind

    /// この重なりが「踏み」か: 踏める種で、前フレーム（carry 後）の足元が敵の頭
    /// （上端 + 2px の猶予）より上に居て、いま下向きに落ちている。
    def isStomp(t1: Float64, prevBottom: Float64, vyFinal: Float64, enemy: Field.Enemy): Bool =
        stompable(enemy)
        and prevBottom <= Field.enemyPosAt(t1, enemy)#y - Field.enemyRadius() + 2.0
        and vyFinal > 0.0

    /// プレイヤーと敵（時刻 t1 の実位置）が重なっているか（円同士・半径の和より近い）。
    def overlapsPlayer(t1: Float64, playerPos: Vec2.Vec2, enemy: Field.Enemy): Bool =
        let d = Vec2.sub(Field.enemyPosAt(t1, enemy), playerPos);
        let reach = Field.playerRadius() + Field.enemyRadius();
        Vec2.dot(d, d) < reach * reach

    // ── 物理の 1 ステップ ──

    /// プレイヤーと地形を positions / shapes に組み、積分と検出まで通して
    /// (積分後の位置, プレイヤーの接触) を返す（separate は一方通行フィルタの後で呼ぶ）。
    /// 地形は velocities に居ないので動かない壁として振る舞う — 動く床は呼び手が
    /// 時刻から導いた実位置のリストを渡すので、このフレームの居場所で当たる。
    def integrateAndDetect(dt: Float64, platforms: List[Field.Platform],
                           playerPos: Vec2.Vec2, playerVel: Vec2.Vec2):
                           (Map[EntityId, Vec2.Vec2], List[Physics2D.Contact]) =
        let velocities = Map.singleton(Field.playerId(), playerVel);
        let integrated = Physics2D.integrate(dt, velocities, positionsOf(platforms, playerPos));
        let contacts = Physics2D.detect(integrated, shapesOf(platforms))
            |> Physics2D.contactsOf(Field.playerId());
        (integrated, contacts)

    /// 全物体の中心座標の Map（プレイヤーは指定位置で差し込む）。
    def positionsOf(platforms: List[Field.Platform], playerPos: Vec2.Vec2): Map[EntityId, Vec2.Vec2] =
        platforms
            |> List.map(platform -> (platform#id, platform#pos))
            |> List.toMap
            |> Map.insert(Field.playerId(), playerPos)

    /// 全物体の当たり判定の形の Map。
    def shapesOf(platforms: List[Field.Platform]): Map[EntityId, CollisionShape2D] =
        platforms
            |> List.map(platform -> (platform#id, Field.platformShape(platform)))
            |> List.toMap
            |> Map.insert(Field.playerId(), Field.playerShape())

    /// 指定位置にプレイヤーを置いたときの接触（検出だけ・積分しない）。下り坂の吸着が使う。
    def detectAt(platforms: List[Field.Platform], playerPos: Vec2.Vec2): List[Physics2D.Contact] =
        Physics2D.detect(positionsOf(platforms, playerPos), shapesOf(platforms))
            |> Physics2D.contactsOf(Field.playerId())

    // ── 下り坂の吸着 ──

    /// 吸着で足元を探る深さ px。坂を降りる 1 フレームの段差はこの範囲に収まる。
    def snapProbe(): Float64 = 6.0

    /// 足元 snapProbe px 下にプレイヤーを置いて接触を探り、支えになる接触
    /// （一方通行フィルタを通り、法線が接地しきい値を満たし、支えの形をしているもの）が
    /// あれば、その位置から分離し直した (位置, 面成分を消した速度, 支持接触) を返す。無ければ None。
    def trySnap(prevBottom: Float64, dropLeft: Float64, platforms: List[Field.Platform],
                pos: Vec2.Vec2, vel: Vec2.Vec2):
                Option[(Vec2.Vec2, Vec2.Vec2, List[Physics2D.Contact])] =
        let probePos = { y = pos#y + snapProbe() | pos };
        let contacts = detectAt(platforms, probePos)
            |> oneWayFilter(prevBottom, dropLeft, platforms)
            |> List.filter(contact -> playerNormal(contact)#y < Field.groundedNormalY()
                                      and supportsSnap(platforms, contact));
        if (List.isEmpty(contacts)) None
        else {
            let velocities = Map.singleton(Field.playerId(), vel);
            let separated = Physics2D.separate(contacts, velocities, positionsOf(platforms, probePos));
            let posSnapped = Map.get(Field.playerId(), separated) |> Option.getWithDefault(probePos);
            let velSnapped = Physics2D.slide(Field.playerId(), contacts, vel);
            Some((posSnapped, velSnapped, contacts))
        }

    /// 探りの接触が「支え」か: 坂は素通し（斜辺の面接触が本命）、矩形は真上向きの
    /// 面接触（|normal.x| がほぼ 0）だけを認める。崖から歩き出た直後の探りは矩形の角を
    /// かすめて斜めの法線（例 (0.2, -0.97)）を返すが、これを拾うと角に貼り付いて
    /// 崖離れが数フレーム遅れるので、角は支えに数えない。
    def supportsSnap(platforms: List[Field.Platform], contact: Physics2D.Contact): Bool =
        let other = if (contact#a == Field.playerId()) contact#b else contact#a;
        let onSlope = List.findLeft(pf -> pf#id == other, platforms)
            |> Option.map(pf -> not Option.isEmpty(pf#slope))
            |> Option.getWithDefault(false);
        onSlope or Float64.abs(playerNormal(contact)#x) < 0.001

    // ── 坂の登り ──
    // 登り（坂に乗っていて入力が高い側）は速度を斜面の接線に沿わせる。目標速度・加速・
    // ダッシュの帯は平地の走りの式（Jump.horizontalStep）をそのまま使うので、45° では
    // 水平換算が 1/2（接線の x 成分の 2 乗）に落ちる = 急坂ほど登りが遅い、が自然に出る。

    /// 登り中に面へ吸い付ける速さ px/s。integrate で 1 フレームあたり 0.125px 面へ沈み、
    /// separate が同じ量を法線方向へ押し戻す（位置への正味は 0）。接触が毎フレーム残るので
    /// 接地と ridingId が途切れない — 登りで重力を掛けない代わりに接触を保つ仕掛け。
    def climbStick(): Float64 = 8.0

    /// 登りの速度（斜面の接線に沿う・重力は掛けない）。登りが成立しない状況は None = 従来の物理:
    /// 坂に乗っていない・空中・このフレームにジャンプ・入力が坂の低い側・
    /// P スピード帯の勢い（平地換算 maxRunSpeed 超）で下へ滑走中。
    /// dash/dir/jumps は同型が並ぶのでレコードで名前渡し。
    def climbVelocity(p: GameParameters.Params, dt: Float64,
                      climb: { dash = Bool, dir = Float64, jumps = Bool },
                      player0: Field.Player,
                      ridingPf: Option[Field.Platform]): Option[Vec2.Vec2] =
        if (climb#dir == 0.0 or climb#jumps or not player0#grounded) None
        else ridingPf |> Option.flatMap(pf -> pf#slope |> Option.flatMap(riseRight -> {
            let uphill = if (riseRight) 1.0 else -1.0;
            if (climb#dir * uphill < 0.0) None
            else {
                // 入力向き（= 登り向き）の単位接線。riseRight は {+w,-h}、riseLeft は {-w,-h}。
                let tDir = Vec2.normalized({ x = uphill * pf#size#x, y = -(pf#size#y) });
                let c = Float64.abs(tDir#x);
                // 斜面に沿った現在の速さを平地換算へ直して走りの式に渡す（負 = ずり下がり中。
                // 入力が登り向きなら減速 → 停止 → 登り返しへ自然に繋がる）。
                let vxEquiv = Vec2.dot(player0#vel, tDir) / c;
                if (vxEquiv < -(p#maxRunSpeed)) None
                else {
                    let vxNext = Jump.horizontalStep(p, dt,
                        { grounded = true, dash = climb#dash, dir = 1.0, vx = vxEquiv });
                    let inward = Vec2.normalized({ x = uphill * pf#size#y, y = pf#size#x });
                    Some(Vec2.add(Vec2.mul(tDir, vxNext * c), Vec2.mul(inward, climbStick())))
                }
            }
        }))

    /// 床の水平速度（このフレームの移動量 / dt）。動かない床・乗っていないときは 0。
    def platformVx(dt: Float64, t0: Float64, t1: Float64, ridingPf: Option[Field.Platform]): Float64 =
        ridingPf
            |> Option.map(pf -> (Field.platformPosAt(t1, pf)#x - Field.platformPosAt(t0, pf)#x) / dt)
            |> Option.getWithDefault(0.0)

    /// 一方通行の接触を選別する。普通の床の接触は素通し。一方通行は
    /// 「降下中でない ∧ 上向きに押される ∧ 前フレームの足元が床上面より上（すれすれ含む）」のときだけ残す。
    /// prevBottom は carry 適用後の値: 下降する一方通行リフトでも足元と上面が同期して下がるので式が成立し続ける。
    /// List.filter なので接触の順序は変えない（Physics2D.slide は検出順に畳む）。
    def oneWayFilter(prevBottom: Float64, dropLeft: Float64,
                     platforms: List[Field.Platform],
                     contacts: List[Physics2D.Contact]): List[Physics2D.Contact] =
        contacts |> List.filter(contact -> {
            let other = if (contact#a == Field.playerId()) contact#b else contact#a;
            match List.findLeft(pf -> pf#id == other, platforms) {
                case None     => true
                case Some(pf) =>
                    if (not pf#oneWay) true
                    else
                        dropLeft <= 0.0
                        and playerNormal(contact)#y < Field.groundedNormalY()
                        and prevBottom <= (pf#pos#y - pf#size#y / 2.0) + 0.01
            }
        })

    /// 支持接触の相手 id: 最も強く上へ押す接触（-normal.y 最大）。同点は小さい id。
    def supportingId(contacts: List[Physics2D.Contact]): Option[EntityId] =
        contacts
            |> List.filter(contact -> playerNormal(contact)#y < Field.groundedNormalY())
            |> List.foldLeft((best, contact) -> {
                let up = -(playerNormal(contact)#y);
                let id = if (contact#a == Field.playerId()) contact#b else contact#a;
                match best {
                    case None => Some((up, id))
                    case Some((bestUp, bestId)) =>
                        if (up > bestUp or (up == bestUp and id < bestId)) Some((up, id)) else Some((bestUp, bestId))
                }
            }, None)
            |> Option.map(pair -> { let (_up, id) = pair; id })

    /// 接触の法線を「プレイヤーを押し出す向き」に揃える（本体は Physics2D.normalToward）。
    def playerNormal(contact: Physics2D.Contact): Vec2.Vec2 =
        Physics2D.normalToward(Field.playerId(), contact)

    // ── 出来事 ──

    def appendLog(time: Float64, events: List[Field.Event],
                  log: List[(Float64, String)]): List[(Float64, String)] =
        let entries = List.map(event -> (time, Field.eventName(event)), events);
        List.append(entries, log) |> List.take(Field.maxEventLog())
}
