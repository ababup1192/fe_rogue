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
    /// 基底クラス → 派生クラスの順で並べる (Swing/Godot Inspector の慣例)
    pub def sectionsFor(node: EngineNode[Unit]): List[FieldSection] =
        ({typeName = "Node2D", fields = node2DCommon()}: FieldSection) :: typeSpecific(node)

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
    /// 各セクションは1つの継承段 (例: Sprite2D は Node2D を継承するので Node2D 段は別途
    /// 自動付与され、ここには「Sprite2D 自身が定義する追加フィールド」を返す)
    def typeSpecific(_node: EngineNode[Unit]): List[FieldSection] =
        // 現状 Node2D 共通フィールド以外は未定義。Sprite2D の texture / Label2D の text 等は
        // 必要になったタイミングで以下に追加する
        Nil

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
