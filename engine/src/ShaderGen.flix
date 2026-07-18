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
                // 位相 = field を cycleRate*uTime で往復させる（0..1 に折り返す三角波）。
                "mix(" + vec3Lit(r#lo) + ", " + vec3Lit(r#hi) + ", " +
                "clamp(abs(fract((" + fieldExpr(r#field, "vUv") + ") + " +
                f(cycleRate) + " * uTime) * 2.0 - 1.0), 0.0, 1.0))"
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
        }

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
