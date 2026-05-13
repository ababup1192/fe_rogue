/// Layout — UI レイアウト記述子と解決アルゴリズム
///
/// scene.json の Container ノードの `layout` フィールドに乗せて、UI ノードの
/// 配置を宣言的に決めるための ADT。
///
/// 設計方針:
///   - Layout は値で composable。enum case が増えても apply の分岐 1 つで対応できる
///   - apply / resolve は純粋関数
///   - Layout の leaf は **実 node 定義の埋め込み** (`Node({name, definition})`)。
///     SceneLoader が definition から実 engine node を作り scene tree に追加する
///   - Container の子は **Control 系 (ColorRect, TextureRect, Label2D, RichTextLabel,
///     Button, TextureButton)** に限定。Node2D 系 (Sprite2D など) は size を持たないため
///     Container 内では使えない (Godot と同じ制約)。UI 画像は TextureRect を使う
///
/// scene.json の規約:
///   - `"kind": "..."` を持つ object → Layout primitive (HBoxContainer / Overlay 等)
///   - `"type": "..."` を持つ object → 実 node 定義 (Node case として扱う)

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
    /// 実 engine node の埋め込み。SceneLoader が definition から build して
    /// scene tree (Container の親 path 配下) に追加する。
    /// Layout.apply は parentPath ++ [name] の path に対し setGlobalPositionAt + setSize を呼ぶ。
    /// definition 内の `"anchor"` / `"margin"` は Panel 内での anchor 配置に使われる。
    case Node({ name = String, definition = Json.JsonElement })
    /// Panel — 親 rect を共有する子レイアウト群。各 Node 子は個別の `anchor` で配置 (Godot の Plain Control に最も近い)。
    /// anchor 未指定の子は TopLeft 扱い。anchor=FullRect の Node は size も親 rect に合わせる。
    case Panel(List[Layout])
}

mod Layout {

    use Json.JsonElement.{JsonObject}
    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ========================================================================
    // JSON デシリアライズ
    // ========================================================================

