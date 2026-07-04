// World — 不変 ECS World とコンポーネント定義（単層スパイクの中核）
//
// entity は EntityId（Int32）。状態は component ごとの Map[EntityId, _] に分かれて入り、
// 同じ id が複数の Map に存在することで 1 体を構成する（player と mob が同じ
// positions/velocities/sprites を共有するのが ECS の肝）。
// resource 的な singleton（phase/score/timers）は World レコードのフィールドに置く。
//
// System はすべて World -> World の関数（systems/ 配下）。描画は render/RenderWorld が
// World -> List[Drawable] に射影する。scene-tree は使わない。

// ── 共有型（ファイル横断で使うので top-level）──
// EntityId は共有 lib flix_engine_world が提供（top-level pub alias）。

/// スプライトの見た目。named clip（"walk"/"up" 等）＋フレーム送り＋反転。
/// AnimatedSprite2D ノードの代替を 1 レコードに畳む。
pub type alias SpriteComp = {
    clips      = Map[String, List[String]],  // clip 名 -> テクスチャ名の列
    current    = String,                      // 再生中の clip
    frame      = Int32,                       // 現フレーム index
    frameTimer = Float64,                     // 次フレームまでの経過秒
    fps        = Float64,
    flipH      = Bool,
    flipV      = Bool
}

pub enum HudKind with Eq {
    case Score
    case Message
    case StartButton
}

/// HUD も entity（単層）。text 要素とボタンを表す。
/// size はボタン枠の描画＆hit-test 矩形（左上＋size）に使う。
pub type alias HudComp = {
    kind    = HudKind,
    text    = String,
    pos     = Vec2.Vec2,
    size    = Vec2.Vec2,
    visible = Bool
}

/// 時間管理（旧 Timer ノード群の代替）。秒のアキュムレータ。
pub type alias Timers = {
    mobSpawn    = Float64,   // `spawn` は Flix 予約語なので mobSpawn
    score       = Float64,
    startDelay  = Float64,
    gameOverMsg = Float64,
    title       = Float64
}

pub enum GamePhase with Eq {
    case Menu
    case Playing
    case GameOver
}

/// 不変 World。nominal な単一ケース enum（推論破綻時のエラーを締める）。
pub enum World {
    case World({
        positions     = Map[EntityId, Vec2.Vec2],
        velocities    = Map[EntityId, Vec2.Vec2],
        sprites       = Map[EntityId, SpriteComp],
        colliders     = Map[EntityId, Collision.Collider],
        mobs          = Set[EntityId],
        player        = Option[EntityId],
        huds          = Map[EntityId, HudComp],
        phase         = GamePhase,
        score         = Int32,
        timers        = Timers,
        paused        = Bool,
        prevKeys      = Set[GameEngine.Key],
        prevMouseDown = Bool,
        nextId        = EntityId
    })
}

mod World {

    // ── 定数 ──

    pub def designWi(): Int32 = 480
    pub def designHi(): Int32 = 720

    def zeroTimers(): Timers =
        {mobSpawn = 0.0, score = 0.0, startDelay = 0.0, gameOverMsg = 0.0, title = 0.0}

    // ── 構築 ──

