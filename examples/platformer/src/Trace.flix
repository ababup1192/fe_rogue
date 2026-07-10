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
          coyoteLeft = Jump.coyoteTime(), bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0 }

    /// 地面だけの世界（浮き床・壁なし）。ジャンプ曲線と走りを邪魔なしで測る。
    pub def flatWorld(): Field.World =
        { player = restingPlayer(160.0),
          platforms = Field.fullGround() :: Nil,
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, deaths = 0, time = 0.0 }

    /// 製品と同じ地形（地面 + 浮き床 3 枚 + 左右の壁）。
    pub def platformWorld(): Field.World = Field.initialWorld()

    /// 浮き床走破の出発点: 製品の地形で、左端（x=20）に接地静止。
    pub def runAcrossWorld(): Field.World =
        { player = restingPlayer(20.0) | Field.initialWorld() }

    /// 広い穴の手前（地面 B の左寄り x=155）に接地静止。ダッシュ崖越えと崖死亡の出発点。
    pub def gapWorld(): Field.World =
        { player = restingPlayer(155.0) | Field.initialWorld() }

    /// ダッシュ崖越えの台本: dash 助走 10f → 低ホップ 6f → 浮き床 B の下をくぐって浮き床 C に着地。
    pub def dashGapCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRightDash(10) :: rightDashJump(6) :: holdRightDash(40) :: Nil)

    /// 崖死亡の台本: 広い穴へ歩き出て落ち、死亡 → 出発点へ戻って着地するまで。
    pub def gapDeathCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(holdRight(10) :: flight(45) :: Nil)

    /// 浮き床走破の台本（リモートデバッグの lockstep で振り付けた実測値・143 フレーム）:
    /// 助走 3f → ジャンプ 12f で床 A（y=156）へ → 2f おいて 14f ジャンプで床 B（y=120）へ →
    /// 走り落ちて床 C（y=168）へ（コヨーテの絵）→ 右壁で止まる。
    pub def runAcrossCues(): List[Replay.Cue[Field.Input]] =
        List.flatten(
            holdRight(3) :: rightJump(12) :: holdRight(26) ::
            holdRight(2) :: rightJump(14) :: holdRight(22) ::
            holdRight(32) :: holdRight(20) :: flight(12) :: Nil)

    /// 崖のある世界: 幅 80 の床の右端ぎりぎりに接地している。右へ 1 歩で床を離れる。
    pub def ledgeWorld(): Field.World =
        let ledge = { id = 100, pos = { x = 80.0, y = 150.0 }, size = { x = 80.0, y = 20.0 } };
        { player = { pos = { x = 116.0, y = 140.0 - Field.playerRadius() } | restingPlayer(116.0) },
          platforms = ledge :: Nil,
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, deaths = 0, time = 0.0 }

    /// 頭上の低い天井: 接地位置の 60px 上に床がある。ジャンプすると頭をぶつける。
    pub def ceilingWorld(): Field.World =
        let ceiling = { id = 101, pos = { x = 160.0, y = Field.groundTop() - 60.0 }, size = { x = 80.0, y = 14.0 } };
        { player = restingPlayer(160.0),
          platforms = Field.fullGround() :: ceiling :: Nil,
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, deaths = 0, time = 0.0 }

    /// コヨーテ猶予が残ったまま空中にいる世界: 崖を離れて数フレーム後の状態を直接組む
    /// （歩き出しのフレーム数に依存せず、猶予内のジャンプ成立だけを見る）。
    pub def coyoteWorld(coyoteLeft: Float64): Field.World =
        let base = fallingWorld(60.0);
        { player = { coyoteLeft = coyoteLeft | base#player } | base }

    /// 空中から落下し始める世界: プレイヤーを地面の上方 height px の空中に置く（速度ゼロ）。
    pub def fallingWorld(height: Float64): Field.World =
        { player = { pos = { x = 160.0, y = Field.groundTop() - Field.playerRadius() - height },
                     vel = Vec2.zero(), grounded = false,
                     coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0 },
          platforms = Field.fullGround() :: Nil,
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, deaths = 0, time = 0.0 }

    // ── 読み取り（テストが World から値を取り出す薄いアクセサ）──

    pub def posOf(world: Field.World): Vec2.Vec2 = world#player#pos
    pub def velOf(world: Field.World): Vec2.Vec2 = world#player#vel
    pub def groundedOf(world: Field.World): Bool = world#player#grounded
    pub def coyoteOf(world: Field.World): Float64 = world#player#coyoteLeft
    pub def bufferOf(world: Field.World): Float64 = world#player#bufferLeft
    pub def eventsOf(world: Field.World): List[String] =
        world#events |> List.map(Field.eventName)
    pub def deathsOf(world: Field.World): Int32 = world#deaths

    /// 一連の World（Replay.timeline の結果）から最高到達点（最小の y）を取り出す。
    pub def apexOf(worlds: List[Field.World]): Float64 =
        worlds |> List.map(world -> world#player#pos#y)
               |> List.minimum
               |> Option.getWithDefault(0.0)
}
