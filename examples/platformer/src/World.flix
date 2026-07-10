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
        squashLeft = Float64,   // 着地スカッシュ演出の残り秒（View 用）
        facing = Float64,       // 向いている向き（+1 右 / -1 左）。最後の非ゼロ入力を保持（カメラ先読み用）
        ridingId = Option[EntityId], // 乗っている床の id（分離後の支持接触から毎フレーム導出・空中は None）
        dropLeft = Float64      // すり抜け降下の残り秒（この間は一方通行を無視する）
    }

    // ── 地形 ──

    /// 動く床の運動仕様（時刻の純関数で位置を導く・状態を持たない）。本体は engine_world の
    /// Motion.Oscillation。三角波(pingPong)なので sin と違い機種依存が無く、速さが一定
    /// (4×amplitude/period px/s) — period を 2 の冪秒にすればテストの pin が厳密になる。
    pub type alias Motion = Motion.Oscillation

    pub type alias Platform = {
        id = EntityId,
        pos = Vec2.Vec2,              // 基準位置（動く床は posAt が実位置を導く）
        size = Vec2.Vec2,
        motion = Option[Motion],      // None = 動かない
        oneWay = Bool,                // true = 下から抜けられる一方通行（上からだけ乗れる）
        slope = Option[Bool]          // None = 矩形。Some(riseRight) = 斜辺が上面の坂
    }

    /// 動かない普通の床。
    pub def rigid(id: EntityId, pos: Vec2.Vec2, size: Vec2.Vec2): Platform =
        { id = id, pos = pos, size = size, motion = None, oneWay = false, slope = None }

    /// 一方通行の床（上からだけ乗れる・下+ジャンプで降りられる）。
    pub def oneWayAt(id: EntityId, pos: Vec2.Vec2, size: Vec2.Vec2): Platform =
        { id = id, pos = pos, size = size, motion = None, oneWay = true, slope = None }

    /// 動く床。pos は基準位置で、実位置は platformPosAt が時刻から導く。
    pub def movingAt(id: EntityId, base: Vec2.Vec2, size: Vec2.Vec2, motion: Motion): Platform =
        { id = id, pos = base, size = size, motion = Some(motion), oneWay = false, slope = None }

    /// 上り坂（直角三角形・斜辺が上面）。riseRight=true なら右へ登る。
    pub def slopeAt(id: EntityId, pos: Vec2.Vec2, size: Vec2.Vec2, riseRight: Bool): Platform =
        { id = id, pos = pos, size = size, motion = None, oneWay = false, slope = Some(riseRight) }

    /// [-1,1] の三角波。0 から立ち上がり、1/4 周期で +1、1/2 で 0、3/4 で -1、1 周期で 0 に戻る。
    /// 本体は engine_world の Curve.pingPong（昇格済み・ここは委譲）。
    pub def pingPong(u: Float64): Float64 = Curve.pingPong(u)

    /// 時刻 t での床の実位置。動かない床は基準位置そのまま。
    pub def platformPosAt(t: Float64, platform: Platform): Vec2.Vec2 =
        match platform#motion {
            case None       => platform#pos
            case Some(m)    => Vec2.add(platform#pos, Motion.oscillationOffset(m, t))
        }

    /// 全部の床を時刻 t の実位置に置き直したリスト。
    pub def platformsAt(t: Float64, platforms: List[Platform]): List[Platform] =
        platforms |> List.map(platform -> { pos = platformPosAt(t, platform) | platform })

    // ── 敵 ──

    /// 敵の種類。歩く敵とパタパタは踏める。トゲは踏んでも死ぬ。
    pub enum EnemyKind with Eq, Order {
        case WalkerKind,
        case FlyerKind,
        case SpikyKind
    }

    /// 敵の種類の名前（WorldDump 用）。
    pub def enemyKindName(kind: EnemyKind): String = match kind {
        case EnemyKind.WalkerKind => "walker"
        case EnemyKind.FlyerKind  => "flyer"
        case EnemyKind.SpikyKind  => "spiky"
    }

    /// 敵 1 体。動きは閉形式: base と motion から時刻の純関数で位置を導く（状態は alive だけ）。
    pub type alias Enemy = {
        id = EntityId,             // 600 番台
        kind = EnemyKind,
        base = Vec2.Vec2,          // 基準位置
        motion = Option[Motion],   // Walker=横 pingPong / Flyer=縦 pingPong / None=固定
        alive = Bool
    }

    /// 時刻 t での敵の実位置。動かない敵は基準位置そのまま（platformPosAt と同型）。
    pub def enemyPosAt(t: Float64, enemy: Enemy): Vec2.Vec2 =
        match enemy#motion {
            case None    => enemy#base
            case Some(m) => Vec2.add(enemy#base, Motion.oscillationOffset(m, t))
        }

    /// 歩く敵: base から横に range だけ pingPong で往復する。
    pub def walkerAt(id: EntityId, base: Vec2.Vec2, range: Float64, period: Float64): Enemy =
        walkerAtPhase(id, base, range, period, 0.0)

    /// 位相つきの歩く敵。疾走感のレベルは踏みバウンドの連鎖が合うよう歩きの位相を調整する。
    pub def walkerAtPhase(id: EntityId, base: Vec2.Vec2, range: Float64, period: Float64,
                          phase: Float64): Enemy =
        { id = id, kind = EnemyKind.WalkerKind, base = base,
          motion = Some({ axis = { x = 1.0, y = 0.0 }, amplitude = range, period = period, phase = phase }),
          alive = true }

    /// パタパタ: base から縦に range だけ pingPong で上下する（正の pingPong で上へ）。
    pub def flyerAt(id: EntityId, base: Vec2.Vec2, range: Float64, period: Float64): Enemy =
        flyerAtPhase(id, base, range, period, 0.0)

    /// 位相つきのパタパタ。疾走感のレベルは走破の通過時刻に高い位置へ来るよう位相を調整する。
    pub def flyerAtPhase(id: EntityId, base: Vec2.Vec2, range: Float64, period: Float64,
                         phase: Float64): Enemy =
        { id = id, kind = EnemyKind.FlyerKind, base = base,
          motion = Some({ axis = { x = 0.0, y = -1.0 }, amplitude = range, period = period, phase = phase }),
          alive = true }

    /// トゲ: 動かない。踏んでも死ぬ。
    pub def spikyAt(id: EntityId, base: Vec2.Vec2): Enemy =
        { id = id, kind = EnemyKind.SpikyKind, base = base, motion = None, alive = true }

    /// 敵の当たり判定（円・半径 10）。
    pub def enemyRadius(): Float64 = 10.0

    /// 踏んだ瞬間だけ世界を止める「手応え」の秒数（ヒットストップ・ちょうど 3 コマ）。
    /// 1/64 の倍数なので凍結は常に 3 フレームぴったり = テストの pin が厳密になる。
    pub def stompFreeze(): Float64 = 3.0 / 64.0

    // ── このフレームの出来事（Sfx と WorldDump が読む）──

    pub enum Event with Eq, Order {
        case JumpEvent,
        case LandEvent,
        case BumpEvent,
        case StompEvent,
        case DeathEvent,
        case CheckpointEvent,
        case ClearEvent,
        case FireworkEvent
    }

    /// 出来事の名前（音名・ログ表記に共用）。
    pub def eventName(event: Event): String = match event {
        case Event.JumpEvent  => "jump"
        case Event.LandEvent  => "land"
        case Event.BumpEvent  => "bump"
        case Event.StompEvent => "stomp"
        case Event.DeathEvent => "death"
        case Event.CheckpointEvent => "checkpoint"
        case Event.ClearEvent => "clear"
        case Event.FireworkEvent => "firework"
    }

    // ── 演出の粒（ダッシュの土埃・ジャンプの噴射）──

    /// 演出の粒の種。閉形式: 粒の位置・透明度は (kind, seed, i, elapsed) の純関数で毎フレーム導出する。
    pub enum FxKind with Eq {
        case DustKind,
        case JetKind,
        case FireworkKind
    }

    /// 演出の粒の種（burst）。状態は種と原点と経過秒だけ；実際の粒の位置・見た目は GameFx が
    /// elapsed から毎フレーム計算する（保存も更新も要らない）。
    /// power（0..1）は勢い: 速いダッシュの土埃・強い着地ほど粒が多く・大きくなる（ジェットは常に 1.0）。
    pub type alias Burst = { kind = FxKind, seed = Int32, pos = Vec2.Vec2, dir = Vec2.Vec2,
                             power = Float64, elapsed = Float64 }

    // ── World ──

    pub type alias World = {
        player = Player,
        platforms = List[Platform],          // 地面・浮き床・坂・左右の壁（すべて静的）
        enemies = List[Enemy],               // 敵（倒されても alive=false でリストに残す）
        params = GameParameters.Params,      // F1 リロードの調整値
        events = List[Event],                // このフレームの出来事（毎フレーム冒頭で空に）
        eventLog = List[(Float64, String)],  // 直近の出来事（新しい順・maxEventLog 件）
        bursts = List[Burst],                // 演出の粒（土埃・ジャンプ噴射。種と経過秒だけを持つ）
        deaths = Int32,                      // 崖に落ちた回数（HUD と WorldDump に出す）
        camX = Float64,                      // カメラ左端の x（Step が毎フレーム進める・View が引く）
        camY = Float64,                      // カメラ上端の y（縦追従。1 画面の高さのレベルでは常に 0）
        levelW = Float64,                    // レベル全幅 px。designW 以下なら camX は常に 0 に張り付く
        levelH = Float64,                    // レベル全高 px。designH 以下なら camY は常に 0 に張り付く
        spawnPos = Vec2.Vec2,                // レベルの出発点（camY の初期スナップ先）
        respawnPos = Vec2.Vec2,              // 死亡時に戻る場所。中間地点を越えるとそこに変わる
        checkpointPos = Vec2.Vec2,           // 中間地点（x が発動線・無いレベルは届かない値）
        goalX = Float64,                     // ゴールの x。越えたらクリア（無いレベルは届かない値）
        clearedAt = Option[Float64],         // クリアした時刻（None = 未クリア）。花火の発射台本の基点
        freezeLeft = Float64,                // ヒットストップの残り秒（>0 の間は時間も物理も丸ごと止まる・踏みで充填）
        time = Float64                       // 通し秒
    }

    pub type alias Input = { left = Bool, right = Bool, dash = Bool,
                             jumpDown = Bool, jumpPressed = Bool, down = Bool }

    pub def noInput(): Input = { left = false, right = false, dash = false,
                                 jumpDown = false, jumpPressed = false, down = false }

    // ── レイアウト定数 ──

    pub def designW(): Float64 = 480.0
    pub def designH(): Float64 = 360.0

    /// classic 地形（シナリオ用 1 画面レベル）の寸法。カメラの design を広げても
    /// ここは 320×240 に固定する — classic の地形・levelW/H が design に連動すると
    /// 壁の位置ごと動いて、既存シナリオの物理 pin と GIF の sim が壊れるため。
    /// design より小さいのでカメラは 0 に張り付き、画面の右端 x=320 の先は虚空が見える。
    pub def classicW(): Float64 = 320.0
    pub def classicH(): Float64 = 240.0

    /// プレイヤー（球体）の半径。
    pub def playerRadius(): Float64 = 12.0

    /// 地面の上面の y。プレイヤーが立つと中心は groundTop - playerRadius になる。
    pub def groundTop(): Float64 = 200.0

    /// 着地スカッシュ演出の長さ（秒）。
    pub def squashTime(): Float64 = 0.15

    /// この速さ（px/秒）以上で着地したときだけ land を出す（そっと乗ったときは鳴らさない）。
    pub def landEventSpeed(): Float64 = 30.0

    /// この線より下へ落ちたら崖死亡（レベルの下端より少し下）。levelH から導くので、
    /// 1 画面のレベル（levelH=240）では従来どおり y=280 の線になる。
    pub def deathLineOf(world: World): Float64 = world#levelH + 40.0

    /// eventLog に残す件数。
    pub def maxEventLog(): Int32 = 16

    /// 下+ジャンプですり抜け降下している間、一方通行を無視する秒数。
    pub def dropTime(): Float64 = 0.15

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

    /// プレイヤーの当たり判定を カプセル にする実験スイッチ（既定は円）。
    /// カプセルは第2弾のエンジン拡張で separate 可能になった。切り替えると全テストの pin が変わるので、
    /// 手触り比較をしたいときだけ手で true にする。
    def useCapsule(): Bool = false

    /// プレイヤーの当たり判定の形。物理へ射影する瞬間に使う。
    pub def playerShape(): CollisionShape2D =
        if (useCapsule()) CollisionShape2D.CapsuleShape2D({ radius = playerRadius(), height = playerRadius() * 3.0, vertical = true })
        else CollisionShape2D.CircleShape2D({ radius = playerRadius() })

    /// 地形 1 枚の当たり判定の形。坂は斜辺が上面の直角三角形、それ以外は矩形。
    pub def platformShape(platform: Platform): CollisionShape2D =
        match platform#slope {
            case Some(riseRight) =>
                CollisionShape2D.SlopeShape2D({ width = platform#size#x, height = platform#size#y, riseRight = riseRight })
            case None =>
                CollisionShape2D.RectShape2D({ width = platform#size#x, height = platform#size#y })
        }

    /// 接触を「接地」とみなす法線の上向き成分のしきい値。45° の坂の法線は y=-0.707 なので
    /// 0.7 だと坂の上でぎりぎり非接地になる。0.6 まで下げて 45° 坂を接地に含める。
    pub def groundedNormalY(): Float64 = -0.6

    /// 角の救済のしきい値 px: 上昇中の頭ぶつけが床の端からこの水平めり込み以内なら、
    /// 止めずに横へずらして通す「プレイヤーは悪くない」救済（bump も出さない）。
    pub def cornerNudge(): Float64 = 6.0

    // ── classic 地形の組み立て ──
    // 本番のレベルは Level（208×30 のテキストグリッド・3328×480px）が正。ここの 1 画面地形は
    // テストとギャラリーのシナリオ用（Trace.classicWorld が使う）に残している。
    // 地面は 3 分割で、間の 2 本が崖（穴）。死亡線（levelH+40）を割ったら死亡 → 出発点へ。
    //   狭い穴（96..146・50px）: 真上に浮き床 A があるので、A に乗って渡る（下をくぐるのは無理）。
    //   広い穴（200..280・80px）: 浮き床 B の下を B ダッシュ + 低ホップでくぐり抜けて渡れる
    //   （素の走りジャンプでは届かず落ちる = ダッシュの見せ場）。浮き床経由の高い道もある。
    // 厚さは地面 40・浮き床 14: 1 フレームの最大落下（maxFallSpeed × 1/64 ≈ 14px）より
    // 「厚さ + 半径」が十分大きく、離散判定でも貫通しない。
    // 左右の壁は走り抜けての画面外落下を防ぐ（壁当ての手触りも見られる）。

    /// 崖なしの幅いっぱいの地面 1 枚（ジャンプ曲線の計測用。Trace の flatWorld などが使う）。
    pub def fullGround(): Platform =
        rigid(groundId(), vec(classicW() / 2.0, groundTop() + 20.0), vec(classicW(), 40.0))

    /// 崖 2 本で 3 分割した地面。A: x 0..96 / 穴 50px / B: 146..200 / 穴 80px / C: 280..320。
    pub def groundSegments(): List[Platform] =
        rigid(groundId(),  vec(48.0, groundTop() + 20.0),  vec(96.0, 40.0)) ::
        rigid(groundIdB(), vec(173.0, groundTop() + 20.0), vec(54.0, 40.0)) ::
        rigid(groundIdC(), vec(300.0, groundTop() + 20.0), vec(40.0, 40.0)) :: Nil

    pub def floatingPlatforms(): List[Platform] =
        match floatIds() {
            case idA :: idB :: idC :: Nil =>
                rigid(idA, vec(110.0, 156.0), vec(64.0, 14.0)) ::
                rigid(idB, vec(210.0, 120.0), vec(64.0, 14.0)) ::
                rigid(idC, vec(285.0, 168.0), vec(50.0, 14.0)) :: Nil
            case _ => Nil
        }

    def wallPlatforms(): List[Platform] =
        rigid(leftWallId(),  vec(4.0, groundTop() / 2.0),   vec(8.0, groundTop())) ::
        rigid(rightWallId(), vec(classicW() - 4.0, groundTop() / 2.0), vec(8.0, groundTop())) :: Nil

    pub def classicPlatforms(): List[Platform] =
        List.append(groundSegments(), List.append(floatingPlatforms(), wallPlatforms()))

    // ── 出発点 ──

    /// 指定の出発点に立つ直前のプレイヤー（少し上の空中・落ちて地面に乗るところから始まる）。
    /// 死亡リスポーン（Step）も World の spawnPos からここへ戻す。
    pub def freshPlayerAt(startAt: Vec2.Vec2): Player =
        { pos = startAt, vel = Vec2.zero(), grounded = false,
          coyoteLeft = 0.0, bufferLeft = 0.0, jumpHeld = false, squashLeft = 0.0,
          facing = 1.0, ridingId = None, dropLeft = 0.0 }

    /// 本番の初期 World: Level のワイドレベル（3328×480px）にスポーンのプレイヤーと敵。
    /// camY は最初からスポーンへスナップしておく（起動直後に画面が縦にパンしない）。
    pub def initialWorld(): World =
        let startAt = Level.spawnOf();
        { player = freshPlayerAt(startAt), platforms = Level.allPlatforms(),
          enemies = Level.enemies(),
          params = GameParameters.defaults(), events = Nil, eventLog = Nil, bursts = Nil,
          deaths = 0,
          camX = FollowCam.snapCam(Level.levelWidth(), startAt#x),
          camY = FollowCam.snapCamY(Level.levelHeight(), startAt#y),
          levelW = Level.levelWidth(), levelH = Level.levelHeight(),
          spawnPos = startAt, respawnPos = startAt, checkpointPos = Level.checkpointPos(),
          goalX = Level.goalX(), clearedAt = None, freezeLeft = 0.0, time = 0.0 }

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
        + " cam=${RemoteDebug.fmt1(world#camX)}"
        + " foes=${world#enemies |> List.filter(e -> e#alive) |> List.length}"
        + " ev=${world#events |> List.map(eventName) |> String.intercalate(",")}"
}
