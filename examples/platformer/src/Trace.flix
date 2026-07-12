// Trace — ギャラリーとテストが共有する、この検証台固有のシナリオ。
//
// プラットフォーマーの物理は update が駆動するので、シナリオは「初期 World」と「入力の列」の
// 組で表す: プレイヤーをどこに置き、どのキーを何フレーム押すか。あとは Replay.play /
// Replay.timeline に流せば、純粋な update が結末を言い当てる —— ジャンプ高さの pin にも、
// GIF の駒にも、同じ 1 つのシナリオが使える。時計は 1/64 秒（2進小数）なので固定した結末は
// 誤差なく正確。パラメータは常に既定値（GameParameters.defaults()）を使う。

mod Trace {

    // ── 時計と入力 ──

    pub def dt(): Float64 = 1.0 / 64.0
    pub def idle(): Field.Input = Field.noInput()

    pub def hold(input: Field.Input, frames: Int32): Replay.Cue[Field.Input] =
        { input = input, frames = frames }

    /// idle のまま n フレーム流す（物理だけを走らせる）。
    pub def flight(frames: Int32): List[Replay.Cue[Field.Input]] = hold(idle(), frames) :: Nil

    /// ジャンプボタンを n フレーム押しっぱなしにする（押した瞬間のエッジは 1 フレーム目だけ）。
    pub def holdJump(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ jumpDown = true, jumpPressed = true | idle() }, 1) ::
        hold({ jumpDown = true | idle() }, frames - 1) :: Nil

    /// 右キーを n フレーム押しっぱなしにする。
    pub def holdRight(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ right = true | idle() }, frames) :: Nil

    /// 左キーを n フレーム押しっぱなしにする。
    pub def holdLeft(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ left = true | idle() }, frames) :: Nil

    /// 右へ走りながらジャンプを n フレーム押す（1 フレーム目だけ押下エッジ）。
    pub def rightJump(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ right = true, jumpDown = true, jumpPressed = true | idle() }, 1) ::
        hold({ right = true, jumpDown = true | idle() }, frames - 1) :: Nil

    /// B ダッシュで右へ n フレーム走る。
    pub def holdRightDash(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ right = true, dash = true | idle() }, frames) :: Nil

    /// B ダッシュで右へ走りながらジャンプを n フレーム押す。
    pub def rightDashJump(frames: Int32): List[Replay.Cue[Field.Input]] =
        hold({ right = true, dash = true, jumpDown = true, jumpPressed = true | idle() }, 1) ::
        hold({ right = true, dash = true, jumpDown = true | idle() }, frames - 1) :: Nil

    // ── シナリオの World ──

    /// 地面の上に接地静止しているプレイヤー（x は指定・接地フラグとコヨーテは充填済み）。
    /// 「立っている状態から」のテストはここから始めると、落下・着地の助走が要らない。
    pub def restingPlayer(x: Float64): Field.Player =
        { pos = { x = x, y = Field.groundTop() - Field.playerRadius() },
          vel = Vec2.zero(), grounded = true,
          coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
          facing = 1.0, ridingId = None, dropLeft = 0.0,
          viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 }

    /// シナリオ World の共通枠（プレイヤーと地形だけ違う・敵は要る場面で足す）。
    /// classic の寸法は 320×240（Field.classicW/H・design 480×360 より小さい）なので
    /// カメラ 2 軸ともクランプで 0 に張り付き、goal はレベル外（届かない）でクリアは
    /// 起きない。spawn は旧レベルの 'P' と同じ (56,104) に固定する — 死亡リスポーンを
    /// 含む classic シナリオ（GIF・pin）のバイト一致を守るための実測値。
    def worldOf(player: Field.Player, platforms: List[Field.Platform]): Field.World =
        { player = player, platforms = platforms, enemies = Nil,
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, bursts = Nil,
          deaths = 0, camX = 0.0, camY = 0.0,
          levelW = Field.classicW(), levelH = Field.classicH(),
          spawnPos = { x = 56.0, y = 104.0 }, respawnPos = { x = 56.0, y = 104.0 },
          checkpointPos = { x = Field.classicW() + 1000.0, y = 104.0 },
          goalX = Field.classicW() + 1000.0,
          clearedAt = None, freezeLeft = 0.0, charIndex = 1, time = 0.0 }

    /// 地面だけの世界（浮き床・壁なし）。ジャンプ曲線と走りを邪魔なしで測る。
    pub def flatWorld(): Field.World =
        worldOf(restingPlayer(160.0), Field.fullGround() :: Nil)

    /// 長い平地の世界（幅 1280 の地面・levelW は classic の 320 のままなのでカメラは動かない）。
    /// P スピードは 160→280 に約 330px の助走が要る — 1 画面の地面では足りない計測に使う。
    pub def longFlatWorld(): Field.World =
        let ground = Field.rigid(100, { x = 640.0, y = Field.groundTop() + 20.0 }, { x = 1280.0, y = 40.0 });
        worldOf(restingPlayer(100.0), ground :: Nil)

    /// classic 地形（1 画面・地面 3 分割 + 浮き床 3 枚 + 左右の壁）の世界。
    /// プレイヤーは左寄りの空中（x=60, y=100）から落ちて始まる。既存のシナリオと pin の舞台。
    pub def classicWorld(): Field.World =
        let player = { pos = { x = 60.0, y = 100.0 }, vel = Vec2.zero(), grounded = false,
                       coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = None, dropLeft = 0.0,
          viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        worldOf(player, Field.classicPlatforms())

    /// 浮き床走破の出発点: classic 地形で、左端（x=20）に接地静止。
    pub def runAcrossWorld(): Field.World =
        { player = restingPlayer(20.0) | classicWorld() }

    /// 広い穴の手前（地面 B の左寄り x=155）に、P スピード済み（vx=280 preset）で接地。
    /// ダッシュ崖越えの出発点。P スピードは 160→280 に約 330px の助走が要るが、classic の
    /// 助走路（54px）では足りないので、シナリオは到達済みの速度を前提に置く
    /// （本番レベルの長い助走路が提供する状態の再現）。崖越えゲートの検証はここから。
    pub def dashGapWorld(): Field.World =
        { player = { vel = { x = 280.0, y = 0.0 } | restingPlayer(155.0) } | classicWorld() }

    /// 崖死亡の出発点: 地面 B の右端ぎりぎり（x=190）に接地静止。1 歩で広い穴に落ちる。
    pub def gapDeathWorld(): Field.World =
        { player = restingPlayer(190.0) | classicWorld() }

    /// ダッシュ崖越えの台本（dashGapWorld = vx 280 preset から）: 縁まで 10f 走り →
    /// 低ホップ 6f → 浮き床 B の下をくぐって広い穴を渡り、浮き床 C に着地して壁で止まる。
    pub def dashGapCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRightDash(10) :: rightDashJump(6) :: holdRightDash(40) :: Nil)

    /// 崖死亡の台本: gapDeathWorld（x=190）から広い穴へ歩き出て落ち、
    /// 死亡 → 出発点へ戻って着地するまで。
    pub def gapDeathCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRight(10) :: flight(45) :: Nil)

    /// レベル走破（スタート → ゴール・1143 フレーム・probe で振り付けた実測値）。
    /// 疾走感の台本: 出発から B ダッシュを離さず、止まらずにゴールまで走り切る。
    /// 速度依存ジャンプ（280 で跳ぶと初速 +12%）で弧が上がったぶん、走りながらの
    /// ホップは旧台本より短い押し（10f→6f・24f→20f）で同じ高さの弧を描く。
    /// 踏みのヒットストップ（3 コマ × 3 回）は入力を黙って食うので、踏みを含む
    /// holdRightDash の区間に同じ数だけ延ばしぶんを織り込んで以降の振り付けを合わせてある
    /// （凍結明けの世界は凍結が無かったときと同一 = 位置は変わらない）。
    ///   f0    落下しながらダッシュ開始 → 助走路で P スピード 280 を作る
    ///   f130  低い段差を 6f ホップで越え、下り際に歩く敵（x648）を踏む（f159 stomp）—
    ///         バウンドがそのまま穴 1（688-720）を丸ごと越える（踏み連鎖 A）
    ///   f197  着地と同時に 4f ホップで 2 体目の歩く敵（x840）を飛び越え、緩い坂に着地
    ///   f274  坂の途中から 5f ホップで 45° 坂と高台をまとめて越える（上空のパタパタは位相調整で高い）
    ///   f320  高台の縁から下りの坂へ — 下りの滑りで 331px/s まで伸びる（P スピード帯の overspeed）
    ///   f407  トゲ（x1608）を 6f ホップで越え、着地の直後に中間地点の旗（x1688・f449）が発動
    ///   f584  P スピードゲートの大穴（128px）を 20f ジャンプで渡り（速度ボーナスつきなので
    ///         旧満タン相当の弧）、下り際に歩く敵（x2488・f628 stomp）→ バウンド →
    ///         歩く敵（x2616・f660 stomp）→ バウンド、と 2 連鎖で敵地帯を頭伝いに通過
    ///         （踏み連鎖 C・パタパタ 2 体は位相調整で上空へ退く）
    ///   f695  着地してそのままフェリー（phase 調整済み・穴の左端で待ち受ける）に走り込み、
    ///         デッキを駆けて f720 に跳ぶ（デッキの水平速度 +45px/s を継承）→ 階段 2 段目へ
    ///   f752  階段を 5f ホップ × 2 で 3 段目・4 段目へ（壁に当てて刻む — 壁で vx が 0 に
    ///         なるので速度ボーナスは乗らず、旧台本と同じ低いホップになる）
    ///   f814  4 段目から 20f ジャンプで最上段を飛び越し、一方通行の棚（行13・y196）へ
    ///         着地（f845）— カメラが上がり、空の高ルートを走る（f845-863）
    ///   f864  棚の右端から 220px の大落下 → 着地してゴールの旗（x3272）を f896 に通過（クリア）
    ///   以後  右壁（x3316）で止まって花火 10 発（0.6 秒のタメ → 0.2 秒間隔・f935-1050）を見届ける
    pub def levelRunCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRightDash(129) :: rightDashJump(6) :: holdRightDash(61) ::
                     rightDashJump(4) :: holdRightDash(73) :: rightDashJump(5) :: holdRightDash(128) ::
                     rightDashJump(6) :: holdRightDash(171) ::
                     rightDashJump(20) :: holdRightDash(116) ::
                     rightDashJump(8) :: holdRightDash(24) ::
                     rightDashJump(5) :: holdRightDash(26) :: rightDashJump(5) :: holdRightDash(26) ::
                     rightDashJump(20) :: holdRightDash(110) :: flight(200) :: Nil)

    /// 浮き床走破の台本（リモートデバッグの lockstep で振り付けた実測値・143 フレーム）:
    /// 助走 3f → ジャンプ 12f で床 A（y=156）へ → 2f おいて 14f ジャンプで床 B（y=120）へ →
    /// 走り落ちて床 C（y=168）へ（コヨーテの絵）→ 右壁で止まる。
    pub def runAcrossCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(
            holdRight(3) :: rightJump(12) :: holdRight(26) ::
            holdRight(2) :: rightJump(14) :: holdRight(22) ::
            holdRight(32) :: holdRight(20) :: flight(12) :: Nil)

    /// 本番レベル（initialWorld）の地面の上に接地静止しているプレイヤー（上面 416 → 中心 404）。
    /// レベル内の任意の地点から始めるテスト・シナリオ用（restingPlayer の Level 版）。
    pub def levelRestingPlayer(x: Float64): Field.Player =
        { pos = { x = x, y = 404.0 }, vel = Vec2.zero(), grounded = true,
          coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
          facing = 1.0, ridingId = None, dropLeft = 0.0,
          viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 }

    /// 崖のある世界: 幅 80 の床の右端ぎりぎりに接地している。右へ 1 歩で床を離れる。
    pub def ledgeWorld(): Field.World =
        let ledge = Field.rigid(100, { x = 80.0, y = 150.0 }, { x = 80.0, y = 20.0 });
        worldOf(
            { pos = { x = 116.0, y = 140.0 - Field.playerRadius() } | restingPlayer(116.0) },
            ledge :: Nil)

    /// 頭上の低い天井: 接地位置の 60px 上に床がある。ジャンプすると頭をぶつける。
    pub def ceilingWorld(): Field.World =
        let ceiling = Field.rigid(101, { x = 160.0, y = Field.groundTop() - 60.0 }, { x = 80.0, y = 14.0 });
        worldOf(restingPlayer(160.0), Field.fullGround() :: ceiling :: Nil)

    /// 角の救済のシナリオ: ceilingWorld の変形で、天井の「左端」を playerRight − overlap に
    /// 合わせて置く — x=160 で真上にジャンプすると、床の端から overlap px だけ頭がかすめる。
    /// 天井の中心 y=137.5（下面 144.5）は、上昇 5 フレーム目（中心 y=153.0）の角の接触が
    /// 「頭ぶつけ」（normal.y > 0.7）として検出される実測の高さ。
    pub def cornerCeilingWorld(overlap: Float64): Field.World =
        let left = 160.0 + Field.playerRadius() - overlap;
        let ceiling = Field.rigid(101, { x = left + 40.0, y = 137.5 }, { x = 80.0, y = 14.0 });
        worldOf(restingPlayer(160.0), Field.fullGround() :: ceiling :: Nil)

    /// 2 天井の谷間: 左の天井の右端と右の天井の左端が、どちらも 4px のかすり —
    /// 逃げる向きが左右に割れるので角の救済は発動せず、従来どおり bump で止まる。
    pub def ceilingValleyWorld(): Field.World =
        let leftC  = Field.rigid(101, { x = 112.0, y = 137.5 }, { x = 80.0, y = 14.0 });
        let rightC = Field.rigid(102, { x = 208.0, y = 137.5 }, { x = 80.0, y = 14.0 });
        worldOf(restingPlayer(160.0), Field.fullGround() :: leftC :: rightC :: Nil)

    /// コヨーテ猶予が残ったまま空中にいる世界: 崖を離れて数フレーム後の状態を直接組む
    /// （歩き出しのフレーム数に依存せず、猶予内のジャンプ成立だけを見る）。
    pub def coyoteWorld(coyoteLeft: Float64): Field.World =
        let base = fallingWorld(60.0);
        { player = { coyoteLeft = coyoteLeft | base#player } | base }

    /// 空中を横速度つきで飛んでいる世界（空中ベクトル変更 = DI の検証用）: 長い平地の
    /// はるか上空（x=600, y=60）に、横速度 preset・上昇 vy=-200 で置く。
    /// 20 フレーム程度では着地も壁当ても起きない — 空中の加速の帯だけを観測できる。
    pub def airborneWorld(vx: Float64): Field.World =
        let player = { pos = { x = 600.0, y = 60.0 }, vel = { x = vx, y = -200.0 },
                       grounded = false,
                       coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = None, dropLeft = 0.0,
          viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        { player = player | longFlatWorld() }

    /// 空中から落下し始める世界: プレイヤーを地面の上方 height px の空中に置く（速度ゼロ）。
    pub def fallingWorld(height: Float64): Field.World =
        let player = { pos = { x = 160.0, y = Field.groundTop() - Field.playerRadius() - height },
                       vel = Vec2.zero(), grounded = false,
                       coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = None, dropLeft = 0.0,
          viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        worldOf(player, Field.fullGround() :: Nil)

    // ── 読み取り（テストが World から値を取り出す薄いアクセサ）──

    pub def posOf(world: Field.World): Vec2.Vec2 = world#player#pos
    pub def velOf(world: Field.World): Vec2.Vec2 = world#player#vel
    pub def groundedOf(world: Field.World): Bool = world#player#grounded
    pub def coyoteOf(world: Field.World): Float64 = world#player#coyoteLeft
    pub def bufferOf(world: Field.World): Float64 = world#player#bufferLeft
    pub def facingOf(world: Field.World): Float64 = world#player#facing
    pub def eventsOf(world: Field.World): List[String] =
        world#events |> List.map(Field.eventName)
    pub def deathsOf(world: Field.World): Int32 = world#deaths

    /// 一連の World（Replay.timeline の結果）から最高到達点（最小の y）を取り出す。
    pub def apexOf(worlds: List[Field.World]): Float64 =
        worlds |> List.map(world -> world#player#pos#y)
               |> List.minimum
               |> Option.getWithDefault(0.0)

    // ── 動く床・一方通行のシナリオ World ──

    /// 縦リフトの世界: 地面なし・動く床 1 枚だけ。プレイヤーはリフトの上に接地済みで始まる
    /// （ridingId も設定済み — carry が最初のフレームから効く）。
    /// amp 32 / period 4 秒 → 速さ 32px/s = 0.5px/frame ちょうど（pin が厳密）。
    pub def liftWorld(): Field.World =
        let mover = Field.movingAt(400, { x = 160.0, y = 150.0 }, { x = 48.0, y = 14.0 },
            { axis = { x = 0.0, y = -1.0 }, amplitude = 32.0, period = 4.0, phase = 0.0 });
        let player = { pos = { x = 160.0, y = 131.0 }, vel = Vec2.zero(), grounded = true,
                       coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = Some(400), dropLeft = 0.0,
                       viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        worldOf(player, mover :: Nil)

    /// 横フェリーの世界: 下は奈落（地面なし）・横に動く床 1 枚。乗って始まる。
    /// amp 48 / period 4 秒 → 速さ 48px/s = 0.75px/frame ちょうど。
    pub def ferryWorld(): Field.World =
        let mover = Field.movingAt(401, { x = 160.0, y = 150.0 }, { x = 48.0, y = 14.0 },
            { axis = { x = 1.0, y = 0.0 }, amplitude = 48.0, period = 4.0, phase = 0.0 });
        let player = { pos = { x = 160.0, y = 131.0 }, vel = Vec2.zero(), grounded = true,
                       coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = Some(401), dropLeft = 0.0,
                       viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        worldOf(player, mover :: Nil)

    /// 一方通行の床の世界: 地面 + その 60px 上に一方通行の薄板。
    pub def oneWayWorld(): Field.World =
        let plank = Field.oneWayAt(300, { x = 160.0, y = Field.groundTop() - 60.0 }, { x = 100.0, y = 12.0 });
        worldOf(restingPlayer(160.0), Field.fullGround() :: plank :: Nil)

    /// 一方通行の上に立っている世界（下+ジャンプの降下テスト用）。下に地面がある。
    pub def onOneWayWorld(): Field.World =
        let plank = Field.oneWayAt(300, { x = 160.0, y = Field.groundTop() - 60.0 }, { x = 100.0, y = 12.0 });
        let player = { pos = { x = 160.0, y = 122.0 }, vel = Vec2.zero(), grounded = true,
                       coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
                       facing = 1.0, ridingId = Some(300), dropLeft = 0.0,
                       viewMode = CharStage.Mode.IdleMode, viewModeT = 0.0, guardLeft = 0, invulnLeft = 0.0 };
        worldOf(player, Field.fullGround() :: plank :: Nil)

    /// 下+ジャンプを 1 フレーム押す（すり抜け降下の開始）。
    pub def pressDownJump(): List[Replay.Cue[Field.Input]] =
        hold({ down = true, jumpDown = true, jumpPressed = true | idle() }, 1) :: Nil

    /// キャラ切り替え（左 Shift）を 1 フレーム押す。
    pub def switchChar(): List[Replay.Cue[Field.Input]] =
        hold({ switchPressed = true | idle() }, 1) :: Nil

    // ── 敵のシナリオ World ──

    /// 歩く敵の世界: 幅いっぱいの地面 + 歩く敵 1 体（x 190..270 を 40px/s で往復・
    /// y=190 = 地面の上面 − 敵半径）。プレイヤーは左の平地（x=160）に接地静止。
    pub def walkerWorld(): Field.World =
        { enemies = Field.walkerAt(600, { x = 230.0, y = Field.groundTop() - Field.enemyRadius() }, 40.0, 4.0) :: Nil
        | flatWorld() }

    /// パタパタの世界: 地面の上空でパタパタが上下する（基準 (240,150)・振れ幅 24・周期 2 秒
    /// → y 126..174 を 48px/s で往復）。プレイヤーは左の平地（x=160）に接地静止。
    pub def flyerWorld(): Field.World =
        { enemies = Field.flyerAt(601, { x = 240.0, y = 150.0 }, 24.0, 2.0) :: Nil
        | flatWorld() }

    /// トゲの世界: 地面の上（x=240・y=190）にトゲが据わっている。プレイヤーは x=160 に接地静止。
    pub def spikyWorld(): Field.World =
        { enemies = Field.spikyAt(602, { x = 240.0, y = Field.groundTop() - Field.enemyRadius() }) :: Nil
        | flatWorld() }

    /// 敵ショーケースの世界: walker 2 体。手前の walker A（x 142..158 をゆっくり往復）は
    /// 踏んで倒せる高さ・位置に、奥の walker B（x 256..304）は走り込むと横から触れる。
    pub def stompPatrolWorld(): Field.World =
        { player = restingPlayer(40.0),
          enemies = Field.walkerAt(610, { x = 150.0, y = Field.groundTop() - Field.enemyRadius() }, 8.0, 2.0) ::
                    Field.walkerAt(611, { x = 280.0, y = Field.groundTop() - Field.enemyRadius() }, 24.0, 4.0) :: Nil
        | flatWorld() }

    /// 敵ショーケースの台本（probe で振り付けた実測値・141 フレーム）: 助走 14f → ジャンプ 12f の
    /// 降下で walker A を踏んで倒し（f48・バウンド + 凍結 3 コマ）、走り続けて walker B に
    /// 横から触れて死に（f102）、出発点へ戻って着地する。
    pub def stompPatrolCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRight(14) :: rightJump(12) :: holdRight(70) :: flight(45) :: Nil)

    /// パタパタ踏みの台本（probe で振り付けた実測値・112 フレーム）: flyerWorld で
    /// 敵の左手前（x≈208・触れない横距離）まで走り（20f）、8f おいて真上に満タンジャンプ（24f）
    /// — 上昇中は横に動かないので、高く戻ってきた敵に触れない。頂点から右へ舵を切り（12f・
    /// 空中の加速は地上と同じ 900）、下降しながら敵の真上へ滑り込んで f66 で stomp
    /// （バウンド + 凍結 3 コマ）→ そのまま右へ流れて着地する。
    /// 踏みは「前フレームの足元が敵の頭より上 ∧ 下向きに落下中」でしか成立しない
    /// （上昇中に横から重なると致命接触になる）ので、舵を切るのは頂点から。
    pub def flyerBobCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRight(20) :: flight(8) :: holdJump(24) :: holdRight(12) :: flight(48) :: Nil)

    /// トゲ落とし穴の台本（probe で振り付けた実測値・111 フレーム）: spikyWorld で
    /// 走って（25f）ジャンプ（16f）で着地しつつ突っ込み、トゲは踏めないので f88 で death →
    /// 出発点（Level.spawnOf の x=56）へ戻り、f108 で着地するまで見せる。
    pub def spikyTrapCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRight(25) :: rightJump(16) :: holdRight(30) :: flight(40) :: Nil)

    /// 指定 id の敵の生死（見つからなければ None）。
    pub def enemyAliveOf(id: EntityId, world: Field.World): Option[Bool] =
        world#enemies |> List.findLeft(e -> e#id == id) |> Option.map(e -> e#alive)

    /// 生きている敵の数。
    pub def aliveEnemiesOf(world: Field.World): Int32 =
        world#enemies |> List.filter(e -> e#alive) |> List.length

    // ── 坂のシナリオ World ──

    /// 45° 坂の世界: 幅いっぱいの地面 + その上に載る右上がりの坂（底辺 64・高さ 64）。
    /// 坂の外接箱は x 168..232 / y 136..200（底面 = 地面の上面 200 にぴったり）。
    /// プレイヤーは坂の左の平地（x=120）に接地静止。
    pub def slopeWorld(): Field.World =
        worldOf(restingPlayer(120.0),
            Field.fullGround() :: Field.slopeAt(140, { x = 200.0, y = 168.0 }, { x = 64.0, y = 64.0 }, true) :: Nil)

    /// 緩い坂（底辺 64・高さ 32 ≈ 26.6°）の世界。外接箱は x 168..232 / y 168..200。
    pub def gentleSlopeWorld(): Field.World =
        worldOf(restingPlayer(120.0),
            Field.fullGround() :: Field.slopeAt(141, { x = 200.0, y = 184.0 }, { x = 64.0, y = 32.0 }, true) :: Nil)

    /// 45° 坂の斜辺の上、頂上寄りに接地静止しているプレイヤーの世界（下りと静止摩擦の出発点）。
    /// 位置は probe の実測値: x=220 で坂に立たせて静止させた分離後の座標。
    /// ridingId は坂（140）を設定済み — 静止摩擦が最初のフレームから効く（liftWorld と同じ流儀）。
    pub def onSlopeWorld(): Field.World =
        { player = { pos = { x = 220.0, y = 131.0294 }, grounded = true, ridingId = Some(140)
                   | restingPlayer(220.0) }
        | slopeWorld() }
}
