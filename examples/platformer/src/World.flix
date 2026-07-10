// World — 全状態の型（mod Field）とレイアウト定数。
//
// プラットフォーマーの手触り検証台なのでフェーズは持たない: 常にプレイ中で、
// 画面の下へ落ちたら出発点へ戻るだけ。状態はプレイヤーの運動学（位置・速度・接地・
// ジャンプ用タイマー）と、静的な地形（platforms）に尽きる。
// 地形は Store（Map）でなく List で持つ: 増減せず、物理へ渡す瞬間に Map へ組む。

mod Field {

    // ── プレイヤー ──

    pub type alias Player = {
        pos = Vec2.Vec2,        // 中心座標（y は下向き正）
        vel = Vec2.Vec2,        // px/秒
        grounded = Bool,        // 前フレームの分離後の接触から導いた接地
        coyoteLeft = Float64,   // 秒。接地中は常に coyoteTime へ充填、離床後に減る
        bufferLeft = Float64,   // 秒。ジャンプ押下で bufferTime へ充填、着地までに残っていれば飛ぶ
        jumpHeld = Bool,        // 上昇カットを離した瞬間の 1 回に限るための印
        squashLeft = Float64    // 着地スカッシュ演出の残り秒（View 用）
    }

    // ── 地形 ──

    pub type alias Platform = { id = EntityId, pos = Vec2.Vec2, size = Vec2.Vec2 }

    // ── このフレームの出来事（Sfx と WorldDump が読む）──

    pub enum Event with Eq, Order {
        case JumpEvent,
        case LandEvent,
        case BumpEvent,
        case DeathEvent
    }

    /// 出来事の名前（音名・ログ表記に共用）。
    pub def eventName(event: Event): String = match event {
        case Event.JumpEvent  => "jump"
        case Event.LandEvent  => "land"
        case Event.BumpEvent  => "bump"
        case Event.DeathEvent => "death"
    }

    // ── World ──

    pub type alias World = {
        player = Player,
        platforms = List[Platform],          // 地面・浮き床・左右の壁（すべて静的な矩形）
        params = GameParameters.Params,      // F1 リロードの調整値
        events = List[Event],                // このフレームの出来事（毎フレーム冒頭で空に）
        eventLog = List[(Float64, String)],  // 直近の出来事（新しい順・maxEventLog 件）
        deaths = Int32,                      // 崖に落ちた回数（HUD と WorldDump に出す）
        time = Float64                       // 通し秒
    }

    pub type alias Input = { left = Bool, right = Bool, dash = Bool,
                             jumpDown = Bool, jumpPressed = Bool }

    pub def noInput(): Input = { left = false, right = false, dash = false,
                                 jumpDown = false, jumpPressed = false }

    // ── レイアウト定数 ──

    pub def designW(): Float64 = 320.0
    pub def designH(): Float64 = 240.0

    /// プレイヤー（球体）の半径。
    pub def playerRadius(): Float64 = 12.0

    /// 地面の上面の y。プレイヤーが立つと中心は groundTop - playerRadius になる。
    pub def groundTop(): Float64 = 200.0

    /// 着地スカッシュ演出の長さ（秒）。
    pub def squashTime(): Float64 = 0.15

    /// この速さ（px/秒）以上で着地したときだけ land を出す（そっと乗ったときは鳴らさない）。
    pub def landEventSpeed(): Float64 = 30.0

    /// これより下へ落ちたら崖死亡（画面の下端より少し下）。
    pub def deathY(): Float64 = designH() + 40.0

    /// eventLog に残す件数。
    pub def maxEventLog(): Int32 = 16

    // ── 物体の id ──

    pub def playerId(): EntityId = 1
    def groundId(): EntityId = 100
    def groundIdB(): EntityId = 104
    def groundIdC(): EntityId = 105
    def floatIds(): List[EntityId] = 101 :: 102 :: 103 :: Nil
    def leftWallId(): EntityId = 110
    def rightWallId(): EntityId = 111

    // ── 形の補助 ──

    def vec(x: Float64, y: Float64): Vec2.Vec2 = { x = x, y = y }

    /// プレイヤーの当たり判定の形。物理へ射影する瞬間に使う。
    pub def playerShape(): CollisionShape2D =
        CollisionShape2D.CircleShape2D({ radius = playerRadius() })

