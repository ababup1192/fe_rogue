// WorldCodec — World ↔ JSON（セーブ/ロード・宣言的オーサリングの土台）
//
// 不変 World は「ただの値」なので、各 component store を共有 lib の EcsCodec.encodeStore /
// decodeStore で往復し、resource（score/phase/timers/nextId）を添えるだけで World↔JSON になる。
// component ごとの encode/decode はゲーム固有なのでここに書く（engine の JsonCodec を再利用）。
// transient な入力状態（prevKeys/paused/prevMouseDown）はセーブ対象外（ロード時に既定）。
// HUD entity もセーブせず、ロード時に World.standardHuds() で器を再構築する（中身は
// hudSyncSystem が phase/score から毎フレーム上書きする。空のままだと表示が出ないため、
// hudSync の「既存 huds を更新するだけ」という性質に合わせて器を必ず置き直す）。

mod WorldCodec {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JBool}

    // ── 小ヘルパ ──
    def num(f: Float64): Json = JNumber(JsonCodec.floatToBd(f))
    def int(i: Int32): Json = JNumber(JsonCodec.intToBd(i))
    def getFloat(k: String, obj: Map[String, Json]): Option[Float64] =
        Map.get(k, obj) |> Option.flatMap(JsonCodec.expectFloat)
    def getInt(k: String, obj: Map[String, Json]): Option[Int32] =
        Map.get(k, obj) |> Option.flatMap(JsonCodec.expectInt)
    def getStr(k: String, obj: Map[String, Json]): Option[String] =
        Map.get(k, obj) |> Option.flatMap(JsonCodec.expectString)
    def getBool(k: String, obj: Map[String, Json]): Option[Bool] =
        Map.get(k, obj) |> Option.flatMap(JsonCodec.expectBool)

    // ── World 全体 ──

    pub def encodeWorld(world: World): Json =
        let World.World(w) = world;
        JObject(Map#{
            "positions"  => EcsCodec.encodeStore(JsonCodec.encodeVec2, w#positions),
            "velocities" => EcsCodec.encodeStore(JsonCodec.encodeVec2, w#velocities),
            "sprites"    => EcsCodec.encodeStore(encodeSprite, w#sprites),
            "colliders"  => EcsCodec.encodeStore(encodeCollider, w#colliders),
            "mobs"       => EcsCodec.encodeIdSet(w#mobs),
            "player"     => EcsCodec.encodeIdOption(w#player),
            "score"      => int(w#score),
            "phase"      => JString(phaseToStr(w#phase)),
            "timers"     => encodeTimers(w#timers),
            "nextId"     => int(w#nextId)
        })

    pub def decodeWorld(json: Json): Option[World] =
        match JsonCodec.expectObject(json) {
            case None      => None
            case Some(obj) => decodeWorldObj(obj)
        }

    def decodeWorldObj(obj: Map[String, Json]): Option[World] =
        // player は欠落/false で None になる lenient フィールドなので forM の外で取る。
        let player = Map.get("player", obj) |> Option.flatMap(EcsCodec.decodeIdOption);
        forM (
            posJ    <- Map.get("positions", obj);  positions  <- EcsCodec.decodeStore(JsonCodec.decodeVec2, posJ);
            velJ    <- Map.get("velocities", obj); velocities <- EcsCodec.decodeStore(JsonCodec.decodeVec2, velJ);
            sprJ    <- Map.get("sprites", obj);    sprites    <- EcsCodec.decodeStore(decodeSprite, sprJ);
            colJ    <- Map.get("colliders", obj);  colliders  <- EcsCodec.decodeStore(decodeCollider, colJ);
            mobsJ   <- Map.get("mobs", obj);       mobs       <- EcsCodec.decodeIdSet(mobsJ);
            score   <- getInt("score", obj);
            phaseS  <- getStr("phase", obj);
            timersJ <- Map.get("timers", obj);     timers     <- decodeTimers(timersJ);
            nextId  <- getInt("nextId", obj)
        ) yield buildWorld(positions, velocities, sprites, colliders, mobs, player,
                           score, strToPhase(phaseS), timers, nextId)

    def buildWorld(positions: Map[EntityId, Vec2.Vec2], velocities: Map[EntityId, Vec2.Vec2],
                   sprites: Map[EntityId, SpriteComp], colliders: Map[EntityId, Collision.Collider],
                   mobs: Set[EntityId], player: Option[EntityId], score: Int32,
                   phase: GamePhase, timers: Timers, nextId: Int32): World =
        let World.World(w) = World.empty();
        // HUD は器を再構築（hudSyncSystem が中身を整える）。transient 入力は empty の既定のまま。
        World.World({
            positions = positions, velocities = velocities, sprites = sprites, colliders = colliders,
            mobs = mobs, player = player, score = score, phase = phase, timers = timers,
            nextId = nextId, huds = World.standardHuds()
            | w
        })

    // ── phase / timers ──

    def phaseToStr(p: GamePhase): String = match p {
        case GamePhase.Menu     => "menu"
        case GamePhase.Playing  => "playing"
        case GamePhase.GameOver => "gameover"
    }

    def strToPhase(s: String): GamePhase = match s {
        case "playing"  => GamePhase.Playing
        case "gameover" => GamePhase.GameOver
        case _          => GamePhase.Menu
    }

    def encodeTimers(t: Timers): Json =
        JObject(Map#{ "mobSpawn" => num(t#mobSpawn), "score" => num(t#score),
                      "startDelay" => num(t#startDelay), "gameOverMsg" => num(t#gameOverMsg),
                      "title" => num(t#title) })

    def decodeTimers(j: Json): Option[Timers] =
        forM (
            obj <- JsonCodec.expectObject(j);
            a   <- getFloat("mobSpawn", obj);
            b   <- getFloat("score", obj);
            c   <- getFloat("startDelay", obj);
            d   <- getFloat("gameOverMsg", obj);
            e   <- getFloat("title", obj)
        ) yield {mobSpawn = a, score = b, startDelay = c, gameOverMsg = d, title = e}

    // ── SpriteComp ──

    def encodeSprite(sc: SpriteComp): Json =
        JObject(Map#{
            "clips"      => JsonCodec.encodeStringMap(fs -> JsonCodec.encodeList(f -> JString(f), fs), sc#clips),
            "current"    => JString(sc#current),
            "frame"      => int(sc#frame),
            "frameTimer" => num(sc#frameTimer),
            "fps"        => num(sc#fps),
            "flipH"      => JBool(sc#flipH),
            "flipV"      => JBool(sc#flipV)
        })

    def decodeSprite(j: Json): Option[SpriteComp] =
        forM (
            obj        <- JsonCodec.expectObject(j);
            clipsJ     <- Map.get("clips", obj);
            clips      <- JsonCodec.decodeStringMap(fj -> JsonCodec.decodeList(JsonCodec.expectString, fj), clipsJ);
            current    <- getStr("current", obj);
            frame      <- getInt("frame", obj);
            frameTimer <- getFloat("frameTimer", obj);
            fps        <- getFloat("fps", obj);
            flipH      <- getBool("flipH", obj);
            flipV      <- getBool("flipV", obj)
        ) yield {clips = clips, current = current, frame = frame, frameTimer = frameTimer,
                 fps = fps, flipH = flipH, flipV = flipV}

    // ── Collider / CollisionShape2D ──

    def encodeCollider(c: Collision.Collider): Json =
        JObject(Map#{ "shape" => encodeShape(c#shape), "layer" => int(c#layer), "mask" => int(c#mask) })

    def decodeCollider(j: Json): Option[Collision.Collider] =
        forM (
            obj    <- JsonCodec.expectObject(j);
            shapeJ <- Map.get("shape", obj);
            shape  <- decodeShape(shapeJ);
            layer  <- getInt("layer", obj);
            mask   <- getInt("mask", obj)
        ) yield {shape = shape, layer = layer, mask = mask}

    def encodeShape(s: CollisionShape2D): Json = match s {
        case CollisionShape2D.CircleShape2D(c) =>
            JObject(Map#{ "type" => JString("circle"), "radius" => num(c#radius) })
        case CollisionShape2D.RectShape2D(r) =>
            JObject(Map#{ "type" => JString("rect"), "width" => num(r#width), "height" => num(r#height) })
        case CollisionShape2D.CapsuleShape2D(c) =>
            JObject(Map#{ "type" => JString("capsule"), "radius" => num(c#radius),
                          "height" => num(c#height), "vertical" => JBool(c#vertical) })
    }

    def decodeShape(j: Json): Option[CollisionShape2D] =
        match JsonCodec.expectObject(j) {
            case None      => None
            case Some(obj) => decodeShapeObj(obj)
        }

    def decodeShapeObj(obj: Map[String, Json]): Option[CollisionShape2D] =
        match getStr("type", obj) {
            case Some("circle") =>
                getFloat("radius", obj) |> Option.map(r -> CollisionShape2D.CircleShape2D({radius = r}))
            case Some("rect") =>
                forM (w <- getFloat("width", obj); h <- getFloat("height", obj))
                    yield CollisionShape2D.RectShape2D({width = w, height = h})
            case Some("capsule") =>
                forM (r <- getFloat("radius", obj); h <- getFloat("height", obj); v <- getBool("vertical", obj))
                    yield CollisionShape2D.CapsuleShape2D({radius = r, height = h, vertical = v})
            case _ => None
        }
}
