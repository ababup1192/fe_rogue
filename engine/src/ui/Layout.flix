/// Layout — UI レイアウト記述子と解決アルゴリズム
///
/// Container ノード（NodeTag.Container を持つ Marker2D）に乗せて、
/// 子ノードの globalPosition を宣言的に決めるための ADT。
///
/// 設計方針:
///   - Layout は値で composable。enum case が増えても apply の分岐 1 つで対応できる
///   - apply / resolve は純粋関数。Leaf が指すノードのサイズは EngineNode.getSize と
///     Label2D.measure から取得する（pure）
///   - Container の子は **Control 系 (ColorRect, TextureRect, Label2D, RichTextLabel,
///     Button, TextureButton)** に限定。Node2D 系 (Sprite2D など) は size を持たないため
///     Container 内では使えない (Godot と同じ制約)。UI 画像は TextureRect を使う

/// HBoxContainer/VBoxContainer の主軸 alignment (Godot BoxContainer.AlignmentMode 準拠)。
/// 余ったスペースを主軸方向のどこに置くか。
/// see: https://docs.godotengine.org/en/stable/classes/class_boxcontainer.html
pub enum MainAxisAlign with Eq {
    /// 主軸の先頭から詰める。余りは末尾に残る (Godot ALIGNMENT_BEGIN)
    case Begin
    /// 子の塊全体を中央寄せ。余りは両端に半分ずつ (Godot ALIGNMENT_CENTER)
    case Center
    /// 主軸の末尾から詰める。余りは先頭に残る (Godot ALIGNMENT_END)
    case End
}

/// HBoxContainer/VBoxContainer の交差軸 alignment。
/// 子の交差軸位置（VBoxContainer なら左右、HBoxContainer なら上下）。
/// Stretch は子矩形に親の交差軸サイズを与える (Godot の size_flags = EXPAND_FILL に相当)。
/// 非 Godot 独自拡張: Godot では子の size_flags で個別指定するが、本 Layout では親側で一括指定する。
pub enum CrossAxisAlign with Eq {
    case Begin
    case Center
    case End
    case Stretch
}

pub enum Layout {
    /// 子を縦方向に並べる (Godot VBoxContainer 準拠)
    case VBoxContainer({
        separation = Float64,
        alignment  = MainAxisAlign,
        crossAxis  = CrossAxisAlign,
        children   = List[Layout]
    })
    /// 子を横方向に並べる (Godot HBoxContainer 準拠)
    case HBoxContainer({
        separation = Float64,
        alignment  = MainAxisAlign,
        crossAxis  = CrossAxisAlign,
        children   = List[Layout]
    })
    /// 親矩形を内側に margin 縮小して子を配置 (Godot MarginContainer 準拠、本実装は全方向同一値)
    case MarginContainer({ margin = Float64, child = Layout })
    /// 子レイアウトを親矩形の中央に配置 (Godot CenterContainer 準拠)
    case CenterContainer(Layout)
    /// scene tree のノードへの参照。position が origin に書き換わる (非 Godot 独自概念)
    case Leaf({ path = NodePath })
    /// 複数の子レイアウトを同じ origin に重ねて配置する (非 Godot 独自拡張)。
    /// Godot 相当の代替: 同じ position の Control を複数重ねる
    case Overlay(List[Layout])
    /// 何もしないプレースホルダ (非 Godot 独自)
    case Empty
}

mod Layout {

    use Json.JsonElement.{JsonObject}
    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ========================================================================
    // JSON デシリアライズ
    // ========================================================================

