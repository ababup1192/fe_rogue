/// WorldDump — F8 注釈チケットに同梱する world.json の本文を組む純粋モジュール。
/// リモートデバッグの view=full も同じ本文を返す。
///
/// annotation.json（絵の側の事実）に対して、こちらはシムの側の事実を残す:
/// プレイヤーの運動学とジャンプ用タイマーの生値・調整中のパラメータ全値（F8 チケットに
/// チューニング状態が焼き込まれる）・地形の一覧・注釈で囲った場所に何があるか・直近の出来事。
/// 「見た目」と「シムの状態」のどちらが食い違っているかを、チケットだけで切り分けられるようにする。
mod WorldDump {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool}

    /// 注釈の矩形（デザイン座標）と表示中の World から world.json の本文を組む。
    /// App.withWorldDump に繋ぐ入口。
    pub def dump(rect: Rect2.Rect2, world: Field.World): String =
        let obj = JObject(Map#{
            "player"          => playerJson(world#player),
            "params"          => paramsJson(world#params),
            "platforms"       => JArray(world#platforms |> List.map(platformJson) |> List.toVector),
            "enemies"         => JArray(world#enemies |> List.map(enemyJson(world#time)) |> List.toVector),
            "rect"            => rectJson(rect),
            "platformsInRect" => JArray(world#platforms
                                     |> List.filter(platform -> intersects(rect, platform))
                                     |> List.map(platform -> JNumber(JsonCodec.intToBd(platform#id)))
                                     |> List.toVector),
            "playerInRect"    => JBool(Rect2.hasPoint(world#player#pos, rect)),
            "eventLog"        => JArray(world#eventLog |> List.map(logJson) |> List.toVector),
            "deaths"          => JNumber(JsonCodec.intToBd(world#deaths)),
            "camX"            => num(world#camX),
            "camY"            => num(world#camY),
            "levelH"          => num(world#levelH),
            "goalX"           => num(world#goalX),
            "respawnX"        => num(world#respawnPos#x),
            "checkpointX"     => num(world#checkpointPos#x),
            "cleared"         => JBool(not Option.isEmpty(world#clearedAt)),
            "freezeLeft"      => num(world#freezeLeft),
            "time"            => num(world#time)
        });
        Util.Json.toPrettyString(2, obj)

    /// 運動学とタイマーの生値。coyote/buffer は残り秒（0 = 切れている）。
    def playerJson(player: Field.Player): Json =
        JObject(Map#{
            "pos"        => vecJson(player#pos),
            "vel"        => vecJson(player#vel),
            "grounded"   => JBool(player#grounded),
            "coyoteLeft" => num(player#coyoteLeft),
            "bufferLeft" => num(player#bufferLeft),
            "jumpHeld"   => JBool(player#jumpHeld),
            "dropLeft"   => num(player#dropLeft),
            "riding"     => JNumber(JsonCodec.intToBd(player#ridingId |> Option.getWithDefault(-1)))
        })

    /// いま効いているパラメータ全値（F1 で差し替え中でもチケットに正確に残る）。
    def paramsJson(p: GameParameters.Params): Json =
        JObject(Map#{
            "jumpHeight"      => num(p#jumpHeight),
            "timeToApex"      => num(p#timeToApex),
            "fallGravityMult" => num(p#fallGravityMult),
            "apexBand"        => num(p#apexBand),
            "apexGravityMult" => num(p#apexGravityMult),
            "cutMult"         => num(p#cutMult),
            "maxFallSpeed"    => num(p#maxFallSpeed),
            "maxRunSpeed"     => num(p#maxRunSpeed),
            "dashMult"        => num(p#dashMult),
            "dashAccel"       => num(p#dashAccel),
            "groundAccel"     => num(p#groundAccel),
            "groundDecel"     => num(p#groundDecel),
            "skidDecel"       => num(p#skidDecel),
            "airAccel"        => num(p#airAccel),
            "airDecel"        => num(p#airDecel),
            "coyoteTime"      => num(p#coyoteTime),
            "bufferTime"      => num(p#bufferTime),
            "jumpSpeedBonus"  => num(p#jumpSpeedBonus),
            "stompBounce"     => num(p#stompBounce),
            "stompBounceHold" => num(p#stompBounceHold)
        })

    def platformJson(platform: Field.Platform): Json =
        JObject(Map#{
            "id"     => JNumber(JsonCodec.intToBd(platform#id)),
            "x"      => num(platform#pos#x),
            "y"      => num(platform#pos#y),
            "w"      => num(platform#size#x),
            "h"      => num(platform#size#y),
            "top"    => num(platform#pos#y - platform#size#y / 2.0),
            "oneWay" => JBool(platform#oneWay),
            "moving" => JBool(not Option.isEmpty(platform#motion)),
            "slope"  => JString(match platform#slope {
                case Some(true)  => "right"
                case Some(false) => "left"
                case None        => "none"
            })
        })

    /// 敵 1 体。x/y は表示中の時刻の実位置（チケットの絵と突き合わせられるように）。
    def enemyJson(time: Float64, enemy: Field.Enemy): Json =
        let pos = Field.enemyPosAt(time, enemy);
        JObject(Map#{
            "id"    => JNumber(JsonCodec.intToBd(enemy#id)),
            "kind"  => JString(Field.enemyKindName(enemy#kind)),
            "x"     => num(pos#x),
            "y"     => num(pos#y),
            "alive" => JBool(enemy#alive)
        })

    def logJson(entry: (Float64, String)): Json =
        let (time, name) = entry;
        JObject(Map#{ "t" => num(time), "event" => JString(name) })

    /// 注釈の矩形と地形（中心とサイズの AABB）が重なるか。
    def intersects(rect: Rect2.Rect2, platform: Field.Platform): Bool =
        let rectEnd = Rect2.end(rect);
        let halfW = platform#size#x / 2.0;
        let halfH = platform#size#y / 2.0;
        platform#pos#x + halfW >= rect#position#x and platform#pos#x - halfW <= rectEnd#x
        and platform#pos#y + halfH >= rect#position#y and platform#pos#y - halfH <= rectEnd#y

    def rectJson(rect: Rect2.Rect2): Json =
        JObject(Map#{
            "x" => num(rect#position#x), "y" => num(rect#position#y),
            "w" => num(rect#size#x),     "h" => num(rect#size#y)
        })

    def vecJson(v: Vec2.Vec2): Json =
        JObject(Map#{ "x" => num(v#x), "y" => num(v#y) })

    def num(v: Float64): Json = JNumber(JsonCodec.floatToBd(v))
}
