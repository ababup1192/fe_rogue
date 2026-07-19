// スライダーの値（World.Params）から池シェーダーの宣言（ShaderDoc.Spec）を組み立てる。
// 構造は Terraria 版の池 JSON（assets/water_caustic_pond.shader.json）と同じで、
// 網の細かさ・太さ・明るさ・流れ・歪み・ムラ・色をパラメータで差し替える。

mod PondShader {

    use ShaderDoc.Field
    use ShaderDoc.Shade
    use ShaderDoc.Out

    /// 0..1 の Float64 を色成分（Float32）へ。範囲外は 0..1 に丸める。
    def f32(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)

    /// 色を k 倍する（暗い縁を作るのに使う）。
    def scaleCol(c: Color, k: Float32): Color =
        { r = c#r * k, g = c#g * k, b = c#b * k }

    /// 2色を t で線形補間する。
    def mixCol(a: Color, b: Color, t: Float32): Color =
        { r = a#r + (b#r - a#r) * t,
          g = a#g + (b#g - a#g) * t,
          b = a#b + (b#b - a#b) * t }

    /// Params から池の Spec を組み立てる。網の細かさは worley factor(=netSize)だけで決まり、
    /// 画面上の見え方は「factor ÷ 池の大きさ」＝dungeon と同じ（UV は矩形内 0..1）。
    pub def build(p: World.Params): ShaderDoc.Spec =
        // Worley の網目を factor 倍（細かさ）＋流れでスクロールし、fbm でうねらせる。
        let worley = Field.Worley({ scale = 1.0, seed = 7, out = ShaderDoc.WorleyOut.F2mF1 });
        let scaled = Field.Scaled({ factor = p#netSize,
            scroll = { x = 0.015 * p#flowSpeed, y = 0.01 * p#flowSpeed }, of = worley });
        // waver: 大きくゆっくりした歪み。流れに乗って網目がゆらゆら揺らめく。
        let wavered = Field.Warp({ amount = p#warpAmt, scale = 2.5, seed = 11, of = scaled });
        // jag: 高周波の細かい歪み。全体の形は保ったまま網の縁を多少ギザギザに荒らす。
        let jagged = Field.Warp({ amount = p#jag, scale = 9.0, seed = 5, of = wavered });
        // smoothstep で細い目地に絞り、反転して「網が明るい」向きにする。
        let net = Field.Un({ op = ShaderDoc.UnOp.OneMinus,
            of = Field.Smoothstep({ lo = 0.0, hi = p#netThick, of = jagged }) });
        // fbm のムラ。のっぺりを崩す。
        let mottle = Field.Scaled({ factor = 2.0,
            scroll = { x = 0.008 * p#flowSpeed, y = 0.012 * p#flowSpeed },
            of = Field.Fbm({ octaves = 2, scale = 1.0, seed = 21 }) });
        // 明るさの場 = 0.34 + (mottle-0.5)*mottle係数 + net*明るさ係数。
        let field =
            Field.Bin({ op = ShaderDoc.BinOp.Add,
                a = Field.Bin({ op = ShaderDoc.BinOp.Add,
                    a = Field.Const(0.34),
                    b = Field.Bin({ op = ShaderDoc.BinOp.Mul,
                        a = Field.Bin({ op = ShaderDoc.BinOp.Sub,
                            a = mottle, b = Field.Const(0.5) }),
                        b = Field.Const(p#mottle) }) }),
                b = Field.Bin({ op = ShaderDoc.BinOp.Mul,
                    a = net, b = Field.Const(p#netBright) }) });
        // 色。基準色（スライダーの RGB）を軸に、暗い深み→基準→白寄りの4段グラデ。
        let base = { r = f32(p#colR), g = f32(p#colG), b = f32(p#colB) };
        let white = { r = 1.0f32, g = 1.0f32, b = 1.0f32 };
        let stops =
            (0.0, scaleCol(base, 0.72f32)) ::
            (0.4, base) ::
            (0.72, mixCol(base, white, 0.5f32)) ::
            (1.0, mixCol(base, white, 0.85f32)) :: Nil;
        { name = "pond", cycleRate = 0.0, bindings = Nil,
          out = Out.Fill({ shade = Shade.Gradient({ stops = stops, field = field }),
                           alpha = Field.Const(p#alpha) }) }
}