    /// JsonElement から Layout を再帰的に構築する。
    /// "type" を持つ object は実 node 定義 → Layout.Node に変換。
    /// "kind" を持つ object は Layout primitive (HBoxContainer 等)。
    pub def fromJson(json: Json.JsonElement): Result[Json.JsonError, Layout] =
        match json {
            case JsonObject(map) =>
                if (Map.memberOf("type", map))
                    forM (
                        name <- (Json.FromJson.getAtKey(Root, "name", map): Result[Json.JsonError, String])
                    ) yield Layout.Node({name = name, definition = json})
                else
                    forM (
                        kind <- (Json.FromJson.getAtKey(Root, "kind", map): Result[Json.JsonError, String]);
                        layout <- buildByKind(kind, map)
                    ) yield layout
            case _ => Err(JsonError(Root, Set#{"JsonObject for Layout"}))
        }

    def buildByKind(kind: String,
                     map: Map[String, Json.JsonElement]): Result[Json.JsonError, Layout] =
        match kind {
            case "MarginContainer" =>
                forM (
                    margin    <- (Json.FromJson.getAtKey(Root, "margin", map): Result[Json.JsonError, Float64]);
                    childJson <- (Json.FromJson.getAtKey(Root, "child", map): Result[Json.JsonError, Json.JsonElement]);
                    child     <- fromJson(childJson)
                ) yield Layout.MarginContainer({margin = margin, child = child})
            case "CenterContainer" =>
                forM (
                    childJson <- (Json.FromJson.getAtKey(Root, "child", map): Result[Json.JsonError, Json.JsonElement]);
                    child     <- fromJson(childJson)
                ) yield Layout.CenterContainer(child)
            case "VBoxContainer" => buildBoxContainer(true, map)
            case "HBoxContainer" => buildBoxContainer(false, map)
            case "Panel" =>
                forM (
                    childrenJson <- (Json.FromJson.getAtKey(Root, "children", map): Result[Json.JsonError, List[Json.JsonElement]]);
                    children     <- traverseLayouts(childrenJson)
                ) yield Layout.Panel(children)
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

    /// children 配列の各要素を Layout に変換する。
    /// 動的な繰り返しが必要な場合は flix code 側で `List.range` などで生成すること。
    def traverseLayouts(jsons: List[Json.JsonElement]): Result[Json.JsonError, List[Layout]] =
        match jsons {
            case Nil       => Ok(Nil)
            case j :: rest =>
                forM (
                    head <- fromJson(j);
                    tail <- traverseLayouts(rest)
                ) yield head :: tail
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

    /// origin 矩形を起点に Layout を解決し、Node 各個の globalPosition を
    /// Scene.setGlobalPositionAt で書き換える純粋関数。
    /// parentPath は Container の親 path (Node の name と結合して full path を作る)。
    pub def apply(parentPath: NodePath, origin: Rect2.Rect2,
                   layout: Layout, scene: Scene[s]): Scene[s] =
        let rects = resolve(parentPath, origin, layout, scene);
        Map.foldLeftWithKey((sc, path, rect) ->
            sc |> Scene.setGlobalPositionAt(path, rect#position)
               |> Scene.mapEngineNode(path, n -> EngineNode.setSize(rect#size, n)),
            scene, rects)

    /// 解決後の各 Node 矩形を返す（デバッグ・テスト用）。
    pub def resolve(parentPath: NodePath, origin: Rect2.Rect2,
                     layout: Layout, scene: Scene[s]): Map[NodePath, Rect2.Rect2] =
        resolveRec(parentPath, origin, layout, scene, Map.empty())

    def resolveRec(parentPath: NodePath, origin: Rect2.Rect2, layout: Layout,
                    scene: Scene[s],
                    acc: Map[NodePath, Rect2.Rect2]): Map[NodePath, Rect2.Rect2] =
        match layout {
            case Layout.Node({name, definition = _}) =>
                Map.insert(List.append(parentPath, name :: Nil), origin, acc)
            case Layout.MarginContainer({margin, child}) =>
                resolveRec(parentPath, Rect2.grow(-margin, origin), child, scene, acc)
            case Layout.CenterContainer(child) =>
                let sz = measure(parentPath, child, scene);
                let pos: Vec2.Vec2 = {
                    x = origin#position#x + (origin#size#x - sz#x) / 2.0,
                    y = origin#position#y + (origin#size#y - sz#y) / 2.0
                };
                let r: Rect2.Rect2 = {position = pos, size = sz};
                resolveRec(parentPath, r, child, scene, acc)
            case Layout.VBoxContainer({separation, alignment, crossAxis, children}) =>
                resolveBoxContainer(parentPath, true, origin, separation, alignment, crossAxis, children, scene, acc)
            case Layout.HBoxContainer({separation, alignment, crossAxis, children}) =>
                resolveBoxContainer(parentPath, false, origin, separation, alignment, crossAxis, children, scene, acc)
            case Layout.Panel(children) =>
                List.foldLeft((a, child) -> resolvePanelChild(parentPath, origin, child, scene, a), acc, children)
        }

    /// Panel 内の子レイアウトを解決する。
    /// Node 子: definition から anchor / margin を読み、Anchor.applyAnchor で rect を算出
    /// その他: 通常通り origin を渡して再帰
    def resolvePanelChild(parentPath: NodePath, origin: Rect2.Rect2, layout: Layout,
                           scene: Scene[s],
                           acc: Map[NodePath, Rect2.Rect2]): Map[NodePath, Rect2.Rect2] =
        match layout {
            case Layout.Node({name, definition}) =>
                let path = List.append(parentPath, name :: Nil);
                let anchor = Option.getWithDefault(Anchor.TopLeft, readAnchor(definition));
                let margin = readMargin(definition);
                let childSize = measureNode(path, scene);
                let rect = Anchor.applyAnchor(anchor, origin, childSize, margin);
                Map.insert(path, rect, acc)
            case _ =>
                resolveRec(parentPath, origin, layout, scene, acc)
        }

    /// JsonElement から `"anchor": "..."` を Anchor preset として読む
    def readAnchor(definition: Json.JsonElement): Option[Anchor] =
        match definition {
            case JsonObject(map) =>
                let result: Result[Json.JsonError, Option[String]] =
                    Json.FromJson.getAtKeyOpt(Root, "anchor", map);
                match result {
                    case Ok(Some(s)) => Anchor.fromString(s)
                    case _           => None
                }
            case _ => None
        }

    /// JsonElement から `"margin": Float64` を読む (デフォルト 0.0)
    def readMargin(definition: Json.JsonElement): Float64 =
        match definition {
            case JsonObject(map) =>
                let result: Result[Json.JsonError, Option[Float64]] =
                    Json.FromJson.getAtKeyOpt(Root, "margin", map);
                match result {
                    case Ok(Some(m)) => m
                    case _           => 0.0
                }
            case _ => 0.0
        }

    /// VBoxContainer / HBoxContainer 共通: vertical=true なら主軸=Y、false なら主軸=X。
    def resolveBoxContainer(parentPath: NodePath, vertical: Bool, origin: Rect2.Rect2,
                             separation: Float64,
                             alignment: MainAxisAlign, crossAxis: CrossAxisAlign,
                             children: List[Layout], scene: Scene[s],
                             acc: Map[NodePath, Rect2.Rect2]): Map[NodePath, Rect2.Rect2] =
        let sizes = List.map(c -> measure(parentPath, c, scene), children);
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
        let crossExtent = if (vertical) origin#size#x else origin#size#y;
        let result = List.foldLeft((st, pair) -> {
            let (child, mainSize) = pair;
            let mainPos = st#pen;
            let baseChildPos: Vec2.Vec2 =
                if (vertical) {x = origin#position#x, y = origin#position#y + mainPos}
                else {x = origin#position#x + mainPos, y = origin#position#y};
            let childRectSize = childRectSizeFor(parentPath, vertical, crossAxis, mainSize, crossExtent, child, scene);
            let childPos = adjustCrossAxis(vertical, crossAxis, origin, baseChildPos, childRectSize);
            let childRect: Rect2.Rect2 = {position = childPos, size = childRectSize};
            let newAcc = resolveRec(parentPath, childRect, child, scene, st#acc);
            {pen = mainPos + mainSize + gap, acc = newAcc}
        }, {pen = startOffset, acc = acc},
           List.zip(children, mains));
        result#acc

    /// 子矩形の交差軸サイズを決める。Stretch なら親の全幅、それ以外なら子の自然サイズ。
    def childRectSizeFor(parentPath: NodePath, vertical: Bool, crossAxis: CrossAxisAlign,
                          mainSize: Float64, crossExtent: Float64,
                          child: Layout, scene: Scene[s]): Vec2.Vec2 =
        let natural = measure(parentPath, child, scene);
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
    /// MarginContainer は子サイズ + 2 * margin。CenterContainer はそのまま。
    /// Node は scene tree 内の実 node を `measureNode` で測る。
    pub def measure(parentPath: NodePath, layout: Layout, scene: Scene[s]): Vec2.Vec2 =
        match layout {
            case Layout.Node({name, definition = _}) =>
                measureNode(List.append(parentPath, name :: Nil), scene)
            case Layout.MarginContainer({margin, child}) =>
                let inner = measure(parentPath, child, scene);
                {x = inner#x + 2.0 * margin, y = inner#y + 2.0 * margin}
            case Layout.CenterContainer(child) => measure(parentPath, child, scene)
            case Layout.VBoxContainer({separation, alignment = _, crossAxis = _, children}) =>
                boxContainerSize(parentPath, true, separation, children, scene)
            case Layout.HBoxContainer({separation, alignment = _, crossAxis = _, children}) =>
                boxContainerSize(parentPath, false, separation, children, scene)
            case Layout.Panel(children) =>
                let sizes = List.map(c -> measure(parentPath, c, scene), children);
                let maxW = List.foldLeft((a, s) -> Float64.max(a, s#x), 0.0, sizes);
                let maxH = List.foldLeft((a, s) -> Float64.max(a, s#y), 0.0, sizes);
                {x = maxW, y = maxH}
        }

    def boxContainerSize(parentPath: NodePath, vertical: Bool, separation: Float64,
                          children: List[Layout], scene: Scene[s]): Vec2.Vec2 =
        let sizes = List.map(c -> measure(parentPath, c, scene), children);
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
                                bug!("Layout.measureNode: node at path ${path} has no intrinsic size; UI 内では Sprite2D ではなく TextureRect を使うこと")
                        }
                }
        }
}
