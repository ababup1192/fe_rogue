// UiSpec — UI ツリーの宣言層（ui.json のパース・生成）
//
// ui.json は「テンプレート + 上書き」方式で UI ノード木を記述する。テンプレートは
// 既定値のまとまりで、各ノードが `use` で参照し、ノード側のフィールドで上書き（パッチ）する。
// parse はファイル内容を受け取らず純粋に Json → Spec（テンプレ解決済みノード木）へ畳む。
// load だけがファイルを読む（SceneLoader と同じ読み方）。
//
// spawnRoot は Spec の各ノードを UiStore.alloc で採番し、parents/order/styles/boxes/texts/
// sprites/visible/bindings/metas/names を登録する。名前パスは "root/child/..." 形式。
// respawn は despawnRoot で spec 由来 store を捨ててから spawnRoot し直す（selection/focus は
// String キーなので生き残る）。

mod UiSpec {
    import java.math.BigDecimal
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber}
    use Util.Json.JsonError
    use JsonCompat.PathTag.Root

    /// ノードの描画種別。box=単色矩形、text=テキスト、sprite=スプライト、poly=塗り潰し多角形、
    /// none=描画を持たないレイアウト専用コンテナ。
    pub enum Widget with Eq {
        case BoxW
        case TextW
        case SpriteW
        case PolyW
        case NoneW
    }

    /// テンプレート解決済みの UI ノード。ツリーは children で再帰する。
    /// `name`: 兄弟内で一意な識別名（名前パスの構成要素）。
    /// `widget`: 描画種別。`style`: レイアウト属性。
    /// `box`/`text`/`sprite`/`poly`: widget に対応する描画コンポーネント（それ以外は None）。
    /// `visible`: 初期可視。`binding`: text 流し込み先の bind key。
    /// `meta`: メニュー項目等の識別 metadata。`layer`: root の描画レイヤ（非 root では無視）。
    /// `children`: 子ノード（宣言順）。
    pub enum Spec {
        case Spec({
            name     = String,
            widget   = Widget,
            style    = UiLayout.Style,
            box      = Option[UiWidget.BoxComp],
            text     = Option[UiWidget.TextComp],
            sprite   = Option[UiWidget.SpriteComp],
            poly     = Option[UiWidget.PolyComp],
            visible  = Bool,
            binding  = Option[String],
            meta     = Option[String],
            layer    = Int32,
            children = List[Spec]
        })
    }

    // ========================================================================
    // parse（純粋）
    // ========================================================================

    /// ui.json（templates + root）を Spec へ畳む。root が無い / JSON Object でない場合は Err。
    pub def parse(json: Json): Result[JsonError, Spec] =
        match json {
            case JObject(topMap) => forM (
                templates <- parseTemplates(topMap);
                rootMap   <- (JsonCompat.getAtKey(Root, "root", topMap): Result[JsonError, Map[String, Json]]);
                spec      <- parseNode(templates, rootMap)
            ) yield spec
            case _ => Err(JsonCompat.jsonError(Root, Set#{"UiSpec must be a JSON object with a 'root'"}))
        }

    /// "templates" を「テンプレート名 → 部分ノード map」の辞書へ変換する。キー欠落は空辞書。
    /// 各テンプレート値は JSON Object でなければならない。
    def parseTemplates(topMap: Map[String, Json]): Result[JsonError, Map[String, Map[String, Json]]] =
        match (JsonCompat.getAtKeyOpt(Root, "templates", topMap): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok(Map.empty())
            case Ok(Some(m)) =>
                Map.foldLeftWithKey((acc, name, json) -> forM (
                    sofar <- acc;
                    tmap  <- asObject("template '${name}'", json)
                ) yield Map.insert(name, tmap, sofar), Ok(Map.empty()), m)
        }

    /// 1 ノードを Spec へ変換する。`use` があればテンプレ値を既定にノード値で上書き合成する。
    def parseNode(templates: Map[String, Map[String, Json]], nodeMap: Map[String, Json]): Result[JsonError, Spec] =
        forM (
            merged       <- resolveTemplate(templates, nodeMap);
            name         <- (JsonCompat.getAtKey(Root, "name", merged): Result[JsonError, String]);
            _validName   <- validateName(name);
            widgetStrOpt <- (JsonCompat.getAtKeyOpt(Root, "widget", merged): Result[JsonError, Option[String]]);
            widget       <- parseWidget(widgetStrOpt);
            style        <- parseStyle(merged);
            box          <- parseBox(widget, merged);
            text         <- parseText(widget, merged);
            sprite       <- parseSprite(widget, merged);
            poly         <- parsePoly(widget, merged);
            visibleOpt   <- (JsonCompat.getAtKeyOpt(Root, "visible", merged): Result[JsonError, Option[Bool]]);
            bindingOpt   <- (JsonCompat.getAtKeyOpt(Root, "bind", merged): Result[JsonError, Option[String]]);
            metaOpt      <- (JsonCompat.getAtKeyOpt(Root, "meta", merged): Result[JsonError, Option[String]]);
            layerOpt     <- (JsonCompat.getAtKeyOpt(Root, "layer", merged): Result[JsonError, Option[Int32]]);
            children     <- parseChildren(templates, merged);
            _uniq        <- ensureUniqueNames(children)
        ) yield Spec.Spec({
            name = name, widget = widget, style = style,
            box = box, text = text, sprite = sprite, poly = poly,
            visible = Option.getWithDefault(true, visibleOpt),
            binding = bindingOpt, meta = metaOpt,
            layer = Option.getWithDefault(0, layerOpt),
            children = children
        })

    /// `use` を解決してテンプレ map の上にノード map を重ねる（ノード側が勝つ）。
    /// `use` が指す名が未定義なら Err。`use` が無ければノード map をそのまま使う。
    def resolveTemplate(templates: Map[String, Map[String, Json]], nodeMap: Map[String, Json]): Result[JsonError, Map[String, Json]] =
        match (JsonCompat.getAtKeyOpt(Root, "use", nodeMap): Result[JsonError, Option[String]]) {
            case Err(e)          => Err(e)
            case Ok(None)        => Ok(nodeMap)
            case Ok(Some(tname)) => match Map.get(tname, templates) {
                case None       => Err(JsonCompat.jsonError(Root, Set#{"unknown template: ${tname}"}))
                case Some(tmap) => Ok(mergeNode(tmap, nodeMap))
            }
        }

    /// base の各キーに over を重ねる。同名キーは over（ノード側）で上書きする。
    def mergeNode(base: Map[String, Json], over: Map[String, Json]): Map[String, Json] =
        Map.foldLeftWithKey((acc, key, value) -> Map.insert(key, value, acc), base, over)

    /// "widget" 文字列を Widget へ。キー欠落は none（レイアウト専用）。未知値は Err。
    def parseWidget(opt: Option[String]): Result[JsonError, Widget] =
        match opt {
            case None           => Ok(Widget.NoneW)
            case Some("box")    => Ok(Widget.BoxW)
            case Some("text")   => Ok(Widget.TextW)
            case Some("sprite") => Ok(Widget.SpriteW)
            case Some("poly")   => Ok(Widget.PolyW)
            case Some("none")   => Ok(Widget.NoneW)
            case Some(unknown)  => Err(JsonCompat.jsonError(Root, Set#{"unknown widget (got: ${unknown})"}))
        }

    /// 子ノード列を宣言順に変換する。"children" 欠落は空。配列でなければ Err。
    def parseChildren(templates: Map[String, Map[String, Json]], map: Map[String, Json]): Result[JsonError, List[Spec]] =
        match Map.get("children", map) {
            case None            => Ok(Nil)
            case Some(JArray(arr)) => Result.traverse(child -> parseChildJson(templates, child), Vector.toList(arr))
            case Some(_)         => Err(JsonCompat.jsonError(Root, Set#{"children must be an array"}))
        }

    /// 子 1 件（JSON Object）を Spec へ。Object でなければ Err。
    def parseChildJson(templates: Map[String, Map[String, Json]], json: Json): Result[JsonError, Spec] =
        forM (m <- asObject("child", json); spec <- parseNode(templates, m)) yield spec

    /// name が名前パス機構を壊さないことを確認する。空文字、または区切り文字 "/" を含めば Err。
    /// 名前パスは "root/child/..." を "/" で連結するため、name 内の "/" は木構造を曖昧にする。
    def validateName(name: String): Result[JsonError, Unit] =
        if (name == "")
            Err(JsonCompat.jsonError(Root, Set#{"node name must not be empty"}))
        else if (String.contains(substr = "/", name))
            Err(JsonCompat.jsonError(Root, Set#{"node name must not contain '/' (got: ${name})"}))
        else Ok(())

    /// 兄弟の name が全て相異なることを確認する。重複があれば Err。
    def ensureUniqueNames(children: List[Spec]): Result[JsonError, Unit] =
        let names = List.map(child -> nameOf(child), children);
        if (List.length(names) == Set.size(List.toSet(names))) Ok(())
        else Err(JsonCompat.jsonError(Root, Set#{"sibling names must be unique (got: ${names})"}))

    // ========================================================================
    // スタイル解析
    // ========================================================================

    /// レイアウト属性を解析する。未指定フィールドは defaultStyle 相当の既定を使う。
    def parseStyle(map: Map[String, Json]): Result[JsonError, UiLayout.Style] =
        forM (
            dirOpt   <- (JsonCompat.getAtKeyOpt(Root, "dir", map): Result[JsonError, Option[String]]);
            dir      <- parseDir(dirOpt);
            gapOpt   <- (JsonCompat.getAtKeyOpt(Root, "gap", map): Result[JsonError, Option[Float64]]);
            pad      <- parsePad(map);
            width    <- parseSizeSpec("width", map);
            height   <- parseSizeSpec("height", map);
            mainOpt  <- (JsonCompat.getAtKeyOpt(Root, "mainAlign", map): Result[JsonError, Option[String]]);
            main     <- parseMainAlign(mainOpt);
            crossOpt <- (JsonCompat.getAtKeyOpt(Root, "crossAlign", map): Result[JsonError, Option[String]]);
            cross    <- parseCrossAlign(crossOpt);
            abs      <- parseAbs(map)
        ) yield ({
            dir = dir, gap = Option.getWithDefault(0.0, gapOpt),
            padLeft = pad#l, padTop = pad#t, padRight = pad#r, padBottom = pad#b,
            width = width, height = height,
            mainAlign = main, crossAlign = cross,
            abs = abs
        }: UiLayout.Style)

    /// "dir" を主軸方向へ。欠落は Column。未知値は Err。
    def parseDir(opt: Option[String]): Result[JsonError, UiLayout.Dir] =
        match opt {
            case None           => Ok(UiLayout.Dir.Column)
            case Some("row")    => Ok(UiLayout.Dir.Row)
            case Some("column") => Ok(UiLayout.Dir.Column)
            case Some(unknown)  => Err(JsonCompat.jsonError(Root, Set#{"dir must be row|column (got: ${unknown})"}))
        }

    /// "mainAlign" を主軸寄せへ。欠落は Start。未知値は Err。
    def parseMainAlign(opt: Option[String]): Result[JsonError, UiLayout.MainAlign] =
        match opt {
            case None                 => Ok(UiLayout.MainAlign.Start)
            case Some("start")        => Ok(UiLayout.MainAlign.Start)
            case Some("center")       => Ok(UiLayout.MainAlign.Center)
            case Some("end")          => Ok(UiLayout.MainAlign.End)
            case Some("spaceBetween") => Ok(UiLayout.MainAlign.SpaceBetween)
            case Some(unknown)        => Err(JsonCompat.jsonError(Root, Set#{"mainAlign unknown (got: ${unknown})"}))
        }

    /// "crossAlign" を交差軸寄せへ。欠落は Start。未知値は Err。
    def parseCrossAlign(opt: Option[String]): Result[JsonError, UiLayout.CrossAlign] =
        match opt {
            case None            => Ok(UiLayout.CrossAlign.Start)
            case Some("start")   => Ok(UiLayout.CrossAlign.Start)
            case Some("center")  => Ok(UiLayout.CrossAlign.Center)
            case Some("end")     => Ok(UiLayout.CrossAlign.End)
            case Some("stretch") => Ok(UiLayout.CrossAlign.Stretch)
            case Some(unknown)   => Err(JsonCompat.jsonError(Root, Set#{"crossAlign unknown (got: ${unknown})"}))
        }

    /// "pad": [left, top, right, bottom] を展開する。欠落は全 0。要素数が 4 でなければ Err。
    def parsePad(map: Map[String, Json]): Result[JsonError, {l = Float64, t = Float64, r = Float64, b = Float64}] =
        match (JsonCompat.getAtKeyOpt(Root, "pad", map): Result[JsonError, Option[List[Float64]]]) {
            case Err(e)                       => Err(e)
            case Ok(None)                     => Ok({l = 0.0, t = 0.0, r = 0.0, b = 0.0})
            case Ok(Some(left :: top :: right :: bottom :: Nil)) => Ok({l = left, t = top, r = right, b = bottom})
            case Ok(Some(_))                  => Err(JsonCompat.jsonError(Root, Set#{"pad must be [left, top, right, bottom]"}))
        }

    /// "abs": [x, y] をフロー外オフセットへ。欠落は None（フロー内）。要素数が 2 でなければ Err。
    def parseAbs(map: Map[String, Json]): Result[JsonError, Option[Vec2.Vec2]] =
        match (JsonCompat.getAtKeyOpt(Root, "abs", map): Result[JsonError, Option[List[Float64]]]) {
            case Err(e)                  => Err(e)
            case Ok(None)                => Ok(None)
            case Ok(Some(x :: y :: Nil)) => Ok(Some({x = x, y = y}))
            case Ok(Some(_))             => Err(JsonCompat.jsonError(Root, Set#{"abs must be [x, y]"}))
        }

    /// "width"/"height" を SizeSpec へ。欠落は Auto。数値は Px、"auto"=Auto、"grow"=Grow(1)。
    def parseSizeSpec(key: String, map: Map[String, Json]): Result[JsonError, UiLayout.SizeSpec] =
        match Map.get(key, map) {
            case None                => Ok(UiLayout.SizeSpec.Auto)
            case Some(JString("auto")) => Ok(UiLayout.SizeSpec.Auto)
            case Some(JString("grow")) => Ok(UiLayout.SizeSpec.Grow(1.0))
            case Some(JNumber(bd))   => Ok(UiLayout.SizeSpec.Px(bigDecToF64(bd)))
            case Some(_)             => Err(JsonCompat.jsonError(Root, Set#{"${key} must be a number, \"auto\", or \"grow\""}))
        }

    // ========================================================================
    // 描画コンポーネント解析
    // ========================================================================

    /// box ノードの BoxComp。color は必須（"#rrggbb"）、alpha 既定 1.0、zIndex 既定 0。
    /// cornerRadius 既定 0.0、borderWidth 既定 0.0、borderColor 既定 白。
    def parseBox(widget: Widget, map: Map[String, Json]): Result[JsonError, Option[UiWidget.BoxComp]] =
        match widget {
            case Widget.BoxW => forM (
                color            <- parseHexColor("color", map);
                alphaOpt         <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[JsonError, Option[Float64]]);
                zIndexOpt        <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
                cornerRadiusOpt  <- (JsonCompat.getAtKeyOpt(Root, "cornerRadius", map): Result[JsonError, Option[Float64]]);
                borderWidthOpt   <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", map): Result[JsonError, Option[Float64]]);
                borderColorOpt   <- parseHexColorOpt("borderColor", map)
            ) yield Some(({
                color = color,
                alpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, alphaOpt)),
                zIndex = Option.getWithDefault(0, zIndexOpt),
                cornerRadius = Option.getWithDefault(0.0, cornerRadiusOpt),
                borderWidth = Option.getWithDefault(0.0, borderWidthOpt),
                borderColor = Option.getWithDefault(white(), borderColorOpt)
            }: UiWidget.BoxComp))
            case _ => Ok(None)
        }

    /// text ノードの TextComp。text 既定 ""、font 既定 "ui"、fontSize 既定 8.0、
    /// tint 既定 白、zIndex 既定 0。bind のみのノードは text 空で始まり実行時に流し込む。
    def parseText(widget: Widget, map: Map[String, Json]): Result[JsonError, Option[UiWidget.TextComp]] =
        match widget {
            case Widget.TextW => forM (
                textOpt     <- (JsonCompat.getAtKeyOpt(Root, "text", map): Result[JsonError, Option[String]]);
                fontOpt     <- (JsonCompat.getAtKeyOpt(Root, "font", map): Result[JsonError, Option[String]]);
                fontSizeOpt <- (JsonCompat.getAtKeyOpt(Root, "fontSize", map): Result[JsonError, Option[Float64]]);
                tintOpt     <- parseHexColorOpt("tint", map);
                zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]])
            ) yield Some(({
                text = Option.getWithDefault("", textOpt),
                font = Option.getWithDefault("ui", fontOpt),
                fontSize = Option.getWithDefault(8.0, fontSizeOpt),
                tint = Option.getWithDefault(white(), tintOpt),
                zIndex = Option.getWithDefault(0, zIndexOpt)
            }: UiWidget.TextComp))
            case _ => Ok(None)
        }

    /// sprite ノードの SpriteComp。texture は必須。regionRect 既定 None、scale 既定 [1,1]、
    /// flipH/flipV 既定 false、tint 既定 白、zIndex 既定 0。
    /// hframes/vframes/frame 既定 1/1/0（engine Sprite2D と同じスプライトシート格子分割）。
    def parseSprite(widget: Widget, map: Map[String, Json]): Result[JsonError, Option[UiWidget.SpriteComp]] =
        match widget {
            case Widget.SpriteW => forM (
                texture    <- (JsonCompat.getAtKey(Root, "texture", map): Result[JsonError, String]);
                regionRect <- parseRegionRectOpt(map);
                scale      <- parseVec2Or("scale", {x = 1.0, y = 1.0}, map);
                flipHOpt   <- (JsonCompat.getAtKeyOpt(Root, "flipH", map): Result[JsonError, Option[Bool]]);
                flipVOpt   <- (JsonCompat.getAtKeyOpt(Root, "flipV", map): Result[JsonError, Option[Bool]]);
                tintOpt    <- parseHexColorOpt("tint", map);
                zIndexOpt  <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
                hframesOpt <- (JsonCompat.getAtKeyOpt(Root, "hframes", map): Result[JsonError, Option[Int32]]);
                vframesOpt <- (JsonCompat.getAtKeyOpt(Root, "vframes", map): Result[JsonError, Option[Int32]]);
                frameOpt   <- (JsonCompat.getAtKeyOpt(Root, "frame", map): Result[JsonError, Option[Int32]])
            ) yield Some(({
                texture = texture, regionRect = regionRect, scale = scale,
                flipH = Option.getWithDefault(false, flipHOpt),
                flipV = Option.getWithDefault(false, flipVOpt),
                tint = Option.getWithDefault(white(), tintOpt),
                zIndex = Option.getWithDefault(0, zIndexOpt),
                hframes = Option.getWithDefault(1, hframesOpt),
                vframes = Option.getWithDefault(1, vframesOpt),
                frame = Option.getWithDefault(0, frameOpt)
            }: UiWidget.SpriteComp))
            case _ => Ok(None)
        }

    /// poly ノードの PolyComp。points は必須（[[x,y], ...]・3 点以上）、color 必須（"#rrggbb"）、
    /// alpha 既定 1.0、zIndex 既定 0。
    def parsePoly(widget: Widget, map: Map[String, Json]): Result[JsonError, Option[UiWidget.PolyComp]] =
        match widget {
            case Widget.PolyW => forM (
                points    <- parsePoints(map);
                color     <- parseHexColor("color", map);
                alphaOpt  <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[JsonError, Option[Float64]]);
                zIndexOpt <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]])
            ) yield Some(({
                points = points,
                color = color,
                alpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, alphaOpt)),
                zIndex = Option.getWithDefault(0, zIndexOpt)
            }: UiWidget.PolyComp))
            case _ => Ok(None)
        }

    /// "points": [[x,y], ...] を Vec2 列へ。キー欠落・配列でない・3 点未満・各要素が [x,y] でなければ Err。
    /// 塗り潰しに最低 3 頂点が要るので 2 点以下は弾く。
    def parsePoints(map: Map[String, Json]): Result[JsonError, List[Vec2.Vec2]] =
        match Map.get("points", map) {
            case None              => Err(JsonCompat.jsonError(Root, Set#{"poly requires 'points'"}))
            case Some(JArray(arr)) => forM (
                points <- Result.traverse(pointJson -> parsePointJson(pointJson), Vector.toList(arr));
                _valid <- if (List.length(points) >= 3) Ok(())
                          else Err(JsonCompat.jsonError(Root, Set#{"poly points must have >= 3 entries (got: ${List.length(points)})"}))
            ) yield points
            case Some(_)           => Err(JsonCompat.jsonError(Root, Set#{"points must be an array of [x, y]"}))
        }

    /// 1 頂点（[x, y]）の JSON を Vec2 へ。数値 2 要素の配列でなければ Err。
    def parsePointJson(json: Json): Result[JsonError, Vec2.Vec2] =
        match json {
            case JArray(v) => match Vector.toList(v) {
                case JNumber(x) :: JNumber(y) :: Nil => Ok({x = bigDecToF64(x), y = bigDecToF64(y)})
                case _                               => Err(JsonCompat.jsonError(Root, Set#{"point must be [x, y]"}))
            }
            case _ => Err(JsonCompat.jsonError(Root, Set#{"point must be [x, y]"}))
        }

    /// "regionRect": {"pos": [x,y], "size": [w,h]} を Rect2 へ。欠落は None。
    def parseRegionRectOpt(map: Map[String, Json]): Result[JsonError, Option[Rect2.Rect2]] =
        match (JsonCompat.getAtKeyOpt(Root, "regionRect", map): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok(None)
            case Ok(Some(m)) => forM (
                pos  <- parseVec2("pos", m);
                size <- parseVec2("size", m)
            ) yield Some(({position = pos, size = size}: Rect2.Rect2))
        }

    /// [x, y] を Vec2 へ（必須）。要素数が 2 でなければ Err。
    def parseVec2(key: String, map: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        match (JsonCompat.getAtKey(Root, key, map): Result[JsonError, List[Float64]]) {
            case Err(e)             => Err(e)
            case Ok(x :: y :: Nil)  => Ok({x = x, y = y})
            case Ok(_)              => Err(JsonCompat.jsonError(Root, Set#{"${key} must be [x, y]"}))
        }

    /// [x, y] を Vec2 へ。欠落は既定値。要素数が 2 でなければ Err。
    def parseVec2Or(key: String, fallback: Vec2.Vec2, map: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        match (JsonCompat.getAtKeyOpt(Root, key, map): Result[JsonError, Option[List[Float64]]]) {
            case Err(e)                  => Err(e)
            case Ok(None)                => Ok(fallback)
            case Ok(Some(x :: y :: Nil)) => Ok({x = x, y = y})
            case Ok(Some(_))             => Err(JsonCompat.jsonError(Root, Set#{"${key} must be [x, y]"}))
        }

    // ========================================================================
    // 色（"#rrggbb"）
    // ========================================================================

    /// "#rrggbb" 文字列（必須）を Color へ。形式不正は Err。
    def parseHexColor(key: String, map: Map[String, Json]): Result[JsonError, Color] =
        forM (
            hex   <- (JsonCompat.getAtKey(Root, key, map): Result[JsonError, String]);
            color <- hexToColor(hex)
        ) yield color

    /// "#rrggbb" 文字列を Color へ。キー欠落は None。形式不正は Err。
    def parseHexColorOpt(key: String, map: Map[String, Json]): Result[JsonError, Option[Color]] =
        match (JsonCompat.getAtKeyOpt(Root, key, map): Result[JsonError, Option[String]]) {
            case Err(e)         => Err(e)
            case Ok(None)       => Ok(None)
            case Ok(Some(hex))  => hexToColor(hex) |> Result.map(color -> Some(color))
        }

    /// "#rrggbb"（先頭 # は任意）を Color へ。6 桁 16 進以外は Err。
    def hexToColor(hex: String): Result[JsonError, Color] =
        let body = if (String.startsWith(prefix = "#", hex)) String.drop(1, hex) else hex;
        match String.toList(body) {
            case r0 :: r1 :: g0 :: g1 :: b0 :: b1 :: Nil =>
                match (byteOf(r0, r1), byteOf(g0, g1), byteOf(b0, b1)) {
                    case (Some(r), Some(g), Some(b)) => Ok({r = channel(r), g = channel(g), b = channel(b)})
                    case _                           => Err(JsonCompat.jsonError(Root, Set#{"invalid hex color: ${hex}"}))
                }
            case _ => Err(JsonCompat.jsonError(Root, Set#{"hex color must be #rrggbb (got: ${hex})"}))
        }

    /// 16 進 2 桁（上位・下位）を 0..255 の値へ。桁が不正なら None。
    def byteOf(hi: Char, lo: Char): Option[Int32] =
        forM (h <- hexNibble(hi); l <- hexNibble(lo)) yield h * 16 + l

    /// 1 桁の 16 進を 0..15 へ。'0'..'9' / 'a'..'f' / 'A'..'F' 以外は None。
    def hexNibble(c: Char): Option[Int32] =
        let code = Char.toBmpCodePoint(c);
        if (code >= 48 and code <= 57) Some(code - 48)
        else if (code >= 97 and code <= 102) Some(code - 97 + 10)
        else if (code >= 65 and code <= 70) Some(code - 65 + 10)
        else None

    /// 0..255 の整数チャンネル値を 0.0..1.0 の Float32 へ。
    def channel(byte: Int32): Float32 =
        Float64.truncateToFloat32(Int32.toFloat64(byte) / 255.0)

    /// 既定の tint（白）。
    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// JSON 値が Object ならその map、それ以外は Err（label で文脈を示す）。
    def asObject(label: String, json: Json): Result[JsonError, Map[String, Json]] =
        match json {
            case JObject(m) => Ok(m)
            case _          => Err(JsonCompat.jsonError(Root, Set#{"${label} must be a JSON object"}))
        }

    /// JNumber の BigDecimal を Float64 へ。
    def bigDecToF64(bd: BigDecimal): Float64 =
        bd.doubleValue()

    // ========================================================================
    // load（ファイル読み）
    // ========================================================================

    /// ui.json を読み込んで parse する（SceneLoader と同じ読み方）。
    /// 読み込み失敗・JSON パース失敗・スキーマ不正はいずれも Err。
    pub def load(path: String): Result[JsonError, Spec] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        match content {
            case Err(readError) => Err(JsonCompat.jsonError(Root, Set#{"failed to read: ${readError}"}))
            case Ok(text)       => match JsonCompat.parse(String.trim(text)) {
                case None       => Err(JsonCompat.jsonError(Root, Set#{"JSON parse failed: ${path}"}))
                case Some(json) => parse(json)
            }
        }

    // ========================================================================
    // spawn / respawn
    // ========================================================================

    /// Spec の全ノードを UiStore へ登録し、root の EntityId と更新後の UiWorld を返す。
    /// 名前パスは root 名を起点に "root/child/..." で組み立てる。
    /// （`spawn` は Flix の予約語のため `spawnRoot` と名付ける。despawnRoot と対になる。）
    pub def spawnRoot(spec: Spec, ui: UiStore.UiWorld): (EntityId, UiStore.UiWorld) =
        spawnNode(spec, nameOf(spec), None, 0, ui)

    /// spec 由来 store を root ごと捨ててから spawnRoot し直す。selection/focus は String キーゆえ生存する。
    /// さらに despawn 前の「名前パス→可視」を採取し、再 spawn 後に同じ名前パスへ引き継ぐ。
    /// これによりゲームが動的に切り替えた可視状態（バー表示・集合中ラベル等）がリロードを生き延びる。
    /// 再 spawn で新設された名前パスは spec 既定の可視のまま。
    pub def respawn(spec: Spec, ui: UiStore.UiWorld): (EntityId, UiStore.UiWorld) =
        let rootPath = nameOf(spec);
        let visibleBefore = UiStore.visibleByPath(rootPath, ui);
        let (id, ui2) = spawnRoot(spec, UiStore.despawnRoot(rootPath, ui));
        (id, UiStore.applyVisibleByPath(visibleBefore, ui2))

    /// ui.json を読み込んで spawnRoot し、root 名パス→アセットパスを sources 台帳へ登録する。
    /// これ 1 本で「読む・木を作る・リロード台帳に載せる」が揃う。load/parse 失敗は Err。
    pub def spawnAsset(path: String, ui: UiStore.UiWorld): Result[JsonError, (EntityId, UiStore.UiWorld)] \ Fs.FileRead =
        forM (spec <- load(path)) yield {
            let (id, ui2) = spawnRoot(spec, ui);
            (id, UiStore.putSource(nameOf(spec), path, ui2))
        }

    /// `spawnAsset` の別名 root 版。同じアセットを複数の root として組みたいとき（味方カードと
    /// 敵カードが 1 枚の `UnitCard.ui.json` を左右 2 root で使う等）に、spec の root 名を
    /// `rootName` に差し替えてから spawn し、`rootName` をキーに sources 台帳へ登録する。
    /// sources のキー（登録した root 名）は名前パス機構とコードの契約なので、reloadAll は
    /// このキーへ強制的に付け直す（後述 reloadOne）。load/parse 失敗は Err。
    pub def spawnAssetAs(path: String, rootName: String, ui: UiStore.UiWorld): Result[JsonError, (EntityId, UiStore.UiWorld)] \ Fs.FileRead =
        forM (spec <- load(path)) yield {
            let (id, ui2) = spawnRoot(withRootName(spec, rootName), ui);
            (id, UiStore.putSource(rootName, path, ui2))
        }

    /// spec の root ノードの `name` だけを差し替える（子孫はそのまま）。別名 spawn / リロードで使う。
    def withRootName(spec: Spec, rootName: String): Spec =
        let Spec.Spec(fields) = spec;
        Spec.Spec({name = rootName | fields})

    /// sources 台帳の全 root を走査し、各アセットを読み直して respawn する（F1 ホットリロード）。
    /// load/parse に失敗した root は旧ツリーを保持し、残りの root のリロードは続行する。
    /// respawn は sources を触らないため、走査中に台帳は変わらない。
    pub def reloadAll(ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        ui#sources |> Map.foldLeftWithKey((acc, rootName, assetPath) -> reloadOne(rootName, assetPath, acc), ui)

    /// 1 アセットを読み直し、登録済み root 名（sources のキー）へ強制的に付け直して respawn する。
    /// spec 自身の root 名がキーと違っても（別名 spawn / json 側の root 名変更）キー名でツリーを
    /// 組み直すので、旧キーの孤児ツリーが残らない。失敗時は現状維持（他 root を巻き添えにしない）。
    def reloadOne(rootName: String, assetPath: String, ui: UiStore.UiWorld): UiStore.UiWorld \ Fs.FileRead =
        match load(assetPath) {
            case Err(_)   => ui
            case Ok(spec) => let (_, ui2) = respawn(withRootName(spec, rootName), ui); ui2
        }

    /// 1 ノードを採番して各 store に登録し、子孫を再帰登録する。
    /// `path`: このノードの完全名パス。`parent`: 親 entity（root は None）。`orderIndex`: 兄弟内の順序。
    def spawnNode(spec: Spec, path: String, parent: Option[EntityId], orderIndex: Int32,
                  ui: UiStore.UiWorld): (EntityId, UiStore.UiWorld) =
        let Spec.Spec(fields) = spec;
        let (id, ui1) = UiStore.alloc(ui);
        let parents1  = match parent { case None => ui1#parents, case Some(pid) => Map.insert(id, pid, ui1#parents) };
        let boxes1    = insertOpt(id, fields#box, ui1#boxes);
        let texts1    = insertOpt(id, fields#text, ui1#texts);
        let sprites1  = insertOpt(id, fields#sprite, ui1#sprites);
        let polys1    = insertOpt(id, fields#poly, ui1#polys);
        let bindings1 = insertOpt(id, fields#binding, ui1#bindings);
        let metas1    = insertOpt(id, fields#meta, ui1#metas);
        let layers1   = match parent { case None => Map.insert(id, fields#layer, ui1#layers), case Some(_) => ui1#layers };
        let ui2 = {
            names    = Map.insert(path, id, ui1#names),
            parents  = parents1,
            order    = Map.insert(id, orderIndex, ui1#order),
            styles   = Map.insert(id, fields#style, ui1#styles),
            boxes    = boxes1,
            texts    = texts1,
            sprites  = sprites1,
            polys    = polys1,
            visible  = Map.insert(id, fields#visible, ui1#visible),
            bindings = bindings1,
            metas    = metas1,
            layers   = layers1
            | ui1
        };
        let stepped = List.foldLeft((state, child) -> {
            let childPath = "${path}/${nameOf(child)}";
            let (_, acc2) = spawnNode(child, childPath, Some(id), state#index, state#ui);
            {index = state#index + 1, ui = acc2}
        }, {index = 0, ui = ui2}, fields#children);
        (id, stepped#ui)

    /// Option が Some のときだけ map へ挿入する。
    def insertOpt(id: EntityId, opt: Option[v], m: Map[EntityId, v]): Map[EntityId, v] =
        match opt {
            case None    => m
            case Some(v) => Map.insert(id, v, m)
        }

    /// Spec ノードの name を取り出す。
    def nameOf(spec: Spec): String =
        let Spec.Spec(fields) = spec;
        fields#name
}
