// UiDoc — ui.json の宣言ドキュメント層。JSON のノード木を Spec（pure data）へ畳み、
// Flex（→ UiLayout）でレイアウトして Render.PlacedItem の列に落とす。
// **ここが ui.json 方言の唯一のパーサ** — UiSpec.parse はこの parse の結果を
// UiStore コンポーネントへ射影する薄い層で、方言の定義はこのモジュールに一本化されている。
//
// 語彙 = 既存 ui.json（templates/use・name/widget/children/visible/bind/meta/layer・
// スタイルキー・box/text/sprite/poly）+ 拡張:
//   図形 widget: "circle" "ngon" "star" "ellipse" "sector" "segment" "line" "polyline" "bezier"
//     - 共通: color（必須）/ alpha（= Render.fade）/ zIndex。座標は解決 rect の中心相対で、
//       図形は rect の中心に描かれる。width/height を書けば優先、無ければ図形の内在サイズ
//       （circle→2r 四方など）が Px として敷かれる。
//     - circle は Box（全角丸）なので borderWidth/borderColor で枠が効く（= ring が書ける）。
//   色: "#rrggbb" に加えて {"hsv":[h,s,v]}（Color.hsv 直行）と {"rgb":[r,g,b]}。
//   poly: rotation（1 周 = 1.0）。pivot 未指定なら rect 中心を原点に Render.rotated で回す
//     （時計の針は「根元 = rect 中心」に頂点を組めば蝶番になる）。pivot=[x,y]（左上相対）指定時は
//     Render.rotatedAround。※この拡張は Flex 経路のみ — UiStore 経路（UiSpec）は loud に断る。
//   トップレベル: "version"（省略時 1。1 以外は Err）。"$schema"・"//" キーは無視（コメント可）。
//
// エラーはノードの名前パス付き（例: `at gallery/row1/box: 'color' is required`）— 手書き
// ドキュメントの編集箇所へ誘導する。
//
// build（Flex 経路）は bind/meta/layer を使わない（動的束縛・レイヤ重ねは UiSpec/UiStore の領分）が、
// Spec には保持する — 同じ JSON が経路で意味を失わないための契約。