    /// 標準 HUD entity（score/message/start ボタン）。Menu 構築とロード復元で共有する。
    /// 値は hudSyncSystem が phase/score から毎フレーム上書きするので、ここでは器を置くだけ。
    pub def standardHuds(): Map[EntityId, HudComp] =
        Map#{
            100 => {kind = HudKind.Score, text = "0",
                    pos = {x = 220.0, y = 20.0}, size = {x = 40.0, y = 30.0}, visible = true},
            101 => {kind = HudKind.Message, text = "Dodge the\nCreeps",
                    pos = {x = 120.0, y = 280.0}, size = {x = 240.0, y = 80.0}, visible = true},
            102 => {kind = HudKind.StartButton, text = "Start",
                    pos = {x = 200.0, y = 420.0}, size = {x = 80.0, y = 36.0}, visible = true} }

    /// 何もない World（phase=Menu）。
    pub def empty(): World =
        World.World({
            positions     = Map.empty(),
            velocities    = Map.empty(),
            sprites       = Map.empty(),
            colliders     = Map.empty(),
            mobs          = Set.empty(),
            player        = None,
            huds          = Map.empty(),
            phase         = GamePhase.Menu,
            score         = 0,
            timers        = zeroTimers(),
            paused        = false,
            prevKeys      = Set.empty(),
            prevMouseDown = false,
            nextId        = 0
        })

    /// player のスプライト component（walk / up clip ＋ flip）。
    pub def playerSprite(): SpriteComp =
        { clips = Map#{ "walk" => "playerGrey_walk1" :: "playerGrey_walk2" :: Nil,
                        "up"   => "playerGrey_up1"   :: "playerGrey_up2"   :: Nil },
          current = "walk", frame = 0, frameTimer = 0.0, fps = 5.0,
          flipH = false, flipV = false }

    /// mob のスプライト component（1 clip）。
    pub def mobSprite(animName: String, t1: String, t2: String): SpriteComp =
        { clips = Map#{ animName => t1 :: t2 :: Nil },
          current = animName, frame = 0, frameTimer = 0.0, fps = 5.0,
          flipH = false, flipV = false }

    // ── Phase2 vertical slice 用のハードコード World ──
    // スキーマと描画の凍結確認に使う。Phase4 で systems 駆動の実 World に置き換える。

    pub def demoWorld(): World =
        let playerId = 0;
        let m0 = 1; let m1 = 2; let m2 = 3;
        let scoreId = 100; let msgId = 101; let btnId = 102;
        let World.World(w) = empty();
        World.World({
            positions =
                Map#{ playerId => {x = 240.0, y = 450.0},
                      m0 => {x = 90.0,  y = 140.0},
                      m1 => {x = 320.0, y = 210.0},
                      m2 => {x = 200.0, y = 320.0} },
            velocities =
                Map#{ m0 => {x = 40.0, y = 60.0},
                      m1 => {x = -30.0, y = 50.0},
                      m2 => {x = 0.0, y = 70.0} },
            sprites =
                Map#{ playerId => playerSprite(),
                      m0 => mobSprite("fly", "enemyFlyingAlt_1", "enemyFlyingAlt_2"),
                      m1 => mobSprite("walk", "enemyWalking_1", "enemyWalking_2"),
                      m2 => mobSprite("swim", "enemySwimming_1", "enemySwimming_2") },
            colliders =
                Map#{ playerId => circleCollider(30.0, playerLayer(), mobLayer()),
                      m0 => circleCollider(30.0, mobLayer(), 0i32),
                      m1 => circleCollider(30.0, mobLayer(), 0i32),
                      m2 => circleCollider(30.0, mobLayer(), 0i32) },
            mobs   = Set#{m0, m1, m2},
            player = Some(playerId),
            huds =
                Map#{ scoreId => {kind = HudKind.Score, text = "0",
                                  pos = {x = 220.0, y = 20.0},
                                  size = {x = 40.0, y = 30.0}, visible = true},
                      msgId   => {kind = HudKind.Message, text = "Dodge the\nCreeps",
                                  pos = {x = 120.0, y = 280.0},
                                  size = {x = 240.0, y = 80.0}, visible = true},
                      btnId   => {kind = HudKind.StartButton, text = "Start",
                                  pos = {x = 200.0, y = 420.0},
                                  size = {x = 80.0, y = 36.0}, visible = true} },
            phase = GamePhase.Menu,
            score = 0
            | w
        })

    // ── 衝突レイヤー（engine の CollisionLayers と同じ意味論）──

    pub def playerLayer(): Int32 = 1i32   // bit0
    pub def mobLayer(): Int32 = 2i32      // bit1

    /// 円 Collider を作る（engine の CircleShape2D を再利用）。
    pub def circleCollider(radius: Float64, layer: Int32, mask: Int32): Collision.Collider =
        { shape = CollisionShape2D.CircleShape2D({radius = radius}), layer = layer, mask = mask }

    // ── entity 操作（spawn / despawn）──

    /// 新しい mob entity を追加する。nextId を採番して各 component map に入れる。
    /// mob は layer=mob, mask=0（誰も観測しない＝mob 同士は当たらない）。
    pub def addMob(pos: Vec2.Vec2, vel: Vec2.Vec2, sc: SpriteComp,
                   radius: Float64, world: World): World =
        let World.World(w) = world;
        let id = w#nextId;
        World.World({
            positions  = Map.insert(id, pos, w#positions),
            velocities = Map.insert(id, vel, w#velocities),
            sprites    = Map.insert(id, sc, w#sprites),
            colliders  = Map.insert(id, circleCollider(radius, mobLayer(), 0i32), w#colliders),
            mobs       = Set.insert(id, w#mobs),
            nextId     = id + 1
            | w
        })

    /// player entity を生成。layer=player, mask=mob（mob だけを観測する）。
    pub def spawnPlayer(pos: Vec2.Vec2, radius: Float64, world: World): World =
        let World.World(w) = world;
        let id = w#nextId;
        World.World({
            positions  = Map.insert(id, pos, w#positions),
            velocities = Map.insert(id, Vec2.zero(), w#velocities),
            sprites    = Map.insert(id, playerSprite(), w#sprites),
            colliders  = Map.insert(id, circleCollider(radius, playerLayer(), mobLayer()), w#colliders),
            player     = Some(id),
            nextId     = id + 1
            | w
        })

    /// entity を全 component map から除去する（despawn）。
    pub def removeEntity(id: EntityId, world: World): World =
        let World.World(w) = world;
        World.World({
            positions  = Map.remove(id, w#positions),
            velocities = Map.remove(id, w#velocities),
            sprites    = Map.remove(id, w#sprites),
            colliders  = Map.remove(id, w#colliders),
            mobs       = Set.remove(id, w#mobs)
            | w
        })

    // ── アクセサ ──

    pub def phaseOf(world: World): GamePhase =
        let World.World(w) = world; w#phase

    pub def isPaused(world: World): Bool =
        let World.World(w) = world; w#paused

    /// 描画中の clip の現フレームのテクスチャ名（無ければ ""）。
    pub def currentTexture(sc: SpriteComp): String =
        Map.get(sc#current, sc#clips)
            |> Option.flatMap(frames -> List.nth(sc#frame, frames))
            |> Option.getWithDefault("")
}