    /// 地形 1 枚の当たり判定の形。
    pub def platformShape(platform: Platform): CollisionShape2D =
        CollisionShape2D.RectShape2D({ width = platform#size#x, height = platform#size#y })

    // ── 地形の組み立て ──
    // 地面は 3 分割で、間の 2 本が崖（穴）。落ちたら deathY で死亡 → 出発点へ。
    //   狭い穴（96..146・50px）: 真上に浮き床 A があるので、A に乗って渡る（下をくぐるのは無理）。
    //   広い穴（200..280・80px）: 浮き床 B の下を B ダッシュ + 低ホップでくぐり抜けて渡れる
    //   （素の走りジャンプでは届かず落ちる = ダッシュの見せ場）。浮き床経由の高い道もある。
    // 厚さは地面 40・浮き床 14: 1 フレームの最大落下（maxFallSpeed × 1/64 ≈ 14px）より
    // 「厚さ + 半径」が十分大きく、離散判定でも貫通しない。
    // 左右の壁は走り抜けての画面外落下を防ぐ（壁当ての手触りも見られる）。

    /// 崖なしの幅いっぱいの地面 1 枚（ジャンプ曲線の計測用。Trace の flatWorld などが使う）。
    pub def fullGround(): Platform =
        { id = groundId(), pos = vec(designW() / 2.0, groundTop() + 20.0), size = vec(designW(), 40.0) }

    /// 崖 2 本で 3 分割した地面。A: x 0..96 / 穴 50px / B: 146..200 / 穴 80px / C: 280..320。
    pub def groundSegments(): List[Platform] =
        { id = groundId(),  pos = vec(48.0, groundTop() + 20.0),  size = vec(96.0, 40.0) } ::
        { id = groundIdB(), pos = vec(173.0, groundTop() + 20.0), size = vec(54.0, 40.0) } ::
        { id = groundIdC(), pos = vec(300.0, groundTop() + 20.0), size = vec(40.0, 40.0) } :: Nil

    pub def floatingPlatforms(): List[Platform] =
        match floatIds() {
            case idA :: idB :: idC :: Nil =>
                { id = idA, pos = vec(110.0, 156.0), size = vec(64.0, 14.0) } ::
                { id = idB, pos = vec(210.0, 120.0), size = vec(64.0, 14.0) } ::
                { id = idC, pos = vec(285.0, 168.0), size = vec(50.0, 14.0) } :: Nil
            case _ => Nil
        }

    def wallPlatforms(): List[Platform] =
        { id = leftWallId(),  pos = vec(4.0, groundTop() / 2.0),   size = vec(8.0, groundTop()) } ::
        { id = rightWallId(), pos = vec(designW() - 4.0, groundTop() / 2.0), size = vec(8.0, groundTop()) } :: Nil

    pub def allPlatforms(): List[Platform] =
        List.append(groundSegments(), List.append(floatingPlatforms(), wallPlatforms()))

    // ── 出発点 ──

    /// プレイヤーの出発点: 左寄りの空中。落ちて地面に乗るところから始まる。
    pub def spawnPos(): Vec2.Vec2 = vec(60.0, 100.0)

    pub def freshPlayer(): Player =
        { pos = spawnPos(), vel = Vec2.zero(), grounded = false,
          coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0 }

    pub def initialWorld(): World =
        { player = freshPlayer(), platforms = allPlatforms(),
          params = GameParameters.defaults(), events = Nil, eventLog = Nil,
          deaths = 0, time = 0.0 }

    // ── リモートデバッグ（view=status）用の 1 行サマリ ──

    /// 調整に効く値だけを短く: 位置・速度・接地・コヨーテ/バッファ残・押しっぱなし・今フレームの出来事。
    pub def statusLine(world: World): String =
        let player = world#player;
        "pos=(${RemoteDebug.fmt1(player#pos#x)},${RemoteDebug.fmt1(player#pos#y)})"
        + " vel=(${RemoteDebug.fmt1(player#vel#x)},${RemoteDebug.fmt1(player#vel#y)})"
        + " grd=${if (player#grounded) "T" else "F"}"
        + " coyote=${RemoteDebug.fmt1(player#coyoteLeft * 1000.0)}ms"
        + " buf=${RemoteDebug.fmt1(player#bufferLeft * 1000.0)}ms"
        + " held=${if (player#jumpHeld) "T" else "F"}"
        + " deaths=${world#deaths}"
        + " ev=${world#events |> List.map(eventName) |> String.intercalate(",")}"
}
