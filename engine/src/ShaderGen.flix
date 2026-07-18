// ShaderGen — Spec を GLSL の fragment シェーダー文字列へ変換する codegen。
// 各部品が自分の GLSL 片（式）を返し、compile がそれらを 1 枚の main() に繋ぐ。
// 出力は決定論（同じ Spec なら常に同じ文字列）なので、テストは絵でなくこの文字列を
// スナップショットで釘打ちできる（codegen を変えたら差分で検出＝リグレッション網）。
// 任意 GLSL は書けない — 語彙の合成だけが GLSL になる。ノイズ（hash2/worley/fbm）は
// prelude に固定テンプレとして持ち、Spec スナップから分離する（prelude 改訂は 1 か所だけ動く）。
// 座標変換（Scaled/Warp）は「inner が読む uv の式」を差し替えることで表す。

mod ShaderGen {

    /// vertex シェーダー（面 quad 1 枚・uv を渡すだけ）。Spec に依存しない固定ソース。
    /// vertex.xy = 0..1 の quad ローカル座標を rect（px）へ写し、vertex.zw を uv として渡す。
    pub def vertexSource(): String =
        "#version 330 core\n" +
        "layout (location = 0) in vec4 vertex;\n" +
        "out vec2 vUv;\n" +
        "uniform mat4 projection;\n" +
        "uniform vec2 uRectPos;\n" +
        "uniform vec2 uRectSize;\n" +
        "void main() {\n" +
        "    vec2 screenPos = uRectPos + vertex.xy * uRectSize;\n" +
        "    gl_Position = projection * vec4(screenPos, 0.0, 1.0);\n" +
        "    vUv = vertex.zw;\n" +
        "}\n"

