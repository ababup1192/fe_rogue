// ThemeDoc — tetris.theme.json（色票）の宣言ドキュメント層と、ミノの種類 → 実色の resolver。
// 盤・枠・ゴースト・閃光の色と、7 ミノの定番配色（I=シアン, O=黄, T=紫, S=緑, Z=赤, J=青, L=橙）を持つ。
// 派生色（ゴーストの薄めなど）は基準色から導ける範囲はコードで導く（導出できる値は Doc に置かない）。
// fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json
    use World.Kind

    /// 画面の色票。bg = 盤の外の背景、board = 盤の中の背景（bg よりわずかに明るい）、
    /// grid = マス目の線（薄い）、wall = 盤を囲う枠、ghost = 着地予測の色、
    /// flash = ライン消しの閃光（白系）、colorI..colorL = 7 ミノの色。
    pub type alias Doc = {
        version = Int32,
        bg = Color,
        board = Color,
        grid = Color,
        wall = Color,
        ghost = Color,
        flash = Color,
        colorI = Color,
        colorO = Color,
        colorT = Color,
        colorS = Color,
        colorZ = Color,
        colorJ = Color,
        colorL = Color
    }

    pub def path(): String = "assets/tetris.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/tetris.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          bg     = rgb(0.058824, 0.070588, 0.101961),   // #0f121a 盤外の暗い紺
          board  = rgb(0.101961, 0.117647, 0.156690),   // #1a1e28 盤内はほんの少し明るい
          grid   = rgb(0.180392, 0.203922, 0.258824),   // #2e3442 マス目の線
          wall   = rgb(0.317647, 0.352941, 0.443137),   // #515a71 枠
          ghost  = rgb(0.470588, 0.517647, 0.611765),   // #78849c 着地予測
          flash  = rgb(1.000000, 1.000000, 1.000000),   // #ffffff 閃光（白）
          colorI = rgb(0.313725, 0.815686, 0.878431),   // シアン
          colorO = rgb(0.945098, 0.796078, 0.235294),   // 黄
          colorT = rgb(0.674510, 0.376471, 0.847059),   // 紫
          colorS = rgb(0.400000, 0.788235, 0.360784),   // 緑
          colorZ = rgb(0.898039, 0.313725, 0.372549),   // 赤
          colorJ = rgb(0.298039, 0.474510, 0.878431),   // 青
          colorL = rgb(0.945098, 0.564706, 0.235294) }  // 橙

    /// ミノの種類 → 実色（固定セル・落下中ミノ・NEXT が使う）。
    pub def colorOf(doc: Doc, kind: Kind): Color =
        match kind {
            case Kind.I => doc#colorI
            case Kind.O => doc#colorO
            case Kind.T => doc#colorT
            case Kind.S => doc#colorS
            case Kind.Z => doc#colorZ
            case Kind.J => doc#colorJ
            case Kind.L => doc#colorL
        }

    /// 白に寄せる（ハイライト）。ミノ天面の照りなどに使う。
    pub def lighten(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(k);
        { r = c#r + (1.0f32 - c#r) * t, g = c#g + (1.0f32 - c#g) * t, b = c#b + (1.0f32 - c#b) * t }

    /// 黒に寄せる（影）。
    pub def darken(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(1.0 - k);
        { r = c#r * t, g = c#g * t, b = c#b * t }

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          bg     = colorOr(d#bg, "bg", root),
          board  = colorOr(d#board, "board", root),
          grid   = colorOr(d#grid, "grid", root),
          wall   = colorOr(d#wall, "wall", root),
          ghost  = colorOr(d#ghost, "ghost", root),
          flash  = colorOr(d#flash, "flash", root),
          colorI = colorOr(d#colorI, "colorI", root),
          colorO = colorOr(d#colorO, "colorO", root),
          colorT = colorOr(d#colorT, "colorT", root),
          colorS = colorOr(d#colorS, "colorS", root),
          colorZ = colorOr(d#colorZ, "colorZ", root),
          colorJ = colorOr(d#colorJ, "colorJ", root),
          colorL = colorOr(d#colorL, "colorL", root) }

    def colorOr(fallbackColor: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallbackColor)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
