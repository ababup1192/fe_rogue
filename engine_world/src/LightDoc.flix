// LightDoc — light.json（光源の質感）の宣言ドキュメント層。
// 「暗さ・照り返しフチ・ハロの大きさ・光源の並び」を JSON に書き、Spec（pure data）へ畳む。
// occluders（壁の遮蔽ポリゴン）は含めない — 壁はゲームの World が持つ形であって、
// json は光の質感パラメータだけを持つ、という分業のため（items へ渡す SceneLightConfig の
// occluders/viewport/glow/z はゲーム側が Spec.toConfig で自分の値を足して組み立てる）。
// light#at も json の値は初期値の扱いで、実行時は World（プレイヤー位置等）が上書きしてよい。
//
// 語彙（version 1）: トップレベルの darkness / rim / haloDiameterFactor / lights は全て
// optional（省略時は Light.defaultXxx 相当の既定値）。色表記は ui.json と同じ
// （UiDoc.colorOf に一本化。#rrggbb / {"hsv":...} / {"rgb":...}）。
// "version" / "$schema" / "note" / "//" キーは fx.json / ui.json と同じ扱い。
//
// エラーはノードのパス付き（例: `at lights[0]: 'radius' is required`）— fx/ui と同じ流儀で
// 手書きドキュメントの編集箇所へ誘導する。
mod LightDoc {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JNumber}
    use Util.Json.JsonError
    use JsonCompat.PathTag.Root

    // ========================================================================
    // 型（pure data）
    // ========================================================================

    /// 1 光源ぶんの宣言。at は初期位置（実行時に World の値で上書きしてよい）。
    pub type alias LightSpec = { at = Vec2.Vec2, radius = Float64, color = Color, halo = Float64 }

    /// ドキュメント全体。darkness/rim/haloDiameterFactor は Light.SceneLightConfig の
    /// 同名フィールドへそのまま流し込む値。
    pub type alias Spec = {
        darkness = Float64,
        rimWidth = Float64, rimStrength = Float64,
        haloDiameterFactor = Float64,
        lights = List[LightSpec],
        note = Option[String]
    }

    /// 全フィールド省略時の既定値（lights=Nil の「今は光源なし」ドキュメントも許す —
    /// FxDoc/UiDoc と違い「空文書を弾く」検査はしない。暗闇だけの演出も正当なため）。
    pub def empty(): Spec =
        { darkness = defaultDarkness(),
          rimWidth = Shadow.defaultRimWidth(), rimStrength = Shadow.defaultRimStrength(),
          haloDiameterFactor = Light.defaultHaloDiameterFactor(),
          lights = Nil, note = None }

    // ========================================================================
    // parse（純粋）
    // ========================================================================

    /// ドキュメントを Spec へ畳む。
    pub def parse(json: Json): Result[JsonError, Spec] =
        match json {
            case JObject(top) => forM (
                _v         <- JsonCompat.checkVersion("light document", top);
                darkness   <- JsonCompat.atNode("(root)", JsonCompat.numOr("darkness", defaultDarkness(), top));
                rim        <- parseRim(top);
                factorOpt  <- JsonCompat.atNode("(root)", (JsonCompat.getAtKeyOpt(Root, "haloDiameterFactor", top): Result[JsonError, Option[Float64]]));
                note       <- (JsonCompat.getAtKeyOpt(Root, "note", top): Result[JsonError, Option[String]]);
                lights     <- parseLights(top)
            ) yield ({
                darkness = darkness,
                rimWidth = rim#width, rimStrength = rim#strength,
                haloDiameterFactor = Option.getWithDefault(Light.defaultHaloDiameterFactor(), factorOpt),
                lights = lights, note = note
            }: Spec)
            case _ => Err(JsonCompat.jsonError(Root, Set#{"LightDoc must be a JSON object"}))
        }

    /// mask 全体の暗さの既定値（Light.SingleLightConfig の doc と同じ既定 0.95 に揃える）。
    def defaultDarkness(): Float64 = 0.95

    /// "rim": {"width": px, "strength": alpha}（省略時は Shadow.defaultRimWidth/Strength）。
    def parseRim(top: Map[String, Json]): Result[JsonError, { width = Float64, strength = Float64 }] =
        match (JsonCompat.getAtKeyOpt(Root, "rim", top): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok({ width = Shadow.defaultRimWidth(), strength = Shadow.defaultRimStrength() })
            case Ok(Some(m)) => JsonCompat.atNode("rim", forM (
                width    <- JsonCompat.numOr("width", Shadow.defaultRimWidth(), m);
                strength <- JsonCompat.numOr("strength", Shadow.defaultRimStrength(), m)
            ) yield { width = width, strength = strength })
        }

    /// "lights": [...]（省略時は空 = 光源なし）。
    def parseLights(top: Map[String, Json]): Result[JsonError, List[LightSpec]] =
        match Map.get("lights", top) {
            case None              => Ok(Nil)
            case Some(JArray(arr)) =>
                Result.traverse(entry -> {
                    let (i, json) = entry;
                    forM (
                        m     <- JsonCompat.atNode("lights[${i}]", JsonCompat.asObject("light", json));
                        light <- parseLight("lights[${i}]", m)
                    ) yield light
                }, List.zipWithIndex(Vector.toList(arr)))
            case Some(_) => Err(JsonCompat.jsonError(Root, Set#{"'lights' must be an array"}))
        }

    /// 1 光源: at（必須 [x,y]）/ radius（必須）/ color（必須）/ halo（省略時 Shadow 系と
    /// 同じ「既定の目安」ではなく、光の演出値なので 0.35 を素朴な既定にする）。
    def parseLight(path: String, m: Map[String, Json]): Result[JsonError, LightSpec] =
        JsonCompat.atNode(path, forM (
            at      <- parseVec2("at", m);
            radius  <- JsonCompat.numAt("radius", m);
            _r      <- require(radius > 0.0, "radius must be > 0 (got: ${radius})");
            color   <- parseColorRequired("color", m);
            halo    <- JsonCompat.numOr("halo", defaultHalo(), m);
            _h      <- require(halo >= 0.0 and halo <= 1.0, "halo must be within 0..1 (got: ${halo})")
        ) yield ({ at = at, radius = radius, color = color, halo = halo }: LightSpec))

    /// halo 省略時の既定値（View.lanternLight 等の実運用値に合わせた素朴な目安）。
    def defaultHalo(): Float64 = 0.35

    def require(ok: Bool, msg: String): Result[JsonError, Unit] =
        if (ok) Ok(()) else Err(JsonCompat.jsonError(Root, Set#{msg}))

    /// "key": [x, y] を Vec2 へ（必須）。
    def parseVec2(key: String, m: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        match (JsonCompat.getAtKey(Root, key, m): Result[JsonError, List[Float64]]) {
            case Err(e)            => Err(e)
            case Ok(x :: y :: Nil) => Ok({x = x, y = y})
            case Ok(_)             => Err(JsonCompat.jsonError(Root, Set#{"${key} must be [x, y]"}))
        }

    /// 色（必須）。色表記は ui.json と同一 — UiDoc.colorOf に一本化（palette 参照 "@name" は
    /// light.json には無いので空パレットで呼ぶ）。
    def parseColorRequired(key: String, m: Map[String, Json]): Result[JsonError, Color] =
        match Map.get(key, m) {
            case None       => Err(JsonCompat.jsonError(Root, Set#{"'${key}' is required"}))
            case Some(json) => UiDoc.colorOf(Map.empty(), key, json)
        }

    // ========================================================================
    // Spec → Light.SceneLightConfig
    // ========================================================================

    /// Spec の質感パラメータに、ゲーム側が持つ occluders/viewport/glow/z を足して
    /// Light.SceneLightConfig を組む。at はゲーム側の runtimeLights で丸ごと差し替え可能
    /// （json の lights はエディタ確認用の初期値、実行中は World の光源位置が正）。
    pub def toConfig(spec: Spec, ctx: { occluders = List[List[Vec2.Vec2]], viewport = Vec2.Vec2,
                                        glow = Light.GlowAssets, z = Int32 }): Light.SceneLightConfig =
        { lights = List.map(lightOf, spec#lights), occluders = ctx#occluders,
          viewport = ctx#viewport, glow = ctx#glow,
          darkness = spec#darkness, z = ctx#z,
          rimWidth = spec#rimWidth, rimStrength = spec#rimStrength,
          haloDiameterFactor = spec#haloDiameterFactor }

    /// toConfig と同じだが、lights を丸ごと runtimeLights に差し替える
    /// （「json は質感、位置はゲーム」の分業口 — World が持つ光源位置をここへ渡す）。
    pub def toConfigWithLights(spec: Spec, runtimeLights: List[Light.Light],
                               ctx: { occluders = List[List[Vec2.Vec2]], viewport = Vec2.Vec2,
                                     glow = Light.GlowAssets, z = Int32 }): Light.SceneLightConfig =
        let base = toConfig(spec, ctx);
        { lights = runtimeLights | base }

    def lightOf(l: LightSpec): Light.Light =
        { at = l#at, radius = l#radius, color = l#color, halo = l#halo }

    // ========================================================================
    // load（ファイル読み — parse は純粋なまま、IO はここだけ）
    // ========================================================================

    /// path を読んで Spec にする。JsonCompat.readJson と同じ fail 経路
    /// （読めない・崩れているときは Err）。
    pub def load(path: String): Result[JsonError, Spec] \ Fs.FileRead =
        JsonCompat.readJson(path) |> Result.flatMap(parse)
}