    /// ノイズ関数の固定テンプレ（hash2 / worley / fbm）。Spec に依存しないので 1 度だけ pin し、
    /// Spec スナップショットからは除外する（テストで preludeSource を別途スナップする）。
    pub def preludeSource(): String =
        "float sg_hash1(vec2 p, float seed) {\n" +
        "    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 0.017) * 43758.5453123);\n" +
        "}\n" +
        "vec2 sg_hash2(vec2 p, float seed) {\n" +
        "    return vec2(sg_hash1(p, seed), sg_hash1(p + vec2(19.19, 7.31), seed));\n" +
        "}\n" +
        // Worley: 近傍 3x3 セルの特徴点までの距離から F1(最近) と F2(次近) を求める。
        "vec2 sg_worleyF1F2(vec2 p, float seed) {\n" +
        "    vec2 ip = floor(p);\n" +
        "    vec2 fp = fract(p);\n" +
        "    float f1 = 8.0; float f2 = 8.0;\n" +
        "    for (int j = -1; j <= 1; j++) {\n" +
        "        for (int i = -1; i <= 1; i++) {\n" +
        "            vec2 g = vec2(float(i), float(j));\n" +
        "            vec2 o = sg_hash2(ip + g, seed);\n" +
        "            vec2 r = g + o - fp;\n" +
        "            float d = length(r);\n" +
        "            if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }\n" +
        "        }\n" +
        "    }\n" +
        "    return vec2(f1, f2);\n" +
        "}\n" +
        // value noise（格子 4 点の hash を双一次補間）と、その多重和 fbm。
        "float sg_valueNoise(vec2 p, float seed) {\n" +
        "    vec2 ip = floor(p);\n" +
        "    vec2 fp = fract(p);\n" +
        "    vec2 w = fp * fp * (3.0 - 2.0 * fp);\n" +
        "    float a = sg_hash1(ip + vec2(0.0, 0.0), seed);\n" +
        "    float b = sg_hash1(ip + vec2(1.0, 0.0), seed);\n" +
        "    float c = sg_hash1(ip + vec2(0.0, 1.0), seed);\n" +
        "    float d = sg_hash1(ip + vec2(1.0, 1.0), seed);\n" +
        "    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);\n" +
        "}\n" +
        // 規則的な丸い鱗: 行ごとに stagger だけずらした格子点への「最近距離」（0→1）。
        // 近傍 3x3 の格子点を見て最短を取るので、隙間なくタイル状に繋がる（孤立した円にならない）。
        "float sg_scales(vec2 uv, float scale, float stagger) {\n" +
        "    vec2 p = uv * scale;\n" +
        "    vec2 ip = floor(p);\n" +
        "    float best = 8.0;\n" +
        "    for (int j = -1; j <= 1; j++) {\n" +
        "        for (int i = -1; i <= 1; i++) {\n" +
        "            vec2 cell = ip + vec2(float(i), float(j));\n" +
        "            vec2 center = cell + vec2(0.5 + mod(cell.y, 2.0) * stagger, 0.5);\n" +
        "            best = min(best, length(p - center));\n" +
        "        }\n" +
        "    }\n" +
        "    return clamp(best, 0.0, 1.0);\n" +
        "}\n" +
        // まばらに明滅する短い横線のきらめき。セルごとに density で点灯・位相ずれで sin 明滅。
        "float sg_glints(vec2 uv, float scale, float rate, float density, float seed) {\n" +
        "    vec2 p = uv * scale;\n" +
        "    vec2 ip = floor(p);\n" +
        "    vec2 fp = fract(p);\n" +
        "    float on = step(1.0 - density, sg_hash1(ip, seed));\n" +
        "    float phase = sg_hash1(ip, seed + 7.0) * 6.2831853;\n" +
        "    float tw = max(0.0, sin(uTime * rate + phase));\n" +
        "    float dash = (1.0 - smoothstep(0.04, 0.10, abs(fp.y - 0.5))) *\n" +
        "                 (1.0 - smoothstep(0.28, 0.46, abs(fp.x - 0.5)));\n" +
        "    return on * tw * dash;\n" +
        "}\n" +
        // 横に波打つ縞: y にサインのゆらぎ(wob)を足した band を、時間で縦に流す。出力 0..1。
        "float sg_ripples(vec2 uv, float freq, float amp, float speed, float seed) {\n" +
        "    float wob = sin(uv.x * 6.2831853 * freq * 0.5 + seed) * amp\n" +
        "              + sin(uv.x * 6.2831853 * freq * 1.3 + seed * 2.7) * amp * 0.4;\n" +
        "    float band = uv.y * freq + wob + uTime * speed;\n" +
        "    return 0.5 + 0.5 * sin(band * 6.2831853);\n" +
        "}\n" +
        // キラッと光る菱形。点滅の回 cyc ごとに「光るセル(on)」と「セル内の位置(pos)」を選び直すので
        // 同じ場所で繰り返さず毎回ランダムな所に出る。pow を大きくして一瞬で光り一瞬で消える鋭いパルス。
        "float sg_sparkle(vec2 uv, float scale, float rate, float density, float seed) {\n" +
        "    vec2 p = uv * scale;\n" +
        "    vec2 ip = floor(p);\n" +
        "    vec2 fp = fract(p);\n" +
        "    float t = uTime * rate + sg_hash1(ip, seed + 3.0) * 6.2831853;\n" +
        "    float cyc = floor(t / 6.2831853);\n" +
        "    float on = step(1.0 - density, sg_hash1(ip + cyc, seed));\n" +
        "    float tw = pow(max(0.0, sin(t)), 12.0);\n" +
        "    vec2 pos = 0.15 + 0.7 * sg_hash2(ip + cyc, seed + 11.0);\n" +
        "    vec2 e = fp - pos;\n" +
        "    float d = abs(e.x) + abs(e.y);\n" +
        "    float point = 1.0 - smoothstep(0.04, 0.26, d);\n" +
        "    return on * tw * point;\n" +
        "}\n" +
        "float sg_fbm(vec2 p, int octaves, float seed) {\n" +
        "    float sum = 0.0; float amp = 0.5; float freq = 1.0;\n" +
        "    for (int i = 0; i < octaves; i++) {\n" +
        "        sum += amp * sg_valueNoise(p * freq, seed + float(i) * 13.0);\n" +
        "        freq *= 2.0; amp *= 0.5;\n" +
        "    }\n" +
        "    return sum;\n" +
        "}\n"

