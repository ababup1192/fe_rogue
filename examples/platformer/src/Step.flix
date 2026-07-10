// Step — 1 フレームのルール（純粋）。入力とタイマー → ジャンプの成立 → 走りと重力 →
// 物理（積分・検出・分離）→ 速度の解決 → 接地の再計算 → 出来事の記録、の順で進む。
//
// 順序が手触りを決める:
//   ジャンプ判定は「前フレームの接地」を見る（1 フレームの遅れはコヨーテタイムが吸収する）。
//   接地の再計算は separate の後 — 押し出し済みの位置での接触が本当の接地で、
//   崖から歩き出た瞬間はここで grounded が消え、次フレームからコヨーテが減り始める。
//   重力は接地中も掛け続ける — separate が毎フレーム打ち消すので接触が切れず、接地が安定する。

mod Step {

    /// 1 フレーム進める。入力 → タイマー → ジャンプ → 走り → 重力 → 物理 → 接地 → 出来事。
    pub def update(input: Field.Input, dt: Float64, world: Field.World): Field.World =
        let p = world#params;
        let player0 = world#player;

        // ── タイマー（バッファは押下で充填、コヨーテは接地中ずっと満タン）──
        let buffer0 = if (input#jumpPressed) p#bufferTime else Jump.tickTimer(dt, player0#bufferLeft);
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

        // ── 走り（慣性・空中制御・B ダッシュ）と重力 ──
        let dir = (if (input#left) -1.0 else 0.0) + (if (input#right) 1.0 else 0.0);
        let vx = Jump.horizontalStep(p, dt,
            { grounded = player0#grounded, dash = input#dash, dir = dir, vx = player0#vel#x });
        let vy = Jump.applyGravity(p, dt, vyCut);
        let vel = { x = vx, y = vy };

        // ── 物理: プレイヤーを一瞬だけ Store に合流させ、積分 → 検出 → 分離を通して読み戻す ──
        let (posResolved, contacts) = stepPhysics(dt, world#platforms, player0#pos, vel);

        // ── 速度の解決: 面に食い込む向きの速度成分をゼロ化（跳ねない）──
        // 着地は vy が消えて vx が残り（慣性）、頭ぶつけは上昇が消え、壁は vx が消える。
        let velResolved = List.foldLeft(resolveVelocity, vel, contacts);

        // ── 接地の再計算（分離後の接触が正）と出来事 ──
        let grounded1 = List.exists(contact -> playerNormal(contact)#y < -0.7, contacts);
        let bumped = List.exists(contact -> playerNormal(contact)#y > 0.7, contacts);
        let landed = not player0#grounded and grounded1 and vy >= Field.landEventSpeed();
        let died = posResolved#y > Field.deathY();
        let events = List.filterMap(identity,
            (if (jumps) Some(Field.Event.JumpEvent) else None) ::
            (if (landed) Some(Field.Event.LandEvent) else None) ::
            (if (bumped) Some(Field.Event.BumpEvent) else None) ::
            (if (died) Some(Field.Event.DeathEvent) else None) :: Nil);

        let time = world#time + dt;
        let player1 = {
            pos = posResolved, vel = velResolved, grounded = grounded1,
            coyoteLeft = coyote1, bufferLeft = buffer1, jumpHeld = held2,
            squashLeft = if (landed) Field.squashTime() else Jump.tickTimer(dt, player0#squashLeft) };

        // 崖死亡: deathY を割ったら出発点へ（タイマー・速度も初期化）。死んだ回数を数える。
        { player = if (died) Field.freshPlayer() else player1,
          events = events,
          eventLog = appendLog(time, events, world#eventLog),
          deaths = world#deaths + (if (died) 1 else 0),
          time = time | world }

    // ── 物理の 1 ステップ ──

    /// プレイヤーと地形を positions / shapes に組み、Physics2D の純関数列
    /// （積分 → 検出 → 分離）を通してプレイヤーの位置と接触を読み戻す。
    /// 地形は velocities に居ないので動かない壁として振る舞い、分離はプレイヤーだけを押し出す。
    def stepPhysics(dt: Float64, platforms: List[Field.Platform],
                    playerPos: Vec2.Vec2, playerVel: Vec2.Vec2): (Vec2.Vec2, List[Physics2D.Contact]) =
        let positions = platforms
            |> List.map(platform -> (platform#id, platform#pos))
            |> List.toMap
            |> Map.insert(Field.playerId(), playerPos);
        let shapes = platforms
            |> List.map(platform -> (platform#id, Field.platformShape(platform)))
            |> List.toMap
            |> Map.insert(Field.playerId(), Field.playerShape());
        let velocities = Map.singleton(Field.playerId(), playerVel);
        let integrated = Physics2D.integrate(dt, velocities, positions);
        let contacts = Physics2D.detect(integrated, shapes)
            |> Physics2D.contactsOf(Field.playerId());
        let separated = Physics2D.separate(contacts, velocities, integrated);
        let newPos = Map.get(Field.playerId(), separated) |> Option.getWithDefault(playerPos);
        (newPos, contacts)

    /// 接触の法線を「プレイヤーを押し出す向き」に揃える（Contact の normal は a を押す向き）。
    def playerNormal(contact: Physics2D.Contact): Vec2.Vec2 =
        if (contact#a == Field.playerId()) contact#normal else Vec2.neg(contact#normal)

    /// 面に近づく速度成分だけを消す。離れる向きの接触（かすめた直後など）は触らない。
    def resolveVelocity(vel: Vec2.Vec2, contact: Physics2D.Contact): Vec2.Vec2 =
        let normal = playerNormal(contact);
        let approach = Vec2.dot(vel, normal);
        if (approach < 0.0) Vec2.sub(vel, Vec2.mul(normal, approach)) else vel

    // ── 出来事 ──

    def appendLog(time: Float64, events: List[Field.Event],
                  log: List[(Float64, String)]): List[(Float64, String)] =
        let entries = List.map(event -> (time, Field.eventName(event)), events);
        List.append(entries, log) |> List.take(Field.maxEventLog())
}
