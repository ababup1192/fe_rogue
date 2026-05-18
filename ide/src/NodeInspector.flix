// NodeInspector — Inspector に表示する node 型ごとのフィールド宣言を集めた module。
//
// Inspector の「何を表示し、編集確定時に何を書き込むか」を 1 か所 (`fieldsFor`) に集約する。
// 新しい node 型のフィールド追加は基本この module 内で完結する。
//
// 各 FieldDef は:
//   - snapshot: 現値を node から取り出して JsonElement で返す (Main が毎フレーム呼ぶ)
//   - apply:    編集確定時に Selection と JsonElement を受け取り SceneSerializer 経由で書き戻す
//
// Inspector の UI 構築は ScenePanel.rebuildInspector / startStatusBarTimer が schema を読んで
// PropertyWidgets で widget を組み立てる。値の往復は state#inspector#currentValues /
// pendingEdits を介する。

mod NodeInspector {
    import java.math.{BigDecimal => JBigDecimal}

    /// 1 フィールドの表現種別。ScenePanel がこの kind に応じて widget を選ぶ。
    /// EnumT は ComboBox の選択肢 (有限の文字列リスト) を payload に持つ
    pub enum FieldKind with Eq, ToString {
        case Vec2T
        case FloatT
        case IntT
        case TextT
        case TexturePathT
        case BoolT
        case ColorT
        case EnumT(List[String])
    }

    /// Inspector に表示する 1 フィールドの定義。
    ///   name:     一意キー (例 "position")。currentValues map のキーになる
    ///   label:    表示文字列 (例 "Local position")
    ///   kind:     widget 種別
    ///   snapshot: live scene から現値を取り出す (Main が毎フレーム呼ぶ)
    ///   apply:    pending edit を SceneSerializer 経由で書き戻す (Main が consume 時に呼ぶ)
    pub type alias FieldDef = {
        name     = String,
        label    = String,
        kind     = FieldKind,
        snapshot = EngineNode[Unit] -> Option[Json.JsonElement],
        apply    = (Editor.Selection, Json.JsonElement) -> Unit \ {Fs.FileRead, Fs.FileWrite}
    }

    /// Pending edit (FX EDT の widget commit から Main の renderLoop に渡す要素)
    pub type alias PendingEdit = {
        perform = Unit -> Unit \ {Fs.FileRead, Fs.FileWrite}
    }

    /// 継承階層の 1 段を表すセクション (Swing 版の見出しと同じ役割)。
    ///   typeName: クラス名 ("Node2D" / "Sprite2D" 等)
    ///   common:   普段表示するフィールド (よく使うもの)
    ///   advanced: 「Advanced ▶」disclosure 内に隠すフィールド (めったに触らないもの)
    pub type alias FieldSection = {
        typeName = String,
        common   = List[FieldDef],
        advanced = List[FieldDef]
    }

    /// 選択 node の継承階層に沿ったセクション列を返す。
    /// 派生クラス → 基底クラス → 共通基底 (CanvasItem) の順で並べる
    pub def sectionsFor(node: EngineNode[Unit]): List[FieldSection] =
        let typeSec = typeSpecific(node);
        let node2DSec: FieldSection = {
            typeName = "Node2D",
            common   = node2DCommon(),
            advanced = node2DAdvanced()
        };
        let canvasItemSec: FieldSection = {
            typeName = "CanvasItem",
            common   = canvasItemCommon(),
            advanced = canvasItemAdvanced()
        };
        List.append(typeSec, node2DSec :: canvasItemSec :: Nil)