    /// Spec → fragment シェーダー全体（prelude + main）。uTime uniform を前提に持つ。
    pub def compile(spec: ShaderDoc.Spec): String =
        "#version 330 core\n" +
        "in vec2 vUv;\n" +
        "out vec4 outColor;\n" +
        "uniform float uTime;\n" +
        preludeSource() +
        "void main() {\n" +
        "    " + outStmt(spec#cycleRate, spec#out) + "\n" +
        "}\n"

    // ── main 本体（prelude 抜き）のスナップショット用。ノイズテンプレを混ぜず Spec だけ pin する。──
    pub def compileBody(spec: ShaderDoc.Spec): String =
        outStmt(spec#cycleRate, spec#out)

    def outStmt(cycleRate: Float64, out: ShaderDoc.Out): String =
        match out {
            case ShaderDoc.Out.Fill(f) =>
                "outColor = vec4(" + shadeExpr(cycleRate, f#shade) + ", " +
                fieldExpr(f#alpha, "vUv") + ");"
        }

    def shadeExpr(cycleRate: Float64, shade: ShaderDoc.Shade): String =
        match shade {
            case ShaderDoc.Shade.Solid(c) => vec3Lit(c)
            case ShaderDoc.Shade.Ramp(r)  =>
                // cycleRate = 0 は素直な補間（field 0→lo・1→hi）。cycleRate>0 のときだけ
                // field を cycleRate*uTime で往復させる三角波にして色が呼吸する（パレット循環）。
                let factor =
                    if (cycleRate == 0.0)
                        "clamp(" + fieldExpr(r#field, "vUv") + ", 0.0, 1.0)"
                    else
                        "clamp(abs(fract((" + fieldExpr(r#field, "vUv") + ") + " +
                        f(cycleRate) + " * uTime) * 2.0 - 1.0), 0.0, 1.0)";
                "mix(" + vec3Lit(r#lo) + ", " + vec3Lit(r#hi) + ", " + factor + ")"
        }

    /// 場を GLSL の float 式へ。uv は「今読むべき座標」の GLSL 式（Scaled/Warp が差し替える）。
    def fieldExpr(field: ShaderDoc.Field, uv: String): String =
        match field {
            case ShaderDoc.Field.Const(v) => f(v)
            case ShaderDoc.Field.Uv(u)    =>
                match u#axis {
                    case ShaderDoc.Axis.U => "(" + uv + ").x"
                    case ShaderDoc.Axis.V => "(" + uv + ").y"
                }
            case ShaderDoc.Field.Worley(w) =>
                let inner = "sg_worleyF1F2((" + uv + ") * " + f(w#scale) + ", " + fSeed(w#seed) + ")";
                match w#out {
                    case ShaderDoc.WorleyOut.F1    => "(" + inner + ".x)"
                    case ShaderDoc.WorleyOut.F2    => "(" + inner + ".y)"
                    case ShaderDoc.WorleyOut.F2mF1 => "(" + inner + ".y - " + inner + ".x)"
                }
            case ShaderDoc.Field.Fbm(b) =>
                "sg_fbm((" + uv + ") * " + f(b#scale) + ", " + iLit(b#octaves) + ", " + fSeed(b#seed) + ")"
            case ShaderDoc.Field.Smoothstep(s) =>
                "smoothstep(" + f(s#lo) + ", " + f(s#hi) + ", " + fieldExpr(s#of, uv) + ")"
            case ShaderDoc.Field.Scaled(s) =>
                // inner の見る座標を factor 倍 + uTime*scroll で差し替える。
                let uv2 = "((" + uv + ") * " + f(s#factor) + " + vec2(" +
                          f(s#scroll#x) + ", " + f(s#scroll#y) + ") * uTime)";
                fieldExpr(s#of, uv2)
            case ShaderDoc.Field.Warp(wp) =>
                // fbm でずらしたオフセットを uv に足して inner を読む（ドメインワープ）。
                let off = "(vec2(sg_fbm((" + uv + ") * " + f(wp#scale) + ", 3, " + fSeed(wp#seed) +
                          "), sg_fbm((" + uv + ") * " + f(wp#scale) + ", 3, " + fSeed(wp#seed) + " + 91.0)) - 0.5)";
                let uv2 = "((" + uv + ") + " + off + " * " + f(wp#amount) + ")";
                fieldExpr(wp#of, uv2)
            case ShaderDoc.Field.Mix(m) =>
                "mix(" + fieldExpr(m#a, uv) + ", " + fieldExpr(m#b, uv) + ", " + f(m#t) + ")"
            case ShaderDoc.Field.Blend(bl) =>
                "mix(" + fieldExpr(bl#a, uv) + ", " + fieldExpr(bl#b, uv) + ", " +
                "clamp(" + fieldExpr(bl#by, uv) + ", 0.0, 1.0))"
            case ShaderDoc.Field.Disk(d) =>
                // 中心からの距離が radius 以内で 1、radius→radius+feather で 0 へ soft fade。
                "(1.0 - smoothstep(" + f(d#radius) + ", " + f(d#radius + d#feather) + ", " +
                "length((" + uv + ") - vec2(" + f(d#cx) + ", " + f(d#cy) + "))))"
            case ShaderDoc.Field.Scales(sc) =>
                "sg_scales((" + uv + "), " + f(sc#scale) + ", " + f(sc#stagger) + ")"
            case ShaderDoc.Field.Glints(g) =>
                "sg_glints((" + uv + "), " + f(g#scale) + ", " + f(g#rate) + ", " +
                f(g#density) + ", " + fSeed(g#seed) + ")"
            case ShaderDoc.Field.Ripples(rp) =>
                "sg_ripples((" + uv + "), " + f(rp#freq) + ", " + f(rp#amp) + ", " +
                f(rp#speed) + ", " + fSeed(rp#seed) + ")"
            case ShaderDoc.Field.Sparkle(sp) =>
                "sg_sparkle((" + uv + "), " + f(sp#scale) + ", " + f(sp#rate) + ", " +
                f(sp#density) + ", " + fSeed(sp#seed) + ")"
            case ShaderDoc.Field.Bin(bn) =>
                let ae = fieldExpr(bn#a, uv);
                let be = fieldExpr(bn#b, uv);
                match bn#op {
                    case ShaderDoc.BinOp.Add  => "(" + ae + " + " + be + ")"
                    case ShaderDoc.BinOp.Sub  => "(" + ae + " - " + be + ")"
                    case ShaderDoc.BinOp.Mul  => "(" + ae + " * " + be + ")"
                    case ShaderDoc.BinOp.Min  => "min(" + ae + ", " + be + ")"
                    case ShaderDoc.BinOp.Max  => "max(" + ae + ", " + be + ")"
                    case ShaderDoc.BinOp.Step => "step(" + ae + ", " + be + ")"
                }
            case ShaderDoc.Field.Un(un) =>
                let x = fieldExpr(un#of, uv);
                match un#op {
                    case ShaderDoc.UnOp.Neg      => "(-(" + x + "))"
                    case ShaderDoc.UnOp.Abs      => "abs(" + x + ")"
                    case ShaderDoc.UnOp.Fract    => "fract(" + x + ")"
                    case ShaderDoc.UnOp.Floor    => "floor(" + x + ")"
                    case ShaderDoc.UnOp.Sin      => "sin(" + x + ")"
                    case ShaderDoc.UnOp.Cos      => "cos(" + x + ")"
                    case ShaderDoc.UnOp.Sat      => "clamp(" + x + ", 0.0, 1.0)"
                    case ShaderDoc.UnOp.OneMinus => "(1.0 - (" + x + "))"
                }
            case ShaderDoc.Field.Pow(pw) =>
                // 整数指数は pow() でなく反復積の文字列にして CPU 側の反復積と構造を合わせる
                // （GPU/CPU で丸め順が揃いパリティが強くなる）。負の底の非整数乗は NaN なので 0 で下切り。
                let base = "max(0.0, " + fieldExpr(pw#of, uv) + ")";
                if (Float64.floor(pw#p) == pw#p)
                    powProduct(base, Float64.floor(pw#p))
                else
                    "pow(max(0.0, (" + fieldExpr(pw#of, uv) + ")), " + f(pw#p) + ")"
            case ShaderDoc.Field.Time(tm) =>
                "(uTime * " + f(tm#scale) + " + (" + fieldExpr(tm#offset, uv) + "))"
        }

    /// base を n 回掛けた GLSL 積の文字列（n=0 は 1.0・n=1 は base そのもの）。
    /// CPU 側の反復積と同じ左結合の並びにする。
    def powProduct(base: String, n: Float64): String =
        let k = Int32.max(0, Float64.tryToInt32(n) |> Option.getWithDefault(0));
        if (k == 0) "1.0"
        else List.foldLeft((acc, _) -> "(" + acc + " * " + base + ")",
                           base, List.range(1, k))

    def vec3Lit(c: Color): String =
        "vec3(" + f32(c#r) + ", " + f32(c#g) + ", " + f32(c#b) + ")"

    /// GLSL の float リテラル（決定論のため必ず小数点を含める）。
    def f(x: Float64): String =
        let s = "${x}";
        if (String.contains({ substr = "." }, s) or String.contains({ substr = "E" }, s)) s else s + ".0"

    def f32(x: Float32): String =
        f(Float32.toFloat64(x))

    /// seed（Int32）を GLSL の float リテラルへ（hash 関数は float seed を取る）。
    def fSeed(seed: Int32): String =
        f(Int32.toFloat64(seed))

    def iLit(n: Int32): String = "${n}"
}
