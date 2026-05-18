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

    /// 1 フィールドの表現種別。ScenePanel がこの kind に応じて widget を選ぶ
    pub enum FieldKind with Eq, ToString {
        case Vec2T
        case FloatT
        case IntT
        case TextT
        case TexturePathT
        case BoolT
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
    ///   fields:   そのクラスで定義されるフィールド列
    /// Inspector はセクションごとに header label を入れて区切る
    pub type alias FieldSection = {
        typeName = String,
        fields   = List[FieldDef]
    }

    /// 選択 node の継承階層に沿ったセクション列を返す。
    /// 派生クラス → 基底クラスの順で並べる (派生フィールドを上、共通フィールドを下に表示)
    pub def sectionsFor(node: EngineNode[Unit]): List[FieldSection] =
        List.append(typeSpecific(node),
                    ({typeName = "Node2D", fields = node2DCommon()}: FieldSection) :: Nil)

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

    /// 型固有セクションのリスト。新しい node 型の Inspector を追加するときはここに case を増やす。
    /// 各セクションは 1 つの継承段 (Node2D 段は別途自動付与され、ここには
    /// 「その型自身が定義する追加フィールド」を返す)
    def typeSpecific(node: EngineNode[Unit]): List[FieldSection] = match node {
        case EngineNode.Sprite2DWithState(_, _) =>
            ({typeName = "Sprite2D", fields = sprite2DFields()}: FieldSection) :: Nil
        case EngineNode.AnimSprite2DWithState(_, _) =>
            ({typeName = "AnimatedSprite2D", fields = animSprite2DFields()}: FieldSection) :: Nil
        case EngineNode.Label2DWithState(_, _) =>
            ({typeName = "Label2D", fields = label2DFields()}: FieldSection) :: Nil
        case _ => Nil
    }

    // ───────────────────────── Sprite2D 固有フィールド ─────────────────────────

    /// Sprite2D 自身が定義するフィールド (Node2D の position/scale/rotation は含めない)
    def sprite2DFields(): List[FieldDef] =
        ({
            name     = "texture",
            label    = "Texture",
            kind     = FieldKind.TexturePathT,
            snapshot = n -> match n {
                case EngineNode.Sprite2DWithState(s, _) =>
                    let Sprite2D.Sprite2D(r) = s;
                    Some(stringToJson(r#texture))
                case _ => None
            },
            apply = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                  sel#jsonPath, sel#jsonNodePath, "texture", s)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "visible",
            label    = "Visible",
            kind     = FieldKind.BoolT,
            snapshot = n -> match n {
                case EngineNode.Sprite2DWithState(s, _) =>
                    let Sprite2D.Sprite2D(r) = s;
                    Some(boolToJson(r#visible))
                case _ => None
            },
            apply = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                  sel#jsonPath, sel#jsonNodePath, "visible", b)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "zIndex",
            label    = "Z index",
            kind     = FieldKind.IntT,
            snapshot = n -> match n {
                case EngineNode.Sprite2DWithState(s, _) =>
                    let Sprite2D.Sprite2D(r) = s;
                    Some(intToJson(r#zIndex))
                case _ => None
            },
            apply = (sel, j) -> match jsonToInt(j) {
                case Some(v) => SceneSerializer.updateInt(
                                  sel#jsonPath, sel#jsonNodePath, "zIndex", v)
                case None    => ()
            }
        }: FieldDef) :: Nil

    // ──────────────────── AnimatedSprite2D 固有フィールド ────────────────────

    /// AnimatedSprite2D 自身が定義するフィールド (Node2D 共通は別途付与)
    def animSprite2DFields(): List[FieldDef] =
        ({
            name     = "animation",
            label    = "Animation",
            kind     = FieldKind.TextT,
            snapshot = n -> match n {
                case EngineNode.AnimSprite2DWithState(s, _) =>
                    let AnimatedSprite2D.AnimatedSprite2D(r) = s;
                    Some(stringToJson(r#animation))
                case _ => None
            },
            apply = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                  sel#jsonPath, sel#jsonNodePath, "animation", s)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "playing",
            label    = "Playing",
            kind     = FieldKind.BoolT,
            snapshot = n -> match n {
                case EngineNode.AnimSprite2DWithState(s, _) =>
                    let AnimatedSprite2D.AnimatedSprite2D(r) = s;
                    Some(boolToJson(r#playing))
                case _ => None
            },
            apply = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                  sel#jsonPath, sel#jsonNodePath, "playing", b)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "speedScale",
            label    = "Speed scale",
            kind     = FieldKind.FloatT,
            snapshot = n -> match n {
                case EngineNode.AnimSprite2DWithState(s, _) =>
                    let AnimatedSprite2D.AnimatedSprite2D(r) = s;
                    Some(floatToJson(r#speedScale))
                case _ => None
            },
            apply = (sel, j) -> match jsonToFloat(j) {
                case Some(v) => SceneSerializer.updateFields(
                                  sel#jsonPath, sel#jsonNodePath,
                                  ({key = "speedScale",
                                    value = SceneSerializer.FieldValue.ScalarValue(v)}: SceneSerializer.FieldUpdate) :: Nil)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "visible",
            label    = "Visible",
            kind     = FieldKind.BoolT,
            snapshot = n -> match n {
                case EngineNode.AnimSprite2DWithState(s, _) =>
                    let AnimatedSprite2D.AnimatedSprite2D(r) = s;
                    Some(boolToJson(r#visible))
                case _ => None
            },
            apply = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                  sel#jsonPath, sel#jsonNodePath, "visible", b)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "zIndex",
            label    = "Z index",
            kind     = FieldKind.IntT,
            snapshot = n -> match n {
                case EngineNode.AnimSprite2DWithState(s, _) =>
                    let AnimatedSprite2D.AnimatedSprite2D(r) = s;
                    Some(intToJson(r#zIndex))
                case _ => None
            },
            apply = (sel, j) -> match jsonToInt(j) {
                case Some(v) => SceneSerializer.updateInt(
                                  sel#jsonPath, sel#jsonNodePath, "zIndex", v)
                case None    => ()
            }
        }: FieldDef) :: Nil

    // ───────────────────────── Label2D 固有フィールド ─────────────────────────

    /// Label2D 自身が定義するフィールド
    def label2DFields(): List[FieldDef] =
        ({
            name     = "text",
            label    = "Text",
            kind     = FieldKind.TextT,
            snapshot = n -> match n {
                case EngineNode.Label2DWithState(l, _) => Some(stringToJson(Label2D.getText(l)))
                case _ => None
            },
            apply = (sel, j) -> match jsonToString(j) {
                case Some(s) => SceneSerializer.updateString(
                                  sel#jsonPath, sel#jsonNodePath, "text", s)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "fontSize",
            label    = "Font size",
            kind     = FieldKind.FloatT,
            snapshot = n -> match n {
                case EngineNode.Label2DWithState(l, _) => Some(floatToJson(Label2D.getFontSize(l)))
                case _ => None
            },
            apply = (sel, j) -> match jsonToFloat(j) {
                case Some(v) => SceneSerializer.updateFontSize(
                                  sel#jsonPath, sel#jsonNodePath, v)
                case None    => ()
            }
        }: FieldDef) ::
        ({
            name     = "visible",
            label    = "Visible",
            kind     = FieldKind.BoolT,
            snapshot = n -> match n {
                case EngineNode.Label2DWithState(l, _) =>
                    let Label2D.Label2D(r) = l;
                    Some(boolToJson(r#visible))
                case _ => None
            },
            apply = (sel, j) -> match jsonToBool(j) {
                case Some(b) => SceneSerializer.updateBool(
                                  sel#jsonPath, sel#jsonNodePath, "visible", b)
                case None    => ()
            }
        }: FieldDef) :: Nil

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

    def radToDeg(rad: Float64): Float64 = rad * 180.0 / 3.14159265358979

    def degToRad(deg: Float64): Float64 = deg * 3.14159265358979 / 180.0
}