    /// CanvasItem 共通: 普段見るのは visible のみ。zIndex / modulate は advanced
    def canvasItemCommon(): List[FieldDef] =
        ({
            name     = "visible",
            label    = "Visible",
            kind     = FieldKind.BoolT,
            snapshot = n -> Some(boolToJson(CanvasItem.isVisible(n))),
            apply = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                  sel#jsonPath, sel#jsonNodePath, "visible", b)
                case None    => ()
            }
        }: FieldDef) :: Nil

    def canvasItemAdvanced(): List[FieldDef] =
        ({
            name     = "zIndex",
            label    = "Z index",
            kind     = FieldKind.IntT,
            snapshot = n -> Some(intToJson(CanvasItem.getZIndex(n))),
            apply = (sel, j) -> match jsonToInt(j) {
                case Some(v) => SceneSerializer.updateInt(
                                  sel#jsonPath, sel#jsonNodePath, "zIndex", v)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "modulate",
            label    = "Modulate",
            kind     = FieldKind.ColorT,
            snapshot = n -> Some(colorToJson(CanvasItem.getModulate(n))),
            apply = (sel, j) -> match jsonToColor(j) {
                case Some(c) => SceneSerializer.updateColor(
                                  sel#jsonPath, sel#jsonNodePath, "modulate", c)
                case None    => ()
            }
        }: FieldDef) :: Nil

    /// SceneTree の 1 ノード。再帰的に子を持つ
    pub enum SceneTreeNode {
        case SNode(String, List[String], List[SceneTreeNode])
    }

    /// 与えられた scene から SceneTree を構築する。Scene.preorderPaths で root の名前を取り、
    /// 各 root から再帰的に子を辿る
    pub def buildSceneTree(scene: Scene[Unit]): List[SceneTreeNode] = {
        let allPaths = Scene.preorderPaths(scene);
        let rootPaths = List.filter(p -> List.length(p) == 1, allPaths);
        List.map(rp -> buildSubtree(rp, scene), rootPaths)
    }

    def buildSubtree(path: List[String], scene: Scene[Unit]): SceneTreeNode = {
        let leaf = List.last(path) |> Option.getWithDefault("");
        let childNames = Scene.getChildrenAt(path, scene);
        let childPaths = List.map(c -> List.append(path, c :: Nil), childNames);
        let children = List.map(cp -> buildSubtree(cp, scene), childPaths);
        SceneTreeNode.SNode(leaf, path, children)
    }

    /// 選択 node の終端クラス名を返す。Selected: 行などで使う
    pub def classNameOf(node: EngineNode[Unit]): String = match node {
        case EngineNode.Sprite2DWithState(_, _)         => "Sprite2D"
        case EngineNode.Area2DWithState(_, _)           => "Area2D"
        case EngineNode.Body2DWithState(_, _)           => "CharacterBody2D"
        case EngineNode.RigidBody2DWithState(_, _)      => "RigidBody2D"
        case EngineNode.AnimSprite2DWithState(_, _)     => "AnimatedSprite2D"
        case EngineNode.Label2DWithState(_, _)          => "Label2D"
        case EngineNode.RichTextLabelWithState(_, _)    => "RichTextLabel"
        case EngineNode.Marker2DWithState(_, _)         => "Marker2D"
        case EngineNode.Path2DWithState(_, _)           => "Path2D"
        case EngineNode.ScreenNotifier2DWithState(_, _) => "VisibleOnScreenNotifier2D"
        case EngineNode.TimerWithState(_, _)            => "Timer"
        case EngineNode.ColorRectWithState(_, _)        => "ColorRect"
        case EngineNode.GPUParticles2DWithState(_, _)   => "GPUParticles2D"
        case EngineNode.CanvasLayerWithState(_, _)      => "CanvasLayer"
        case EngineNode.ControlWithState(_, _)          => "Control"
        case EngineNode.ButtonWithState(_, _)           => "Button"
        case EngineNode.TextureButtonWithState(_, _)    => "TextureButton"
        case EngineNode.TextureRectWithState(_, _)      => "TextureRect"
        case EngineNode.Camera2DWithState(_, _)         => "Camera2D"
        case EngineNode.StaticBody2DWithState(_, _)     => "StaticBody2D"
        case EngineNode.TileMapLayerWithState(_, _)     => "TileMapLayer"
        case EngineNode.PanelWithState(_, _)            => "Panel"
        case _                                          => "Node2D"
    }

    /// Node2D 共通: position / scale / rotation。
    /// 大抵の node はこれだけで間に合う
    def node2DCommon(): List[FieldDef] =
        ({
            name     = "position",
            label    = "Local position",
            kind     = FieldKind.Vec2T,
            snapshot = n -> Some(vec2ToJson(Node2D.getPosition(n))),
            apply    = (sel, j) -> match jsonToVec2(j) {
                case Some(v) => SceneSerializer.updatePos(sel#jsonPath, sel#jsonNodePath, v)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "scale",
            label    = "Scale",
            kind     = FieldKind.Vec2T,
            snapshot = n -> Some(vec2ToJson(Node2D.getScale(n))),
            apply    = (sel, j) -> match jsonToVec2(j) {
                case Some(v) => SceneSerializer.updateScale(sel#jsonPath, sel#jsonNodePath, v)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "rotation",
            label    = "Rotation (°)",
            kind     = FieldKind.FloatT,
            snapshot = n -> Some(floatToJson(radToDeg(Node2D.getRotation(n)))),
            apply    = (sel, j) -> match jsonToFloat(j) {
                case Some(deg) => SceneSerializer.updateRotation(
                                     sel#jsonPath, sel#jsonNodePath, degToRad(deg))
                case None      => ()
            }
        }: FieldDef) :: Nil

    def node2DAdvanced(): List[FieldDef] =
        ({
            name     = "skew",
            label    = "Skew (°)",
            kind     = FieldKind.FloatT,
            snapshot = n -> Some(floatToJson(radToDeg(Node2D.getSkew(n)))),
            apply    = (sel, j) -> match jsonToFloat(j) {
                case Some(deg) => SceneSerializer.updateFields(
                                     sel#jsonPath, sel#jsonNodePath,
                                     ({key = "skew",
                                       value = SceneSerializer.FieldValue.ScalarValue(degToRad(deg))}: SceneSerializer.FieldUpdate) :: Nil)
                case None      => ()
            }
        }: FieldDef) :: Nil

    /// 型固有セクションのリスト。新しい node 型の Inspector を追加するときはここに case を増やす。
    /// 各セクションは 1 つの継承段 (Node2D 段は別途自動付与され、ここには
    /// 「その型自身が定義する追加フィールド」を返す)
    def typeSpecific(node: EngineNode[Unit]): List[FieldSection] = match node {
        case EngineNode.Sprite2DWithState(_, _) =>
            let (c, a) = sprite2DFields();
            ({typeName = "Sprite2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.AnimSprite2DWithState(_, _) =>
            let (c, a) = animSprite2DFields();
            ({typeName = "AnimatedSprite2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.Label2DWithState(_, _) =>
            let (c, a) = label2DFields();
            ({typeName = "Label2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.Area2DWithState(_, _) =>
            let (c, a) = area2DFields();
            ({typeName = "Area2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.ColorRectWithState(_, _) =>
            let (c, a) = colorRectFields();
            ({typeName = "ColorRect", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.Camera2DWithState(_, _) =>
            let (c, a) = camera2DFields();
            ({typeName = "Camera2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.Body2DWithState(_, _) =>
            let (c, a) = characterBody2DFields();
            ({typeName = "CharacterBody2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.StaticBody2DWithState(_, _) =>
            let (c, a) = staticBody2DFields();
            ({typeName = "StaticBody2D", common = c, advanced = a}: FieldSection) :: Nil
        case EngineNode.TextureRectWithState(_, _) =>
            let (c, a) = textureRectFields();
            ({typeName = "TextureRect", common = c, advanced = a}: FieldSection) :: Nil
        case _ => Nil
    }

    // ─────────────────── 汎用 FieldDef ビルダー (boilerplate 削減) ───────────────────

    /// Bool フィールドの FieldDef を作る。read は node から値を取り出す関数
    pub def boolField(jsonKey: String, label: String,
                       read: EngineNode[Unit] -> Option[Bool]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.BoolT,
            snapshot = n -> Option.map(boolToJson, read(n)),
            apply    = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                   sel#jsonPath, sel#jsonNodePath, jsonKey, b)
                case None    => ()
            }
        }

    /// Int32 フィールドの FieldDef を作る
    pub def intField(jsonKey: String, label: String,
                      read: EngineNode[Unit] -> Option[Int32]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.IntT,
            snapshot = n -> Option.map(intToJson, read(n)),
            apply    = (sel, j) -> match jsonToInt(j) {
                case Some(v) => SceneSerializer.updateInt(
                                   sel#jsonPath, sel#jsonNodePath, jsonKey, v)
                case None    => ()
            }
        }

    /// Float64 フィールドの FieldDef を作る
    pub def scalarFloatField(jsonKey: String, label: String,
                              read: EngineNode[Unit] -> Option[Float64]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.FloatT,
            snapshot = n -> Option.map(floatToJson, read(n)),
            apply    = (sel, j) -> match jsonToFloat(j) {
                case Some(v) => SceneSerializer.updateFields(
                                   sel#jsonPath, sel#jsonNodePath,
                                   ({key = jsonKey,
                                     value = SceneSerializer.FieldValue.ScalarValue(v)}: SceneSerializer.FieldUpdate) :: Nil)
                case None    => ()
            }
        }

    /// Float32 フィールド (alpha 等) の FieldDef を作る
    pub def scalarFloat32Field(jsonKey: String, label: String,
                                read: EngineNode[Unit] -> Option[Float32]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.FloatT,
            snapshot = n -> Option.map(v -> floatToJson(Float32.toFloat64(v)), read(n)),
            apply    = (sel, j) -> match jsonToFloat(j) {
                case Some(v) => SceneSerializer.updateFields(
                                   sel#jsonPath, sel#jsonNodePath,
                                   ({key = jsonKey,
                                     value = SceneSerializer.FieldValue.ScalarValue(v)}: SceneSerializer.FieldUpdate) :: Nil)
                case None    => ()
            }
        }

    /// String フィールドの FieldDef を作る
    pub def stringField(jsonKey: String, label: String,
                         read: EngineNode[Unit] -> Option[String]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.TextT,
            snapshot = n -> Option.map(stringToJson, read(n)),
            apply    = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                   sel#jsonPath, sel#jsonNodePath, jsonKey, s)
                case None    => ()
            }
        }

    /// Vec2 フィールドの FieldDef を作る
    pub def vec2Field(jsonKey: String, label: String,
                       read: EngineNode[Unit] -> Option[Vec2.Vec2]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.Vec2T,
            snapshot = n -> Option.map(vec2ToJson, read(n)),
            apply    = (sel, j) -> match jsonToVec2(j) {
                case Some(v) => SceneSerializer.updateFields(
                                   sel#jsonPath, sel#jsonNodePath,
                                   ({key = jsonKey,
                                     value = SceneSerializer.FieldValue.VecValue(v)}: SceneSerializer.FieldUpdate) :: Nil)
                case None    => ()
            }
        }

    /// Enum フィールドの FieldDef を作る。`read` は enum 値を ToString した文字列を返す
    pub def enumField(jsonKey: String, label: String, options: List[String],
                       read: EngineNode[Unit] -> Option[String]): FieldDef =
        {
            name     = jsonKey,
            label    = label,
            kind     = FieldKind.EnumT(options),
            snapshot = n -> Option.map(stringToJson, read(n)),
            apply    = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                   sel#jsonPath, sel#jsonNodePath, jsonKey, s)
                case None    => ()
            }
        }

    // ───────────────────────── Sprite2D 固有フィールド ─────────────────────────

    /// Sprite2D: common = よく触るフィールド / advanced = 普段は隠す
    def sprite2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.Sprite2DWithState(sp, _) => let Sprite2D.Sprite2D(r) = sp; Some(r)
            case _                                    => None
        };
        let textureField: FieldDef = {
            name     = "texture",
            label    = "Texture",
            kind     = FieldKind.TexturePathT,
            snapshot = n -> Option.map(r -> stringToJson(r#texture), pick(n)),
            apply    = (sel, j) -> match jsonToString(j) {
                case Some(v) => SceneSerializer.updateString(
                                   sel#jsonPath, sel#jsonNodePath, "texture", v)
                case None    => ()
            }
        };
        let common =
            textureField ::
            boolField("flipH",          "Flip H",       n -> Option.map(r -> r#flipH, pick(n))) ::
            boolField("flipV",          "Flip V",       n -> Option.map(r -> r#flipV, pick(n))) :: Nil;
        let advanced =
            scalarFloat32Field("alpha", "Alpha",        n -> Option.map(r -> r#alpha, pick(n))) ::
            boolField("centered",       "Centered",     n -> Option.map(r -> r#centered, pick(n))) ::
            vec2Field("offset",         "Offset",       n -> Option.map(r -> r#offset, pick(n))) ::
            intField("hframes",         "H frames",     n -> Option.map(r -> r#hframes, pick(n))) ::
            intField("vframes",         "V frames",     n -> Option.map(r -> r#vframes, pick(n))) ::
            intField("frame",           "Frame",        n -> Option.map(r -> r#frame, pick(n))) ::
            boolField("ySortEnabled",   "Y-sort",       n -> Option.map(r -> r#ySortEnabled, pick(n))) :: Nil;
        (common, advanced)

    // ──────────────────── AnimatedSprite2D 固有フィールド ────────────────────

    def animSprite2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.AnimSprite2DWithState(sp, _) =>
                let AnimatedSprite2D.AnimatedSprite2D(r) = sp; Some(r)
            case _ => None
        };
        let common =
            stringField("animation", "Animation",   n -> Option.map(r -> r#animation, pick(n))) ::
            boolField("playing",     "Playing",     n -> Option.map(r -> r#playing, pick(n))) ::
            stringField("autoplay",  "Autoplay",    n -> Option.map(r -> r#autoplay, pick(n))) :: Nil;
        let advanced =
            scalarFloatField("speedScale", "Speed scale", n -> Option.map(r -> r#speedScale, pick(n))) ::
            intField("frame",         "Frame",     n -> Option.map(r -> r#frame, pick(n))) ::
            boolField("centered",     "Centered",  n -> Option.map(r -> r#centered, pick(n))) ::
            vec2Field("offset",       "Offset",    n -> Option.map(r -> r#offset, pick(n))) ::
            boolField("flipH",        "Flip H",    n -> Option.map(r -> r#flipH, pick(n))) ::
            boolField("flipV",        "Flip V",    n -> Option.map(r -> r#flipV, pick(n))) ::
            boolField("ySortEnabled", "Y-sort",    n -> Option.map(r -> r#ySortEnabled, pick(n))) :: Nil;
        (common, advanced)

    // ───────────────────────── Label2D 固有フィールド ─────────────────────────

    def label2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.Label2DWithState(l, _) =>
                let Label2D.Label2D(r) = l; Some(r)
            case _ => None
        };
        let hAlignOptions = "Left" :: "Center" :: "Right" :: "Fill" :: Nil;
        let vAlignOptions = "Top" :: "Center" :: "Bottom" :: "Fill" :: Nil;
        let common =
            stringField("text", "Text",                 n -> Option.map(r -> r#text, pick(n))) ::
            scalarFloatField("fontSize", "Font size",   n -> Option.map(r -> r#fontSize, pick(n))) :: Nil;
        let advanced =
            enumField("horizontalAlignment", "H align", hAlignOptions,
                      n -> Option.map(r -> "${r#horizontalAlignment}", pick(n))) ::
            enumField("verticalAlignment",   "V align", vAlignOptions,
                      n -> Option.map(r -> "${r#verticalAlignment}", pick(n))) :: Nil;
        (common, advanced)

    // ────────────── 新規 node 型のフィールド (Phase 機能拡張 A) ──────────────

    def area2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.Area2DWithState(a, _) => let Area2D.Area2D(r) = a; Some(r)
            case _ => None
        };
        let common =
            boolField("monitoring",  "Monitoring",  n -> Option.map(r -> r#monitoring, pick(n))) ::
            boolField("monitorable", "Monitorable", n -> Option.map(r -> r#monitorable, pick(n))) :: Nil;
        let advanced =
            intField("priority",       "Priority",        n -> Option.map(r -> r#priority, pick(n))) ::
            intField("collisionLayer", "Collision layer", n -> Option.map(r -> r#collisionLayer, pick(n))) ::
            intField("collisionMask",  "Collision mask",  n -> Option.map(r -> r#collisionMask, pick(n))) :: Nil;
        (common, advanced)

    def colorRectFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.ColorRectWithState(c, _) => let ColorRect.ColorRect(r) = c; Some(r)
            case _ => None
        };
        let sizeField: FieldDef = {
            name     = "size",
            label    = "Size",
            kind     = FieldKind.Vec2T,
            snapshot = n -> Option.map(r -> vec2ToJson(r#size), pick(n)),
            apply    = (sel, j) -> match jsonToVec2(j) {
                case Some(v) => SceneSerializer.updateSize(sel#jsonPath, sel#jsonNodePath, v)
                case None    => ()
            }
        };
        let common =
            sizeField ::
            scalarFloat32Field("alpha", "Alpha", n -> Option.map(r -> r#alpha, pick(n))) :: Nil;
        (common, Nil)

    def camera2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.Camera2DWithState(c, _) => let Camera2D.Camera2D(r) = c; Some(r)
            case _ => None
        };
        let anchorOptions = "DragCenter" :: "FixedTopLeft" :: Nil;
        let processOptions = "PhysicsProcess" :: "IdleProcess" :: Nil;
        let common =
            boolField("enabled", "Enabled", n -> Option.map(r -> r#enabled, pick(n))) ::
            vec2Field("offset",  "Offset",  n -> Option.map(r -> r#offset, pick(n))) ::
            vec2Field("zoom",    "Zoom",    n -> Option.map(r -> r#zoom, pick(n))) :: Nil;
        let advanced =
            enumField("anchorMode",                 "Anchor mode", anchorOptions,
                      n -> Option.map(r -> "${r#anchorMode}", pick(n))) ::
            enumField("processCallback",            "Process callback", processOptions,
                      n -> Option.map(r -> "${r#processCallback}", pick(n))) ::
            boolField("ignoreRotation",             "Ignore rotation",  n -> Option.map(r -> r#ignoreRotation, pick(n))) ::
            intField("limitLeft",                   "Limit left",       n -> Option.map(r -> r#limitLeft, pick(n))) ::
            intField("limitTop",                    "Limit top",        n -> Option.map(r -> r#limitTop, pick(n))) ::
            intField("limitRight",                  "Limit right",      n -> Option.map(r -> r#limitRight, pick(n))) ::
            intField("limitBottom",                 "Limit bottom",     n -> Option.map(r -> r#limitBottom, pick(n))) ::
            boolField("limitSmoothed",              "Limit smoothed",   n -> Option.map(r -> r#limitSmoothed, pick(n))) ::
            boolField("positionSmoothingEnabled",   "Pos smoothing on", n -> Option.map(r -> r#positionSmoothingEnabled, pick(n))) ::
            scalarFloatField("positionSmoothingSpeed", "Pos smoothing speed", n -> Option.map(r -> r#positionSmoothingSpeed, pick(n))) ::
            boolField("rotationSmoothingEnabled",   "Rot smoothing on", n -> Option.map(r -> r#rotationSmoothingEnabled, pick(n))) ::
            scalarFloatField("rotationSmoothingSpeed", "Rot smoothing speed", n -> Option.map(r -> r#rotationSmoothingSpeed, pick(n))) ::
            boolField("dragHorizontalEnabled",      "Drag H enabled",   n -> Option.map(r -> r#dragHorizontalEnabled, pick(n))) ::
            boolField("dragVerticalEnabled",        "Drag V enabled",   n -> Option.map(r -> r#dragVerticalEnabled, pick(n))) :: Nil;
        (common, advanced)

    def characterBody2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.Body2DWithState(b, _) =>
                let CharacterBody2D.CharacterBody2D(r) = b; Some(r)
            case _ => None
        };
        let common =
            scalarFloatField("moveSpeed", "Move speed", n -> Option.map(r -> r#moveSpeed, pick(n))) :: Nil;
        let advanced =
            vec2Field("upDirection",          "Up direction",          n -> Option.map(r -> r#upDirection, pick(n))) ::
            scalarFloatField("floorMaxAngle", "Floor max angle (rad)", n -> Option.map(r -> r#floorMaxAngle, pick(n))) ::
            intField("maxSlides",             "Max slides",            n -> Option.map(r -> r#maxSlides, pick(n))) ::
            boolField("monitoring",           "Monitoring",            n -> Option.map(r -> r#monitoring, pick(n))) ::
            boolField("monitorable",          "Monitorable",           n -> Option.map(r -> r#monitorable, pick(n))) ::
            intField("priority",              "Priority",              n -> Option.map(r -> r#priority, pick(n))) ::
            intField("collisionLayer",        "Collision layer",       n -> Option.map(r -> r#collisionLayer, pick(n))) ::
            intField("collisionMask",         "Collision mask",        n -> Option.map(r -> r#collisionMask, pick(n))) :: Nil;
        (common, advanced)

    def staticBody2DFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.StaticBody2DWithState(b, _) =>
                let StaticBody2D.StaticBody2D(r) = b; Some(r)
            case _ => None
        };
        let common =
            boolField("physicsCollisionEnabled", "Physics collision", n -> Option.map(r -> r#physicsCollisionEnabled, pick(n))) :: Nil;
        let advanced =
            boolField("monitoring",      "Monitoring",      n -> Option.map(r -> r#monitoring, pick(n))) ::
            boolField("monitorable",     "Monitorable",     n -> Option.map(r -> r#monitorable, pick(n))) ::
            intField("priority",         "Priority",        n -> Option.map(r -> r#priority, pick(n))) ::
            intField("collisionLayer",   "Collision layer", n -> Option.map(r -> r#collisionLayer, pick(n))) ::
            intField("collisionMask",    "Collision mask",  n -> Option.map(r -> r#collisionMask, pick(n))) :: Nil;
        (common, advanced)

    def textureRectFields(): (List[FieldDef], List[FieldDef]) =
        let pick = n -> match n {
            case EngineNode.TextureRectWithState(t, _) =>
                let TextureRect.TextureRect(r) = t; Some(r)
            case _ => None
        };
        let textureField: FieldDef = {
            name     = "texture",
            label    = "Texture",
            kind     = FieldKind.TexturePathT,
            snapshot = n -> Option.map(r -> stringToJson(r#texture), pick(n)),
            apply    = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                   sel#jsonPath, sel#jsonNodePath, "texture", s)
                case None    => ()
            }
        };
        let sizeField: FieldDef = {
            name     = "size",
            label    = "Size",
            kind     = FieldKind.Vec2T,
            snapshot = n -> Option.map(r -> vec2ToJson(r#size), pick(n)),
            apply    = (sel, j) -> match jsonToVec2(j) {
                case Some(v) => SceneSerializer.updateSize(sel#jsonPath, sel#jsonNodePath, v)
                case None    => ()
            }
        };
        let common = textureField :: sizeField :: Nil;
        let advanced =
            scalarFloat32Field("alpha", "Alpha",  n -> Option.map(r -> r#alpha, pick(n))) ::
            boolField("flipH",          "Flip H", n -> Option.map(r -> r#flipH, pick(n))) ::
            boolField("flipV",          "Flip V", n -> Option.map(r -> r#flipV, pick(n))) :: Nil;
        (common, advanced)

    // ───────────────────────── JSON ↔ 値 変換ヘルパー ─────────────────────────

    pub def vec2ToJson(v: Vec2.Vec2): Json.JsonElement =
        let pairs = ("x", floatToJson(v#x)) :: ("y", floatToJson(v#y)) :: Nil;
        Json.JsonElement.JsonObject(List.toMap(pairs))

    pub def jsonToVec2(j: Json.JsonElement): Option[Vec2.Vec2] =
        match j {
            case Json.JsonElement.JsonObject(m) =>
                let xOpt = Map.get("x", m) |> Option.flatMap(jsonToFloat);
                let yOpt = Map.get("y", m) |> Option.flatMap(jsonToFloat);
                match (xOpt, yOpt) {
                    case (Some(x), Some(y)) => Some({x = x, y = y})
                    case _                  => None
                }
            case _ => None
        }

    pub def floatToJson(v: Float64): Json.JsonElement =
        Json.JsonElement.JsonNumber(JBigDecimal.valueOf(v))

    pub def jsonToFloat(j: Json.JsonElement): Option[Float64] =
        match j {
            case Json.JsonElement.JsonNumber(bd) => BigDecimal.tryToFloat64(bd)
            case _                               => None
        }

    pub def intToJson(v: Int32): Json.JsonElement =
        Json.JsonElement.JsonNumber(unsafe IO {
            let bd = JBigDecimal.valueOf(Int32.toFloat64(v)).stripTrailingZeros();
            if (bd.scale() < 0) bd.setScale(0) else bd
        })

    pub def jsonToInt(j: Json.JsonElement): Option[Int32] =
        jsonToFloat(j) |> Option.flatMap(Float64.tryToInt32)

    pub def stringToJson(v: String): Json.JsonElement =
        Json.JsonElement.JsonString(v)

    pub def jsonToString(j: Json.JsonElement): Option[String] =
        match j {
            case Json.JsonElement.JsonString(s) => Some(s)
            case _                              => None
        }

    pub def boolToJson(v: Bool): Json.JsonElement =
        Json.JsonElement.JsonBool(v)

    pub def jsonToBool(j: Json.JsonElement): Option[Bool] =
        match j {
            case Json.JsonElement.JsonBool(b) => Some(b)
            case _                            => None
        }

    /// Color (r, g, b: Float32) を {r, g, b} の JsonObject に変換
    pub def colorToJson(c: Color): Json.JsonElement =
        let pairs = ("r", floatToJson(Float32.toFloat64(c#r))) ::
                    ("g", floatToJson(Float32.toFloat64(c#g))) ::
                    ("b", floatToJson(Float32.toFloat64(c#b))) :: Nil;
        Json.JsonElement.JsonObject(List.toMap(pairs))

    pub def jsonToColor(j: Json.JsonElement): Option[Color] =
        match j {
            case Json.JsonElement.JsonObject(m) =>
                let rOpt = Map.get("r", m) |> Option.flatMap(jsonToFloat);
                let gOpt = Map.get("g", m) |> Option.flatMap(jsonToFloat);
                let bOpt = Map.get("b", m) |> Option.flatMap(jsonToFloat);
                match (rOpt, gOpt, bOpt) {
                    case (Some(r), Some(g), Some(b)) =>
                        Some({r = Float64.tryToFloat32(r) |> Option.getWithDefault(1.0f32),
                              g = Float64.tryToFloat32(g) |> Option.getWithDefault(1.0f32),
                              b = Float64.tryToFloat32(b) |> Option.getWithDefault(1.0f32)})
                    case _ => None
                }
            case _ => None
        }

    def radToDeg(rad: Float64): Float64 = rad * 180.0 / 3.14159265358979

    def degToRad(deg: Float64): Float64 = deg * 3.14159265358979 / 180.0
}