mod UiDoc {
    import java.math.BigDecimal
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString, JNumber}
    use Util.Json.JsonError
    use JsonCompat.PathTag.Root

    // ========================================================================
    // 型（テンプレ解決済み・pure data）
    // ========================================================================

    pub enum Spec {
        case Spec({ name = String, widget = Widget, style = UiLayout.Style,
                    visible = Bool, binding = Option[String], meta = Option[String],
                    layer = Int32, children = List[Spec] })
    }

    pub enum Widget {
        case NoneW
        case BoxW(UiWidget.BoxComp)
        case TextW(UiWidget.TextComp)
        case SpriteW(UiWidget.SpriteComp)
        case PolyW(PolySpec)
        case ShapeW(UiShape.ShapeComp)
    }

    /// poly widget（UiWidget.PolyComp の宣言形 + rotation/pivot 拡張）。
    pub type alias PolySpec = {
        points = List[Vec2.Vec2], color = Color, alpha = Float32, zIndex = Int32,
        rotation = Float64, pivot = Option[Vec2.Vec2]
    }

    pub def nameOf(spec: Spec): String =
        match spec { case Spec.Spec(node) => node#name }

    // ========================================================================
    // parse（純粋）
    // ========================================================================

    /// ドキュメント（version + templates + root）を Spec へ畳む。
    pub def parse(json: Json): Result[JsonError, Spec] =
        match json {
            case JObject(topMap) => forM (
                _v          <- checkVersion(topMap);
                templates   <- parseTemplates(topMap);
                defaultFont <- parseDefaultFont(topMap);
                rootMap     <- (JsonCompat.getAtKey(Root, "root", topMap): Result[JsonError, Map[String, Json]]);
                spec        <- parseNode(templates, defaultFont, "", rootMap)
            ) yield spec
            case _ => Err(JsonCompat.jsonError(Root, Set#{"UiDoc must be a JSON object with a 'root'"}))
        }

    /// "version"（省略時 1）。この実装が知らない版は loud に断る（黙って誤読しない）。
    def checkVersion(topMap: Map[String, Json]): Result[JsonError, Unit] =
        match (JsonCompat.getAtKeyOpt(Root, "version", topMap): Result[JsonError, Option[Int32]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok(())
            case Ok(Some(1)) => Ok(())
            case Ok(Some(v)) => Err(JsonCompat.jsonError(Root, Set#{"unsupported ui document version ${v} (supported: 1)"}))
        }

    def parseDefaultFont(topMap: Map[String, Json]): Result[JsonError, String] =
        (JsonCompat.getAtKeyOpt(Root, "defaultFont", topMap): Result[JsonError, Option[String]])
            |> Result.map(Option.getWithDefault("ui"))

    def parseTemplates(topMap: Map[String, Json]): Result[JsonError, Map[String, Map[String, Json]]] =
        match (JsonCompat.getAtKeyOpt(Root, "templates", topMap): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Ok(Map.empty())
            case Ok(Some(m)) =>
                Map.foldLeftWithKey((acc, tname, json) -> forM (
                    sofar <- acc;
                    tmap  <- asObject("template '${tname}'", json)
                ) yield Map.insert(tname, tmap, sofar), Ok(Map.empty()), m)
        }

    /// 1 ノードを Spec へ。`use` のテンプレ値の上にノード値を重ねる（ノード勝ち）。
    /// エラーはこのノードの名前パスでタグする（子は子が自分でタグ済み）。
    def parseNode(templates: Map[String, Map[String, Json]], defaultFont: String,
                  parentPath: String, nodeMap: Map[String, Json]): Result[JsonError, Spec] =
        match nodeIdentity(templates, parentPath, nodeMap) {
            case Err(e) => Err(e)
            case Ok((name, merged)) =>
                let path = if (parentPath == "") name else "${parentPath}/${name}";
                forM (
                    own      <- JsonCompat.atNode(path, parseOwnFields(defaultFont, merged));
                    children <- parseChildren(templates, defaultFont, path, merged);
                    _uniq    <- JsonCompat.atNode(path, ensureUniqueNames(children))
                ) yield Spec.Spec({
                    name = name, widget = own#widget, style = own#style,
                    visible = own#visible, binding = own#binding, meta = own#meta,
                    layer = own#layer, children = children
                })
        }

    /// use 解決と name の取り出し。自分のパスが確定する前に失敗し得るので親パスでタグする。
    def nodeIdentity(templates: Map[String, Map[String, Json]], parentPath: String,
                     nodeMap: Map[String, Json]): Result[JsonError, (String, Map[String, Json])] =
        JsonCompat.atNode(if (parentPath == "") "(root)" else parentPath, forM (
            merged <- resolveTemplate(templates, nodeMap);
            name   <- (JsonCompat.getAtKey(Root, "name", merged): Result[JsonError, String]);
            _valid <- validateName(name)
        ) yield (name, merged))

    /// ノード自身の属性（widget・style・visible・bind/meta/layer）。
    def parseOwnFields(defaultFont: String, merged: Map[String, Json]):
            Result[JsonError, { widget = Widget, style = UiLayout.Style, visible = Bool,
                                binding = Option[String], meta = Option[String], layer = Int32 }] =
        forM (
            widgetOpt  <- (JsonCompat.getAtKeyOpt(Root, "widget", merged): Result[JsonError, Option[String]]);
            widget     <- parseWidget(widgetOpt, defaultFont, merged);
            style      <- parseStyle(merged);
            visibleOpt <- (JsonCompat.getAtKeyOpt(Root, "visible", merged): Result[JsonError, Option[Bool]]);
            bindingOpt <- (JsonCompat.getAtKeyOpt(Root, "bind", merged): Result[JsonError, Option[String]]);
            metaOpt    <- (JsonCompat.getAtKeyOpt(Root, "meta", merged): Result[JsonError, Option[String]]);
            layerOpt   <- (JsonCompat.getAtKeyOpt(Root, "layer", merged): Result[JsonError, Option[Int32]])
        ) yield {
            widget = widget, style = applyIntrinsic(widget, style),
            visible = Option.getWithDefault(true, visibleOpt),
            binding = bindingOpt, meta = metaOpt,
            layer = Option.getWithDefault(0, layerOpt)
        }

    def resolveTemplate(templates: Map[String, Map[String, Json]],
                        nodeMap: Map[String, Json]): Result[JsonError, Map[String, Json]] =
        match (JsonCompat.getAtKeyOpt(Root, "use", nodeMap): Result[JsonError, Option[String]]) {
            case Err(e)          => Err(e)
            case Ok(None)        => Ok(nodeMap)
            case Ok(Some(tname)) => match Map.get(tname, templates) {
                case None       => Err(JsonCompat.jsonError(Root, Set#{"unknown template: ${tname}"}))
                case Some(tmap) => Ok(mergeNode(tmap, nodeMap))
            }
        }

    def mergeNode(base: Map[String, Json], over: Map[String, Json]): Map[String, Json] =
        Map.foldLeftWithKey((acc, key, value) -> Map.insert(key, value, acc), base, over)

    def parseChildren(templates: Map[String, Map[String, Json]], defaultFont: String,
                      path: String, map: Map[String, Json]): Result[JsonError, List[Spec]] =
        match Map.get("children", map) {
            case None              => Ok(Nil)
            case Some(JArray(arr)) =>
                Result.traverse(child -> forM (
                    m    <- JsonCompat.atNode(path, asObject("child", child));
                    spec <- parseNode(templates, defaultFont, path, m)
                ) yield spec, Vector.toList(arr))
            case Some(_)           => Err(JsonCompat.jsonError(Root, Set#{"children must be an array"}))
        }

    def validateName(name: String): Result[JsonError, Unit] =
        if (name == "")
            Err(JsonCompat.jsonError(Root, Set#{"node name must not be empty"}))
        else if (String.contains(substr = "/", name))
            Err(JsonCompat.jsonError(Root, Set#{"node name must not contain '/' (got: ${name})"}))
        else Ok(())

    def ensureUniqueNames(children: List[Spec]): Result[JsonError, Unit] =
        let names = List.map(child -> nameOf(child), children);
        if (List.length(names) == Set.size(List.toSet(names))) Ok(())
        else Err(JsonCompat.jsonError(Root, Set#{"sibling names must be unique (got: ${names})"}))

    /// 図形 widget の width/height 未指定（Auto）を内在サイズの Px に置き換える。
    def applyIntrinsic(widget: Widget, style: UiLayout.Style): UiLayout.Style =
        match widget {
            case Widget.ShapeW(s) =>
                let size = UiShape.intrinsicSize(s#shape);
                let w = match style#width {
                    case UiLayout.SizeSpec.Auto => UiLayout.SizeSpec.Px(size#x)
                    case other                  => other
                };
                let h = match style#height {
                    case UiLayout.SizeSpec.Auto => UiLayout.SizeSpec.Px(size#y)
                    case other                  => other
                };
                { width = w, height = h | style }
            case _ => style
        }

    // ========================================================================
    // widget 解析
    // ========================================================================

    def parseWidget(opt: Option[String], defaultFont: String,
                    map: Map[String, Json]): Result[JsonError, Widget] =
        match opt {
            case None             => Ok(Widget.NoneW)
            case Some("none")     => Ok(Widget.NoneW)
            case Some("box")      => parseBox(map)               |> Result.map(b -> Widget.BoxW(b))
            case Some("text")     => parseText(defaultFont, map) |> Result.map(t -> Widget.TextW(t))
            case Some("sprite")   => parseSprite(map)            |> Result.map(sp -> Widget.SpriteW(sp))
            case Some("poly")     => parsePoly(map)              |> Result.map(p -> Widget.PolyW(p))
            case Some("circle")   => shapeWidget(map, parseCircle(map))
            case Some("ngon")     => shapeWidget(map, parseNgon(map))
            case Some("star")     => shapeWidget(map, parseStar(map))
            case Some("ellipse")  => shapeWidget(map, parseEllipse(map))
            case Some("sector")   => shapeWidget(map, parseSweep(map, true))
            case Some("segment")  => shapeWidget(map, parseSweep(map, false))
            case Some("line")     => shapeWidget(map, parseLine(map))
            case Some("polyline") => shapeWidget(map, parsePolyline(map))
            case Some("bezier")   => shapeWidget(map, parseBezier(map))
            case Some(unknown)    => Err(JsonCompat.jsonError(Root, Set#{"unknown widget (got: ${unknown})"}))
        }

    def parseBox(map: Map[String, Json]): Result[JsonError, UiWidget.BoxComp] =
        forM (
            color           <- parseColor("color", map);
            alphaOpt        <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[JsonError, Option[Float64]]);
            zIndexOpt       <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
            cornerRadiusOpt <- (JsonCompat.getAtKeyOpt(Root, "cornerRadius", map): Result[JsonError, Option[Float64]]);
            borderWidthOpt  <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", map): Result[JsonError, Option[Float64]]);
            borderColorOpt  <- parseColorOpt("borderColor", map)
        ) yield ({
            color = color,
            alpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, alphaOpt)),
            zIndex = Option.getWithDefault(0, zIndexOpt),
            cornerRadius = Option.getWithDefault(0.0, cornerRadiusOpt),
            borderWidth = Option.getWithDefault(0.0, borderWidthOpt),
            borderColor = Option.getWithDefault(white(), borderColorOpt)
        }: UiWidget.BoxComp)

    def parseText(defaultFont: String, map: Map[String, Json]): Result[JsonError, UiWidget.TextComp] =
        forM (
            textOpt     <- (JsonCompat.getAtKeyOpt(Root, "text", map): Result[JsonError, Option[String]]);
            fontOpt     <- (JsonCompat.getAtKeyOpt(Root, "font", map): Result[JsonError, Option[String]]);
            fontSizeOpt <- (JsonCompat.getAtKeyOpt(Root, "fontSize", map): Result[JsonError, Option[Float64]]);
            tintOpt     <- parseColorOpt("tint", map);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]])
        ) yield ({
            text = Option.getWithDefault("", textOpt),
            font = Option.getWithDefault(defaultFont, fontOpt),
            fontSize = Option.getWithDefault(8.0, fontSizeOpt),
            tint = Option.getWithDefault(white(), tintOpt),
            zIndex = Option.getWithDefault(0, zIndexOpt)
        }: UiWidget.TextComp)

    /// sprite（既存 ui.json と同義。tint は色 3 表記の上位互換）。
    def parseSprite(map: Map[String, Json]): Result[JsonError, UiWidget.SpriteComp] =
        forM (
            texture    <- (JsonCompat.getAtKey(Root, "texture", map): Result[JsonError, String]);
            regionRect <- parseRegionRectOpt(map);
            scale      <- parseVec2Or("scale", {x = 1.0, y = 1.0}, map);
            flipHOpt   <- (JsonCompat.getAtKeyOpt(Root, "flipH", map): Result[JsonError, Option[Bool]]);
            flipVOpt   <- (JsonCompat.getAtKeyOpt(Root, "flipV", map): Result[JsonError, Option[Bool]]);
            tintOpt    <- parseColorOpt("tint", map);
            zIndexOpt  <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
            hframesOpt <- (JsonCompat.getAtKeyOpt(Root, "hframes", map): Result[JsonError, Option[Int32]]);
            vframesOpt <- (JsonCompat.getAtKeyOpt(Root, "vframes", map): Result[JsonError, Option[Int32]]);
            frameOpt   <- (JsonCompat.getAtKeyOpt(Root, "frame", map): Result[JsonError, Option[Int32]])
        ) yield ({
            texture = texture, regionRect = regionRect, scale = scale,
            flipH = Option.getWithDefault(false, flipHOpt),
            flipV = Option.getWithDefault(false, flipVOpt),
            tint = Option.getWithDefault(white(), tintOpt),
            zIndex = Option.getWithDefault(0, zIndexOpt),
            hframes = Option.getWithDefault(1, hframesOpt),
            vframes = Option.getWithDefault(1, vframesOpt),
            frame = Option.getWithDefault(0, frameOpt)
        }: UiWidget.SpriteComp)

    def parsePoly(map: Map[String, Json]): Result[JsonError, PolySpec] =
        forM (
            points      <- parsePointList(map);
            _enough     <- if (List.length(points) >= 3) Ok(())
                           else Err(JsonCompat.jsonError(Root, Set#{"poly points must have >= 3 entries (got: ${List.length(points)})"}));
            color       <- parseColor("color", map);
            alphaOpt    <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[JsonError, Option[Float64]]);
            zIndexOpt   <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
            rotationOpt <- (JsonCompat.getAtKeyOpt(Root, "rotation", map): Result[JsonError, Option[Float64]]);
            pivot       <- parseVec2Opt("pivot", map)
        ) yield ({
            points = points, color = color,
            alpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, alphaOpt)),
            zIndex = Option.getWithDefault(0, zIndexOpt),
            rotation = Option.getWithDefault(0.0, rotationOpt),
            pivot = pivot
        }: PolySpec)

    // ── 図形 widget の共通フィールドと各パラメータ ──

    def shapeWidget(map: Map[String, Json], shapeRes: Result[JsonError, UiShape.Shape]): Result[JsonError, Widget] =
        forM (
            shape          <- shapeRes;
            color          <- parseColor("color", map);
            alphaOpt       <- (JsonCompat.getAtKeyOpt(Root, "alpha", map): Result[JsonError, Option[Float64]]);
            zIndexOpt      <- (JsonCompat.getAtKeyOpt(Root, "zIndex", map): Result[JsonError, Option[Int32]]);
            borderWidthOpt <- (JsonCompat.getAtKeyOpt(Root, "borderWidth", map): Result[JsonError, Option[Float64]]);
            borderColorOpt <- parseColorOpt("borderColor", map)
        ) yield Widget.ShapeW({
            shape = shape, color = color,
            alpha = Float64.truncateToFloat32(Option.getWithDefault(1.0, alphaOpt)),
            zIndex = Option.getWithDefault(0, zIndexOpt),
            borderWidth = Option.getWithDefault(0.0, borderWidthOpt),
            borderColor = borderColorOpt
        })

    def parseCircle(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (radius <- (JsonCompat.getAtKey(Root, "radius", map): Result[JsonError, Float64]))
        yield UiShape.Shape.CircleS({ radius = radius })

    def parseNgon(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            n      <- (JsonCompat.getAtKey(Root, "n", map): Result[JsonError, Int32]);
            radius <- (JsonCompat.getAtKey(Root, "radius", map): Result[JsonError, Float64])
        ) yield UiShape.Shape.NgonS({ n = n, radius = radius })

    def parseStar(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            points <- (JsonCompat.getAtKey(Root, "points", map): Result[JsonError, Int32]);
            outer  <- (JsonCompat.getAtKey(Root, "outer", map): Result[JsonError, Float64]);
            inner  <- (JsonCompat.getAtKey(Root, "inner", map): Result[JsonError, Float64]);
            via    <- parseVia(map)
        ) yield UiShape.Shape.StarS({ points = points, outer = outer, inner = inner, via = via })

    def parseEllipse(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            radii    <- parseVec2("radii", map);
            segsOpt  <- (JsonCompat.getAtKeyOpt(Root, "segments", map): Result[JsonError, Option[Int32]]);
            via      <- parseVia(map)
        ) yield UiShape.Shape.EllipseS({ radii = radii, segments = Option.getWithDefault(32, segsOpt), via = via })

    /// sector / segment 共通（radius + from/to）。isSector で作る形を選ぶ。
    def parseSweep(map: Map[String, Json], isSector: Bool): Result[JsonError, UiShape.Shape] =
        forM (
            radius <- (JsonCompat.getAtKey(Root, "radius", map): Result[JsonError, Float64]);
            fromT  <- (JsonCompat.getAtKey(Root, "from", map): Result[JsonError, Float64]);
            toT    <- (JsonCompat.getAtKey(Root, "to", map): Result[JsonError, Float64])
        ) yield {
            if (isSector) UiShape.Shape.SectorS({ radius = radius, fromT = fromT, toT = toT })
            else          UiShape.Shape.SegmentS({ radius = radius, fromT = fromT, toT = toT })
        }

    def parseLine(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            points    <- parsePointList(map);
            lineWidth <- (JsonCompat.getAtKey(Root, "lineWidth", map): Result[JsonError, Float64]);
            shape     <- match points {
                case a :: b :: Nil => Ok(UiShape.Shape.LineS({ a = a, b = b, lineWidth = lineWidth }))
                case _ => Err(JsonCompat.jsonError(Root, Set#{"line points must be [[x1,y1],[x2,y2]]"}))
            }
        ) yield shape

    def parsePolyline(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            points    <- parsePointList(map);
            lineWidth <- (JsonCompat.getAtKey(Root, "lineWidth", map): Result[JsonError, Float64]);
            _enough   <- if (List.length(points) >= 2) Ok(())
                         else Err(JsonCompat.jsonError(Root, Set#{"polyline points must have >= 2 entries"}))
        ) yield UiShape.Shape.PolylineS({ points = points, lineWidth = lineWidth })

    def parseBezier(map: Map[String, Json]): Result[JsonError, UiShape.Shape] =
        forM (
            points   <- parsePointList(map);
            stepsOpt <- (JsonCompat.getAtKeyOpt(Root, "steps", map): Result[JsonError, Option[Int32]]);
            taper    <- parseTaper(map);
            shape    <- match points {
                case p0 :: ctrl :: p1 :: Nil =>
                    Ok(UiShape.Shape.BezierS({ p0 = p0, ctrl = ctrl, p1 = p1,
                                               steps = Option.getWithDefault(16, stepsOpt),
                                               widthFrom = taper#w0, widthTo = taper#w1 }))
                case _ => Err(JsonCompat.jsonError(Root, Set#{"bezier points must be [[p0],[ctrl],[p1]]"}))
            }
        ) yield shape

    def parseVia(map: Map[String, Json]): Result[JsonError, UiShape.Via] =
        match (JsonCompat.getAtKeyOpt(Root, "via", map): Result[JsonError, Option[String]]) {
            case Err(e)              => Err(e)
            case Ok(None)            => Ok(UiShape.Via.RenderVia)
            case Ok(Some("render"))  => Ok(UiShape.Via.RenderVia)
            case Ok(Some("bezier"))  => Ok(UiShape.Via.BezierVia)
            case Ok(Some(unknown))   => Err(JsonCompat.jsonError(Root, Set#{"via must be render|bezier (got: ${unknown})"}))
        }

    /// "taper": {"from": w0, "to": w1}（bezier の線形太さ。t=0 で w0、t=1 で w1）。
    /// レコードラベルの from/to は Flix の予約語なので内部名は w0/w1。
    def parseTaper(map: Map[String, Json]): Result[JsonError, {w0 = Float64, w1 = Float64}] =
        match (JsonCompat.getAtKeyOpt(Root, "taper", map): Result[JsonError, Option[Map[String, Json]]]) {
            case Err(e)      => Err(e)
            case Ok(None)    => Err(JsonCompat.jsonError(Root, Set#{"bezier requires 'taper' {\"from\": w0, \"to\": w1}"}))
            case Ok(Some(m)) => forM (
                w0 <- (JsonCompat.getAtKey(Root, "from", m): Result[JsonError, Float64]);
                w1 <- (JsonCompat.getAtKey(Root, "to", m): Result[JsonError, Float64])
            ) yield { w0 = w0, w1 = w1 }
        }

    // ========================================================================
    // スタイル解析
    // ========================================================================

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
            abs      <- parseVec2Opt("abs", map)
        ) yield ({
            dir = dir, gap = Option.getWithDefault(0.0, gapOpt),
            padLeft = pad#l, padTop = pad#t, padRight = pad#r, padBottom = pad#b,
            width = width, height = height,
            mainAlign = main, crossAlign = cross,
            abs = abs
        }: UiLayout.Style)

    def parseDir(opt: Option[String]): Result[JsonError, UiLayout.Dir] =
        match opt {
            case None           => Ok(UiLayout.Dir.Column)
            case Some("row")    => Ok(UiLayout.Dir.Row)
            case Some("column") => Ok(UiLayout.Dir.Column)
            case Some(unknown)  => Err(JsonCompat.jsonError(Root, Set#{"dir must be row|column (got: ${unknown})"}))
        }

    def parseMainAlign(opt: Option[String]): Result[JsonError, UiLayout.MainAlign] =
        match opt {
            case None                 => Ok(UiLayout.MainAlign.Start)
            case Some("start")        => Ok(UiLayout.MainAlign.Start)
            case Some("center")       => Ok(UiLayout.MainAlign.Center)
            case Some("end")          => Ok(UiLayout.MainAlign.End)
            case Some("spaceBetween") => Ok(UiLayout.MainAlign.SpaceBetween)
            case Some(unknown)        => Err(JsonCompat.jsonError(Root, Set#{"mainAlign unknown (got: ${unknown})"}))
        }

    def parseCrossAlign(opt: Option[String]): Result[JsonError, UiLayout.CrossAlign] =
        match opt {
            case None            => Ok(UiLayout.CrossAlign.Start)
            case Some("start")   => Ok(UiLayout.CrossAlign.Start)
            case Some("center")  => Ok(UiLayout.CrossAlign.Center)
            case Some("end")     => Ok(UiLayout.CrossAlign.End)
            case Some("stretch") => Ok(UiLayout.CrossAlign.Stretch)
            case Some(unknown)   => Err(JsonCompat.jsonError(Root, Set#{"crossAlign unknown (got: ${unknown})"}))
        }

    def parsePad(map: Map[String, Json]): Result[JsonError, {l = Float64, t = Float64, r = Float64, b = Float64}] =
        match (JsonCompat.getAtKeyOpt(Root, "pad", map): Result[JsonError, Option[List[Float64]]]) {
            case Err(e)   => Err(e)
            case Ok(None) => Ok({l = 0.0, t = 0.0, r = 0.0, b = 0.0})
            case Ok(Some(left :: top :: right :: bottom :: Nil)) => Ok({l = left, t = top, r = right, b = bottom})
            case Ok(Some(_)) => Err(JsonCompat.jsonError(Root, Set#{"pad must be [left, top, right, bottom]"}))
        }

    def parseSizeSpec(key: String, map: Map[String, Json]): Result[JsonError, UiLayout.SizeSpec] =
        match Map.get(key, map) {
            case None                  => Ok(UiLayout.SizeSpec.Auto)
            case Some(JString("auto")) => Ok(UiLayout.SizeSpec.Auto)
            case Some(JString("grow")) => Ok(UiLayout.SizeSpec.Grow(1.0))
            case Some(JNumber(bd))     => Ok(UiLayout.SizeSpec.Px(bigDecToF64(bd)))
            case Some(_)               => Err(JsonCompat.jsonError(Root, Set#{"${key} must be a number, \"auto\", or \"grow\""}))
        }

    // ========================================================================
    // 点・ベクトル・色
    // ========================================================================

    /// "points": [[x,y], ...] を Vec2 列へ（点数の下限は呼び手が形ごとに検査する）。
    def parsePointList(map: Map[String, Json]): Result[JsonError, List[Vec2.Vec2]] =
        match Map.get("points", map) {
            case None              => Err(JsonCompat.jsonError(Root, Set#{"'points' is required"}))
            case Some(JArray(arr)) => Result.traverse(pointJson -> parsePointJson(pointJson), Vector.toList(arr))
            case Some(_)           => Err(JsonCompat.jsonError(Root, Set#{"points must be an array of [x, y]"}))
        }

    def parsePointJson(json: Json): Result[JsonError, Vec2.Vec2] =
        match json {
            case JArray(v) => match Vector.toList(v) {
                case JNumber(x) :: JNumber(y) :: Nil => Ok({x = bigDecToF64(x), y = bigDecToF64(y)})
                case _                               => Err(JsonCompat.jsonError(Root, Set#{"point must be [x, y]"}))
            }
            case _ => Err(JsonCompat.jsonError(Root, Set#{"point must be [x, y]"}))
        }

    /// [x, y] を Vec2 へ（必須）。
    def parseVec2(key: String, map: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        match (JsonCompat.getAtKey(Root, key, map): Result[JsonError, List[Float64]]) {
            case Err(e)            => Err(e)
            case Ok(x :: y :: Nil) => Ok({x = x, y = y})
            case Ok(_)             => Err(JsonCompat.jsonError(Root, Set#{"${key} must be [x, y]"}))
        }

    /// [x, y] を Vec2 へ。キー欠落は None。
    def parseVec2Opt(key: String, map: Map[String, Json]): Result[JsonError, Option[Vec2.Vec2]] =
        match (JsonCompat.getAtKeyOpt(Root, key, map): Result[JsonError, Option[List[Float64]]]) {
            case Err(e)                  => Err(e)
            case Ok(None)                => Ok(None)
            case Ok(Some(x :: y :: Nil)) => Ok(Some({x = x, y = y}))
            case Ok(Some(_))             => Err(JsonCompat.jsonError(Root, Set#{"${key} must be [x, y]"}))
        }

    /// [x, y] を Vec2 へ。欠落は既定値。
    def parseVec2Or(key: String, fallback: Vec2.Vec2, map: Map[String, Json]): Result[JsonError, Vec2.Vec2] =
        parseVec2Opt(key, map) |> Result.map(Option.getWithDefault(fallback))

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

    /// 色（必須）: "#rrggbb" | {"hsv":[h,s,v]} | {"rgb":[r,g,b]}。
    def parseColor(key: String, map: Map[String, Json]): Result[JsonError, Color] =
        match Map.get(key, map) {
            case None       => Err(JsonCompat.jsonError(Root, Set#{"'${key}' is required"}))
            case Some(json) => colorOf(key, json)
        }

    /// 色。キー欠落は None。
    def parseColorOpt(key: String, map: Map[String, Json]): Result[JsonError, Option[Color]] =
        match Map.get(key, map) {
            case None       => Ok(None)
            case Some(json) => colorOf(key, json) |> Result.map(color -> Some(color))
        }

    def colorOf(key: String, json: Json): Result[JsonError, Color] =
        match json {
            case JString(hex) => hexToColor(hex)
            case JObject(m)   => match (Map.get("hsv", m), Map.get("rgb", m)) {
                case (Some(hsvJson), None) =>
                    floats3(key, hsvJson) |> Result.map(t -> {
                        let (h, s, v) = t;
                        Color.hsv({ h = h, s = s, v = v })
                    })
                case (None, Some(rgbJson)) =>
                    floats3(key, rgbJson) |> Result.map(t -> {
                        let (r, g, b) = t;
                        ({ r = Float64.truncateToFloat32(r),
                           g = Float64.truncateToFloat32(g),
                           b = Float64.truncateToFloat32(b) }: Color)
                    })
                case _ => Err(colorFormatError(key))
            }
            case _ => Err(colorFormatError(key))
        }

    def colorFormatError(key: String): JsonError =
        JsonCompat.jsonError(Root, Set#{"${key} must be \"#rrggbb\", {\"hsv\":[h,s,v]}, or {\"rgb\":[r,g,b]}"})

    def floats3(key: String, json: Json): Result[JsonError, (Float64, Float64, Float64)] =
        match json {
            case JArray(v) => match Vector.toList(v) {
                case JNumber(a) :: JNumber(b) :: JNumber(c) :: Nil =>
                    Ok((bigDecToF64(a), bigDecToF64(b), bigDecToF64(c)))
                case _ => Err(JsonCompat.jsonError(Root, Set#{"${key} components must be 3 numbers"}))
            }
            case _ => Err(JsonCompat.jsonError(Root, Set#{"${key} components must be 3 numbers"}))
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

    def byteOf(hi: Char, lo: Char): Option[Int32] =
        forM (h <- hexNibble(hi); l <- hexNibble(lo)) yield h * 16 + l

    def hexNibble(c: Char): Option[Int32] =
        let code = Char.toBmpCodePoint(c);
        if (code >= 48 and code <= 57) Some(code - 48)
        else if (code >= 97 and code <= 102) Some(code - 97 + 10)
        else if (code >= 65 and code <= 70) Some(code - 65 + 10)
        else None

    def channel(byte: Int32): Float32 =
        Float64.truncateToFloat32(Int32.toFloat64(byte) / 255.0)

    def white(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    def asObject(label: String, json: Json): Result[JsonError, Map[String, Json]] =
        match json {
            case JObject(m) => Ok(m)
            case _          => Err(JsonCompat.jsonError(Root, Set#{"${label} must be a JSON object"}))
        }

    def bigDecToF64(bd: BigDecimal): Float64 =
        bd.doubleValue()

    // ========================================================================
    // build（Spec → Flex.Node — 静的な Flex 経路）
    // ========================================================================

    /// Spec を Flex 木へ。atlasOf はフォント名 → FontAtlas（text の実寸計測と描画に使う）。
    /// sprite ノードを含むドキュメントは buildWith / renderWith（textureInfoOf 注入）を使う —
    /// この近道はテクスチャ寸法を引けないので、格子分割 sprite はセル切り出しされない。
    /// visible=false の子は部分木ごと落とす（display:none）。root の visible は無視する。
    pub def build(atlasOf: String -> FontAtlas, spec: Spec): Flex.Node =
        buildWith(atlasOf, _ -> None, spec)

    /// build の sprite 対応版。textureInfoOf はテクスチャ名 → 寸法（frame 格子の解決に使う）。
    pub def buildWith(atlasOf: String -> FontAtlas,
                      textureInfoOf: String -> Option[GameEngine.TextureInfo],
                      spec: Spec): Flex.Node =
        match spec {
            case Spec.Spec(node) =>
                let childNodes = node#children
                    |> List.filter(child -> match child { case Spec.Spec(c) => c#visible })
                    |> List.map(child -> buildWith(atlasOf, textureInfoOf, child));
                match node#widget {
                    case Widget.NoneW       => Flex.box(node#style, childNodes)
                    case Widget.BoxW(b)     => Flex.boxDrawn(node#style, r -> drawBox(b, r), childNodes)
                    case Widget.TextW(t)    => buildText(atlasOf, node#style, t, childNodes)
                    case Widget.SpriteW(sp) => Flex.boxDrawn(node#style,
                        r -> ({ at = r#position, item = UiExtract.spriteItem(sp, textureInfoOf) }) :: Nil,
                        childNodes)
                    case Widget.PolyW(p)    => Flex.boxDrawn(node#style, r -> drawPoly(p, r), childNodes)
                    case Widget.ShapeW(s)   => Flex.boxDrawn(node#style, r -> UiShape.placedItems(s, r), childNodes)
                }
        }

    /// 近道: build して place まで。
    pub def render(atlasOf: String -> FontAtlas, spec: Spec, rootRect: Rect2.Rect2): List[Render.PlacedItem] =
        Flex.place(build(atlasOf, spec), rootRect)

    /// render の sprite 対応版。
    pub def renderWith(atlasOf: String -> FontAtlas,
                       textureInfoOf: String -> Option[GameEngine.TextureInfo],
                       spec: Spec, rootRect: Rect2.Rect2): List[Render.PlacedItem] =
        Flex.place(buildWith(atlasOf, textureInfoOf, spec), rootRect)

    /// text ノード。width/height 未指定なら実寸（Text.measure）を Px として敷く。
    def buildText(atlasOf: String -> FontAtlas, style: UiLayout.Style, t: UiWidget.TextComp,
                  childNodes: List[Flex.Node]): Flex.Node =
        let atlas = atlasOf(t#font);
        let dims = Text.measure(Text.make(t#text, atlas, t#fontSize));
        let w = match style#width {
            case UiLayout.SizeSpec.Auto => UiLayout.SizeSpec.Px(dims#x)
            case other                  => other
        };
        let h = match style#height {
            case UiLayout.SizeSpec.Auto => UiLayout.SizeSpec.Px(dims#y)
            case other                  => other
        };
        Flex.boxDrawn({ width = w, height = h | style },
            r -> ({ at = r#position,
                    item = Render.textTinted(t#text, atlas, t#fontSize, t#tint, t#zIndex) }) :: Nil,
            childNodes)

    /// box: rect を塗る（cornerRadius → rounded、alpha → fade、border → outline の順で修飾）。
    def drawBox(b: UiWidget.BoxComp, r: Rect2.Rect2): List[Render.PlacedItem] =
        let base = Render.box(r#size, b#color, b#zIndex);
        let it1 = if (b#cornerRadius > 0.0) Render.rounded(b#cornerRadius, base) else base;
        let it2 = UiShape.fadeIf(b#alpha, it1);
        let it3 = if (b#borderWidth > 0.0) Render.outline(b#borderColor, b#borderWidth, it2) else it2;
        ({ at = r#position, item = it3 }) :: Nil

    /// poly: 頂点は rect 左上相対（UiSpec 互換）。rotation は pivot 未指定なら
    /// 「rect 中心を原点」に Render.rotated（頂点をどこ原点で組むかが軸、の流儀そのまま）。
    def drawPoly(p: PolySpec, r: Rect2.Rect2): List[Render.PlacedItem] =
        if (p#rotation == 0.0 and Option.isEmpty(p#pivot))
            ({ at = r#position, item = polyItem(p, p#points) }) :: Nil
        else match p#pivot {
            case Some(pivot) =>
                ({ at = r#position,
                   item = polyItem(p, Render.rotatedAround(p#rotation, pivot, p#points)) }) :: Nil
            case None =>
                let centerLocal = Vec2.div(r#size, 2.0);
                let rel = List.map(v -> Vec2.sub(v, centerLocal), p#points);
                ({ at = Rect2.center(r), item = polyItem(p, Render.rotated(p#rotation, rel)) }) :: Nil
        }

    def polyItem(p: PolySpec, vertices: List[Vec2.Vec2]): Render.Item =
        UiShape.fadeIf(p#alpha, Render.polygon(vertices, p#color, p#zIndex))

    // ========================================================================
    // load（ファイル読み — parse は純粋なまま、IO はここだけ）
    // ========================================================================

    pub def load(path: String): Result[JsonError, Spec] \ Fs.FileRead =
        let content = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead;
        match content {
            case Err(readError) => Err(JsonCompat.jsonError(Root, Set#{"failed to read: ${readError}"}))
            case Ok(text)       => match JsonCompat.parse(String.trim(text)) {
                case None       => Err(JsonCompat.jsonError(Root, Set#{"JSON parse failed: ${path}"}))
                case Some(json) => parse(json)
            }
        }

    /// 起動時ロード用の近道。失敗はドキュメントの書き損じなので即死してエラーを見せる。
    pub def loadOrBug(path: String): Spec \ Fs.FileRead =
        match load(path) {
            case Ok(spec) => spec
            case Err(e)   => bug!("UiDoc.load(${path}): ${e}")
        }
}
