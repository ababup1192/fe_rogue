// CarView — 浮遊マシンを翼・船体・コックピット・噴射光へ分けて描く。
// 形はコードに置き、色と遠近だけを外から受け取る。
mod CarView {

    /// 遠くでも色に頼らず見分けられる、3種類の機体輪郭。
    pub enum Silhouette {
        case Player,
        case Dart,
        case Twin
    }

    /// 1台を描くために必要な情報。
    pub type alias Spec = {
        center = Vec2.Vec2,
        color = Color,
        z = Int32,
        scale = Float64,
        boosting = Bool,
        bank = Float64,
        thrust = Float64,
        silhouette = Silhouette
    }

    /// 後ろ姿の浮遊マシンを、遠景でも輪郭が潰れにくい多角形で組む。
    pub def draw(spec: Spec): List[Render.PlacedItem] =
        let dark = ThemeDoc.darken(spec#color, 0.76);
        let glass = ThemeDoc.darken(spec#color, 0.45);
        let bright = ThemeDoc.lighten(spec#color, 0.58);
        let thrust = Float64.max(0.0, Float64.min(1.0, spec#thrust));
        let flameLength = 7.0 + thrust * 24.0 + if (spec#boosting) 15.0 else 0.0;
        let exhaustSize = 12.0 + thrust * 12.0 + if (spec#boosting) 12.0 else 0.0;
        let exhaustAlpha = if (spec#boosting) 0.72 else 0.34;
        // 色覚や遠近に左右されない識別へ寄せるため、ライバルも自機と同じ輪郭にはしない。
           polygon(spec, flameVertices(-10.0, flameLength, spec#scale),
                   bright, spec#z)
        ::: polygon(spec, flameVertices(10.0, flameLength, spec#scale),
                    spec#color, spec#z)
        ::: glow(
               { x = spec#center#x - 10.0 * spec#scale,
                 y = spec#center#y + 14.0 * spec#scale },
               exhaustSize * spec#scale, spec#color, exhaustAlpha, spec#z)
        ::: glow(
               { x = spec#center#x + 10.0 * spec#scale,
                 y = spec#center#y + 14.0 * spec#scale },
               exhaustSize * spec#scale, bright, exhaustAlpha, spec#z)
        ::: body(spec, dark, glass)
        ::: polygon(spec, rearLightVertices(spec#scale), bright, spec#z + 4)

    /// 輪郭ごとの面構成。描画だけを分け、運転規則と当たり判定は World に残す。
    def body(spec: Spec, dark: Color, glass: Color): List[Render.PlacedItem] =
        match spec#silhouette {
            case Silhouette.Player =>
                   polygon(spec, wingVertices(spec#scale), dark, spec#z + 1)
                ::: polygon(spec, hullVertices(spec#scale), spec#color, spec#z + 2)
                ::: polygon(spec, canopyVertices(spec#scale), glass, spec#z + 3),
            case Silhouette.Dart =>
                   polygon(spec, dartFinVertices(spec#scale), dark, spec#z + 1)
                ::: polygon(spec, dartHullVertices(spec#scale), spec#color, spec#z + 2)
                ::: polygon(spec, dartCanopyVertices(spec#scale), glass, spec#z + 3),
            case Silhouette.Twin =>
                   polygon(spec, twinBridgeVertices(spec#scale), dark, spec#z + 1)
                ::: polygon(spec, twinLeftVertices(spec#scale), spec#color, spec#z + 2)
                ::: polygon(spec, twinRightVertices(spec#scale), spec#color, spec#z + 2)
                ::: polygon(spec, twinCanopyVertices(spec#scale), glass, spec#z + 3)
        }

    /// 左右へ張り出す安定翼の輪郭。
    def wingVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = -27.0, y = 7.0 }
            :: { x = -19.0, y = -4.0 }
            :: { x = -9.0, y = -1.0 }
            :: { x = 0.0, y = -10.0 }
            :: { x = 9.0, y = -1.0 }
            :: { x = 19.0, y = -4.0 }
            :: { x = 27.0, y = 7.0 }
            :: { x = 13.0, y = 13.0 }
            :: { x = -13.0, y = 13.0 }
            :: Nil)

    /// 中央船体の輪郭。
    def hullVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 0.0, y = -19.0 }
            :: { x = 13.0, y = -5.0 }
            :: { x = 11.0, y = 14.0 }
            :: { x = -11.0, y = 14.0 }
            :: { x = -13.0, y = -5.0 }
            :: Nil)

    /// 後方から光を拾うコックピットの面。
    def canopyVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 0.0, y = -12.0 }
            :: { x = 7.0, y = -3.0 }
            :: { x = 5.0, y = 5.0 }
            :: { x = -5.0, y = 5.0 }
            :: { x = -7.0, y = -3.0 }
            :: Nil)

    /// 先端の長い矢じり型。細身でも後端のフィンで横幅を読める。
    def dartFinVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = -23.0, y = 12.0 }
            :: { x = -9.0, y = 0.0 }
            :: { x = 0.0, y = 5.0 }
            :: { x = 9.0, y = 0.0 }
            :: { x = 23.0, y = 12.0 }
            :: { x = 8.0, y = 14.0 }
            :: { x = -8.0, y = 14.0 }
            :: Nil)

    def dartHullVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 0.0, y = -24.0 }
            :: { x = 8.0, y = 2.0 }
            :: { x = 6.0, y = 16.0 }
            :: { x = -6.0, y = 16.0 }
            :: { x = -8.0, y = 2.0 }
            :: Nil)

    def dartCanopyVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 0.0, y = -10.0 }
            :: { x = 4.0, y = 3.0 }
            :: { x = -4.0, y = 3.0 }
            :: Nil)

    /// 双胴型は中央を空け、左右2本の船体を遠景でも残す。
    def twinBridgeVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = -19.0, y = 1.0 }
            :: { x = 19.0, y = 1.0 }
            :: { x = 19.0, y = 9.0 }
            :: { x = -19.0, y = 9.0 }
            :: Nil)

    def twinLeftVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = -15.0, y = -17.0 }
            :: { x = -7.0, y = -5.0 }
            :: { x = -8.0, y = 16.0 }
            :: { x = -23.0, y = 13.0 }
            :: { x = -22.0, y = -5.0 }
            :: Nil)

    def twinRightVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 15.0, y = -17.0 }
            :: { x = 22.0, y = -5.0 }
            :: { x = 23.0, y = 13.0 }
            :: { x = 8.0, y = 16.0 }
            :: { x = 7.0, y = -5.0 }
            :: Nil)

    def twinCanopyVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = 0.0, y = -9.0 }
            :: { x = 6.0, y = 4.0 }
            :: { x = 0.0, y = 10.0 }
            :: { x = -6.0, y = 4.0 }
            :: Nil)

    /// 後方へ細く伸びるバーナー。加速とブーストで長さだけが変わる。
    def flameVertices(offsetX: Float64, length: Float64,
                      scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = offsetX - 3.5, y = 11.0 }
            :: { x = offsetX + 3.5, y = 11.0 }
            :: { x = offsetX + 1.3, y = 11.0 + length }
            :: { x = offsetX, y = 15.0 + length }
            :: { x = offsetX - 1.3, y = 11.0 + length }
            :: Nil)

    def rearLightVertices(scale: Float64): List[Vec2.Vec2] =
        scaleVertices(scale,
            { x = -13.0, y = 6.8 }
            :: { x = 13.0, y = 6.8 }
            :: { x = 13.0, y = 9.3 }
            :: { x = -13.0, y = 9.3 }
            :: Nil)

    /// 相対頂点を機体中心へ置く。
    def polygon(spec: Spec, vertices: List[Vec2.Vec2],
                color: Color, z: Int32): List[Render.PlacedItem] =
        { at = spec#center,
          item = Render.polygon(bankVertices(spec#bank, vertices), color, z) } :: Nil

    /// 左右入力で翼端の高さを変え、平面上でも機体が旋回へ反応して見えるようにする。
    def bankVertices(bank: Float64, vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        vertices |> List.map(vertex ->
            { x = vertex#x, y = vertex#y + vertex#x * bank })

    /// 遠近に合わせて機体の輪郭を等倍縮小する。
    def scaleVertices(scale: Float64, vertices: List[Vec2.Vec2]): List[Vec2.Vec2] =
        vertices |> List.map(vertex ->
            { x = vertex#x * scale, y = vertex#y * scale })

    /// 加算光をリストとして返し、機体の面と連結しやすくする。
    def glow(center: Vec2.Vec2, radius: Float64, color: Color,
             alpha: Float64, z: Int32): List[Render.PlacedItem] =
        Render.glowAt(
            center, radius, color,
            { alpha = alpha, blend = DrawCmd.BlendMode.Add }, z)
}