    /// JsonElement から Layout を再帰的に構築する。
    /// scene.json の Container ノードの `layout` フィールドをパースするために使う。
    /// 未知の kind や必須フィールドの欠落は Result.Err を返す。
    pub def fromJson(json: Json.JsonElement): Result[Json.JsonError, Layout] =
        match json {
            case JsonObject(map) =>
                forM (
                    kind <- (Json.FromJson.getAtKey(Root, "kind", map): Result[Json.JsonError, String]);
                    layout <- buildByKind(kind, map)
                ) yield layout
            case _ => Err(JsonError(Root, Set#{"JsonObject for Layout"}))
        }

    def buildByKind(kind: String,
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, Layout] =
        match kind {
            case "Empty" => Ok(Layout.Empty)
            case "Leaf" =>
                forM (
                    path <- (Json.FromJson.getAtKey(Root, "path", map): Result[Json.JsonError, List[String]])
                ) yield Layout.Leaf({path = path})
            case "MarginContainer" =>
                forM (
                    margin <- (Json.FromJson.getAtKey(Root, "margin", map): Result[Json.JsonError, Float64]);
                    childJson <- (Json.FromJson.getAtKey(Root, "child", map): Result[Json.JsonError, Json.JsonElement]);
                    child <- fromJson(childJson)
                ) yield Layout.MarginContainer({margin = margin, child = child})
            case "CenterContainer" =>
                forM (
                    childJson <- (Json.FromJson.getAtKey(Root, "child", map): Result[Json.JsonError, Json.JsonElement]);
                    child <- fromJson(childJson)
                ) yield Layout.CenterContainer(child)
            case "VBoxContainer" => buildBoxContainer(true, map)
            case "HBoxContainer" => buildBoxContainer(false, map)
            case "Overlay" =>
                forM (
                    childrenJson <- (Json.FromJson.getAtKey(Root, "children", map): Result[Json.JsonError, List[Json.JsonElement]]);
                    children <- traverseLayouts(childrenJson)
                ) yield Layout.Overlay(children)
            case unknown =>
                Err(JsonError(Root, Set#{"known Layout kind (got: ${unknown})"}))
        }

    def buildBoxContainer(vertical: Bool,
                           map: Map[String, Json.JsonElement]): Result[Json.JsonError, Layout] =
        forM (
            separation   <- (Json.FromJson.getAtKey(Root, "separation", map): Result[Json.JsonError, Float64]);
            alignStr     <- (Json.FromJson.getAtKey(Root, "alignment", map): Result[Json.JsonError, String]);
            crossStr     <- (Json.FromJson.getAtKey(Root, "crossAxis", map): Result[Json.JsonError, String]);
            alignment    <- parseMainAxis(alignStr);
            crossAxis    <- parseCrossAxis(crossStr);
            childrenJson <- (Json.FromJson.getAtKey(Root, "children", map): Result[Json.JsonError, List[Json.JsonElement]]);
            children     <- traverseLayouts(childrenJson)
        ) yield if (vertical)
            Layout.VBoxContainer({separation = separation, alignment = alignment,
                                   crossAxis = crossAxis, children = children})
        else
            Layout.HBoxContainer({separation = separation, alignment = alignment,
                                   crossAxis = crossAxis, children = children})

    /// 各要素を Layout に変換。要素が `"kind": "Repeat"` の場合はその場で count 個に展開する。
    /// VBoxContainer/HBoxContainer/Overlay の children 配列内で使うことで「同じ template を i=0..N-1 で繰り返し」が書ける。
    def traverseLayouts(jsons: List[Json.JsonElement]): Result[Json.JsonError, List[Layout]] =
        match jsons {
            case Nil       => Ok(Nil)
            case j :: rest =>
                forM (
                    heads <- expandOrSingleLayout(j);
                    tail  <- traverseLayouts(rest)
                ) yield List.append(heads, tail)
        }

    def expandOrSingleLayout(j: Json.JsonElement): Result[Json.JsonError, List[Layout]] =
        match j {
            case JsonObject(map) =>
                let kindResult: Result[Json.JsonError, String] =
                    Json.FromJson.getAtKey(Root, "kind", map);
                match kindResult {
                    case Ok("Repeat") => expandRepeat(map)
                    case _            =>
                        forM (l <- fromJson(j)) yield l :: Nil
                }
            case _ =>
                forM (l <- fromJson(j)) yield l :: Nil
        }

    def expandRepeat(map: Map[String, Json.JsonElement]): Result[Json.JsonError, List[Layout]] =
        forM (
            count        <- (Json.FromJson.getAtKey(Root, "count", map): Result[Json.JsonError, Int32]);
            indexVar     <- (Json.FromJson.getAtKey(Root, "indexVar", map): Result[Json.JsonError, String]);
            templateJson <- (Json.FromJson.getAtKey(Root, "template", map): Result[Json.JsonError, Json.JsonElement]);
            baseLayout   <- fromJson(templateJson)
        ) yield {
            let placeholder = "{${indexVar}}";
            List.map(i -> substituteIndex(placeholder, i, baseLayout), List.range(0, count))
        }

    /// Layout 内の Leaf.path 文字列要素にある `{indexVar}` プレースホルダを i の文字列で置換する。
    /// 他フィールド (margin/separation 等の数値) は変更しない。
    pub def substituteIndex(placeholder: String, i: Int32, layout: Layout): Layout =
        let replacement = "${i}";
        match layout {
            case Layout.Empty => Layout.Empty
            case Layout.Leaf({path}) =>
                Layout.Leaf({path = List.map(s ->
                    String.replace(src = placeholder, dst = replacement, s), path)})
            case Layout.MarginContainer({margin, child}) =>
                Layout.MarginContainer({margin = margin, child = substituteIndex(placeholder, i, child)})
            case Layout.CenterContainer(child) =>
                Layout.CenterContainer(substituteIndex(placeholder, i, child))
            case Layout.VBoxContainer({separation, alignment, crossAxis, children}) =>
                Layout.VBoxContainer({separation = separation, alignment = alignment, crossAxis = crossAxis,
                                       children = List.map(c ->
                                           substituteIndex(placeholder, i, c), children)})
            case Layout.HBoxContainer({separation, alignment, crossAxis, children}) =>
                Layout.HBoxContainer({separation = separation, alignment = alignment, crossAxis = crossAxis,
                                       children = List.map(c ->
                                           substituteIndex(placeholder, i, c), children)})
            case Layout.Overlay(children) =>
                Layout.Overlay(List.map(c -> substituteIndex(placeholder, i, c), children))
        }

    def parseMainAxis(s: String): Result[Json.JsonError, MainAxisAlign] =
        match s {
            case "Begin"  => Ok(MainAxisAlign.Begin)
            case "Center" => Ok(MainAxisAlign.Center)
            case "End"    => Ok(MainAxisAlign.End)
            case other    => Err(JsonError(Root, Set#{"MainAxisAlign (got: ${other})"}))
        }

    def parseCrossAxis(s: String): Result[Json.JsonError, CrossAxisAlign] =
        match s {
            case "Begin"   => Ok(CrossAxisAlign.Begin)
            case "Center"  => Ok(CrossAxisAlign.Center)
            case "End"     => Ok(CrossAxisAlign.End)
            case "Stretch" => Ok(CrossAxisAlign.Stretch)
            case other     => Err(JsonError(Root, Set#{"CrossAxisAlign (got: ${other})"}))
        }

    // ========================================================================
    // 解決
    // ========================================================================

    /// origin 矩形を起点に Layout を解決し、Leaf 各個の globalPosition を
    /// Scene.setGlobalPositionAt で書き換えて返す純粋関数。
    pub def apply(origin: Rect2.Rect2, layout: Layout, scene: Scene[s]): Scene[s] =
        let rects = resolve(origin, layout, scene);
        Map.foldLeftWithKey((sc, path, rect) ->
            Scene.setGlobalPositionAt(path, rect#position, sc), scene, rects)

    /// 解決後の各 Leaf 矩形を返す（デバッグ・テスト用）。
    pub def resolve(origin: Rect2.Rect2, layout: Layout, scene: Scene[s]):
                    Map[NodePath, Rect2.Rect2] =
        resolveRec(origin, layout, scene, Map.empty())

    def resolveRec(origin: Rect2.Rect2, layout: Layout, scene: Scene[s],
                    acc: Map[NodePath, Rect2.Rect2]): Map[NodePath, Rect2.Rect2] =
        match layout {
            case Layout.Empty             => acc
            case Layout.Leaf({path})      => Map.insert(path, origin, acc)
            case Layout.MarginContainer({margin, child}) =>
                resolveRec(Rect2.grow(-margin, origin), child, scene, acc)
            case Layout.CenterContainer(child) =>
                let sz = measure(child, scene);
                let pos: Vec2.Vec2 = {
                    x = origin#position#x + (origin#size#x - sz#x) / 2.0,
                    y = origin#position#y + (origin#size#y - sz#y) / 2.0
                };
                let r: Rect2.Rect2 = {position = pos, size = sz};
                resolveRec(r, child, scene, acc)
            case Layout.VBoxContainer({separation, alignment, crossAxis, children}) =>
                resolveBoxContainer(true, origin, separation, alignment, crossAxis, children, scene, acc)
            case Layout.HBoxContainer({separation, alignment, crossAxis, children}) =>
                resolveBoxContainer(false, origin, separation, alignment, crossAxis, children, scene, acc)
            case Layout.Overlay(children) =>
                List.foldLeft((a, child) -> resolveRec(origin, child, scene, a), acc, children)
        }

    /// VBoxContainer / HBoxContainer 共通: vertical=true なら主軸=Y、false なら主軸=X。
    def resolveBoxContainer(vertical: Bool, origin: Rect2.Rect2, separation: Float64,
                             alignment: MainAxisAlign, crossAxis: CrossAxisAlign,
                             children: List[Layout], scene: Scene[s],
                             acc: Map[NodePath, Rect2.Rect2]): Map[NodePath, Rect2.Rect2] =
        let sizes = List.map(c -> measure(c, scene), children);
        let mains = List.map(s -> if (vertical) s#y else s#x, sizes);
        let total = List.foldLeft((a, m) -> a + m, 0.0, mains)
                  + separation * Int32.toFloat64(Int32.max(0, List.length(children) - 1));
        let mainExtent = if (vertical) origin#size#y else origin#size#x;
        let extra      = Float64.max(0.0, mainExtent - total);
        let (startOffset, gap) = match alignment {
            case MainAxisAlign.Begin  => (0.0, separation)
            case MainAxisAlign.Center => (extra / 2.0, separation)
            case MainAxisAlign.End    => (extra, separation)
        };
        // 各子の主軸位置を pen で進めながら配置
        let crossExtent = if (vertical) origin#size#x else origin#size#y;
        let result = List.foldLeft((st, pair) -> {
            let (child, mainSize) = pair;
            let mainPos = st#pen;
            let baseChildPos: Vec2.Vec2 =
                if (vertical) {x = origin#position#x, y = origin#position#y + mainPos}
                else {x = origin#position#x + mainPos, y = origin#position#y};
            let childRectSize = childRectSizeFor(vertical, crossAxis, mainSize, crossExtent, child, scene);
            let childPos = adjustCrossAxis(vertical, crossAxis, origin, baseChildPos, childRectSize);
            let childRect: Rect2.Rect2 = {position = childPos, size = childRectSize};
            let newAcc = resolveRec(childRect, child, scene, st#acc);
            {pen = mainPos + mainSize + gap, acc = newAcc}
        }, {pen = startOffset, acc = acc},
           List.zip(children, mains));
        result#acc

    /// 子矩形の交差軸サイズを決める。Stretch なら親の全幅、それ以外なら子の自然サイズ。
    def childRectSizeFor(vertical: Bool, crossAxis: CrossAxisAlign,
                          mainSize: Float64, crossExtent: Float64,
                          child: Layout, scene: Scene[s]): Vec2.Vec2 =
        let natural = measure(child, scene);
        let cross = match crossAxis {
            case CrossAxisAlign.Stretch => crossExtent
            case _                       => if (vertical) natural#x else natural#y
        };
        if (vertical) {x = cross, y = mainSize}
        else {x = mainSize, y = cross}

    /// 交差軸の位置を crossAxis に応じて調整する。
    def adjustCrossAxis(vertical: Bool, crossAxis: CrossAxisAlign,
                         origin: Rect2.Rect2, basePos: Vec2.Vec2, childSize: Vec2.Vec2): Vec2.Vec2 =
        let crossExtent = if (vertical) origin#size#x else origin#size#y;
        let childCross  = if (vertical) childSize#x else childSize#y;
        let offset = match crossAxis {
            case CrossAxisAlign.Begin   => 0.0
            case CrossAxisAlign.Center  => (crossExtent - childCross) / 2.0
            case CrossAxisAlign.End     => crossExtent - childCross
            case CrossAxisAlign.Stretch => 0.0
        };
        if (vertical) {x = basePos#x + offset, y = basePos#y}
        else {x = basePos#x, y = basePos#y + offset}

    // ========================================================================
    // 測定
    // ========================================================================

    /// レイアウトの自然サイズ（intrinsic size）を返す。
    /// VBoxContainer/HBoxContainer は子の合計（+ separation）と最大交差サイズ。
    /// MarginContainer は子サイズ + 2 * margin。CenterContainer / Leaf / Sized はそのまま。
    pub def measure(layout: Layout, scene: Scene[s]): Vec2.Vec2 =
        match layout {
            case Layout.Empty                              => Vec2.zero()
            case Layout.Leaf({path})                       => measureNode(path, scene)
            case Layout.MarginContainer({margin, child}) =>
                let inner = measure(child, scene);
                {x = inner#x + 2.0 * margin, y = inner#y + 2.0 * margin}
            case Layout.CenterContainer(child) => measure(child, scene)
            case Layout.VBoxContainer({separation, alignment = _, crossAxis = _, children}) =>
                boxContainerSize(true, separation, children, scene)
            case Layout.HBoxContainer({separation, alignment = _, crossAxis = _, children}) =>
                boxContainerSize(false, separation, children, scene)
            case Layout.Overlay(children) =>
                let sizes = List.map(c -> measure(c, scene), children);
                let maxW = List.foldLeft((a, s) -> Float64.max(a, s#x), 0.0, sizes);
                let maxH = List.foldLeft((a, s) -> Float64.max(a, s#y), 0.0, sizes);
                {x = maxW, y = maxH}
        }

    def boxContainerSize(vertical: Bool, separation: Float64,
                          children: List[Layout], scene: Scene[s]): Vec2.Vec2 =
        let sizes = List.map(c -> measure(c, scene), children);
        let mains = List.map(s -> if (vertical) s#y else s#x, sizes);
        let crosses = List.map(s -> if (vertical) s#x else s#y, sizes);
        let total = List.foldLeft((a, m) -> a + m, 0.0, mains)
                  + separation * Int32.toFloat64(Int32.max(0, List.length(children) - 1));
        let crossMax = List.foldLeft((a, c) -> Float64.max(a, c), 0.0, crosses);
        if (vertical) {x = crossMax, y = total}
        else {x = total, y = crossMax}

    /// scene tree 内の単一ノードの自然サイズを取る。
    ///   - Label2D: Label2D.measure（テキスト幅と行高）
    ///   - ColorRect / Control / Button / TextureButton / TextureRect / RichTextLabel:
    ///       EngineNode.getSize（明示 size フィールド、Control 系）
    ///   - その他 (Sprite2D 等の Node2D 系): bug! でフェイルファースト。
    ///     UI 内で画像を表示するなら Sprite2D ではなく TextureRect を使う
    pub def measureNode(path: NodePath, scene: Scene[s]): Vec2.Vec2 =
        match Scene.getEngineNode(path, scene) {
            case None       => bug!("Layout.measureNode: node not found at path ${path}")
            case Some(node) =>
                match node {
                    case EngineNode.Label2DWithState(label, _) => Label2D.measure(label)
                    case _ =>
                        match EngineNode.getSize(node) {
                            case Some(sz) => sz
                            case None     =>
                                bug!("Layout.measureNode: node at path ${path} has no intrinsic size; wrap it in Sized()")
                        }
                }
        }
}
